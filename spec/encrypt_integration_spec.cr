require "./spec_helper"

# Tests d'intégration du chiffrement bout-en-bout :
#   * via `pdf.encrypt(...)` direct
#   * via la section `encrypt:` du YAML (BookletBuilder)
#   * surcharges CLI (override_user_password, override_encrypt_level…)
#
# On fabrique des PDF d'entrée à la volée, on les chiffre, puis on
# vérifie qu'ils s'ouvrent avec le bon mot de passe (et seulement
# avec le bon).
describe "Chiffrement combine-pdf (intégration)" do
  describe "CombinePDF::PDF#encrypt" do
    {% for level in [:rc4_128, :aes_128, :aes_256] %}
      it "round-trip {{ level.id }} via pdf.encrypt + PDF::Reader.open" do
        dir = File.join(SpecHelper::TMP_DIR, "rt-{{ level.id }}")
        Dir.mkdir_p(dir)
        SpecHelper.write_a4(File.join(dir, "in.pdf"))

        output_path = File.join(dir, "out.pdf")
        pdf = CombinePDF.load(File.join(dir, "in.pdf"))
        pdf.encrypt(user_password: "u-pwd", owner_password: "o-pwd", level: {{ level }})
        pdf.save(output_path)
        File.size(output_path).should be > 0

        # Bon mot de passe ouvre
        reader = PDF::Reader.open(output_path, password: "u-pwd")
        reader.page_count.should eq(1)

        # Mauvais mot de passe rejeté
        expect_raises(PDF::EncryptedPdfError) do
          PDF::Reader.open(output_path, password: "wrong")
        end
      end
    {% end %}
  end

  describe "BookletBuilder + section `encrypt:` du YAML" do
    it "chiffre le livret quand encrypt.enabled = true" do
      dir = File.join(SpecHelper::TMP_DIR, "bb-encrypt-yaml")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "one.pdf"))

      File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
        output: livret.pdf
        title: "Livret chiffré"
        author: "ALOLI"
        paper_size: a4
        duplex: false
        cover:
          mode: none
        numbering:
          enabled: false
        encrypt:
          enabled: true
          level: aes_256
          user_password: yaml-pwd
        files:
          - one.pdf
        YAML

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      output = builder.build
      File.size(output).should be > 0

      reader = PDF::Reader.open(output, password: "yaml-pwd")
      reader.page_count.should eq(1)

      expect_raises(PDF::EncryptedPdfError) do
        PDF::Reader.open(output, password: "wrong")
      end
    end

    it "ne chiffre pas quand encrypt.enabled = false" do
      dir = File.join(SpecHelper::TMP_DIR, "bb-encrypt-disabled")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "one.pdf"))

      File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
        output: livret.pdf
        title: "Livret"
        paper_size: a4
        cover: {mode: none}
        numbering: {enabled: false}
        encrypt:
          enabled: false
          user_password: should-be-ignored
        files:
          - one.pdf
        YAML

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      output = builder.build
      # Pas de mot de passe nécessaire — pas chiffré
      reader = PDF::Reader.open(output)
      reader.page_count.should eq(1)
    end

    it "surcharge CLI : override_user_password + override_encrypt_level" do
      dir = File.join(SpecHelper::TMP_DIR, "bb-override-cli")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "one.pdf"))

      File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
        output: livret.pdf
        title: "Livret"
        paper_size: a4
        cover: {mode: none}
        numbering: {enabled: false}
        encrypt:
          enabled: true
          level: aes_128
          user_password: yaml-pwd
        files:
          - one.pdf
        YAML

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      builder.override_user_password = "cli-pwd"
      builder.override_encrypt_level = "aes_256"
      output = builder.build

      # CLI password fonctionne, YAML password rejeté
      reader = PDF::Reader.open(output, password: "cli-pwd")
      reader.page_count.should eq(1)
      expect_raises(PDF::EncryptedPdfError) do
        PDF::Reader.open(output, password: "yaml-pwd")
      end
    end

    it "override_encrypt_enabled = false bypass le YAML" do
      dir = File.join(SpecHelper::TMP_DIR, "bb-override-off")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "one.pdf"))

      File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
        output: livret.pdf
        title: "Livret"
        paper_size: a4
        cover: {mode: none}
        numbering: {enabled: false}
        encrypt:
          enabled: true
          user_password: would-encrypt-without-override
        files:
          - one.pdf
        YAML

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      builder.override_encrypt_enabled = false
      output = builder.build
      # Doit ouvrir SANS mot de passe
      reader = PDF::Reader.open(output)
      reader.page_count.should eq(1)
    end

    it "override_encrypt_enabled = true active sans section encrypt: dans le YAML" do
      dir = File.join(SpecHelper::TMP_DIR, "bb-override-on")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "one.pdf"))

      File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
        output: livret.pdf
        title: "Livret"
        paper_size: a4
        cover: {mode: none}
        numbering: {enabled: false}
        files:
          - one.pdf
        YAML

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      builder.override_encrypt_enabled = true
      builder.override_user_password = "from-cli-only"
      output = builder.build

      reader = PDF::Reader.open(output, password: "from-cli-only")
      reader.page_count.should eq(1)
    end
  end

  describe "ConfigInitializer (init)" do
    it "génère une section encrypt: commentée par défaut" do
      dir = File.join(SpecHelper::TMP_DIR, "init-encrypt-default")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "a.pdf"))
      opts = CombinePDF::ConfigInitializer::InitOptions.new
      CombinePDF::ConfigInitializer.init(dir, options: opts)
      content = File.read(File.join(dir, ".crystal-combine-pdf.yml"))
      # Section présente mais commentée
      content.should contain("# encrypt:")
      content.should contain("# ─── Chiffrement ──")
      # Pas active par défaut
      content.should_not contain("\nencrypt:\n")
    end
  end

  describe "Config::Encrypt" do
    it "level_symbol mappe les chaînes vers les symboles" do
      CombinePDF::Config::Encrypt.new(level: "aes_256").level_symbol.should eq(:aes_256)
      CombinePDF::Config::Encrypt.new(level: "aes-128").level_symbol.should eq(:aes_128)
      CombinePDF::Config::Encrypt.new(level: "rc4_128").level_symbol.should eq(:rc4_128)
    end

    it "level_symbol lève sur niveau inconnu" do
      enc = CombinePDF::Config::Encrypt.new(level: "des_56")
      expect_raises(Exception, /Niveau de chiffrement inconnu/) do
        enc.level_symbol
      end
    end

    it "permissions_for_pdf mappe correctement les chaînes" do
      enc = CombinePDF::Config::Encrypt.new(permissions: ["print", "copy"])
      perms = enc.permissions_for_pdf
      perms.size.should eq(2)
      perms.should contain(PDF::Security::Permission::Print)
      perms.should contain(PDF::Security::Permission::Copy)
    end

    it "permissions_for_pdf retourne tout autorisé quand nil" do
      enc = CombinePDF::Config::Encrypt.new(permissions: nil)
      enc.permissions_for_pdf.size.should eq(4)
    end
  end
end
