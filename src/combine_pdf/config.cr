module CombinePDF
  # Modèle de données du fichier `.crystal-combine-pdf.yml`.
  #
  # Mappé un-pour-un sur la structure du YAML. Pas de `YAML::Serializable`
  # ici — la section `files:` est parsée hors-YAML pour préserver les
  # commentaires et les titres inline lors d'un `--refresh`. Le loader
  # YAML standard est utilisé pour le reste (voir `ConfigLoader`).
  class Config
    # Nom du fichier PDF de sortie.
    property output : String
    # Titre du livret. Écrit dans le `/Info /Title` du PDF.
    property title : String
    # Auteur. Écrit dans le `/Info /Author`.
    property author : String
    # `true` = livret recto-verso. Bascule la sémantique des positions
    # `outer-*` / `inner-*` (alternance par parité).
    property duplex : Bool
    # Configuration des pages de couverture.
    property cover : Cover
    # Configuration de la numérotation des pages.
    property numbering : Numbering
    # Configuration du sommaire (bookmarks + future page texte).
    property toc : Toc?
    # Filigrane optionnel (texte semi-transparent en diagonale, etc.).
    property watermark : Watermark?
    # Liste ordonnée des fichiers à assembler.
    property files : Array(FileEntry)

    def initialize(
      @output : String = "output.pdf",
      @title : String = "",
      @author : String = "",
      @duplex : Bool = false,
      @cover : Cover = Cover.new,
      @numbering : Numbering = Numbering.new,
      @toc : Toc? = nil,
      @watermark : Watermark? = nil,
      @files : Array(FileEntry) = [] of FileEntry,
    )
    end

    # Une entrée du tableau `files:`.
    #
    # `path` : chemin relatif au dossier du `.crystal-combine-pdf.yml`.
    # `title` : libellé personnalisé pour le bookmark / TOC. `nil` = on
    #           dérive du nom de fichier (tirets → espaces, sans
    #           extension).
    # `excluded` : `true` quand l'entrée est en commentaire dans le
    #              YAML (`# - foo.pdf`). Conservée pour que `--refresh`
    #              ne réintroduise pas un fichier que l'utilisateur a
    #              explicitement écarté.
    record FileEntry,
      path : String,
      title : String? = nil,
      excluded : Bool = false do
      # Libellé à afficher dans les bookmarks / TOC. Préfère `title`
      # si défini, sinon dérive du nom de fichier.
      def display_title : String
        if t = @title
          t
        else
          base = File.basename(@path, File.extname(@path))
          base.tr("-_", "  ")
        end
      end
    end

    # Couverture avant et arrière.
    #
    # Sémantique :
    # * `mode: "none"`        — pas de couverture
    # * `mode: "recto"`       — 1 page de couverture (avant ET arrière)
    # * `mode: "recto-verso"` — 2 pages de couverture (avant ET arrière)
    #
    # Pour des asymétries (cas rare), surchargez via `front:` / `back:`.
    # Quand `front` ou `back` est non-`nil`, il prime sur `mode`.
    #
    # `include_in_numbering` :
    # * `false` (défaut) — la couverture n'est pas numérotée et la
    #   numérotation démarre à 1 sur la première page de contenu
    # * `true`           — la couverture compte (page 1 = couverture)
    # Ignoré silencieusement quand `mode == "none"`.
    class Cover
      property mode : String
      property front : String?
      property back : String?
      property include_in_numbering : Bool

      def initialize(
        @mode : String = "none",
        @front : String? = nil,
        @back : String? = nil,
        @include_in_numbering : Bool = false,
      )
      end

      # Nombre de pages de couverture en début de livret.
      def front_pages : Int32
        cover_pages_for(@front || @mode)
      end

      # Nombre de pages de couverture en fin de livret.
      def back_pages : Int32
        cover_pages_for(@back || @mode)
      end

      private def cover_pages_for(value : String) : Int32
        case value
        when "none"        then 0
        when "recto"       then 1
        when "recto-verso" then 2
        else                    0
        end
      end
    end

    # Configuration de la numérotation.
    class Numbering
      # Toggle global. `false` = aucune page numérotée.
      property enabled : Bool
      # Couche « numéro global de page » (ex: « 3/12 »).
      property global : Layer
      # Couche « numéro intra-partition » (ex: « 1/4 »).
      property partition : Layer
      # Couche « titre de partition en haut de page » — optionnelle.
      property header : Layer?
      # Liste 1-based de pages à laisser intactes (couvertures
      # additionnelles, intercalaires, etc.).
      property skip_pages : Array(Int32)

      def initialize(
        @enabled : Bool = true,
        @global : Layer = Layer.global_default,
        @partition : Layer = Layer.partition_default,
        @header : Layer? = nil,
        @skip_pages : Array(Int32) = [] of Int32,
      )
      end

      # Une couche de numérotation (global / partition / header).
      #
      # Toutes les couches partagent la même grammaire : activation,
      # format de chaîne (avec `%page%` et `%total%`), style visuel,
      # position, taille de police, couleur, marge.
      class Layer
        property enabled : Bool
        property format : String
        # Style visuel : `"plain"` (texte nu), `"badge"` (cadre arrondi),
        # `"circle"`, `"square"`, `"oval"`. Voir `Numberer` pour le rendu.
        property style : String
        # Position cardinale (statique) ou duplex-aware. Liste complète :
        # statiques  : top-left, top-center, top-right,
        #              bottom-left, bottom-center, bottom-right
        # duplex     : outer-top, inner-top, outer-bottom, inner-bottom
        property position : String
        property font_size : Float64
        property color : Tuple(Float64, Float64, Float64)
        property margin : Float64
        # Pour la couche `partition` : ne rien afficher quand la
        # partition fait une seule page. Sans effet pour les autres
        # couches.
        property hide_when_single : Bool

        def initialize(
          @enabled : Bool = true,
          @format : String = "%page%/%total%",
          @style : String = "plain",
          @position : String = "bottom-right",
          @font_size : Float64 = 10.0,
          @color : Tuple(Float64, Float64, Float64) = {0.2, 0.2, 0.2},
          @margin : Float64 = 24.0,
          @hide_when_single : Bool = false,
        )
        end

        # Défauts pour la couche globale (numéro de page du livret).
        def self.global_default : Layer
          new(position: "bottom-right")
        end

        # Défauts pour la couche partition (marque « 1/4 »).
        def self.partition_default : Layer
          new(
            position: "top-right",
            font_size: 9.0,
            color: {0.4, 0.4, 0.4},
            hide_when_single: true,
          )
        end

        # Défauts pour la couche header (titre de partition).
        def self.header_default : Layer
          new(
            position: "top-center",
            font_size: 9.0,
            color: {0.5, 0.5, 0.5},
            margin: 18.0,
          )
        end
      end
    end

    # Configuration du sommaire.
    #
    # `bookmarks` : génère le `/Outlines` du PDF (barre latérale
    # navigable du lecteur). Toujours dispo dans v1.0.31.2.
    #
    # `page` (futur) : page texte cliquable insérée après la
    # couverture. Prévu pour v1.0.31.3.
    class Toc
      property bookmarks : Bool

      def initialize(@bookmarks : Bool = true)
      end
    end

    # Filigrane (semi-transparent, en diagonale par défaut).
    #
    # Délégué à `crystal-watermark` (`CrystalWatermark.apply`). Les
    # styles disponibles correspondent à `CrystalWatermark::Style` :
    # `"diagonal"`, `"tiled"`, `"header"`, `"footer"`, `"center"`.
    class Watermark
      property text : String
      property style : String
      property font_size : Int32
      property color : Tuple(Float64, Float64, Float64)
      property opacity : Float64
      property rotation : Float64

      def initialize(
        @text : String,
        @style : String = "diagonal",
        @font_size : Int32 = 48,
        @color : Tuple(Float64, Float64, Float64) = {0.8, 0.8, 0.8},
        @opacity : Float64 = 0.15,
        @rotation : Float64 = 45.0,
      )
      end
    end
  end
end
