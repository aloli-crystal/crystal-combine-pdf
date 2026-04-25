require "spec"
require "file_utils"
require "../src/combine_pdf"

# Shared test helpers: generate fresh fixture PDFs at known formats
# (A4, Letter) and a known number of pages. The numberer's only
# observable side effects are byte-level (size growth, content stream
# additions, MediaBox preservation), so we don't need a re-parser.
module SpecHelper
  TMP_DIR = File.join(__DIR__, "tmp")

  # Writes a PDF with `page_count` A4 pages, each carrying a small
  # marker line so the document is not literally empty.
  def self.write_a4(path : String, page_count : Int32 = 1) : Nil
    Dir.mkdir_p(File.dirname(path))
    pdf = PDF::Document.new
    page_count.times do |i|
      pdf.page(size: :a4) do |page|
        page.font("Helvetica", size: 14)
        page.text("Booklet page #{i + 1}", at: {72, 750})
      end
    end
    pdf.save(path)
  end

  # Writes a single-page US Letter PDF — used to confirm that the
  # numberer's coordinates honour the actual MediaBox.
  def self.write_letter(path : String) : Nil
    Dir.mkdir_p(File.dirname(path))
    pdf = PDF::Document.new
    pdf.page(size: :letter) do |page|
      page.font("Helvetica", size: 14)
      page.text("Letter page", at: {72, 720})
    end
    pdf.save(path)
  end

  # Returns the byte-level count of `pattern` in the file at `path`.
  # PDF content streams may contain arbitrary high bytes that break
  # Crystal's UTF-8 regex, so we walk the bytes manually.
  def self.count_byte_pattern(path : String, pattern : String) : Int32
    bytes = File.read(path).to_slice
    needle = pattern.to_slice
    return 0 if needle.size == 0 || needle.size > bytes.size
    count = 0
    i = 0
    last = bytes.size - needle.size
    while i <= last
      match = true
      j = 0
      while j < needle.size
        if bytes[i + j] != needle[j]
          match = false
          break
        end
        j += 1
      end
      if match
        count += 1
        i += needle.size
      else
        i += 1
      end
    end
    count
  end
end

at_exit do
  FileUtils.rm_rf(SpecHelper::TMP_DIR) if Dir.exists?(SpecHelper::TMP_DIR)
end
