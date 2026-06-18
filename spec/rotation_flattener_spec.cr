require "./spec_helper"

# Spec d'intégration pour `RotationFlattener` : détection des pages
# avec /Rotate ≠ 0 + cuisson via `qpdf --flatten-rotation`.
# Skippé pour la partie cuisson si `qpdf` est absent du PATH.
describe CombinePDF::RotationFlattener do
  # Forge un PDF minimal avec /Rotate `degrees` sur la page unique.
  # Identique à l'helper du spec côté shard pdf — répliqué ici car
  # `write_a4` n'expose pas /Rotate dans le writer du shard.
  write_rotated = ->(degrees : Int32, path : String) do
    objs = [
      "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
      "2 0 obj\n<< /Type /Pages /Count 1 /Kids [3 0 R] >>\nendobj\n",
      "3 0 obj\n<< /Type /Page /Parent 2 0 R /Rotate #{degrees} " \
      "/MediaBox [0 0 595 842] /Contents 4 0 R /Resources << >> >>\nendobj\n",
      "4 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n",
    ]
    header = "%PDF-1.4\n%\xff\xff\xff\xff\n"
    offsets = [0]
    cursor = header.bytesize
    objs.each do |obj|
      offsets << cursor
      cursor += obj.bytesize
    end
    xref_offset = cursor
    xref = String.build do |s|
      s << "xref\n0 #{objs.size + 1}\n"
      s << "0000000000 65535 f \n"
      offsets[1..].each { |off| s << "%010d 00000 n \n" % off }
    end
    trailer = "trailer\n<< /Size #{objs.size + 1} /Root 1 0 R >>\n" \
              "startxref\n#{xref_offset}\n%%EOF\n"
    File.write(path, header + objs.join + xref + trailer)
  end

  describe ".detect" do
    it "retourne aucune page rotatée pour un PDF normal" do
      dir = File.join(SpecHelper::TMP_DIR, "rotflat-detect-clean")
      Dir.mkdir_p(dir)
      path = File.join(dir, "in.pdf")
      SpecHelper.write_a4(path, page_count: 3)

      result = CombinePDF::RotationFlattener.detect(path)
      result.rotated_pages.should be_empty
    end

    it "détecte une page avec /Rotate 180" do
      dir = File.join(SpecHelper::TMP_DIR, "rotflat-detect-180")
      Dir.mkdir_p(dir)
      path = File.join(dir, "in.pdf")
      write_rotated.call(180, path)

      result = CombinePDF::RotationFlattener.detect(path)
      result.rotated_pages.should eq([1])
    end
  end

  describe ".preprocess" do
    it "renvoie le path original si aucune page n'est rotatée" do
      dir = File.join(SpecHelper::TMP_DIR, "rotflat-pre-clean")
      Dir.mkdir_p(dir)
      path = File.join(dir, "in.pdf")
      SpecHelper.write_a4(path)

      result = CombinePDF::RotationFlattener.preprocess(path, warn_io: nil)
      result.should eq(path)
    end

    it "renvoie le path original si le flag est désactivé" do
      dir = File.join(SpecHelper::TMP_DIR, "rotflat-pre-off")
      Dir.mkdir_p(dir)
      path = File.join(dir, "in.pdf")
      write_rotated.call(180, path)

      result = CombinePDF::RotationFlattener.preprocess(path, enabled: false, warn_io: nil)
      result.should eq(path)
    end

    it "cuit la rotation via qpdf et renvoie un temp à /Rotate 0" do
      unless CombinePDF::RotationFlattener.qpdf_available?
        pending! "qpdf non installé"
      end
      dir = File.join(SpecHelper::TMP_DIR, "rotflat-pre-bake")
      Dir.mkdir_p(dir)
      path = File.join(dir, "in.pdf")
      write_rotated.call(180, path)

      result = CombinePDF::RotationFlattener.preprocess(path, warn_io: nil)
      result.should_not eq(path)
      File.exists?(result).should be_true

      # Le PDF cuit a /Rotate 0 sur sa page
      reader = PDF::Reader.open(result)
      reader.pages[0].rotate.should eq(0)
      File.delete(result)
    end

    it "écrit l'avertissement dans warn_io quand qpdf cuit la rotation" do
      unless CombinePDF::RotationFlattener.qpdf_available?
        pending! "qpdf non installé"
      end
      dir = File.join(SpecHelper::TMP_DIR, "rotflat-pre-warn")
      Dir.mkdir_p(dir)
      path = File.join(dir, "in.pdf")
      write_rotated.call(180, path)

      buf = IO::Memory.new
      result = CombinePDF::RotationFlattener.preprocess(path, warn_io: buf)
      buf.to_s.should contain("cuit /Rotate sur 1 page(s)")
      buf.to_s.should contain("(1)")
      File.delete(result) if result != path && File.exists?(result)
    end
  end

  describe "Merger intégration" do
    it "Merger#add cuit automatiquement /Rotate des PDFs sources" do
      unless CombinePDF::RotationFlattener.qpdf_available?
        pending! "qpdf non installé"
      end
      dir = File.join(SpecHelper::TMP_DIR, "rotflat-merger")
      Dir.mkdir_p(dir)
      src = File.join(dir, "rotated.pdf")
      output = File.join(dir, "merged.pdf")
      write_rotated.call(180, src)

      merger = CombinePDF::Merger.new
      merger.flatten_rotation_warn_io = nil
      merger.add(src)
      merger.save(output)

      reader = PDF::Reader.open(output)
      reader.pages[0].rotate.should eq(0)
    end

    it "Merger#add préserve /Rotate quand flatten_rotation = false" do
      dir = File.join(SpecHelper::TMP_DIR, "rotflat-merger-off")
      Dir.mkdir_p(dir)
      src = File.join(dir, "rotated.pdf")
      output = File.join(dir, "merged.pdf")
      write_rotated.call(180, src)

      merger = CombinePDF::Merger.new
      merger.flatten_rotation = false
      merger.flatten_rotation_warn_io = nil
      merger.add(src)
      merger.save(output)

      reader = PDF::Reader.open(output)
      reader.pages[0].rotate.should eq(180)
    end
  end
end
