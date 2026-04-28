module CombinePDF
  # Génère un fichier `.crystal-combine-pdf.yml` par défaut dans un
  # dossier — utilisé par `crystal-combine-pdf --init`.
  #
  # Le YAML produit contient :
  # * des champs scalaires raisonnables (output, title déduits du nom
  #   du dossier ; author depuis git config si dispo)
  # * la liste `files:` peuplée avec les `*.pdf` du dossier triés par
  #   ordre alphabétique
  # * tous les autres réglages en commentaires explicatifs (toc,
  #   watermark, header) ou avec leurs valeurs par défaut
  module ConfigInitializer
    extend self

    CONFIG_FILENAME = ".crystal-combine-pdf.yml"

    # Options de personnalisation du YAML généré par `init`.
    #
    # Chaque champ correspond à un drapeau CLI (`--paper-size`,
    # `--duplex`, `--with-toc`, `--skip-watermark`, …). Les valeurs
    # par défaut reproduisent le template historique :
    # * sections `cover`, `numbering` actives
    # * sections `toc.page`, `watermark`, `numbering.header` en
    #   commentaires (visibles mais inactives)
    #
    # Trois états par section optionnelle :
    # * `:default` — section présente en commentaires (état actuel)
    # * `:enabled` — section active, pas de `# ` préfixe
    # * `:omitted` — section absente du YAML (pour les utilisateurs
    #               qui veulent un fichier compact)
    struct InitOptions
      # Réglages directs (overrides des valeurs déduites)
      property paper_size : String = "a4"
      property duplex : Bool = false
      property title : String? = nil
      property author : String? = nil
      property output : String? = nil

      # Numérotation
      property numbering_enabled : Bool = true
      property global_format : String = "\u{2022} %page% / %total% \u{2022}"

      # Couverture
      property cover_mode : String = "none"

      # Sections optionnelles (3 états : default | enabled | omitted)
      property toc_state : Symbol = :default
      property watermark_state : Symbol = :default
      property watermark_text : String? = nil # Si :enabled, ce texte (sinon: nom dossier)
      property header_state : Symbol = :default

      def initialize
      end
    end

    # Initialise le YAML dans `dir`. Lève si le fichier existe déjà.
    # `recursive` : `true` pour scanner les sous-dossiers (chemins
    # enregistrés relatifs au dossier racine).
    # `options` : personnalisation du template — cf. `InitOptions`.
    def init(dir : String, recursive : Bool = false, options : InitOptions = InitOptions.new) : String
      target = File.join(dir, CONFIG_FILENAME)
      if File.exists?(target)
        raise "Le fichier #{CONFIG_FILENAME} existe déjà dans #{dir}. Utilisez --refresh pour mettre à jour la liste des fichiers."
      end

      pdfs = scan_pdfs(dir, recursive)
      if pdfs.empty?
        raise "Aucun fichier .pdf trouvé dans #{dir}#{recursive ? " (ni dans ses sous-dossiers)" : ""}."
      end

      yaml = build_yaml(dir, pdfs, options)
      File.write(target, yaml)
      target
    end

    # Liste les `*.pdf` d'un dossier (insensible à la casse), avec
    # ordre alphabétique. Mode récursif : parents d'abord, puis
    # sous-dossiers triés alpha.
    def scan_pdfs(dir : String, recursive : Bool) : Array(String)
      results = [] of String
      collect_pdfs_in_dir(dir, "", recursive, results)
      results
    end

    private def collect_pdfs_in_dir(
      base : String,
      relative : String,
      recursive : Bool,
      acc : Array(String),
    ) : Nil
      full_path = relative.empty? ? base : File.join(base, relative)
      return unless Dir.exists?(full_path)

      # Fichiers PDF du dossier courant, triés alpha (insensible casse)
      pdfs = Dir.entries(full_path)
        .select { |e| e != "." && e != ".." && File.extname(e).downcase == ".pdf" }
        .sort! { |a, b| a.downcase <=> b.downcase }
      pdfs.each do |name|
        acc << (relative.empty? ? name : File.join(relative, name))
      end

      return unless recursive

      # Sous-dossiers, triés alpha (parents d'abord = on a déjà
      # ajouté les fichiers du courant, on descend ensuite)
      subdirs = Dir.entries(full_path)
        .select do |e|
          next false if e == "." || e == ".." || e.starts_with?(".")
          File.directory?(File.join(full_path, e))
        end
        .sort! { |a, b| a.downcase <=> b.downcase }
      subdirs.each do |sub|
        sub_relative = relative.empty? ? sub : File.join(relative, sub)
        collect_pdfs_in_dir(base, sub_relative, recursive, acc)
      end
    end

    # Construit le contenu YAML — appelle les helpers `build_section_*`
    # selon les options. Sections optionnelles (`toc`, `watermark`,
    # `header`) selon leur `*_state` :
    # * `:default`  — commentée (visible mais inactive)
    # * `:enabled`  — active (sans `# `)
    # * `:omitted`  — absente du YAML
    def build_yaml(dir : String, pdfs : Array(String), options : InitOptions = InitOptions.new) : String
      folder_name = File.basename(File.expand_path(dir))
      output = options.output || "#{folder_name}.pdf"
      title = options.title || folder_name
      author = options.author || detect_author

      String.build do |s|
        s << "# .crystal-combine-pdf.yml\n"
        s << "# Généré par `crystal-combine-pdf init` — éditez librement.\n"
        s << "# Pour rafraîchir après ajout/retrait de PDF :\n"
        s << "#   crystal-combine-pdf refresh\n"
        s << "\n"
        s << "output: " << output << "\n"
        s << "title:  \"" << title << "\"\n"
        s << "author: \"" << author << "\"\n"
        s << "\n"

        s << <<-FILES_HEADER
          # ─── Liste des fichiers ───────────────────────────────────────
          # C'est la section qu'on édite le plus.
          # Ordre = ordre du livret. Réordonnez les lignes à votre
          # convenance. Préfixez par `# -` pour exclure une entrée
          # sans la supprimer (`refresh` la conservera commentée).
          # Ajoutez `: "Titre"` pour personnaliser le bookmark
          # (forme longue : `- foo.pdf: "Titre lisible"`).
          files:

          FILES_HEADER

        pdfs.each do |path|
          s << "  - " << yaml_quote_if_needed(path) << "\n"
        end
        s << "\n"

        # ─── Sections globales ─────────────────────────────────────
        build_section_paper_size(s, options)
        build_section_duplex(s, options)
        build_section_cover(s, options)
        build_section_numbering(s, options)
        build_section_toc(s, options)
        build_section_watermark(s, options, folder_name)
      end
    end

    # ─── Builders de sections ────────────────────────────────────
    # Chaque section optionnelle (toc, watermark, header) a 3 modes :
    # `:default` (commenté), `:enabled` (actif), `:omitted` (rien).

    private def build_section_paper_size(s : IO, options : InitOptions) : Nil
      s << <<-BLOCK
        # ─── Format de page ───────────────────────────────────────────
        # Format des pages générées par ce shard (TOC, pages blanches…).
        # Les PDF d'entrée gardent leur format d'origine — ce réglage
        # ne s'applique qu'aux pages que le shard fabrique lui-même.
        # Valeurs : a4 (défaut), letter, legal, a3, a5, b5, executive
        #           ou "WxH" en points (ex. "595x842")
        paper_size: #{options.paper_size}

        BLOCK
    end

    private def build_section_duplex(s : IO, options : InitOptions) : Nil
      s << <<-BLOCK
        # true = recto-verso (les positions outer/inner alternent par
        #        parité de page)
        # false = recto seul
        duplex: #{options.duplex}

        BLOCK
    end

    private def build_section_cover(s : IO, options : InitOptions) : Nil
      s << <<-BLOCK
        # ─── Couverture ───────────────────────────────────────────────
        # `mode` s'applique symétriquement (avant + arrière). Pour des
        # valeurs différentes, remplacez `mode:` par `front:` et `back:`.
        #
        # Si include_in_numbering est false, NI les pages de couverture
        # avant NI les pages de couverture arrière ne sont numérotées,
        # et la numérotation démarre à 1 sur la première page utile.
        cover:
          mode: #{options.cover_mode}              # none | recto | recto-verso
          include_in_numbering: false

        BLOCK
    end

    private def build_section_numbering(s : IO, options : InitOptions) : Nil
      s << <<-DOC
        # ─── Numérotation ─────────────────────────────────────────────
        # Positions disponibles :
        #
        #   ┌─ Statiques (position fixe quelle que soit la page) ───────
        #   │ top-left      top-center      top-right
        #   │ bottom-left   bottom-center   bottom-right
        #
        #   ┌─ Duplex-aware (alternent par parité de page) ─────────────
        #   │ outer-top     inner-top
        #   │ outer-bottom  inner-bottom
        #   │
        #   │ Quand duplex: true (livret relié)
        #   │   outer-* = côté opposé à la reliure (le bord extérieur du
        #   │            livret). Sur page impaire (recto) = droite ;
        #   │            sur page paire (verso) = gauche.
        #   │   inner-* = côté reliure. Sur page impaire = gauche ; sur
        #   │            page paire = droite. (Rare : l'œil cherche le
        #   │            numéro côté extérieur.)
        #   │
        #   │ Quand duplex: false (recto seul)
        #   │   outer-* ≡ right        inner-* ≡ left
        #
        # Styles disponibles :
        #   plain  | texte nu sans cadre
        #   badge  | cadre arrondi gris très pâle, discret
        #   oval   | pastille pill (très arrondie) avec bordure noire fine
        #            — recommandé pour le numéro global, ça marque l'œil
        #   circle | cercle parfait
        #   square | rectangle à coins droits
        #
        # Format de chaîne :
        #   * %page%   sera remplacé par le numéro de page courant
        #   * %total%  sera remplacé par le nombre total de pages utiles
        #
        # Exemples de formats — combinez avec ce que vous voulez :
        #   "%page%/%total%"         → 6/12       (compact)
        #   "%page% / %total%"       → 6 / 12     (espacé)
        #   "• %page% / %total% •"   → • 6 / 12 • (puces, par défaut)
        #   "- %page% / %total% -"   → - 6 / 12 - (tirets ASCII)
        #   "page %page% sur %total%" → page 6 sur 12
        #   "« %page%/%total% »"     → « 6/12 »   (guillemets français)
        #   "† %page% †"             → † 6 †      (croix)
        #
        # Caractères supportés :
        #   * ASCII + Latin-1 (accents français è é ê à ç ô …)
        #   * Symboles typographiques WinAnsi (€ • † ‡ … ‹ › « »
        #     " " ' ' – — ™ ‰ Œ œ Š Ÿ ƒ ‚ „)
        #   * Dingbats ZapfDingbats : étoiles (★ ☆ ✦ ✧ ✩ ✪ ✫ ✬ ✭
        #     ✮ ✯ ✰), cœurs (♥ ❤), pique/trèfle/carreau (♠ ♣ ♦),
        #     coches (✓ ✔ ✗ ✘), croix (✚ ✙ ✛ ✜ ✝ ✞ ✟ ✠), flèches
        #     (→ ➡ ➤ ➢), ornements (✿ ❀ ❁ ❖ ❧)
        #
        # Exemples avec dingbats :
        #   "★ %page% / %total% ★"   → ★ 6 / 12 ★ (étoiles)
        #   "♥ %page% / %total% ♥"   → ♥ 6 / 12 ♥ (cœurs)
        #   "❖ %page% / %total% ❖"   → ❖ 6 / 12 ❖ (losanges)
        #   "✦ %page% / %total% ✦"   → ✦ 6 / 12 ✦ (étoiles 4-pts)
        #
        # Pour les caractères hors de tout cela (emojis, CJK,
        # dingbats Unicode non listés), substitués par "?" — il
        # faudrait embarquer une police TTF pour les rendre.

        DOC

      s << "numbering:\n"
      s << "  enabled: " << options.numbering_enabled << "            # désactive toute la numérotation si false\n"
      s << "\n"
      s << <<-GLOBAL
          # Numéro global (ex: "• 6 / 12 •" sur la 6e page d'un
          # livret de 12 pages utiles). Le total est utile : un
          # musicien qui tient une page seule sait combien de pages
          # restent. Les puces typographiques (• U+2022) ressortent
          # mieux que les tirets ASCII.
          global:
            enabled: true
            format: "#{options.global_format}"
            style: oval            # pastille gris pâle bordure fine
            position: bottom-right
            font_size: 13
            color: "#000000"
            margin: 24
            bold: false
            italic: false

          # ─── Numérotation intra-partition ─────────────────────────
          # Pour un recueil composé de plusieurs partitions (morceaux,
          # chants, fascicules…), affiche en plus de la numérotation
          # globale une marque "n / t" (ex: "2 / 4" sur la 2e page
          # d'une partition de 4 pages). Les tailles de partitions
          # sont auto-détectées : chaque fichier de la liste `files:`
          # = une partition. `hide_when_single: true` masque la
          # marque pour les partitions d'une seule page.
          partition:
            enabled: true
            format: "%page% / %total%"
            style: plain
            position: top-right
            font_size: 27           # gros pour être lu à 1m
            color: "#000000"
            margin: 24
            bold: true              # Helvetica-Bold
            italic: false
            hide_when_single: true

        GLOBAL

      build_section_header(s, options)

      s << "  skip_pages: []           # 1-based ; ex: [1] pour épargner\n\n"
    end

    private def build_section_header(s : IO, options : InitOptions) : Nil
      case options.header_state
      when :omitted
        # rien
      when :enabled
        s << <<-ENABLED
            # Header de partition (titre du fichier en haut de chaque
            # page de la partition). Source du texte : la clé `title`
            # de l'entrée dans `files:` (forme longue).
            header:
              enabled: true
              position: top-center
              font_size: 9
              color: "#888888"
              margin: 18

          ENABLED
      else
        # :default — section commentée
        s << <<-DEFAULT
            # Décommenter pour titrer chaque partition (texte = clé title
            # du fichier dans la liste `files:` ci-dessous).
            # header:
            #   enabled: true
            #   position: top-center
            #   font_size: 9
            #   color: "#888888"
            #   margin: 18

          DEFAULT
      end
    end

    private def build_section_toc(s : IO, options : InitOptions) : Nil
      case options.toc_state
      when :omitted
        # rien
      when :enabled
        s << <<-ENABLED
          # ─── Sommaire ─────────────────────────────────────────────────
          toc:
            bookmarks: true          # barre latérale du lecteur PDF
            # Page de titre + sommaire cliquable insérée en tête du livret.
            # Compte comme page de couverture supplémentaire (non numérotée
            # quand cover.include_in_numbering est false).
            page:
              enabled: true
              title: ""              # vide = utilise `title:` du document
              subtitle: "Sommaire"
              show_author: true      # affiche "par <auteur>" si défini
              leader_dots: true      # pointillés entre titre et numéro
              title_font_size: 24
              subtitle_font_size: 16
              entry_font_size: 11
              paper_size: ""         # vide = hérite de paper_size global

          ENABLED
      else
        # :default — section entièrement commentée
        s << <<-DEFAULT
          # ─── Sommaire ─────────────────────────────────────────────────
          # toc:
          #   bookmarks: true          # barre latérale du lecteur PDF (v1.0.31.4)
          #
          #   # Page de titre + sommaire cliquable insérée en tête du livret.
          #   # Compte comme page de couverture supplémentaire (non numérotée
          #   # quand cover.include_in_numbering est false).
          #   page:
          #     enabled: true
          #     title: ""              # vide = utilise `title:` du document
          #     subtitle: "Sommaire"
          #     show_author: true      # affiche "par <auteur>" si défini
          #     leader_dots: true      # pointillés entre titre et numéro
          #     title_font_size: 24
          #     subtitle_font_size: 16
          #     entry_font_size: 11
          #     paper_size: ""         # vide = hérite de paper_size global

          DEFAULT
      end
    end

    private def build_section_watermark(s : IO, options : InitOptions, folder_name : String) : Nil
      case options.watermark_state
      when :omitted
        # rien
      when :enabled
        text = options.watermark_text || folder_name
        s << <<-ENABLED
          # ─── Filigrane ────────────────────────────────────────────────
          watermark:
            text: "#{text}"
            style: diagonal          # diagonal | tiled | header | footer | center
            font_size: 48
            color: "#cccccc"
            opacity: 0.15
            rotation: 45

          ENABLED
      else
        # :default — section commentée avec le nom du dossier en placeholder
        s << <<-DEFAULT
          # ─── Filigrane ────────────────────────────────────────────────
          # watermark:
          #   text: "#{folder_name}"
          #   style: diagonal          # diagonal | tiled | header | footer | center
          #   font_size: 48
          #   color: "#cccccc"
          #   opacity: 0.15
          #   rotation: 45

          DEFAULT
      end
    end

    # Auteur par défaut : `git config user.name` ou chaîne vide.
    private def detect_author : String
      io = IO::Memory.new
      status = Process.run("git", ["config", "user.name"], output: io, error: Process::Redirect::Close)
      return "" unless status.success?
      io.to_s.strip
    rescue
      ""
    end

    # Cite la valeur YAML si elle contient des caractères qui
    # nécessitent un échappement (espace, deux-points, apostrophe…).
    def yaml_quote_if_needed(s : String) : String
      needs_quoting = s.includes?(' ') || s.includes?(':') ||
                      s.includes?('\'') || s.includes?('"') ||
                      s.starts_with?('#') || s.starts_with?('-') ||
                      s.starts_with?('?') || s.starts_with?('[') ||
                      s.starts_with?(']')
      return s unless needs_quoting

      # Préfère les guillemets doubles ; échappe les `"` et `\` à l'intérieur.
      escaped = s.gsub('\\', "\\\\").gsub('"', "\\\"")
      "\"#{escaped}\""
    end
  end
end
