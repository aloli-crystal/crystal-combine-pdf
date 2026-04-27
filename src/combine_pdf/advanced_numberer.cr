module CombinePDF
  # Moteur de numérotation v1.0.31.2 — refonte de `Numberer` qui prend
  # une `Config` complète et gère :
  #
  # * positions cardinales (top/bottom × left/center/right)
  # * positions duplex-aware (outer/inner) qui alternent par parité
  # * cover (front + back) avec `include_in_numbering: false` qui
  #   décale le démarrage de la numérotation
  # * couches multiples (global + partition + header optionnel)
  # * styles visuels (`plain`, `badge` arrondi)
  # * `skip_pages` 1-based (s'ajoute aux pages cover)
  class AdvancedNumberer
    @config : Config
    @partitions : Array(Int32)
    @toc_pages : Int32

    # `toc_pages` = nombre de pages de TOC insérées en tête (0 ou 1).
    # Ces pages sont JAMAIS numérotées et n'ont pas d'info partition.
    def initialize(@config : Config, @partitions : Array(Int32), @toc_pages : Int32 = 0)
    end

    def apply(input : String, output : String) : Nil
      reader = ::PDF::Reader.open(input)
      total = reader.page_count

      sum = @partitions.sum + @toc_pages
      if sum != total
        raise ArgumentError.new(
          "partitions sum (#{@partitions.sum}) + toc_pages (#{@toc_pages}) does not match the PDF page count (#{total})"
        )
      end

      cover = @config.cover
      front = cover.front_pages
      back = cover.back_pages
      content_total = total - @toc_pages - front - back
      content_total = 0 if content_total < 0

      # Map 0-based page index → infos de partition (n_dans_partition, n_total_partition)
      # Décalé de toc_pages pour que la 1ère partition commence après la TOC.
      page_to_partition = build_page_to_partition_map(total)

      reader.pages.each_with_index do |page, idx|
        page_num_pdf = idx + 1 # 1-based

        # ─── Calcul du numéro affiché
        # Pages TOC : aucune numérotation, aucune partition.
        is_toc = idx < @toc_pages
        # Couvertures : APRÈS la TOC en tête, et AVANT la fin pour
        # le back cover.
        is_front_cover = !is_toc && idx < (@toc_pages + front)
        is_back_cover = idx >= (total - back)
        is_cover = is_front_cover || is_back_cover

        # Numéro global affiché
        if is_toc
          show_global = false
          displayed_global = 0
          displayed_total = content_total
        elsif @config.cover.include_in_numbering
          displayed_global = idx - @toc_pages + 1
          displayed_total = total - @toc_pages
          show_global = true
        else
          if is_cover
            show_global = false
            displayed_global = 0
            displayed_total = content_total
          else
            displayed_global = idx - @toc_pages - front + 1 # 1-based dans le contenu
            displayed_total = content_total
            show_global = true
          end
        end

        # Skip pages (1-based, basé sur la numérotation PDF brute)
        show_global = false if @config.numbering.skip_pages.includes?(page_num_pdf)

        # ─── Construction des couches
        layers = [] of Tuple(Float64, Float64, String, Config::Numbering::Layer, String)

        # Couche globale
        if @config.numbering.global.enabled && show_global
          text = format(@config.numbering.global.format, displayed_global, displayed_total)
          x, y = compute_xy(
            @config.numbering.global,
            page.width, page.height,
            text, page_num_pdf,
          )
          layers << {x, y, text, @config.numbering.global, "global"}
        end

        # Couche partition (jamais sur les pages TOC ni couvertures)
        if @config.numbering.partition.enabled && !is_cover && !is_toc
          if pi = page_to_partition[idx]?
            part_n, part_total = pi
            unless @config.numbering.partition.hide_when_single && part_total <= 1
              text = format(@config.numbering.partition.format, part_n, part_total)
              x, y = compute_xy(
                @config.numbering.partition,
                page.width, page.height,
                text, page_num_pdf,
              )
              layers << {x, y, text, @config.numbering.partition, "partition"}
            end
          end
        end

        # Header (TODO v1.0.31.3 — nécessite le titre par fichier)

        next if layers.empty?

        stream = build_stream(layers)
        page.add_content_stream(stream) unless stream.empty?
      end

      reader.save(output)
    end

    # Construit le mapping page index → {n_dans_partition, total_partition}.
    # Les `@toc_pages` premières pages sont nil (= pages TOC, hors
    # logique partition).
    private def build_page_to_partition_map(total : Int32) : Array(Tuple(Int32, Int32)?)
      result = Array(Tuple(Int32, Int32)?).new(total, nil)
      idx = @toc_pages
      @partitions.each do |part_size|
        part_size.times do |i|
          result[idx] = {i + 1, part_size}
          idx += 1
        end
      end
      result
    end

    # Calcule (x, y) en points pour une couche, en tenant compte de
    # la position (cardinale ou duplex-aware) et du sens du livret.
    private def compute_xy(
      layer : Config::Numbering::Layer,
      width : Float64, height : Float64,
      text : String, page_num_pdf : Int32,
    ) : Tuple(Float64, Float64)
      # Résolution outer/inner → left/right selon parité de page
      resolved = resolve_position(layer.position, page_num_pdf)
      v, h = parse_vh(resolved)

      text_w = approx_text_width(text, layer.font_size)

      x = case h
          when "left"   then layer.margin
          when "center" then (width - text_w) / 2
          when "right"  then width - layer.margin - text_w
          else               width - layer.margin - text_w
          end

      y = case v
          when "top"    then height - layer.margin - layer.font_size
          when "bottom" then layer.margin
          else               layer.margin
          end

      {x, y}
    end

    # Résout outer-* / inner-* en position cardinale concrète.
    # Page impaire (recto) : outer = right, inner = left.
    # Page paire (verso)   : outer = left,  inner = right.
    # Si duplex: false → outer ≡ right, inner ≡ left (toujours).
    private def resolve_position(position : String, page_num_pdf : Int32) : String
      return position unless position.starts_with?("outer-") || position.starts_with?("inner-")
      vertical = position.split("-").last # "top" ou "bottom"
      side =
        if @config.duplex
          is_recto = page_num_pdf.odd?
          if position.starts_with?("outer-")
            is_recto ? "right" : "left"
          else
            is_recto ? "left" : "right"
          end
        else
          position.starts_with?("outer-") ? "right" : "left"
        end
      "#{vertical}-#{side}"
    end

    # Décompose "top-right" en {"top", "right"}.
    private def parse_vh(position : String) : Tuple(String, String)
      parts = position.split("-")
      return {parts[0], parts[1]} if parts.size == 2
      {"bottom", "right"}
    end

    private def format(template : String, page : Int32, total : Int32) : String
      template.gsub("%page%", page.to_s).gsub("%total%", total.to_s)
    end

    private def approx_text_width(text : String, font_size : Float64) : Float64
      text.size * font_size * 0.55
    end

    # Génère le content stream PDF pour toutes les couches d'une page.
    # Style "badge" = dessine un cadre arrondi gris pâle derrière.
    private def build_stream(layers : Array(Tuple(Float64, Float64, String, Config::Numbering::Layer, String))) : String
      String.build do |io|
        io << "q\n"
        layers.each do |entry|
          x, y, text, layer, _kind = entry
          render_layer(io, x, y, text, layer)
        end
        io << "Q\n"
      end
    end

    private def render_layer(io : IO, x : Float64, y : Float64, text : String, layer : Config::Numbering::Layer) : Nil
      text_w = approx_text_width(text, layer.font_size)

      # Style badge : cadre arrondi gris très pâle derrière
      if layer.style == "badge" || layer.style == "circle" ||
         layer.style == "square" || layer.style == "oval"
        pad_x = layer.font_size * 0.6
        pad_y = layer.font_size * 0.3
        rx = x - pad_x
        ry = y - pad_y
        rw = text_w + 2 * pad_x
        rh = layer.font_size + 2 * pad_y
        radius = case layer.style
                 when "square" then 0.0
                 when "circle" then [rw, rh].min / 2
                 when "oval"   then [rw, rh].min / 2
                 else               rh / 3 # badge
                 end
        draw_rounded_rect(io, rx, ry, rw, rh, radius)
      end

      r, g, b = layer.color
      io << "BT\n"
      io << format_number(r) << " " << format_number(g) << " " << format_number(b) << " rg\n"
      io << "/Helvetica " << format_number(layer.font_size) << " Tf\n"
      io << format_number(x) << " " << format_number(y) << " Td\n"
      io << "(" << escape_pdf_string(text) << ") Tj\n"
      io << "ET\n"
    end

    # Trace un rectangle arrondi (ou un cercle/oval si rayon = min/2).
    # Approximation Bézier classique pour les coins arrondis.
    private def draw_rounded_rect(io : IO, x : Float64, y : Float64, w : Float64, h : Float64, r : Float64) : Nil
      r = [r, w / 2, h / 2].min
      # Couleur de remplissage très pâle, grise, pour discret
      io << "0.92 0.92 0.92 rg\n"
      io << "0.7 0.7 0.7 RG\n"
      io << "0.5 w\n"

      if r <= 0.001
        # Rectangle simple
        io << format_number(x) << " " << format_number(y) << " "
        io << format_number(w) << " " << format_number(h) << " re\n"
      else
        # Path arrondi (4 quadrants Bézier)
        c = r * 0.5523 # constante magique d'approximation circulaire
        x2 = x + w
        y2 = y + h
        # Démarre coin bas-gauche post-arrondi
        io << format_number(x + r) << " " << format_number(y) << " m\n"
        io << format_number(x2 - r) << " " << format_number(y) << " l\n"
        io << format_number(x2 - r + c) << " " << format_number(y) << " "
        io << format_number(x2) << " " << format_number(y + r - c) << " "
        io << format_number(x2) << " " << format_number(y + r) << " c\n"
        io << format_number(x2) << " " << format_number(y2 - r) << " l\n"
        io << format_number(x2) << " " << format_number(y2 - r + c) << " "
        io << format_number(x2 - r + c) << " " << format_number(y2) << " "
        io << format_number(x2 - r) << " " << format_number(y2) << " c\n"
        io << format_number(x + r) << " " << format_number(y2) << " l\n"
        io << format_number(x + r - c) << " " << format_number(y2) << " "
        io << format_number(x) << " " << format_number(y2 - r + c) << " "
        io << format_number(x) << " " << format_number(y2 - r) << " c\n"
        io << format_number(x) << " " << format_number(y + r) << " l\n"
        io << format_number(x) << " " << format_number(y + r - c) << " "
        io << format_number(x + r - c) << " " << format_number(y) << " "
        io << format_number(x + r) << " " << format_number(y) << " c\n"
      end
      io << "B\n" # Fill + Stroke
    end

    private def format_number(n : Float64) : String
      if n == n.to_i64.to_f64
        n.to_i64.to_s
      else
        sprintf("%.4f", n).sub(/0+$/, "").sub(/\.$/, ".0")
      end
    end

    private def escape_pdf_string(text : String) : String
      text.gsub('\\', "\\\\").gsub('(', "\\(").gsub(')', "\\)")
    end
  end
end
