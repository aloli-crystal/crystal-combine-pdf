require "crystal-pdf/src/pdf"

require "./combine_pdf/version"
require "./combine_pdf/options"
require "./combine_pdf/numberer"

# CombinePDF — PDF post-processing in pure Crystal.
#
# Currently focused on **page numbering** of an already-assembled PDF
# (booklet of musical scores, course handouts, …) — the gap left by
# `combine_pdf.number_pages` from the Ruby gem, which hardcodes US
# Letter coordinates and does not understand multi-page partitions.
#
# Multi-PDF merging is planned for v0.2.
#
# ```
# require "crystal-combine-pdf"
#
# # Number the pages of a single assembled PDF, with the format
# # "N/T" in the bottom-right corner. Coordinates derived from the
# # actual MediaBox of each page (no A4-vs-Letter mismatch).
# CombinePDF.number(
#   input: "booklet.pdf",
#   output: "booklet-numbered.pdf",
# )
#
# # Same, but mark intra-partition pages too: pages 1-4 belong to
# # partition 1 (4 pages → marked "1/4" through "4/4" top-left), pages
# # 5-6 to partition 2 (2 pages → "1/2", "2/2"), pages 7-7 to
# # partition 3 (1 page → no intra-partition mark).
# CombinePDF.number(
#   input: "booklet.pdf",
#   output: "booklet-numbered.pdf",
#   partitions: [4, 2, 1],
# )
# ```
module CombinePDF
  # Convenience: numbers the pages of `input` and writes the result to
  # `output`. See `Numberer` for the full set of options.
  def self.number(input : String,
                  output : String,
                  partitions : Array(Int32)? = nil,
                  options : Options = Options.new) : Nil
    Numberer.new(options, partitions).apply(input, output)
  end
end
