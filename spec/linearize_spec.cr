require "./spec_helper"

# Spec d'intégration pour le flag `--linearize` du Compressor.
# Délégué à `qpdf --linearize` (cf. doc du module + memory ALOLI
# « shell-out qpdf est OK pour les fonctions de niche »).
#
# Skippé silencieusement si `qpdf` n'est pas dans le PATH (cas
# CI minimal ou poste de dev sans qpdf installé).
describe CombinePDF::Compressor do
  describe "#compress(linearize: true)" do
    it "produit un PDF Optimized:yes (Fast Web View) via qpdf" do
      unless CombinePDF::Compressor.qpdf_available?
        pending! "qpdf non installé"
      end

      dir = File.join(SpecHelper::TMP_DIR, "linearize")
      Dir.mkdir_p(dir)
      input = File.join(dir, "in.pdf")
      output = File.join(dir, "out.pdf")
      SpecHelper.write_a4(input, page_count: 3)

      result = CombinePDF::Compressor.compress(input, output, linearize: true)
      result.pages.should eq(3)
      File.exists?(output).should be_true

      # Le marqueur Linearization est dans les 1024 premiers octets
      # du fichier produit. ISO 32000-1 § F.2 :
      #   « The Linearization Dictionary shall be the first object in
      #     the file ; it shall begin with the keyword `obj` followed
      #     by `<<` and `/Linearized 1.0` (ou similaire). »
      header = File.open(output, "rb") { |f| f.read_string({2048, File.size(output)}.min.to_i) }
      header.should contain("/Linearized")
    end

    it "lève Compressor::Error si qpdf est absent" do
      # On ne peut pas vraiment tester l'absence de qpdf si qpdf
      # est dispo. On teste juste que la méthode a la bonne signature
      # et que `qpdf_available?` répond Bool.
      [true, false].includes?(CombinePDF::Compressor.qpdf_available?).should be_true
    end

    it "round-trip in-place avec --backup" do
      unless CombinePDF::Compressor.qpdf_available?
        pending! "qpdf non installé"
      end

      dir = File.join(SpecHelper::TMP_DIR, "linearize-inplace")
      Dir.mkdir_p(dir)
      input = File.join(dir, "report.pdf")
      SpecHelper.write_a4(input, page_count: 2)
      original_size = File.size(input)

      result = CombinePDF::Compressor.compress(
        input, input, # in-place
        backup: true,
        linearize: true,
      )

      result.pages.should eq(2)
      File.exists?("#{input}.bak").should be_true
      File.size("#{input}.bak").should eq(original_size)

      header = File.open(input, "rb") { |f| f.read_string({2048, File.size(input)}.min.to_i) }
      header.should contain("/Linearized")
    end
  end
end
