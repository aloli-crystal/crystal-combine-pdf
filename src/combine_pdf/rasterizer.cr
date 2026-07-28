module CombinePDF
  # Rastérise un PDF page par page : chaque page devient une
  # image JPEG plein page embarquée dans le PDF de sortie.
  #
  # Cas d'usage : anti-extraction / anti-falsification.
  # * Un PDF rastérisé n'expose plus son texte à `pdftotext` ni au
  #   copier-coller.
  # * Un filigrane qui faisait partie de la page source devient
  #   indissociable du contenu — impossible à retirer sans détruire
  #   les données utiles (chiffres d'IBAN, etc.).
  # * Pattern observé chez DossierFacile (RIB protégés émis par la
  #   plateforme) : tout le PDF est un JPEG plein page.
  #
  # Pipeline interne :
  # 1. `gs` rend chaque page du PDF source en JPEG haute résolution
  #    (DPI configurable, défaut 200) dans un dossier temporaire.
  # 2. Le shard `pdf` reconstruit un nouveau PDF avec une page par
  #    JPEG, en préservant les dimensions de chaque page source
  #    (lues via `PDF::Reader` avant la rastérisation).
  # 3. Le dossier temporaire est nettoyé en `ensure`.
  #
  # Compromis :
  # * Accessibilité dégradée (pas de texte extractible — mauvais pour
  #   les lecteurs d'écran, OCR éventuel requis pour réutiliser les
  #   données).
  # * Taille du fichier nettement supérieure à un PDF vectoriel
  #   équivalent (compression JPEG vs. texte + filtres Flate).
  # Ces compromis sont assumés : la rastérisation est explicite,
  # commandée par l'utilisateur quand l'anti-falsification prime.
  module Rasterizer
    extend self

    class Error < Exception
    end

    DEFAULT_DPI          = 200
    DEFAULT_JPEG_QUALITY =  85

    # Rastérise `input` vers `output`. Lève `Error` si `gs` (Ghostscript)
    # n'est pas dans le PATH ou si la conversion échoue.
    #
    # * `dpi` : résolution de rendu (défaut 200 dpi — équilibre
    #   qualité / taille fichier). Monter à 300 pour de l'archivage
    #   imprimable, baisser à 150 pour un usage écran simple.
    # * `jpeg_quality` : 0-100, défaut 85 (TJpeg standard).
    # * `password` : si le PDF source est chiffré, mot de passe
    #   d'ouverture (vide par défaut).
    def rasterize(
      input : String,
      output : String,
      dpi : Int32 = DEFAULT_DPI,
      jpeg_quality : Int32 = DEFAULT_JPEG_QUALITY,
      password : String = "",
    ) : Nil
      unless ghostscript_available?
        raise Error.new(
          "gs (Ghostscript) binary not found in PATH (requis pour " \
          "rasterize). Install : `brew install ghostscript` (macOS), " \
          "`pkg install ghostscript` (FreeBSD), " \
          "`apt install ghostscript` (Debian/Ubuntu)."
        )
      end

      # Étape 1 : lire les dimensions de chaque page du source. On le
      # fait AVANT le rendu gs pour pouvoir reconstruire un PDF qui
      # préserve la géométrie (A4, Letter, format custom de scan, etc.).
      pages_dims = read_page_dimensions(input, password: password)
      if pages_dims.empty?
        raise Error.new("PDF source vide (#{input}) — rien à rastériser.")
      end

      tmp_dir = File.tempname("ccp-rasterize", "")
      Dir.mkdir_p(tmp_dir)
      begin
        # Étape 2 : gs → 1 JPEG par page, numérotés à partir de 1.
        pattern = File.join(tmp_dir, "page-%d.jpg")
        gs_args = [
          "-dNOPAUSE", "-dBATCH", "-dQUIET", "-dSAFER",
          "-sDEVICE=jpeg",
          "-r#{dpi}",
          "-dJPEGQ=#{jpeg_quality}",
          "-sOutputFile=#{pattern}",
        ]
        unless password.empty?
          gs_args << "-sPDFPassword=#{password}"
        end
        gs_args << input

        err_buf = IO::Memory.new
        status = Process.run("gs", gs_args, output: Process::Redirect::Close, error: err_buf)
        unless status.success?
          raise Error.new(
            "gs a échoué (exit #{status.exit_code}). " \
            "stderr : #{err_buf.to_s.lines.first?.try(&.strip)}"
          )
        end

        # Étape 3 : réembarquage. Une page par JPEG, dimensions
        # héritées du source. L'image remplit la page intégralement
        # (origin {0, 0}, width/height = MediaBox).
        doc = ::PDF::Document.new
        pages_dims.each_with_index do |dim, i|
          jpg_path = File.join(tmp_dir, "page-#{i + 1}.jpg")
          unless File.exists?(jpg_path)
            raise Error.new(
              "gs n'a pas produit #{jpg_path} (sortie incomplète)."
            )
          end
          width, height = dim
          img = ::PDF::Images::Image.load(jpg_path)
          doc.page(width: width, height: height) do |page|
            page.image(img, at: {0.0, 0.0}, width: width, height: height)
          end
        end

        # Métadonnée : on marque la rastérisation pour traçabilité
        # (audit éventuel d'un document protégé).
        doc.producer = "combine-pdf #{CombinePDF::VERSION} (rasterized)"

        doc.save(output)
      ensure
        if Dir.exists?(tmp_dir)
          Dir.glob(File.join(tmp_dir, "*")).each { |f| File.delete(f) if File.exists?(f) }
          Dir.delete(tmp_dir)
        end
      end
    end

    # Récupère `[{w, h}, …]` des MediaBox de chaque page du PDF source.
    private def read_page_dimensions(path : String, password : String = "") : Array(Tuple(Float64, Float64))
      reader = ::PDF::Reader.open(path, password: password)
      reader.pages.map { |p| {p.width.to_f, p.height.to_f} }
    end

    @@ghostscript_available : Bool? = nil

    def ghostscript_available? : Bool
      if cached = @@ghostscript_available
        return cached
      end
      result = !Process.find_executable("gs").nil?
      @@ghostscript_available = result
      result
    end

    # Reset du cache (utilisé par les specs).
    def reset_ghostscript_cache! : Nil
      @@ghostscript_available = nil
    end
  end
end
