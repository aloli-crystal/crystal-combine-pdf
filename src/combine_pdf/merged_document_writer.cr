module CombinePDF
  # Minimalist PDF writer that takes an arbitrary set of indirect
  # objects + a catalog reference + an info reference and writes
  # a complete, valid PDF.
  #
  # We don't reuse `::PDF::Writer::DocumentWriter` because it walks
  # `::PDF::Document#pages` (the in-memory pages added via
  # `Document#page`), which doesn't apply when we're stitching
  # together pages parsed from external sources.
  #
  # This writer is intentionally simple — no compression of the
  # xref table (PDF 1.5 cross-reference streams), no object streams,
  # no incremental update mode. Plain PDF 1.7 with a classical
  # xref table.
  class MergedDocumentWriter
    @objects : Array(::PDF::Objects::Indirect)
    @catalog_id : Int32
    @info_id : Int32

    # Optionnel : handler de chiffrement à appliquer sur tous les
    # streams et chaînes indirectes au moment de l'écriture. Si
    # défini, un /Encrypt indirect est ajouté et un /ID est inscrit
    # dans le trailer.
    @security_handler : ::PDF::Encryption::StandardSecurity?
    @file_id : Bytes?

    def initialize(@objects : Array(::PDF::Objects::Indirect),
                   @catalog_id : Int32,
                   @info_id : Int32,
                   @security_handler : ::PDF::Encryption::StandardSecurity? = nil,
                   @file_id : Bytes? = nil)
    end

    # Writes the complete PDF to `io`.
    def write(io : IO) : Nil
      # Si chiffrement actif : ajouter le dict /Encrypt à @objects
      # et chiffrer tous les autres objets avant sérialisation.
      encrypt_obj_id = nil
      if handler = @security_handler
        encrypt_obj_id = next_id_for_encrypt
        encrypt_dict = handler.to_encrypt_dict
        @objects << ::PDF::Objects::Indirect.new(encrypt_obj_id, encrypt_dict)
        encrypt_objects(handler, encrypt_obj_id)
      end

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
      io << build_trailer(sorted, xref_offset, encrypt_obj_id)
    end

    # Choisit un object number libre pour le dict /Encrypt — le plus
    # grand existant + 1.
    private def next_id_for_encrypt : Int32
      max_id = @objects.max_of?(&.object_number) || 0
      max_id + 1
    end

    # Chiffre tous les streams + strings indirectes (sauf /Encrypt).
    private def encrypt_objects(handler : ::PDF::Encryption::StandardSecurity,
                                encrypt_obj_id : Int32) : Nil
      @objects.each do |indirect|
        next if indirect.object_number == encrypt_obj_id
        encrypt_in_place(indirect.value, indirect.object_number, indirect.generation, handler)
      end
    end

    private def encrypt_in_place(obj : ::PDF::Objects::Base,
                                 obj_num : Int32, gen : Int32,
                                 handler : ::PDF::Encryption::StandardSecurity) : Nil
      case obj
      when ::PDF::Objects::Stream
        encoded = obj.encoded_data
        encrypted = handler.encrypt_object(encoded, obj_num, gen)
        obj.replace_encoded!(encrypted)
        obj.dictionary[::PDF::Objects::Name::LENGTH] = ::PDF::Objects::Number.new(encrypted.size)
      when ::PDF::Objects::Str
        encrypted = handler.encrypt_object(obj.value.to_slice, obj_num, gen)
        obj.value = String.new(encrypted)
        obj.hex = true
      when ::PDF::Objects::Dictionary
        obj.values.each { |v| encrypt_in_place(v, obj_num, gen, handler) }
      when ::PDF::Objects::Array
        obj.each { |v| encrypt_in_place(v, obj_num, gen, handler) }
      end
    end

    # Builds the classical xref table. We assume objects are
    # numbered contiguously from 1 to N. Most readers tolerate
    # gaps but a contiguous xref is simplest and what we get
    # naturally from the merger's allocator.
    private def build_xref(sorted : Array(::PDF::Objects::Indirect),
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

    private def build_trailer(sorted : Array(::PDF::Objects::Indirect),
                              xref_offset : Int64,
                              encrypt_obj_id : Int32?) : String
      total = sorted.size + 1
      String.build do |io|
        io << "trailer\n"
        io << "<< /Size " << total
        io << " /Root " << @catalog_id << " 0 R"
        io << " /Info " << @info_id << " 0 R"
        if num = encrypt_obj_id
          io << " /Encrypt " << num << " 0 R"
        end
        if id = @file_id
          hex = id.map(&.to_s(16, upcase: true).rjust(2, '0')).join
          io << " /ID [<" << hex << "><" << hex << ">]"
        end
        io << " >>\n"
        io << "startxref\n"
        io << xref_offset << '\n'
        io << "%%EOF\n"
      end
    end
  end
end
