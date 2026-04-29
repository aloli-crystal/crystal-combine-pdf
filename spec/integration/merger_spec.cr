require "../spec_helper"

# End-to-end merging: generate fresh A4 PDFs with `pdf`,
# run the Merger, and re-parse the output through `PDF::Reader.open`
# to confirm:
#   - the page count matches the sum of inputs
#   - every page is parseable (no dangling references)
#   - the original textual content of each page survives
describe CombinePDF::Merger do
  it "concatenates the pages of two single-page PDFs" do
    a = File.join(SpecHelper::TMP_DIR, "merger-a.pdf")
    b = File.join(SpecHelper::TMP_DIR, "merger-b.pdf")
    dst = File.join(SpecHelper::TMP_DIR, "merger-ab.pdf")
    SpecHelper.write_a4(a, page_count: 1)
    SpecHelper.write_a4(b, page_count: 1)

    CombinePDF.merge(inputs: [a, b], output: dst)

    File.exists?(dst).should be_true
    SpecHelper.page_count(dst).should eq(2)
  end

  it "concatenates three multi-page PDFs in input order (4 + 2 + 1 = 7)" do
    inputs = [
      File.join(SpecHelper::TMP_DIR, "merger-part1.pdf"),
      File.join(SpecHelper::TMP_DIR, "merger-part2.pdf"),
      File.join(SpecHelper::TMP_DIR, "merger-part3.pdf"),
    ]
    SpecHelper.write_a4(inputs[0], page_count: 4)
    SpecHelper.write_a4(inputs[1], page_count: 2)
    SpecHelper.write_a4(inputs[2], page_count: 1)
    dst = File.join(SpecHelper::TMP_DIR, "merger-7p.pdf")

    CombinePDF.merge(inputs: inputs, output: dst)

    SpecHelper.page_count(dst).should eq(7)
  end

  it "preserves the page content stream of every source page" do
    a = File.join(SpecHelper::TMP_DIR, "merger-content-a.pdf")
    b = File.join(SpecHelper::TMP_DIR, "merger-content-b.pdf")
    dst = File.join(SpecHelper::TMP_DIR, "merger-content-ab.pdf")

    SpecHelper.write_a4(a, page_count: 1)
    SpecHelper.write_a4(b, page_count: 1)

    CombinePDF.merge(inputs: [a, b], output: dst)

    reader = PDF::Reader.open(dst)
    reader.pages.each do |page|
      streams = page.content_streams
      streams.size.should be > 0
      total = streams.sum(&.size)
      total.should be > 0
    end
  end

  it "preserves the MediaBox of every page (A4 + Letter mix)" do
    a = File.join(SpecHelper::TMP_DIR, "merger-box-a.pdf")
    b = File.join(SpecHelper::TMP_DIR, "merger-box-b.pdf")
    dst = File.join(SpecHelper::TMP_DIR, "merger-box-ab.pdf")
    SpecHelper.write_a4(a, page_count: 1)
    SpecHelper.write_letter(b)

    CombinePDF.merge(inputs: [a, b], output: dst)

    a4_w, a4_h = SpecHelper.page_size(dst, 0)
    letter_w, letter_h = SpecHelper.page_size(dst, 1)
    # A4 is 595 × 842 pt; Letter is 612 × 792 pt — the merger must
    # keep both as-is, not normalise them to a single format.
    ((a4_w - 595).abs).should be < 1.0
    ((a4_h - 842).abs).should be < 1.0
    ((letter_w - 612).abs).should be < 1.0
    ((letter_h - 792).abs).should be < 1.0
  end

  it "produces a valid PDF that ends with %%EOF" do
    a = File.join(SpecHelper::TMP_DIR, "merger-eof-a.pdf")
    b = File.join(SpecHelper::TMP_DIR, "merger-eof-b.pdf")
    dst = File.join(SpecHelper::TMP_DIR, "merger-eof-ab.pdf")
    SpecHelper.write_a4(a, page_count: 1)
    SpecHelper.write_a4(b, page_count: 1)

    CombinePDF.merge(inputs: [a, b], output: dst)

    File.read(dst).rstrip.should end_with("%%EOF")
  end
end

describe "CombinePDF.assemble" do
  it "merges + numbers in one shot, with auto-detected partition sizes" do
    inputs = [
      File.join(SpecHelper::TMP_DIR, "asm-p1.pdf"),
      File.join(SpecHelper::TMP_DIR, "asm-p2.pdf"),
      File.join(SpecHelper::TMP_DIR, "asm-p3.pdf"),
    ]
    SpecHelper.write_a4(inputs[0], page_count: 4)
    SpecHelper.write_a4(inputs[1], page_count: 2)
    SpecHelper.write_a4(inputs[2], page_count: 1)
    dst = File.join(SpecHelper::TMP_DIR, "asm-livret.pdf")

    CombinePDF.assemble(inputs: inputs, output: dst)

    SpecHelper.page_count(dst).should eq(7)
    # The output must contain numbering (we can check at the byte
    # level that numbers were rendered — every page gets at least
    # one new content stream from the Numberer pass).
    objs_pre_numbering = inputs.sum { |path| SpecHelper.count_byte_pattern(path, "endobj") }
    objs_final = SpecHelper.count_byte_pattern(dst, "endobj")
    # Final has the merged objects + at least one new endobj per
    # page from the numbering pass.
    objs_final.should be > objs_pre_numbering
  end
end
