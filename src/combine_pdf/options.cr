module CombinePDF
  # User-facing options for the page-numbering pass.
  #
  # Defaults are chosen for the typical music-booklet use case:
  #   - global page numbers in the bottom-right corner, format "N/T"
  #     (where T is the total page count of the booklet)
  #   - intra-partition numbers in the top-left corner, format "n/t"
  #     (only when t > 1 — single-page partitions stay unmarked)
  #   - 10 pt Helvetica, plain black, no background box (subtle —
  #     does not visually compete with score notation)
  #
  # Coordinates are always derived from the actual page `MediaBox` so
  # that A4, Letter, A3 and any other format render correctly without
  # a manual flag.
  class Options
    # Font size of the rendered numbers, in points.
    property font_size : Float64
    # RGB colour, components 0.0-1.0 each.
    property color : Tuple(Float64, Float64, Float64)
    # Margin from the page edge, in points.
    property margin : Float64
    # Format string for the global (booklet-wide) page number.
    # Two placeholders are recognised: `%page%` (1-based current
    # page) and `%total%` (total number of pages).
    property global_format : String
    # Format string for the intra-partition page number. Recognised
    # placeholders: `%page%` (1-based page within the partition) and
    # `%total%` (number of pages in the partition).
    property partition_format : String
    # Skip rendering the intra-partition number when the partition
    # contains a single page (most useful default — unmarked pages
    # are obviously stand-alone).
    property hide_partition_when_single : Bool
    # Skip rendering the global page number on a specific list of
    # 1-based page indices (e.g. `[1]` to leave the cover page
    # untouched).
    property skip_pages : Array(Int32)

    def initialize(
      @font_size : Float64 = 10.0,
      @color : Tuple(Float64, Float64, Float64) = {0.2, 0.2, 0.2},
      @margin : Float64 = 24.0,
      @global_format : String = "%page%/%total%",
      @partition_format : String = "%page%/%total%",
      @hide_partition_when_single : Bool = true,
      @skip_pages : Array(Int32) = [] of Int32,
    )
    end
  end
end
