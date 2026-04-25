require "../spec_helper"

# End-to-end numbering: generate fresh A4 / Letter PDFs with
# crystal-pdf, run the Numberer, and assert byte-level properties on
# the output. We do not rely on `PDF::Reader.open` for the output
# (crystal-pdf v0.3.3 does not yet handle the incremental update
# format that `add_content_stream` produces).
describe CombinePDF::Numberer do
  it "appends a numbered content stream on every page (A4)" do
    src = File.join(SpecHelper::TMP_DIR, "src-a4.pdf")
    dst = File.join(SpecHelper::TMP_DIR, "out-a4.pdf")
    SpecHelper.write_a4(src, page_count: 3)

    CombinePDF.number(input: src, output: dst)

    File.exists?(dst).should be_true
    File.size(dst).should be > File.size(src)
    File.read(dst).rstrip.should end_with("%%EOF")
    # Three new content streams (one per page) → strictly more `endobj`
    # markers than in the source.
    new_objs = SpecHelper.count_byte_pattern(dst, "endobj") -
               SpecHelper.count_byte_pattern(src, "endobj")
    new_objs.should be >= 3
  end

  it "honours the actual MediaBox on US Letter pages (no A4 hardcode)" do
    src = File.join(SpecHelper::TMP_DIR, "src-letter.pdf")
    dst = File.join(SpecHelper::TMP_DIR, "out-letter.pdf")
    SpecHelper.write_letter(src)

    CombinePDF.number(input: src, output: dst)

    # MediaBox of US Letter (612 × 792 pt) is preserved verbatim.
    SpecHelper.count_byte_pattern(dst, "/MediaBox [0 0 612 792]").should be > 0
    # And no A4 MediaBox `[0 0 595 842]` snuck in — that would be
    # the regression we're guarding against.
    SpecHelper.count_byte_pattern(dst, "/MediaBox [0 0 595 842]").should eq(0)
  end

  it "raises ArgumentError when partition sizes don't sum to total pages" do
    src = File.join(SpecHelper::TMP_DIR, "src-partition-bad.pdf")
    dst = File.join(SpecHelper::TMP_DIR, "out-partition-bad.pdf")
    SpecHelper.write_a4(src, page_count: 5)

    expect_raises(ArgumentError, /partitions sum/) do
      CombinePDF.number(input: src, output: dst, partitions: [3, 1])
    end
  end

  it "accepts well-sized partition sizes and writes the output" do
    src = File.join(SpecHelper::TMP_DIR, "src-partition-ok.pdf")
    dst = File.join(SpecHelper::TMP_DIR, "out-partition-ok.pdf")
    # 7-page booklet split as 4 + 2 + 1.
    SpecHelper.write_a4(src, page_count: 7)

    CombinePDF.number(input: src, output: dst, partitions: [4, 2, 1])

    File.exists?(dst).should be_true
    # Each page got a numbered stream (the third partition has only
    # one page so it does NOT get an intra-partition mark, but the
    # global number is still rendered).
    new_objs = SpecHelper.count_byte_pattern(dst, "endobj") -
               SpecHelper.count_byte_pattern(src, "endobj")
    new_objs.should be >= 7
  end

  it "skips pages listed in skip_pages" do
    src = File.join(SpecHelper::TMP_DIR, "src-skip.pdf")
    dst_with = File.join(SpecHelper::TMP_DIR, "out-skip-with.pdf")
    dst_skip = File.join(SpecHelper::TMP_DIR, "out-skip-without.pdf")
    SpecHelper.write_a4(src, page_count: 3)

    # Reference run: every page is numbered.
    CombinePDF.number(input: src, output: dst_with)
    # Skipped run: page 1 is not numbered (cover page case).
    CombinePDF.number(
      input: src,
      output: dst_skip,
      options: CombinePDF::Options.new(skip_pages: [1]),
    )

    # Skipping a page must produce a smaller output.
    File.size(dst_skip).should be < File.size(dst_with)
  end
end
