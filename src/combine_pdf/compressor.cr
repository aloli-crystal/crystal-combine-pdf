require "file_utils"

module CombinePDF
  # Réduit la taille d'un PDF en pur Crystal (sans appel à un service
  # en ligne). Stratégie :
  #
  # 1. **Recompression Flate** des streams non compressés ou mal
  #    compressés. C'est le mécanisme qui a fait passer un livret
  #    de 21 Mo à 2,6 Mo lors d'un cas réel (8× réduction).
  #    Implémenté via le `Merger` qui rattache un filtre Flate à
  #    chaque stream décodé qu'il copie (cf. `Merger#remap`).
  #
  # 2. **Garbage collection** : seuls les objets accessibles depuis
  #    le `/Catalog` sont conservés. Les objets orphelins (xref
  #    obsolète, ressources délaissées après édition incrémentale)
  #    sont éliminés.
  #
  # 3. **Nettoyage métadata** : `/Info` est ré-écrit avec le
  #    `Producer` à jour ; `Title`/`Author` du PDF d'origine sont
  #    préservés ; `ModDate`/`CreationDate` redondants sont retirés.
  #
  # **Limitations** :
  # * Pas de downsampling d'images (300 DPI → 150 DPI) — nécessite du
  #   traitement d'image qu'on n'a pas en pur Crystal.
  # * Pas de recompression JPEG, ni de subsetting de fonts.
  # * Pour ces optimisations, voir le futur flag `--deep` qui
  #   déléguera à `aloli-crystal/ghostscript`.
  #
  # **Gain typique** : 30-80 % selon que le PDF d'entrée a déjà
  # ses streams en Flate (gain modéré : juste GC + métadata) ou
  # non (gain massif : ré-écriture en Flate).
  module Compressor
    extend self

    # Résultat d'une compression. `before` et `after` sont en bytes.
    struct Result
      getter before : Int64
      getter after : Int64
      getter pages : Int32

      def initialize(@before : Int64, @after : Int64, @pages : Int32)
      end

      # Pourcentage de réduction (peut être négatif si la sortie est
      # plus grosse — rare mais possible quand le PDF d'entrée
      # utilisait déjà des filtres plus efficaces que Flate).
      def reduction_percent : Float64
        return 0.0 if @before == 0
        (1.0 - @after.to_f64 / @before.to_f64) * 100.0
      end

      def to_s(io : IO) : Nil
        io << format_size(@before) << " → " << format_size(@after)
        io << " (" << ("%.1f" % reduction_percent) << " %)"
      end

      private def format_size(bytes : Int64) : String
        kb = bytes / 1024.0
        return "%.1f Ko" % kb if kb < 1024
        "%.2f Mo" % (kb / 1024.0)
      end
    end

    # Compresse `input` vers `output`. Si `output == input`, écrit
    # via un fichier temporaire puis remplace (sécurité crash).
    #
    # `backup` : si `true`, conserve l'original sous `<input>.bak`
    # avant le remplacement in-place.
    #
    # `deep` : si `true`, délègue à Ghostscript (downsampling
    # d'images, recompression JPEG, font subsetting). Nécessite que
    # `gs` soit installé. Lève `Error` sinon.
    #
    # `deep_quality` : preset de qualité Ghostscript quand `deep:
    # true`. `:screen` (72 dpi), `:ebook` (150 dpi, défaut),
    # `:printer` (300 dpi), `:prepress` (300 dpi color-preserving).
    #
    # `linearize` : si `true`, post-traite la sortie via `qpdf
    # --linearize` pour produire un PDF *Fast Web View* (ISO 32000-1
    # § F). Utile pour servir le PDF en streaming HTTP — le viewer
    # peut afficher la page 1 dès qu'il a reçu son préfixe sans
    # attendre le téléchargement complet. Sans intérêt pour les
    # PDFs téléchargés en entier puis lus localement (livret,
    # rapport archivé, document signé, etc.). Nécessite `qpdf`
    # installé. ⚠ NE PAS linéariser un PDF *déjà signé* (PAdES) :
    # la réorganisation des octets invalide la signature.
    def compress(
      input : String,
      output : String,
      backup : Bool = false,
      deep : Bool = false,
      deep_quality : ::Ghostscript::Quality | Symbol = :ebook,
      linearize : Bool = false,
    ) : Result
      raise ArgumentError.new("Fichier introuvable : #{input}") unless File.exists?(input)

      before_size = File.size(input).to_i64
      page_count = ::PDF::Reader.open(input).page_count

      in_place = File.expand_path(input) == File.expand_path(output)
      target = in_place ? "#{output}.tmp.#{Process.pid}" : output

      if deep
        compress_deep(input, target, deep_quality)
      else
        compress_flate(input, target)
      end

      # Linéarisation post-compression. On la fait APRÈS compress
      # parce que qpdf a son propre filtre Flate ; le faire avant
      # serait gaspillé. On écrit dans un fichier temp puis on
      # remplace `target`.
      linearize_in_place(target) if linearize

      if in_place
        FileUtils.cp(input, "#{input}.bak") if backup
        File.rename(target, input)
        after_path = input
      else
        after_path = output
      end

      after_size = File.size(after_path).to_i64
      Result.new(before_size, after_size, page_count)
    end

    # Linéarise `path` en place via `qpdf --linearize`. Lève
    # `Error` si `qpdf` est absent du PATH ou si la conversion
    # échoue. Utilise un fichier temporaire pour ne pas écraser
    # `path` en cas d'erreur du sous-process.
    private def linearize_in_place(path : String) : Nil
      unless qpdf_available?
        raise Error.new(
          "qpdf binary not found in PATH (requis pour --linearize). " \
          "Install it with `brew install qpdf` (macOS), " \
          "`pkg install qpdf` (FreeBSD) or " \
          "`apt install qpdf` (Debian/Ubuntu)."
        )
      end

      tmp = "#{path}.linearize.tmp.#{Process.pid}"
      err_buf = IO::Memory.new
      status = Process.run(
        "qpdf",
        ["--linearize", path, tmp],
        output: Process::Redirect::Close,
        error: err_buf,
      )
      unless status.success?
        File.delete(tmp) if File.exists?(tmp)
        raise Error.new(
          "qpdf --linearize a échoué (exit #{status.exit_code}). " \
          "stderr : #{err_buf.to_s.lines.first?.try(&.strip)}"
        )
      end
      File.rename(tmp, path)
    end

    # Vérifie une seule fois la présence de `qpdf` dans le PATH.
    # Cache de classe pour éviter le `Process.find_executable`
    # répété sur de gros lots.
    @@qpdf_available : Bool? = nil

    def qpdf_available? : Bool
      if cached = @@qpdf_available
        return cached
      end
      result = !Process.find_executable("qpdf").nil?
      @@qpdf_available = result
      result
    end

    # Recompression Flate + GC implicite via `Merger` (pur Crystal).
    # Voir le commentaire d'en-tête du module pour le détail.
    private def compress_flate(input : String, target : String) : Nil
      merger = Merger.new
      merger.add(input)
      info = read_info(input)
      merger.metadata_title = info[:title]
      merger.metadata_author = info[:author]
      merger.save(target)
    end

    # Compression « profonde » via Ghostscript. Downsampling images,
    # recompression JPEG, font subsetting. Nécessite `gs` installé.
    private def compress_deep(input : String, target : String, quality) : Nil
      unless ::Ghostscript.available?
        raise Error.new(
          "Ghostscript binary `gs` not found in PATH. " \
          "Install it with `brew install ghostscript` (macOS), " \
          "`pkg install ghostscript10` (FreeBSD) or " \
          "`apt install ghostscript` (Debian/Ubuntu)."
        )
      end
      result = ::Ghostscript.compress(input, target, quality: quality)
      unless result.success?
        raise Error.new(
          "Ghostscript a échoué (exit #{result.exit_code}). " \
          "stderr : #{result.stderr.lines.first?.try(&.strip)}"
        )
      end
    end

    # Erreur levée par les méthodes du Compressor pour les cas qui
    # ne sont pas des `ArgumentError`.
    class Error < Exception
    end

    # Lit le dictionnaire `/Info` du PDF d'entrée pour extraire
    # `Title` et `Author`. Retourne un nommé tuple ; les valeurs
    # absentes sont `nil`.
    private def read_info(path : String) : NamedTuple(title: String?, author: String?)
      reader = ::PDF::Reader.open(path)
      trailer = reader.@trailer
      info_ref = trailer["Info"]?
      return {title: nil, author: nil} unless info_ref

      info = reader.resolve(info_ref)
      return {title: nil, author: nil} unless info.is_a?(::PDF::Objects::Dictionary)

      title = info["Title"]?.try { |v| v.is_a?(::PDF::Objects::Str) ? v.value : nil }
      author = info["Author"]?.try { |v| v.is_a?(::PDF::Objects::Str) ? v.value : nil }
      {title: title, author: author}
    rescue
      {title: nil, author: nil}
    end
  end
end
