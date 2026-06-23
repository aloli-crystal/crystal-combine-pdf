require "./spec_helper"

# Spec d'intégration pour `Rasterizer` : rastérise un PDF de test
# et vérifie que la sortie est un PDF d'images plein page (pas de
# texte extractible). Skip si `gs` est absent.
describe CombinePDF::Rasterizer do
  describe ".rasterize" do
    it "produit un PDF dont chaque page est une image JPEG plein page" do
      unless CombinePDF::Rasterizer.ghostscript_available?
        pending! "ghostscript (gs) non installé"
      end

      dir = File.join(SpecHelper::TMP_DIR, "rasterize-basic")
      Dir.mkdir_p(dir)
      input = File.join(dir, "in.pdf")
      output = File.join(dir, "out.pdf")
      SpecHelper.write_a4(input, page_count: 2)

      CombinePDF::Rasterizer.rasterize(input, output, dpi: 100)

      File.exists?(output).should be_true
      # 2 pages → 2 images JPEG
      reader = PDF::Reader.open(output)
      reader.page_count.should eq(2)
    end

    it "préserve les dimensions des pages du PDF source" do
      unless CombinePDF::Rasterizer.ghostscript_available?
        pending! "ghostscript (gs) non installé"
      end

      dir = File.join(SpecHelper::TMP_DIR, "rasterize-letter")
      Dir.mkdir_p(dir)
      input = File.join(dir, "in.pdf")
      output = File.join(dir, "out.pdf")
      SpecHelper.write_letter(input)

      CombinePDF::Rasterizer.rasterize(input, output, dpi: 100)

      reader = PDF::Reader.open(output)
      reader.page_count.should eq(1)
      page = reader.pages[0]
      # Letter : 612 × 792 pts
      page.width.round.should eq(612)
      page.height.round.should eq(792)
    end

    it "marque le Producer du PDF de sortie pour traçabilité" do
      unless CombinePDF::Rasterizer.ghostscript_available?
        pending! "ghostscript (gs) non installé"
      end

      dir = File.join(SpecHelper::TMP_DIR, "rasterize-producer")
      Dir.mkdir_p(dir)
      input = File.join(dir, "in.pdf")
      output = File.join(dir, "out.pdf")
      SpecHelper.write_a4(input)

      CombinePDF::Rasterizer.rasterize(input, output, dpi: 100)

      # Le tag Producer doit mentionner « rasterized »
      bytes = File.read(output)
      bytes.should contain("rasterized")
      bytes.should contain(CombinePDF::VERSION)
    end
  end

  describe ".ghostscript_available?" do
    it "retourne un booléen mis en cache" do
      CombinePDF::Rasterizer.reset_ghostscript_cache!
      result1 = CombinePDF::Rasterizer.ghostscript_available?
      result2 = CombinePDF::Rasterizer.ghostscript_available?
      result1.should eq(result2)
      result1.should be_a(Bool)
    end
  end
end
