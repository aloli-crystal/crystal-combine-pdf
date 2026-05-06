module CombinePDF
  # Exécute une `Config` : assemble les fichiers, applique la
  # numérotation (cover-aware, duplex-aware, multi-positions), pose
  # le filigrane et écrit le PDF de sortie.
  #
  # C'est le moteur de la commande `crystal-combine-pdf` (sans
  # sous-commande) qui lit `.crystal-combine-pdf.yml` et produit
  # le livret.
  class BookletBuilder
    @config : Config
    @base_dir : String

    def initialize(@config : Config, @base_dir : String)
    end

    # Charge la config depuis `dir` et construit le livret.
    def self.from_dir(dir : String) : BookletBuilder
      yml = File.join(dir, ConfigInitializer::CONFIG_FILENAME)
      unless File.exists?(yml)
        raise "Aucun fichier #{ConfigInitializer::CONFIG_FILENAME} dans #{dir}. Lancez d'abord `crystal-combine-pdf init`."
      end
      new(ConfigLoader.load(yml), dir)
    end

    # Construit le livret. Renvoie le chemin du fichier produit.
    def build : String
      active = @config.files.reject(&.excluded)
      if active.empty?
        raise "Aucun fichier actif dans la liste `files:` du YAML."
      end

      # Vérifier l'existence sur disque
      missing = active.map(&.path).reject { |p| File.exists?(File.join(@base_dir, p)) }
      unless missing.empty?
        raise "Fichiers introuvables dans #{@base_dir} : #{missing.join(", ")}"
      end

      output_path = File.join(@base_dir, @config.output)

      # Validation préalable : tente d'ouvrir ET de matérialiser tous
      # les objets de chaque fichier pour repérer les rares cas où
      # `pdf` n'arrive pas à parser (PDF malformé, encryption non
      # supportée, stream avec en-tête zlib invalide d'un PDF
      # linéarisé Acrobat ancien, etc.).
      #
      # On ne se contente PAS de `page_count` : ouvrir le PDF n'est
      # qu'une lecture du xref, mais les streams ne sont décompressés
      # que lors de la matérialisation. Forcer la résolution de tous
      # les objets attrape les erreurs Zlib/Filter qui surviendraient
      # plus tard pendant la fusion et donneraient un message
      # cryptique sans contexte de fichier.
      bad_files = [] of Tuple(String, String)
      active.each do |entry|
        full = File.join(@base_dir, entry.path)
        begin
          reader = ::PDF::Reader.open(full)
          total_size = reader.@trailer["Size"]?.try(&.as?(::PDF::Objects::Number)).try(&.to_i64.to_i32) || 0
          (1...total_size).each { |id| reader.resolve(::PDF::Objects::Reference.new(id)) }
        rescue ex : ::PDF::EncryptedPdfError
          # Cas spécifique : PDF chiffré (RC4/AES). Message beaucoup
          # plus ciblé que le générique « Invalid header ».
          bad_files << {entry.path, "chiffré — #{ex.message}"}
        rescue ex
          bad_files << {entry.path, ex.message || "erreur inconnue"}
        end
      end
      unless bad_files.empty?
        msg = String.build do |s|
          s << "Fichiers non lisibles :\n"
          bad_files.each do |path, err|
            s << "  - " << path << "\n    → " << err << "\n"
          end
          s << "\nContournements possibles :\n"
          s << "  1. Normaliser le PDF via Ghostscript (recommandé) :\n"
          bad_files.each do |path, _|
            s << "       crystal-combine-pdf gs " << path << " -i\n"
          end
          s << "     Réécrit le PDF en place avec une structure standard\n"
          s << "     que le shard arrive à parser. Nécessite `gs` installé.\n"
          s << "\n"
          s << "  2. Ou exclure l'entrée du YAML en la préfixant par `# - `.\n"
          s << "\n"
          s << "  3. Ou (équivalent à #1, sans la sous-commande) :\n"
          s << "       gs -sDEVICE=pdfwrite -dPDFSETTINGS=/default \\\n"
          s << "          -o normalise.pdf -dNOPAUSE -dQUIET -dBATCH \\\n"
          s << "          fichier-cassé.pdf\n"
        end
        raise msg
      end

      # 1) Fusion des PDF dans l'ordre
      tmp_merged = File.tempname("ccp-merged", ".pdf")
      begin
        inputs = active.map { |entry| File.join(@base_dir, entry.path) }
        # On utilise une instance de Merger plutôt que Merger.merge
        # pour pouvoir insérer une page TOC en tête après tous les
        # `add()`. Si la TOC n'est pas activée, le résultat est
        # identique à `Merger.merge`.
        merger = Merger.new
        inputs.each { |path| merger.add(path) }

        if toc = @config.toc.try(&.page)
          insert_toc_page(merger, active, toc)
        end

        merger.save(tmp_merged)

        # 2) Numérotation (cover-aware, duplex-aware)
        tmp_numbered = File.tempname("ccp-numbered", ".pdf")
        begin
          if @config.numbering.enabled
            partitions = active.map { |entry| ::PDF::Reader.open(File.join(@base_dir, entry.path)).page_count }
            toc_pages = (@config.toc.try(&.page).try(&.enabled)) ? 1 : 0
            AdvancedNumberer.new(@config, partitions, toc_pages).apply(tmp_merged, tmp_numbered)
          else
            File.copy(tmp_merged, tmp_numbered)
          end

          # 3) Filigrane (si demandé)
          tmp_watermarked = File.tempname("ccp-watermarked", ".pdf")
          begin
            if wm = @config.watermark
              apply_watermark(tmp_numbered, tmp_watermarked, wm)
            else
              File.copy(tmp_numbered, tmp_watermarked)
            end

            # 4) Métadonnées (title/author) via PDF wrapper
            pdf = CombinePDF.load(tmp_watermarked)
            pdf.title = @config.title unless @config.title.empty?
            pdf.author = @config.author unless @config.author.empty?
            pdf.save(output_path)
          ensure
            File.delete(tmp_watermarked) if File.exists?(tmp_watermarked)
          end
        ensure
          File.delete(tmp_numbered) if File.exists?(tmp_numbered)
        end
      ensure
        File.delete(tmp_merged) if File.exists?(tmp_merged)
      end

      output_path
    end

    # Construit les entrées TOC (à partir de la liste de fichiers
    # active et du nombre de pages de chaque fichier), génère le
    # content stream + annotations via TocBuilder, et insère la
    # page TOC en tête du merger.
    private def insert_toc_page(merger : Merger,
                                active : Array(Config::FileEntry),
                                _toc : Config::Toc::Page) : Nil
      # `merger.page_refs` à ce stade contient les références des
      # pages des partitions, dans l'ordre. Pour chaque entrée
      # active, on associe sa première page = la `cumulative + 1`-ième
      # référence du merger.
      entries = [] of TocBuilder::Entry
      cumulative = 0
      active.each do |file_entry|
        full = File.join(@base_dir, file_entry.path)
        partition_pages = ::PDF::Reader.open(full).page_count
        target_ref = merger.page_refs[cumulative]?
        next unless target_ref

        # Numéro affiché : 1-based dans le livret final, en
        # tenant compte du décalage de la TOC (+1 page) et de
        # cover.include_in_numbering.
        displayed = compute_displayed_page_number(cumulative)

        entries << TocBuilder::Entry.new(
          title: file_entry.display_title,
          page_number: displayed,
          target_page_ref: target_ref,
        )
        cumulative += partition_pages
      end

      builder = TocBuilder.new(@config, entries)
      content, annots = builder.build
      merger.insert_toc_page(content, annots, builder.page_width, builder.page_height)
    end

    # Calcule le numéro de page affiché pour une page située à
    # l'index `idx` dans le contenu (0-based, AVANT insertion de la
    # TOC). Tient compte de cover.front_pages et de
    # cover.include_in_numbering.
    private def compute_displayed_page_number(idx : Int32) : Int32
      cover = @config.cover
      front = cover.front_pages
      if cover.include_in_numbering
        # La couverture compte ; la TOC compte aussi (en première
        # position). Donc page 1 = TOC, page 2 = front-cover-1, …
        idx + front + 2
      else
        # Couverture et TOC sautées. Numérotation = idx - front + 1
        # avec un plancher à 1 si la TOC pointe avant la couverture
        # (rare mais possible).
        if idx < front
          1
        else
          idx - front + 1
        end
      end
    end

    private def apply_watermark(input : String, output : String, wm : Config::Watermark) : Nil
      # watermark a son propre vocabulaire de styles. On mappe
      # nos chaînes vers ses constantes.
      style = case wm.style
              when "diagonal" then Watermark::Style::Diagonal
              when "tiled"    then Watermark::Style::Tiled
              when "header"   then Watermark::Style::Header
              when "footer"   then Watermark::Style::Footer
              when "center"   then Watermark::Style::Center
              else                 Watermark::Style::Diagonal
              end

      options = Watermark::Options.new(
        font_size: wm.font_size,
        color: wm.color,
        opacity: wm.opacity,
        rotation: wm.rotation,
      )

      Watermark.apply(input, output, wm.text, style, options)
    end
  end
end
