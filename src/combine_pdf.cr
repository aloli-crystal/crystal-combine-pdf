require "crystal-pdf/src/pdf"
require "crystal-watermark/src/crystal_watermark"

require "./combine_pdf/version"
require "./combine_pdf/options"
require "./combine_pdf/numberer"
require "./combine_pdf/merged_document_writer"
require "./combine_pdf/merger"
require "./combine_pdf/pdf"
require "./combine_pdf/config"
require "./combine_pdf/config_loader"
require "./combine_pdf/winansi"
require "./combine_pdf/config_initializer"
require "./combine_pdf/config_refresher"
require "./combine_pdf/advanced_numberer"
require "./combine_pdf/toc_builder"
require "./combine_pdf/booklet_builder"

# CombinePDF — PDF post-processing in pure Crystal.
#
# Three operations are exposed as of v0.2 :
#
# * `CombinePDF.merge`  — concatenate several PDFs into one
# * `CombinePDF.number` — add page numbers to an assembled PDF
# * `CombinePDF.assemble` — merge + number in one shot
#                            (the booklet-of-partitions use case)
#
# ```
# require "crystal-combine-pdf"
#
# # Merge three partitions into one PDF.
# CombinePDF.merge(
#   inputs: ["partition1.pdf", "partition2.pdf", "partition3.pdf"],
#   output: "livret.pdf",
# )
#
# # Number the pages of an existing PDF with the global "N/T"
# # format in the bottom-right corner. A4-aware (reads each page's
# # actual MediaBox).
# CombinePDF.number(
#   input: "livret.pdf",
#   output: "livret-numeroted.pdf",
# )
#
# # Mark intra-partition pages too: pages 1-4 belong to partition 1
# # (4 pages → "1/4" through "4/4" top-left), pages 5-6 to partition
# # 2 ("1/2", "2/2"), page 7 to partition 3 (1 page → no
# # intra-partition mark by default).
# CombinePDF.number(
#   input: "livret.pdf",
#   output: "livret-numeroted.pdf",
#   partitions: [4, 2, 1],
# )
#
# # End-to-end booklet assembly: merge N partitions, then number
# # everything with intra-partition marks derived automatically
# # from the input page counts. This is the typical workflow for
# # a music score booklet.
# CombinePDF.assemble(
#   inputs: ["partition1.pdf", "partition2.pdf", "partition3.pdf"],
#   output: "livret.pdf",
# )
# ```
module CombinePDF
  # ─────────────────────────────────────────────────────────────────
  # ISO-compatible module entry points
  #
  # These mirror the Ruby gem `combine_pdf` v1.0.31 module API so
  # examples from the upstream README work verbatim :
  #
  # ```
  # pdf = CombinePDF.new
  # pdf << CombinePDF.load("a.pdf")
  # pdf << CombinePDF.load("b.pdf")
  # pdf.save("merged.pdf")
  # ```
  # ─────────────────────────────────────────────────────────────────

  # Returns a fresh, empty `PDF` ready to receive pages.
  # Equivalent to `CombinePDF.new` in Ruby.
  def self.new : PDF
    PDF.new
  end

  # Loads a PDF file and returns it as a `PDF` instance.
  # Equivalent to `CombinePDF.load(path)` in Ruby.
  def self.load(path : String) : PDF
    PDF.from_file(path)
  end

  # Parses raw PDF bytes (or a binary string) into a `PDF` instance.
  # Equivalent to `CombinePDF.parse(data)` in Ruby.
  def self.parse(data : Bytes | String) : PDF
    PDF.from_data(data)
  end

  # ─────────────────────────────────────────────────────────────────
  # Crystal-specific functional helpers (kept as bonuses)
  # ─────────────────────────────────────────────────────────────────

  # Concatenates `inputs` into a single PDF written to `output`.
  # Pages are taken in the input order. Object IDs are renumbered
  # to avoid collisions between sources.
  def self.merge(inputs : Array(String), output : String) : Nil
    Merger.merge(inputs, output)
  end

  # Numbers the pages of `input` and writes the result to `output`.
  # See `Numberer` for the full set of options.
  def self.number(input : String,
                  output : String,
                  partitions : Array(Int32)? = nil,
                  options : Options = Options.new) : Nil
    Numberer.new(options, partitions).apply(input, output)
  end

  # End-to-end booklet assembly: merge `inputs` into a single PDF,
  # then add global page numbers in the bottom-right corner and
  # intra-partition numbers in the top-left corner (the partition
  # sizes are derived automatically from the input page counts —
  # each input file = one partition).
  #
  # Equivalent to calling `merge` then `number(partitions: ...)`
  # but with auto-detected partitions and a single temp file.
  def self.assemble(inputs : Array(String),
                    output : String,
                    options : Options = Options.new) : Nil
    # Auto-detect partition sizes by counting pages in each input.
    partitions = inputs.map { |path| ::PDF::Reader.open(path).page_count }

    # Merge into a temp file, then number into the final output.
    tmp = File.tempname("ccp-assemble", ".pdf")
    begin
      merge(inputs, tmp)
      number(input: tmp, output: output, partitions: partitions, options: options)
    ensure
      File.delete(tmp) if File.exists?(tmp)
    end
  end
end
