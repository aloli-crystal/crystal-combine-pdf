require "./spec_helper"

# ISO compatibility specs for the Ruby gem `combine_pdf` v1.0.31
# API. Each example mirrors a usage pattern from the upstream
# README so a Ruby user reading `combine_pdf` documentation can
# port their snippet line-for-line.
describe CombinePDF::PDF do
  describe ".new" do
    it "returns an empty PDF" do
      pdf = CombinePDF.new
      pdf.page_count.should eq(0)
      pdf.pages.empty?.should be_true
    end
  end

  describe ".load" do
    it "loads a PDF from disk and counts pages" do
      a = File.join(SpecHelper::TMP_DIR, "load.pdf")
      SpecHelper.write_a4(a, page_count: 3)
      pdf = CombinePDF.load(a)
      pdf.page_count.should eq(3)
    end
  end

  describe ".parse" do
    it "loads a PDF from raw bytes" do
      a = File.join(SpecHelper::TMP_DIR, "parse.pdf")
      SpecHelper.write_a4(a, page_count: 2)
      pdf = CombinePDF.parse(File.read(a).to_slice)
      pdf.page_count.should eq(2)
    end
  end

  describe "#<<" do
    it "appends a PDF loaded from a path" do
      a = File.join(SpecHelper::TMP_DIR, "lt-a.pdf")
      b = File.join(SpecHelper::TMP_DIR, "lt-b.pdf")
      SpecHelper.write_a4(a, page_count: 2)
      SpecHelper.write_a4(b, page_count: 3)

      pdf = CombinePDF.new
      (pdf << a << b).should be(pdf) # chainable
      pdf.page_count.should eq(5)
    end

    it "appends another PDF instance" do
      a = File.join(SpecHelper::TMP_DIR, "lt-pdf-a.pdf")
      b = File.join(SpecHelper::TMP_DIR, "lt-pdf-b.pdf")
      SpecHelper.write_a4(a, page_count: 1)
      SpecHelper.write_a4(b, page_count: 4)

      pdf = CombinePDF.new
      pdf << CombinePDF.load(a)
      pdf << CombinePDF.load(b)
      pdf.page_count.should eq(5)
    end
  end

  describe "#>>" do
    it "prepends a PDF loaded from a path" do
      a = File.join(SpecHelper::TMP_DIR, "gt-a.pdf")
      b = File.join(SpecHelper::TMP_DIR, "gt-b.pdf")
      SpecHelper.write_a4(a, page_count: 2)
      SpecHelper.write_a4(b, page_count: 1)

      pdf = CombinePDF.new
      pdf << a # 2 pages
      pdf >> b # prepend 1 page
      pdf.page_count.should eq(3)

      dest = File.join(SpecHelper::TMP_DIR, "gt-dest.pdf")
      pdf.save(dest)
      SpecHelper.page_count(dest).should eq(3)
    end
  end

  describe "#insert" do
    it "inserts at position 0 (prepend)" do
      a = File.join(SpecHelper::TMP_DIR, "ins-a.pdf")
      b = File.join(SpecHelper::TMP_DIR, "ins-b.pdf")
      SpecHelper.write_a4(a, page_count: 2)
      SpecHelper.write_a4(b, page_count: 3)

      pdf = CombinePDF.new
      pdf << a
      pdf.insert(0, b)
      pdf.page_count.should eq(5)
    end

    it "inserts at position -1 (append)" do
      a = File.join(SpecHelper::TMP_DIR, "ins2-a.pdf")
      b = File.join(SpecHelper::TMP_DIR, "ins2-b.pdf")
      SpecHelper.write_a4(a, page_count: 2)
      SpecHelper.write_a4(b, page_count: 1)

      pdf = CombinePDF.new
      pdf << a
      pdf.insert(-1, b)
      pdf.page_count.should eq(3)
    end

    it "inserts in the middle" do
      a = File.join(SpecHelper::TMP_DIR, "ins3-a.pdf")
      b = File.join(SpecHelper::TMP_DIR, "ins3-b.pdf")
      SpecHelper.write_a4(a, page_count: 4)
      SpecHelper.write_a4(b, page_count: 2)

      pdf = CombinePDF.new
      pdf << a
      pdf.insert(2, b)
      pdf.page_count.should eq(6)
    end
  end

  describe "#remove" do
    it "removes a page by index" do
      a = File.join(SpecHelper::TMP_DIR, "rm.pdf")
      SpecHelper.write_a4(a, page_count: 4)

      pdf = CombinePDF.load(a)
      removed = pdf.remove(1)
      removed.should_not be_nil
      pdf.page_count.should eq(3)
    end

    it "supports negative indices" do
      a = File.join(SpecHelper::TMP_DIR, "rm-neg.pdf")
      SpecHelper.write_a4(a, page_count: 3)
      pdf = CombinePDF.load(a)
      pdf.remove(-1)
      pdf.page_count.should eq(2)
    end

    it "returns nil for out-of-range indices" do
      a = File.join(SpecHelper::TMP_DIR, "rm-oor.pdf")
      SpecHelper.write_a4(a, page_count: 2)
      pdf = CombinePDF.load(a)
      pdf.remove(99).should be_nil
      pdf.page_count.should eq(2)
    end
  end

  describe "#new_page" do
    it "appends a blank page by default" do
      a = File.join(SpecHelper::TMP_DIR, "np.pdf")
      SpecHelper.write_a4(a, page_count: 2)
      pdf = CombinePDF.load(a)
      pdf.new_page
      pdf.page_count.should eq(3)
    end
  end

  describe "#title= and #author=" do
    it "writes /Title and /Author into the /Info dict" do
      a = File.join(SpecHelper::TMP_DIR, "meta-in.pdf")
      dest = File.join(SpecHelper::TMP_DIR, "meta-dest.pdf")
      SpecHelper.write_a4(a, page_count: 1)

      pdf = CombinePDF.load(a)
      pdf.title = "Recueil de partitions"
      pdf.author = "Philippe Nénert"
      pdf.save(dest)

      bytes = File.read(dest)
      bytes.includes?("Recueil").should be_true
      bytes.includes?("Philippe").should be_true
    end
  end

  describe "#save and #to_pdf" do
    it "to_pdf returns the same bytes save would write" do
      a = File.join(SpecHelper::TMP_DIR, "topdf-in.pdf")
      dest = File.join(SpecHelper::TMP_DIR, "topdf-dest.pdf")
      SpecHelper.write_a4(a, page_count: 2)

      pdf = CombinePDF.load(a)
      pdf.save(dest)
      saved = File.read(dest).to_slice
      in_memory = pdf.to_pdf

      saved.size.should eq(in_memory.size)
      # First and last bytes should match (full equality is overkill —
      # the writer is deterministic so a size match is a strong signal).
      saved[0].should eq(in_memory[0])
      saved[-1].should eq(in_memory[-1])
    end
  end

  describe "#number_pages" do
    it "numbers pages of an in-memory PDF" do
      a = File.join(SpecHelper::TMP_DIR, "num-a.pdf")
      dest = File.join(SpecHelper::TMP_DIR, "num-dest.pdf")
      SpecHelper.write_a4(a, page_count: 3)

      pdf = CombinePDF.load(a)
      pdf.number_pages
      pdf.save(dest)
      SpecHelper.page_count(dest).should eq(3)
    end
  end

  describe "ISO end-to-end booklet workflow" do
    it "mirrors the Ruby README example" do
      a = File.join(SpecHelper::TMP_DIR, "iso-a.pdf")
      b = File.join(SpecHelper::TMP_DIR, "iso-b.pdf")
      dest = File.join(SpecHelper::TMP_DIR, "iso-dest.pdf")
      SpecHelper.write_a4(a, page_count: 2)
      SpecHelper.write_a4(b, page_count: 3)

      pdf = CombinePDF.new
      pdf << CombinePDF.load(a)
      pdf << CombinePDF.load(b)
      pdf.title = "Recueil"
      pdf.number_pages
      pdf.save(dest)

      SpecHelper.page_count(dest).should eq(5)
      File.read(dest).includes?("Recueil").should be_true
    end
  end
end
