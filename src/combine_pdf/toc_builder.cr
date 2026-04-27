module CombinePDF
  # Génère la page de titre + sommaire cliquable insérée en tête
  # du livret.
  #
  # Sortie : un content stream PDF + une liste de dictionnaires
  # `Annot` (sous-type `Link`) qui pointent vers les pages cibles.
  # Le `Merger` se charge ensuite d'allouer les IDs d'objet et
  # d'attacher la page TOC en première position de l'arbre `/Pages`.
  #
  # ## Format de page
  #
  # A4 portrait (595 × 842 pt). Marges 72 pt. Layout :
  # ```
  # ┌─────────────────────────────────────┐
  # │                                     │
  # │            <Title>                  │   24 pt, gras, centré
  # │                                     │
  # │           <Subtitle>                │   16 pt, italique, centré
  # │                                     │
  # │           par <Author>              │   11 pt, italique, centré
  # │                                     │
  # │   1. Couverture ............... 1   │   11 pt, justifié
  # │   2. Si le Père vous appelle .. 3   │
  # │   3. Notre Père ............... 7   │
  # │      …                              │
  # │                                     │
  # └─────────────────────────────────────┘
  # ```
  #
  # ## Limitations v1.0.31.4
  #
  # * Une seule page (déborde si trop d'entrées — la liste est
  #   tronquée). Une future version paginera.
  # * Police Helvetica (Type1 standard, pas d'embedding) → seuls
  #   les caractères WinAnsi rendent ; les autres tomberont sur
  #   le glyphe `?` ou seront mangés selon le viewer.
  # * Annotations Link sans bordure, action GoTo simple.
  class TocBuilder
    # Format A4 par défaut. Le merger n'impose pas de format
    # particulier — un livret peut mélanger A4 et Letter — mais
    # la TOC est toujours générée en A4 pour être lisible quel que
    # soit le contenu.
    PAGE_WIDTH    = 595.0
    PAGE_HEIGHT   = 842.0
    MARGIN        =  72.0
    LINE_GAP      =   4.0 # espacement vertical entre lignes
    BLOCK_GAP     =  18.0 # espacement entre blocs (titre/sous-titre/liste)
    NUM_COL_WIDTH =  30.0 # largeur réservée pour les numéros de page

    # Une entrée du sommaire : titre affiché + numéro de page +
    # référence à la page cible (sera remappée par le merger).
    record Entry,
      title : String,
      page_number : Int32,
      target_page_ref : ::PDF::Objects::Reference

    @config : Config
    @entries : Array(Entry)

    def initialize(@config : Config, @entries : Array(Entry))
    end

    # Renvoie `{content_stream, annotations}`.
    #
    # `content_stream` : la chaîne d'opérateurs PDF à mettre dans
    # le `/Contents` de la page.
    # `annotations` : un dictionnaire par entrée TOC, à mettre dans
    # le `/Annots` de la page (le merger se charge des IDs).
    def build : Tuple(String, Array(::PDF::Objects::Dictionary))
      page = @config.toc.try(&.page)
      raise "TocBuilder appelé sans config.toc.page" unless page

      annotations = [] of ::PDF::Objects::Dictionary

      content = String.build do |io|
        io << "q\n"

        # Cursor vertical, descendant depuis le haut de la page.
        y = PAGE_HEIGHT - MARGIN

        # ─── Titre ─────────────────────────────────────────────
        title = page.title.empty? ? @config.title : page.title
        if !title.empty?
          y -= page.title_font_size
          draw_centered(io, title, y, page.title_font_size, "Helvetica-Bold")
          y -= BLOCK_GAP
        end

        # ─── Sous-titre ────────────────────────────────────────
        unless page.subtitle.empty?
          y -= page.subtitle_font_size
          draw_centered(io, page.subtitle, y, page.subtitle_font_size, "Helvetica-Oblique")
          y -= BLOCK_GAP
        end

        # ─── Auteur ────────────────────────────────────────────
        if page.show_author && !@config.author.empty?
          y -= page.entry_font_size
          draw_centered(io, "par #{@config.author}", y, page.entry_font_size, "Helvetica-Oblique")
          y -= BLOCK_GAP * 1.5
        end

        # ─── Liste des entrées ─────────────────────────────────
        max_lines = ((y - MARGIN) / (page.entry_font_size + LINE_GAP)).to_i
        @entries.first(max_lines).each_with_index do |entry, idx|
          line_top = y
          line_baseline = y - page.entry_font_size

          render_entry(io, entry, idx + 1, line_baseline, page)

          # Annotation Link sur toute la largeur de la ligne
          rect_x1 = MARGIN
          rect_y1 = line_baseline - 2.0
          rect_x2 = PAGE_WIDTH - MARGIN
          rect_y2 = line_top + 2.0
          annotations << build_link_annotation(
            rect_x1, rect_y1, rect_x2, rect_y2,
            entry.target_page_ref,
          )

          y = line_baseline - LINE_GAP
        end

        io << "Q\n"
      end

      {content, annotations}
    end

    # Centre un texte horizontalement à la `y` baseline donnée.
    private def draw_centered(io : IO, text : String, y : Float64, size : Float64, font : String) : Nil
      width = approx_text_width(text, size, font)
      x = (PAGE_WIDTH - width) / 2.0
      io << "BT\n"
      io << "0 0 0 rg\n"
      io << "/" << font_short(font) << " " << format_number(size) << " Tf\n"
      io << format_number(x) << " " << format_number(y) << " Td\n"
      io << '('
      write_winansi(io, text)
      io << ") Tj\n"
      io << "ET\n"
    end

    # Trace une ligne d'entrée TOC : numéro + titre + leader dots
    # (optionnels) + numéro de page (aligné à droite).
    private def render_entry(io : IO, entry : Entry, idx : Int32,
                             y : Float64, page : Config::Toc::Page) : Nil
      size = page.entry_font_size
      prefix = "#{idx}. "
      title_text = "#{prefix}#{entry.title}"
      page_text = entry.page_number.to_s

      title_width = approx_text_width(title_text, size, "Helvetica")
      page_width = approx_text_width(page_text, size, "Helvetica")

      x_title = MARGIN
      x_page = PAGE_WIDTH - MARGIN - page_width
      dots_start = x_title + title_width + 4.0
      dots_end = x_page - 4.0

      # Texte (titre et numéro)
      io << "BT\n"
      io << "0 0 0 rg\n"
      io << "/F1 " << format_number(size) << " Tf\n"
      io << format_number(x_title) << " " << format_number(y) << " Td\n"
      io << '('
      write_winansi(io, title_text)
      io << ") Tj\n"
      io << "ET\n"
      io << "BT\n"
      io << "/F1 " << format_number(size) << " Tf\n"
      io << format_number(x_page) << " " << format_number(y) << " Td\n"
      io << '('
      write_winansi(io, page_text)
      io << ") Tj\n"
      io << "ET\n"

      # Pointillés
      if page.leader_dots && dots_end > dots_start
        dot_size = size * 0.6
        # Approximation : un point tous les 3 pt
        spacing = 3.0
        n_dots = ((dots_end - dots_start) / spacing).to_i
        next_x = dots_start
        io << "BT\n"
        io << "0.6 0.6 0.6 rg\n"
        io << "/F1 " << format_number(dot_size) << " Tf\n"
        io << format_number(next_x) << " " << format_number(y) << " Td\n"
        dots_str = ("." * n_dots)
        io << "(" << dots_str << ") Tj\n"
        io << "ET\n"
      end
    end

    # Construit l'annotation Link pour une entrée du sommaire.
    private def build_link_annotation(x1 : Float64, y1 : Float64,
                                      x2 : Float64, y2 : Float64,
                                      target : ::PDF::Objects::Reference) : ::PDF::Objects::Dictionary
      annot = ::PDF::Objects::Dictionary.new
      annot["Type"] = ::PDF::Objects::Name.new("Annot")
      annot["Subtype"] = ::PDF::Objects::Name.new("Link")

      rect = ::PDF::Objects::Array.new
      rect << ::PDF::Objects::Number.new(x1)
      rect << ::PDF::Objects::Number.new(y1)
      rect << ::PDF::Objects::Number.new(x2)
      rect << ::PDF::Objects::Number.new(y2)
      annot["Rect"] = rect

      # Pas de bordure visible
      border = ::PDF::Objects::Array.new
      border << ::PDF::Objects::Number.new(0_i64)
      border << ::PDF::Objects::Number.new(0_i64)
      border << ::PDF::Objects::Number.new(0_i64)
      annot["Border"] = border

      # Destination : [page_ref /XYZ null null null]
      # null = préserve la position et le zoom courants
      dest = ::PDF::Objects::Array.new
      dest << target
      dest << ::PDF::Objects::Name.new("XYZ")
      dest << ::PDF::Objects::Null.instance
      dest << ::PDF::Objects::Null.instance
      dest << ::PDF::Objects::Null.instance
      annot["Dest"] = dest

      annot
    end

    # Approximation paresseuse de la largeur en points de `text` à
    # une taille `size` donnée. Bon pour Helvetica plain ; les
    # variants Bold/Oblique suivent les mêmes proportions à 5 % près.
    private def approx_text_width(text : String, size : Float64, font : String) : Float64
      ratio = font.includes?("Bold") ? 0.58 : 0.55
      text.size * size * ratio
    end

    # Mappe les noms longs sur les noms courts utilisés dans
    # `/Resources /Font` (cf. `Merger#insert_toc_page`).
    private def font_short(name : String) : String
      case name
      when "Helvetica"         then "F1"
      when "Helvetica-Bold"    then "F2"
      when "Helvetica-Oblique" then "F3"
      else                          "F1"
      end
    end

    private def format_number(n : Float64) : String
      if n == n.to_i64.to_f64
        n.to_i64.to_s
      else
        sprintf("%.4f", n).sub(/0+$/, "").sub(/\.$/, ".0")
      end
    end

    # Écrit `text` (UTF-8 Crystal) sur `io` en encodage WinAnsi
    # (Windows-1252) avec échappement PDF des caractères réservés
    # `\\`, `(`, `)`. Les caractères Latin-1 (U+00A0 à U+00FF) sont
    # encodés directement sur leur byte unique. Les caractères
    # typographiques courants (apostrophes, guillemets, tirets, …)
    # sont mappés sur leurs positions WinAnsi 0x80-0x9F. Tout autre
    # caractère hors WinAnsi est remplacé par `?`.
    #
    # Les fonts utilisées par la TOC sont les Type1 standards
    # `Helvetica` / `Helvetica-Bold` / `Helvetica-Oblique` avec
    # `/Encoding /WinAnsiEncoding` (cf. `Merger#insert_toc_page`),
    # donc cette routine produit des octets que le viewer rendra
    # correctement.
    private def write_winansi(io : IO, text : String) : Nil
      text.each_char do |ch|
        cp = ch.ord
        case cp
        when 0x5C then io.write_byte(0x5C_u8); io.write_byte(0x5C_u8) # `\` → `\\`
        when 0x28 then io.write_byte(0x5C_u8); io.write_byte(0x28_u8) # `(` → `\(`
        when 0x29 then io.write_byte(0x5C_u8); io.write_byte(0x29_u8) # `)` → `\)`
        when 0x00..0x7F
          io.write_byte(cp.to_u8)
        when 0xA0..0xFF
          # Latin-1 supplément = WinAnsi direct
          io.write_byte(cp.to_u8)
        when 0x20AC then io.write_byte(0x80_u8) # €
        when 0x201A then io.write_byte(0x82_u8) # ‚
        when 0x0192 then io.write_byte(0x83_u8) # ƒ
        when 0x201E then io.write_byte(0x84_u8) # „
        when 0x2026 then io.write_byte(0x85_u8) # …
        when 0x2020 then io.write_byte(0x86_u8) # †
        when 0x2021 then io.write_byte(0x87_u8) # ‡
        when 0x02C6 then io.write_byte(0x88_u8) # ˆ
        when 0x2030 then io.write_byte(0x89_u8) # ‰
        when 0x0160 then io.write_byte(0x8A_u8) # Š
        when 0x2039 then io.write_byte(0x8B_u8) # ‹
        when 0x0152 then io.write_byte(0x8C_u8) # Œ
        when 0x017D then io.write_byte(0x8E_u8) # Ž
        when 0x2018 then io.write_byte(0x91_u8) # '
        when 0x2019 then io.write_byte(0x92_u8) # '
        when 0x201C then io.write_byte(0x93_u8) # "
        when 0x201D then io.write_byte(0x94_u8) # "
        when 0x2022 then io.write_byte(0x95_u8) # •
        when 0x2013 then io.write_byte(0x96_u8) # –
        when 0x2014 then io.write_byte(0x97_u8) # —
        when 0x02DC then io.write_byte(0x98_u8) # ˜
        when 0x2122 then io.write_byte(0x99_u8) # ™
        when 0x0161 then io.write_byte(0x9A_u8) # š
        when 0x203A then io.write_byte(0x9B_u8) # ›
        when 0x0153 then io.write_byte(0x9C_u8) # œ
        when 0x017E then io.write_byte(0x9E_u8) # ž
        when 0x0178 then io.write_byte(0x9F_u8) # Ÿ
        else
          io.write_byte('?'.ord.to_u8)
        end
      end
    end
  end
end
