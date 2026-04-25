module CombinePDF
  # The page-numbering engine.
  #
  # Reads the input PDF, walks every page, and appends a content
  # stream that draws:
  #
  # 1. The **global** page number in the bottom-right corner
  #    (format `Options#global_format`, e.g. `"3/12"`), unless the
  #    page index is in `Options#skip_pages`.
  #
  # 2. The **intra-partition** page number in the top-left corner
  #    (format `Options#partition_format`, e.g. `"2/4"`), only when
  #    the page belongs to a partition longer than one page (under
  #    the default `hide_partition_when_single: true`).
  #
  # Coordinates are expressed in the PDF user-space (origin
  # bottom-left, points), derived from each page's actual `MediaBox`
  # — so A4, Letter, A3 and any other page format render correctly
  # without any per-format flag.
  #
  # The watermark is implemented as a Type1 standard `Helvetica` text
  # block (`q … BT … ET … Q`) appended via
  # `PDF::ReaderPage#add_content_stream`. No font embedding, no
  # encoding pitfalls — only ASCII digits and `/`.
  class Numberer
    @options : Options
    # Sizes of the partitions, in 1-based page order. `nil` means
    # the whole booklet is a single partition (no intra-partition
    # numbering at all).
    @partitions : Array(Int32)?

    def initialize(@options : Options, @partitions : Array(Int32)? = nil)
    end

    # Reads `input`, applies the numbering on every page and writes
    # the result to `output`. Raises `ArgumentError` when the
    # partition sizes don't sum to the total page count.
    def apply(input : String, output : String) : Nil
      reader = PDF::Reader.open(input)
      total = reader.page_count

      if (parts = @partitions)
        sum = parts.sum
        if sum != total
          raise ArgumentError.new(
            "partitions sum (#{sum}) does not match the PDF page count (#{total})"
          )
        end
      end

      page_to_partition = build_page_to_partition_map(total)

      reader.pages.each_with_index do |page, idx|
        page_num = idx + 1 # 1-based
        next if @options.skip_pages.includes?(page_num)

        stream = build_page_stream(page.width, page.height, page_num, total, page_to_partition[idx]?)
        page.add_content_stream(stream) unless stream.empty?
      end

      reader.save(output)
    end

    # Returns an array indexed by 0-based page index, each entry a
    # `{partition_page, partition_total}` tuple — or `nil` when no
    # partition information was provided.
    private def build_page_to_partition_map(total : Int32) : Array(Tuple(Int32, Int32)?)
      result = Array(Tuple(Int32, Int32)?).new(total, nil)
      parts = @partitions
      return result unless parts
      idx = 0
      parts.each do |part_size|
        part_size.times do |i|
          result[idx] = {i + 1, part_size}
          idx += 1
        end
      end
      result
    end

    # Builds the PDF content stream that draws the global +
    # intra-partition numbers on a single page.
    private def build_page_stream(width : Float64,
                                  height : Float64,
                                  page_num : Int32,
                                  total : Int32,
                                  partition_info : Tuple(Int32, Int32)?) : String
      lines = [] of {Float64, Float64, String}

      # Global page number — bottom-right.
      global_text = format(@options.global_format, page_num, total)
      global_w = approx_text_width(global_text, @options.font_size)
      gx = width - @options.margin - global_w
      gy = @options.margin
      lines << {gx, gy, global_text}

      # Intra-partition number — top-left, only when meaningful.
      if pi = partition_info
        part_page, part_total = pi
        unless @options.hide_partition_when_single && part_total <= 1
          part_text = format(@options.partition_format, part_page, part_total)
          px = @options.margin
          py = height - @options.margin - @options.font_size
          lines << {px, py, part_text}
        end
      end

      return "" if lines.empty?

      r, g, b = @options.color
      String.build do |io|
        io << "q\n"
        io << format_number(r) << " " << format_number(g) << " " << format_number(b) << " rg\n"
        io << "BT\n"
        io << "/Helvetica " << format_number(@options.font_size) << " Tf\n"
        lines.each do |entry|
          x, y, text = entry
          io << format_number(x) << " " << format_number(y) << " Td\n"
          io << "(" << escape_pdf_string(text) << ") Tj\n"
          # Reset position for the next line (Td is incremental).
          io << format_number(-x) << " " << format_number(-y) << " Td\n"
        end
        io << "ET\n"
        io << "Q\n"
      end
    end

    # Substitutes `%page%` and `%total%` in a format string. Keeping
    # this manual (rather than using `String#%`) lets us accept
    # human-friendly tokens that survive accidental `%` characters
    # in the surrounding text.
    private def format(template : String, page : Int32, total : Int32) : String
      template.gsub("%page%", page.to_s).gsub("%total%", total.to_s)
    end

    # Cheap monospace-ish approximation of the rendered width, used
    # to right-align the global number. Helvetica digits are about
    # 0.5 em wide, plus a slash; good enough for the 24 pt margin
    # default.
    private def approx_text_width(text : String, font_size : Float64) : Float64
      text.size * font_size * 0.55
    end

    # PDF number formatter: trims trailing zeros, drops the decimal
    # point when the value is integral.
    private def format_number(n : Float64) : String
      if n == n.to_i64.to_f64
        n.to_i64.to_s
      else
        sprintf("%.4f", n).sub(/0+$/, "").sub(/\.$/, ".0")
      end
    end

    # Escape `(`, `)` and `\` in a PDF literal string. Page numbers
    # are pure ASCII digits + `/`, so no character set fuss is
    # needed beyond that.
    private def escape_pdf_string(text : String) : String
      text.gsub('\\', "\\\\").gsub('(', "\\(").gsub(')', "\\)")
    end
  end
end
