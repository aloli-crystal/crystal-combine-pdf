module CombinePDF
  # Minimalist PDF writer that takes an arbitrary set of indirect
  # objects + a catalog reference + an info reference and writes
  # a complete, valid PDF.
  #
  # We don't reuse `PDF::Writer::DocumentWriter` because it walks
  # `PDF::Document#pages` (the in-memory pages added via
  # `Document#page`), which doesn't apply when we're stitching
  # together pages parsed from external sources.
  #
  # This writer is intentionally simple — no compression of the
  # xref table (PDF 1.5 cross-reference streams), no object streams,
  # no incremental update mode. Plain PDF 1.7 with a classical
  # xref table.
  class MergedDocumentWriter
    @objects : Array(PDF::Objects::Indirect)
    @catalog_id : Int32
    @info_id : Int32

    def initialize(@objects : Array(PDF::Objects::Indirect),
                   @catalog_id : Int32,
                   @info_id : Int32)
    end

    # Writes the complete PDF to `io`.
    def write(io : IO) : Nil
      offsets = {} of Int32 => Int64
      position = 0_i64

      # Header — version + binary marker (per PDF spec § 7.5.2).
      header = "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n"
      io << header
      position += header.bytesize

      # Indirect objects, sorted by object number for a clean xref.
      sorted = @objects.sort_by(&.object_number)
      sorted.each do |obj|
        offsets[obj.object_number] = position
        body = obj.to_pdf + "\n"
        io << body
        position += body.bytesize
      end

      # Cross-reference table.
      xref_offset = position
      io << build_xref(sorted, offsets)

      # Trailer.
      io << build_trailer(sorted, xref_offset)
    end

    # Builds the classical xref table. We assume objects are
    # numbered contiguously from 1 to N. Most readers tolerate
    # gaps but a contiguous xref is simplest and what we get
    # naturally from the merger's allocator.
    private def build_xref(sorted : Array(PDF::Objects::Indirect),
                           offsets : Hash(Int32, Int64)) : String
      total = sorted.size + 1 # + object 0 (free)
      String.build do |io|
        io << "xref\n"
        io << "0 #{total}\n"
        # Object 0 — head of free list, generation 65535.
        io << "0000000000 65535 f \n"
        sorted.each do |obj|
          offset = offsets[obj.object_number]? || 0_i64
          io << offset.to_s.rjust(10, '0')
          io << ' '
          io << obj.generation.to_s.rjust(5, '0')
          io << " n \n"
        end
      end
    end

    private def build_trailer(sorted : Array(PDF::Objects::Indirect),
                              xref_offset : Int64) : String
      total = sorted.size + 1
      String.build do |io|
        io << "trailer\n"
        io << "<< /Size " << total
        io << " /Root " << @catalog_id << " 0 R"
        io << " /Info " << @info_id << " 0 R"
        io << " >>\n"
        io << "startxref\n"
        io << xref_offset << '\n'
        io << "%%EOF\n"
      end
    end
  end
end
