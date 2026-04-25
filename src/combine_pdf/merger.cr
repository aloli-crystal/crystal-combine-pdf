module CombinePDF
  # Merges several source PDFs into a single output PDF.
  #
  # The strategy is the classic « renumber + concat » used by
  # `combine_pdf` (Ruby) and `pypdf` (Python) :
  #
  # 1. For each source PDF, read every indirect object via
  #    `PDF::Reader`.
  # 2. Allocate a fresh object number for every source object so
  #    objects coming from different files cannot collide.
  # 3. Walk every object and rewrite its `Objects::Reference`
  #    instances to point at the freshly-allocated IDs (recursive
  #    remap through dictionaries, arrays and stream metadata).
  # 4. Collect the renumbered page dictionaries into a single
  #    `/Pages` tree, write a fresh `/Catalog`, and serialise the
  #    whole thing via `MergedDocumentWriter`.
  #
  # No deduplication of common resources (fonts, images) in v0.2 —
  # the result is correct but slightly larger than what an
  # optimising merger would produce. Worth tackling in v0.3 once
  # we have real-world feedback.
  class Merger
    @next_id : Int32 = 1
    @objects : Array(PDF::Objects::Indirect) = [] of PDF::Objects::Indirect
    @page_refs : Array(PDF::Objects::Reference) = [] of PDF::Objects::Reference

    def initialize
    end

    # Reads every PDF in `inputs` and writes the merged result to
    # `output`. Pages are concatenated in the order given.
    def self.merge(inputs : Array(String), output : String) : Nil
      merger = new
      inputs.each { |path| merger.add(path) }
      merger.save(output)
    end

    # Reads `path`, renumbers every object, and queues its pages
    # for the final tree.
    def add(path : String) : Nil
      reader = PDF::Reader.open(path)

      # Force the lazy reader to materialise every object referenced
      # by the xref. `Reader#objects` is a cache populated on demand,
      # so without this loop we'd only see the objects already
      # touched by `build_page_tree` (catalog, pages tree, page
      # dicts) — fonts, images and content streams would be missing
      # and the merged PDF would have dangling references.
      total_size = reader.@trailer["Size"]?.try(&.as?(PDF::Objects::Number)).try(&.to_i64.to_i32) || 0
      (1...total_size).each do |id|
        reader.resolve(PDF::Objects::Reference.new(id))
      end

      # Allocate a fresh ID for every object in this source.
      id_map = {} of Int32 => Int32
      reader.objects.each_value do |obj|
        id_map[obj.object_number] = allocate_id
      end

      # Track which old IDs correspond to pages of this source —
      # we need their new IDs for the final /Pages tree.
      page_old_ids = reader.pages.map(&.object_number)

      # Remap and copy every indirect object.
      reader.objects.each_value do |obj|
        new_id = id_map[obj.object_number]
        new_value = remap(obj.value, id_map)
        # Strip any /Parent reference — page parents will be rewritten
        # to point at OUR /Pages root once it's allocated. Without
        # this, pages would still point at the source's pages tree.
        if (dict = new_value.as?(PDF::Objects::Dictionary)) && dict["Type"]?.try(&.as(PDF::Objects::Name).value) == "Page"
          dict.delete("Parent")
        end
        @objects << PDF::Objects::Indirect.new(new_id, obj.generation, new_value)
      end

      page_old_ids.each do |old_id|
        @page_refs << PDF::Objects::Reference.new(id_map[old_id])
      end
    end

    # Builds the catalog + pages tree, registers them, and writes
    # the merged PDF to `path`.
    def save(path : String) : Nil
      File.open(path, "wb") { |io| write(io) }
    end

    # Same as `#save` but to an arbitrary IO.
    def write(io : IO) : Nil
      pages_id = allocate_id
      catalog_id = allocate_id
      info_id = allocate_id

      # Patch every page dict to point at the new pages tree.
      pages_ref = PDF::Objects::Reference.new(pages_id)
      @page_refs.each do |page_ref|
        page_obj = @objects.find!(&.object_number.==(page_ref.object_number))
        page_dict = page_obj.value.as(PDF::Objects::Dictionary)
        page_dict["Parent"] = pages_ref
      end

      # /Pages tree: a single flat node containing every page.
      pages_dict = PDF::Objects::Dictionary.new
      pages_dict["Type"] = PDF::Objects::Name.new("Pages")
      kids = PDF::Objects::Array.new
      @page_refs.each { |ref| kids << ref }
      pages_dict["Kids"] = kids
      pages_dict["Count"] = PDF::Objects::Number.new(@page_refs.size)
      @objects << PDF::Objects::Indirect.new(pages_id, pages_dict)

      # /Catalog
      catalog_dict = PDF::Objects::Dictionary.new
      catalog_dict["Type"] = PDF::Objects::Name.new("Catalog")
      catalog_dict["Pages"] = pages_ref
      @objects << PDF::Objects::Indirect.new(catalog_id, catalog_dict)

      # /Info (minimal)
      info_dict = PDF::Objects::Dictionary.new
      info_dict["Producer"] = PDF::Objects::Str.new("crystal-combine-pdf #{CombinePDF::VERSION}")
      @objects << PDF::Objects::Indirect.new(info_id, info_dict)

      MergedDocumentWriter.new(@objects, catalog_id, info_id).write(io)
    end

    private def allocate_id : Int32
      id = @next_id
      @next_id += 1
      id
    end

    # Recursively rewrites every `Objects::Reference` inside `obj`
    # to use the new IDs from `id_map`. Returns a new instance of
    # the same class (no in-place mutation — we may merge several
    # sources that share parsed objects via the cache and we don't
    # want them to interfere).
    private def remap(obj : PDF::Objects::Base, id_map : Hash(Int32, Int32)) : PDF::Objects::Base
      case obj
      when PDF::Objects::Reference
        new_id = id_map[obj.object_number]?
        if new_id
          PDF::Objects::Reference.new(new_id, obj.generation)
        else
          # Reference to an object that wasn't in the source's
          # objects map (shouldn't happen on a well-formed PDF, but
          # we leave it as-is rather than crash).
          obj
        end
      when PDF::Objects::Dictionary
        new_dict = PDF::Objects::Dictionary.new
        obj.each { |k, v| new_dict[k] = remap(v, id_map) }
        new_dict
      when PDF::Objects::Array
        new_arr = PDF::Objects::Array.new
        obj.size.times { |i| new_arr << remap(obj.unsafe_fetch(i), id_map) }
        new_arr
      when PDF::Objects::Stream
        # Stream has a metadata dict (which may contain references)
        # plus an opaque byte payload (which doesn't). Remap the
        # dict, keep the data verbatim.
        #
        # IMPORTANT : the Reader stores DECODED bytes in
        # `Stream#data` but leaves the original `/Filter` entry in
        # the dictionary. If we just copy them as-is, the next
        # parser will try to Flate-decode the already-clear bytes
        # and crash with "Invalid header". Strip the filter so the
        # output stream is read back as plain text. We also drop
        # /Length, which the writer rewrites from `data.size`.
        new_dict = remap(obj.dictionary, id_map).as(PDF::Objects::Dictionary)
        new_dict.delete("Filter")
        new_dict.delete("DecodeParms")
        new_dict.delete("Length")
        PDF::Objects::Stream.new(new_dict, obj.data)
      else
        # Number, Str, Name, Boolean, Null — no nested references.
        obj
      end
    end
  end
end
