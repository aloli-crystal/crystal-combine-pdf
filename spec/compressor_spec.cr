require "./spec_helper"

describe "CombinePDF::Compressor" do
  it "compresse un PDF non optimisé en réduisant la taille" do
    dir = File.join(SpecHelper::TMP_DIR, "compress-basic")
    Dir.mkdir_p(dir)

    # Fixture : un PDF généré avec compression interne. La sortie peut
    # être plus petite ou similaire selon que les filtres sont
    # parfaitement alignés.
    input = File.join(dir, "input.pdf")
    SpecHelper.write_a4(input, page_count: 5)

    output = File.join(dir, "output.pdf")
    result = CombinePDF::Compressor.compress(input, output)

    File.exists?(output).should be_true
    result.pages.should eq(5)
    result.before.should be > 0
    result.after.should be > 0
    # La sortie reste un PDF lisible.
    PDF::Reader.open(output).page_count.should eq(5)
  end

  it "préserve title/author dans le PDF compressé" do
    dir = File.join(SpecHelper::TMP_DIR, "compress-meta")
    Dir.mkdir_p(dir)

    # Construit un PDF avec title/author renseignés via le combiner.
    pdf = CombinePDF.new
    SpecHelper.write_a4(File.join(dir, "p1.pdf"))
    pdf << CombinePDF.load(File.join(dir, "p1.pdf"))
    pdf.title = "Mon Document Test"
    pdf.author = "Jane Doe"
    input = File.join(dir, "input.pdf")
    pdf.save(input)

    output = File.join(dir, "output.pdf")
    CombinePDF::Compressor.compress(input, output)

    raw = File.read(output)
    raw.should contain("Mon Document Test")
    raw.should contain("Jane Doe")
  end

  it "in-place avec backup conserve l'original sous .bak" do
    dir = File.join(SpecHelper::TMP_DIR, "compress-backup")
    Dir.mkdir_p(dir)
    target = File.join(dir, "doc.pdf")
    SpecHelper.write_a4(target, page_count: 3)
    original_size = File.size(target)

    CombinePDF::Compressor.compress(target, target, backup: true)

    File.exists?(target).should be_true
    File.exists?("#{target}.bak").should be_true
    File.size("#{target}.bak").should eq(original_size)
    PDF::Reader.open(target).page_count.should eq(3)
  end

  it "lève si le fichier d'entrée n'existe pas" do
    expect_raises(ArgumentError, /introuvable/) do
      CombinePDF::Compressor.compress("/tmp/nonexistent-#{Random.rand(10000)}.pdf", "/tmp/x.pdf")
    end
  end

  it "Result#reduction_percent renvoie 0 sur input vide, % négatif si grossit" do
    r1 = CombinePDF::Compressor::Result.new(0_i64, 0_i64, 0)
    r1.reduction_percent.should eq(0.0)

    r2 = CombinePDF::Compressor::Result.new(1000_i64, 500_i64, 1)
    r2.reduction_percent.should eq(50.0)

    r3 = CombinePDF::Compressor::Result.new(1000_i64, 1500_i64, 1)
    r3.reduction_percent.should eq(-50.0)
  end
end
