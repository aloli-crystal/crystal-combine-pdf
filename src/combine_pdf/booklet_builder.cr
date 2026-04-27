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
        raise "Aucun fichier #{ConfigInitializer::CONFIG_FILENAME} dans #{dir}. Lancez d'abord crystal-combine-pdf --init."
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

      # Validation préalable : tente d'ouvrir chaque fichier pour
      # repérer les rares cas où `crystal-pdf` n'arrive pas à
      # parser (PDF malformé, encryption non supportée, etc.).
      # Depuis crystal-pdf v0.3.6 les xref streams et les filtres
      # CCITTFaxDecode/DCTDecode/JBIG2Decode sont gérés ;
      # cette boucle attrape les cas restants et donne un message
      # explicite au lieu d'un crash plus loin dans la pipeline.
      bad_files = [] of Tuple(String, String)
      active.each do |entry|
        full = File.join(@base_dir, entry.path)
        begin
          ::PDF::Reader.open(full).page_count
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
          s << "\nVous pouvez exclure une entrée dans le YAML en la préfixant par `# - `.\n"
        end
        raise msg
      end

      # 1) Fusion des PDF dans l'ordre
      tmp_merged = File.tempname("ccp-merged", ".pdf")
      begin
        inputs = active.map { |entry| File.join(@base_dir, entry.path) }
        Merger.merge(inputs, tmp_merged)

        # 2) Numérotation (cover-aware, duplex-aware)
        tmp_numbered = File.tempname("ccp-numbered", ".pdf")
        begin
          if @config.numbering.enabled
            partitions = active.map { |entry| ::PDF::Reader.open(File.join(@base_dir, entry.path)).page_count }
            AdvancedNumberer.new(@config, partitions).apply(tmp_merged, tmp_numbered)
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

    private def apply_watermark(input : String, output : String, wm : Config::Watermark) : Nil
      # crystal-watermark a son propre vocabulaire de styles. On mappe
      # nos chaînes vers ses constantes.
      style = case wm.style
              when "diagonal" then CrystalWatermark::Style::Diagonal
              when "tiled"    then CrystalWatermark::Style::Tiled
              when "header"   then CrystalWatermark::Style::Header
              when "footer"   then CrystalWatermark::Style::Footer
              when "center"   then CrystalWatermark::Style::Center
              else                 CrystalWatermark::Style::Diagonal
              end

      options = CrystalWatermark::Options.new(
        font_size: wm.font_size,
        color: wm.color,
        opacity: wm.opacity,
        rotation: wm.rotation,
      )

      CrystalWatermark.apply(input, output, wm.text, style, options)
    end
  end
end
