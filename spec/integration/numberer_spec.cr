require "../spec_helper"

# End-to-end numbering: generate fresh A4 / Letter PDFs with
# `crystal-pdf`, run the Numberer, and re-parse the output through
# `PDF::Reader.open` to confirm the page count and MediaBox survive
# the incremental update.
#
# crystal-pdf v0.3.4+ correctly re-reads the incremental update
# format that `add_content_stream` produces, so the assertions go
# through the real reader (no more byte-level workarounds).
describe CombinePDF::Numberer do
  it "appends a numbered content stream on every page (A4)" do
    src = File.join(SpecHelper::TMP_DIR, "src-a4.pdf")
    dst = File.join(SpecHelper::TMP_DIR, "out-a4.pdf")
    SpecHelper.write_a4(src, page_count: 3)
    original_dims = SpecHelper.page_size(src, 0)

    CombinePDF.number(input: src, output: dst)

    File.exists?(dst).should be_true
    File.size(dst).should be > File.size(src)
    # Page count and geometry are preserved.
    SpecHelper.page_count(dst).should eq(3)
    SpecHelper.page_size(dst, 0).should eq(original_dims)
    SpecHelper.page_size(dst, 1).should eq(original_dims)
    SpecHelper.page_size(dst, 2).should eq(original_dims)
  end

  it "honours the actual MediaBox on US Letter pages (no A4 hardcode)" do
    src = File.join(SpecHelper::TMP_DIR, "src-letter.pdf")
    dst = File.join(SpecHelper::TMP_DIR, "out-letter.pdf")
    SpecHelper.write_letter(src)

    # Confirm the source is really US Letter, not A4.
    src_w, src_h = SpecHelper.page_size(src, 0)
    ((src_w - 612).abs).should be < 1.0
    ((src_h - 792).abs).should be < 1.0

    CombinePDF.number(input: src, output: dst)

    # Output keeps the same Letter geometry — and is *not* A4.
    out_w, out_h = SpecHelper.page_size(dst, 0)
    out_w.should eq(src_w)
    out_h.should eq(src_h)
    ((out_w - 595).abs).should be > 1.0 # not A4 width
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
    SpecHelper.page_count(dst).should eq(7)
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

    # Both outputs re-parse cleanly with the original page count…
    SpecHelper.page_count(dst_with).should eq(3)
    SpecHelper.page_count(dst_skip).should eq(3)
    # …and skipping a page produces a smaller output.
    File.size(dst_skip).should be < File.size(dst_with)
  end
end
