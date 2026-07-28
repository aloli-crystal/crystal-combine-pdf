module CombinePDF
  # Merges several source PDFs into a single output PDF.
  #
  # The strategy is the classic « renumber + concat » used by
  # `combine_pdf` (Ruby) and `pypdf` (Python) :
  #
  # 1. For each source PDF, read every indirect object via
  #    `::PDF::Reader`.
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
    @objects : Array(::PDF::Objects::Indirect) = [] of ::PDF::Objects::Indirect

    # Ordered list of references to page objects that will land in
    # the final /Pages tree. Exposed as a getter so the high-level
    # `CombinePDF::PDF` class can reorder, snapshot, clear, and
    # re-append entries (insert / remove operations).
    getter page_refs : Array(::PDF::Objects::Reference) = [] of ::PDF::Objects::Reference

    # Document metadata. When set, override the default `/Info` dict
    # entries during `#write`. Used by `CombinePDF::PDF#title=` and
    # `#author=` to surface user-set values in the output PDF.
    property metadata_title : String? = nil
    property metadata_author : String? = nil

    # Chiffrement — quand défini, le writer ajoute /Encrypt et chiffre
    # tous les streams + chaînes indirectes au moment de l'écriture.
    property security_handler : ::PDF::Encryption::StandardSecurity? = nil
    property file_id : Bytes? = nil

    # Quand `true` (défaut), pré-traite chaque PDF source via
    # `qpdf --flatten-rotation` si l'une de ses pages porte un tag
    # `/Rotate ≠ 0`. Cuit ainsi les rotations posées par Aperçu
    # macOS / Acrobat (cf. `RotationFlattener`). Désactiver avec
    # `--no-flatten-rotation` côté CLI.
    property flatten_rotation : Bool = true

    # IO d'avertissement (défaut STDERR). Le pré-traitement écrit
    # un message par PDF rotaté ; mettre à `nil` pour silencieux.
    property flatten_rotation_warn_io : IO? = STDERR

    # Liste des fichiers temporaires créés par le pré-traitement
    # `qpdf --flatten-rotation`. Supprimés au `save`.
    @flatten_rotation_tmps : Array(String) = [] of String

    def initialize
    end

    # Reads every PDF in `inputs` and writes the merged result to
    # `output`. Pages are concatenated in the order given.
    def self.merge(
      inputs : Array(String),
      output : String,
      flatten_rotation : Bool = true,
      flatten_rotation_warn_io : IO? = STDERR,
    ) : Nil
      merger = new
      merger.flatten_rotation = flatten_rotation
      merger.flatten_rotation_warn_io = flatten_rotation_warn_io
      inputs.each { |path| merger.add(path) }
      merger.save(output)
    end

    # Reads `path`, renumbers every object, and queues its pages
    # for the final tree. `password` est utilisé si le PDF source
    # est chiffré (vide par défaut, ce qui suffit pour la majorité
    # des PDFs « owner-only protected »).
    def add(path : String, password : String = "") : Nil
      # Pré-traitement /Rotate : si l'une des pages a /Rotate ≠ 0,
      # cuire via qpdf pour ne pas embarquer du contenu inversé
      # dans le PDF assemblé. Le fichier de travail est swapé vers
      # un temp ; la suppression est différée au `save` final.
      working_path = RotationFlattener.preprocess(
        path,
        password: password,
        enabled: @flatten_rotation,
        warn_io: @flatten_rotation_warn_io,
      )
      @flatten_rotation_tmps << working_path if working_path != path

      reader = ::PDF::Reader.open(working_path, password: password)

      # Force the lazy reader to materialise every object referenced
      # by the xref. `Reader#objects` is a cache populated on demand,
      # so without this loop we'd only see the objects already
      # touched by `build_page_tree` (catalog, pages tree, page
      # dicts) — fonts, images and content streams would be missing
      # and the merged PDF would have dangling references.
      total_size = reader.@trailer["Size"]?.try(&.as?(::PDF::Objects::Number)).try(&.to_i64.to_i32) || 0
      (1...total_size).each do |id|
        reader.resolve(::PDF::Objects::Reference.new(id))
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
        if (dict = new_value.as?(::PDF::Objects::Dictionary)) && dict["Type"]?.try(&.as(::PDF::Objects::Name).value) == "Page"
          dict.delete("Parent")
        end
        @objects << ::PDF::Objects::Indirect.new(new_id, obj.generation, new_value)
      end

      page_old_ids.each do |old_id|
        @page_refs << ::PDF::Objects::Reference.new(id_map[old_id])
      end
    end

    # Insère une page de titre + sommaire en première position de
    # l'arbre `/Pages`. Doit être appelée APRÈS toutes les `add()`
    # (sinon les références de destination ne pointeront vers rien).
    #
    # `content` : opérateurs PDF à mettre dans `/Contents` de la page
    # `annotations` : dicts `Annot` à mettre dans `/Annots` (les
    #                 références qu'ils contiennent sont déjà des
    #                 `::PDF::Objects::Reference` valides vers des
    #                 pages déjà mergées).
    # `width`, `height` : dimensions du `/MediaBox` en points
    #                     (defaut A4 595 × 842).
    def insert_toc_page(content : String,
                        annotations : Array(::PDF::Objects::Dictionary),
                        width : Float64 = 595.0,
                        height : Float64 = 842.0) : Nil
      # Allouer l'ID du content stream et l'ajouter au pool.
      content_id = allocate_id
      content_stream = ::PDF::Objects::Stream.new(::PDF::Objects::Dictionary.new, content.to_slice, true)
      @objects << ::PDF::Objects::Indirect.new(content_id, content_stream)

      # Allouer un ID par annotation et les ajouter.
      annot_refs = ::PDF::Objects::Array.new
      annotations.each do |annot|
        aid = allocate_id
        @objects << ::PDF::Objects::Indirect.new(aid, annot)
        annot_refs << ::PDF::Objects::Reference.new(aid)
      end

      # Resources : Helvetica + variants. Type1 standard, pas
      # d'embedding. Le font dictionary est inline (pas indirect)
      # pour éviter d'allouer 3 IDs supplémentaires.
      font_dict = ::PDF::Objects::Dictionary.new
      ["F1", "F2", "F3"].zip(["Helvetica", "Helvetica-Bold", "Helvetica-Oblique"]) do |key, name|
        font_entry = ::PDF::Objects::Dictionary.new
        font_entry["Type"] = ::PDF::Objects::Name.new("Font")
        font_entry["Subtype"] = ::PDF::Objects::Name.new("Type1")
        font_entry["BaseFont"] = ::PDF::Objects::Name.new(name)
        font_entry["Encoding"] = ::PDF::Objects::Name.new("WinAnsiEncoding")
        font_dict[key] = font_entry
      end
      resources = ::PDF::Objects::Dictionary.new
      resources["Font"] = font_dict

      # Page dictionary (le /Parent sera fixé dans `write` comme
      # pour toutes les autres pages).
      page_dict = ::PDF::Objects::Dictionary.new
      page_dict["Type"] = ::PDF::Objects::Name.new("Page")
      mediabox = ::PDF::Objects::Array.new
      mediabox << ::PDF::Objects::Number.new(0_i64)
      mediabox << ::PDF::Objects::Number.new(0_i64)
      mediabox << ::PDF::Objects::Number.new(width)
      mediabox << ::PDF::Objects::Number.new(height)
      page_dict["MediaBox"] = mediabox
      page_dict["Resources"] = resources
      page_dict["Contents"] = ::PDF::Objects::Reference.new(content_id)
      unless annot_refs.empty?
        page_dict["Annots"] = annot_refs
      end

      page_id = allocate_id
      @objects << ::PDF::Objects::Indirect.new(page_id, page_dict)

      # Insérer en tête de l'arbre des pages.
      @page_refs.unshift(::PDF::Objects::Reference.new(page_id))
    end

    # Builds the catalog + pages tree, registers them, and writes
    # the merged PDF to `path`.
    def save(path : String) : Nil
      File.open(path, "wb") { |io| write(io) }
    ensure
      cleanup_rotation_tmps
    end

    # Supprime les fichiers temporaires créés par le pré-traitement
    # `qpdf --flatten-rotation`. Public pour les tests ; appelé
    # automatiquement par `save`.
    def cleanup_rotation_tmps : Nil
      @flatten_rotation_tmps.each do |tmp|
        File.delete(tmp) if File.exists?(tmp)
      end
      @flatten_rotation_tmps.clear
    end

    # Same as `#save` but to an arbitrary IO.
    #
    # Idempotent: a snapshot of `@objects.size` and `@next_id` is
    # taken on entry and restored on exit. Without this, calling
    # `write` (or `to_pdf` / `save`) more than once on the same
    # `Merger` would accumulate orphan `/Pages`, `/Catalog`, and
    # `/Info` indirect objects, each call producing a slightly
    # different (and bloated) byte stream.
    def write(io : IO) : Nil
      saved_objects_size = @objects.size
      saved_next_id = @next_id
      begin
        write_internal(io)
      ensure
        @objects = @objects[0, saved_objects_size]
        @next_id = saved_next_id
      end
    end

    private def write_internal(io : IO) : Nil
      pages_id = allocate_id
      catalog_id = allocate_id
      info_id = allocate_id

      # Patch every page dict to point at the new pages tree.
      pages_ref = ::PDF::Objects::Reference.new(pages_id)
      @page_refs.each do |page_ref|
        page_obj = @objects.find!(&.object_number.==(page_ref.object_number))
        page_dict = page_obj.value.as(::PDF::Objects::Dictionary)
        page_dict["Parent"] = pages_ref
      end

      # /Pages tree: a single flat node containing every page.
      pages_dict = ::PDF::Objects::Dictionary.new
      pages_dict["Type"] = ::PDF::Objects::Name.new("Pages")
      kids = ::PDF::Objects::Array.new
      @page_refs.each { |ref| kids << ref }
      pages_dict["Kids"] = kids
      pages_dict["Count"] = ::PDF::Objects::Number.new(@page_refs.size)
      @objects << ::PDF::Objects::Indirect.new(pages_id, pages_dict)

      # /Catalog
      catalog_dict = ::PDF::Objects::Dictionary.new
      catalog_dict["Type"] = ::PDF::Objects::Name.new("Catalog")
      catalog_dict["Pages"] = pages_ref
      @objects << ::PDF::Objects::Indirect.new(catalog_id, catalog_dict)

      # /Info — Producer is always set ; Title/Author only when the
      # caller surfaced them via `CombinePDF::PDF#title=` / `#author=`.
      #
      # On utilise `Str.unicode(...)` (et non `Str.new(...)`) pour
      # forcer l'encodage UTF-16BE avec BOM `\xFE\xFF` quand le texte
      # contient des caractères non-ASCII. Sans ça, les octets UTF-8
      # bruts sont interprétés en PDFDocEncoding (~ Latin-1) par les
      # readers (pdfinfo, Acrobat, Preview), produisant du mojibake
      # type « Philippe NÃ©nert » au lieu de « Philippe Nénert ».
      # Cf. spec PDF ISO 32000-1 § 7.9.2.2 et § 14.3.3.
      info_dict = ::PDF::Objects::Dictionary.new
      info_dict["Producer"] = ::PDF::Objects::Str.unicode("combine-pdf #{CombinePDF::VERSION}")
      if t = @metadata_title
        info_dict["Title"] = ::PDF::Objects::Str.unicode(t)
      end
      if a = @metadata_author
        info_dict["Author"] = ::PDF::Objects::Str.unicode(a)
      end
      @objects << ::PDF::Objects::Indirect.new(info_id, info_dict)

      MergedDocumentWriter.new(
        @objects, catalog_id, info_id,
        security_handler: @security_handler,
        file_id: @file_id,
      ).write(io)
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
    private def remap(obj : ::PDF::Objects::Base, id_map : Hash(Int32, Int32)) : ::PDF::Objects::Base
      case obj
      when ::PDF::Objects::Reference
        new_id = id_map[obj.object_number]?
        if new_id
          ::PDF::Objects::Reference.new(new_id, obj.generation)
        else
          # Reference to an object that wasn't in the source's
          # objects map (shouldn't happen on a well-formed PDF, but
          # we leave it as-is rather than crash).
          obj
        end
      when ::PDF::Objects::Dictionary
        new_dict = ::PDF::Objects::Dictionary.new
        obj.each { |k, v| new_dict[k] = remap(v, id_map) }
        new_dict
      when ::PDF::Objects::Array
        new_arr = ::PDF::Objects::Array.new
        obj.size.times { |i| new_arr << remap(obj.unsafe_fetch(i), id_map) }
        new_arr
      when ::PDF::Objects::Stream
        # Stream has a metadata dict (which may contain references)
        # plus an opaque byte payload (which doesn't). Remap the
        # dict, keep the data verbatim.
        #
        # `Stream#decoded` (pdf v0.3.6+) tells us if the
        # payload is plain text or still encoded :
        #
        # * `decoded == true` — Reader inverted all filters on the
        #   way in. The bytes in `obj.data` are clear ; the writer
        #   will not re-encode them. We MUST drop `/Filter` and
        #   `/DecodeParms` so the next parser doesn't try to
        #   Flate-decode plain text.
        #
        # * `decoded == false` — Reader hit a filter it cannot
        #   invert (CCITTFaxDecode for fax-style B&W scans,
        #   DCTDecode for JPEGs, JBIG2Decode, JPXDecode, …). The
        #   bytes in `obj.data` are STILL ENCODED. We MUST preserve
        #   `/Filter` and `/DecodeParms` so the next parser knows
        #   how to read them — otherwise the image silently
        #   corrupts to grey blobs (or the parser crashes).
        #
        # `/Length` is rewritten from `data.size` either way.
        #
        # **Recompression** : si la stream a été décodée par le
        # parser (`decoded == true`), on attache un filtre Flate au
        # nouveau stream pour qu'il soit recompressé à l'écriture.
        # Sans ça les bytes décodés (potentiellement plusieurs Mo
        # par PDF source : images, content streams, fonts) sont
        # écrits en clair → bloat ×5-×10. Avec, le résultat est
        # comparable à la taille cumulée des sources.
        new_dict = remap(obj.dictionary, id_map).as(::PDF::Objects::Dictionary)
        new_dict.delete("Length")
        if obj.decoded
          new_dict.delete("Filter")
          new_dict.delete("DecodeParms")
        end
        new_stream = ::PDF::Objects::Stream.new(new_dict, obj.data, obj.decoded)
        new_stream.add_filter(::PDF::Filters::Flate.new) if obj.decoded
        new_stream
      else
        # Number, Str, Name, Boolean, Null — no nested references.
        obj
      end
    end
  end
end
