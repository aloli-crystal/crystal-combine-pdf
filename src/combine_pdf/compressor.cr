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
    # `backup` : si `true`, conserve l'original sous `<input>.bak`
    # avant le remplacement in-place.
    def compress(input : String, output : String, backup : Bool = false) : Result
      raise ArgumentError.new("Fichier introuvable : #{input}") unless File.exists?(input)

      before_size = File.size(input).to_i64
      page_count = ::PDF::Reader.open(input).page_count

      in_place = File.expand_path(input) == File.expand_path(output)
      target = in_place ? "#{output}.tmp.#{Process.pid}" : output

      # Le `Merger` recompresse Flate les streams décodés (depuis
      # v1.0.31.20) ET élimine les objets non référencés (puisqu'il
      # ne copie QUE les objets atteignables depuis les pages —
      # `reader.objects.each_value`). C'est notre GC implicite.
      merger = Merger.new
      merger.add(input)

      # Préserver Title/Author du PDF d'entrée pour la métadata
      # de sortie. Le `Producer` sera rafraîchi automatiquement par
      # le merger.
      info = read_info(input)
      merger.metadata_title = info[:title]
      merger.metadata_author = info[:author]

      merger.save(target)

      if in_place
        if backup
          FileUtils.cp(input, "#{input}.bak")
        end
        File.rename(target, input)
        after_path = input
      else
        after_path = output
      end

      after_size = File.size(after_path).to_i64
      Result.new(before_size, after_size, page_count)
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
