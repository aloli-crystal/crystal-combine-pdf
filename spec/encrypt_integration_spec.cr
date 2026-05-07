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

    it "génère une ligne input_password commentée" do
      dir = File.join(SpecHelper::TMP_DIR, "init-input-pwd")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "a.pdf"))
      CombinePDF::ConfigInitializer.init(dir)
      content = File.read(File.join(dir, ".crystal-combine-pdf.yml"))
      content.should contain("# input_password:")
      content.should contain("# ─── PDFs sources chiffrés ──")
      # Pas active par défaut
      content.should_not contain("\ninput_password:")
    end
  end

  describe "Décryptage de PDFs sources via input_password" do
    it "ouvre un PDF chiffré listé dans `files:` quand input_password est fourni dans le YAML" do
      dir = File.join(SpecHelper::TMP_DIR, "input-pwd-yaml")
      Dir.mkdir_p(dir)

      # PDF source chiffré
      pdf = PDF::Document.new
      pdf.encrypt(user_password: "src-pwd", level: :aes_256)
      pdf.page do |p|
        p.font("Helvetica", size: 12)
        p.text("Encrypted source", at: {72, 720})
      end
      pdf.save(File.join(dir, "source.pdf"))

      File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
        output: out.pdf
        title: ""
        paper_size: a4
        cover: {mode: none}
        numbering: {enabled: false}
        input_password: "src-pwd"
        files:
          - source.pdf
        YAML

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      output = builder.build
      File.size(output).should be > 0

      # Le livret est en clair (pas de section encrypt:)
      reader = PDF::Reader.open(output)
      reader.page_count.should eq(1)
    end

    it "surcharge CLI : override_input_password l'emporte sur le YAML" do
      dir = File.join(SpecHelper::TMP_DIR, "input-pwd-cli-override")
      Dir.mkdir_p(dir)

      pdf = PDF::Document.new
      pdf.encrypt(user_password: "real-pwd", level: :aes_128)
      pdf.page do |p|
        p.font("Helvetica", size: 12)
        p.text("Encrypted", at: {72, 720})
      end
      pdf.save(File.join(dir, "source.pdf"))

      # YAML déclare un MAUVAIS mot de passe ; on le surcharge en CLI
      File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
        output: out.pdf
        title: ""
        paper_size: a4
        cover: {mode: none}
        numbering: {enabled: false}
        input_password: wrong-pwd
        files:
          - source.pdf
        YAML

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      builder.override_input_password = "real-pwd"
      output = builder.build
      File.size(output).should be > 0
    end

    it "lève une erreur quand le PDF source est chiffré et qu'aucun mot de passe n'est fourni" do
      dir = File.join(SpecHelper::TMP_DIR, "input-pwd-missing")
      Dir.mkdir_p(dir)

      pdf = PDF::Document.new
      pdf.encrypt(user_password: "needed", level: :aes_256)
      pdf.page do |p|
        p.font("Helvetica", size: 12)
        p.text("Encrypted", at: {72, 720})
      end
      pdf.save(File.join(dir, "source.pdf"))

      File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
        output: out.pdf
        title: ""
        paper_size: a4
        cover: {mode: none}
        numbering: {enabled: false}
        files:
          - source.pdf
        YAML

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      expect_raises(Exception, /chiffré|Mot de passe/) do
        builder.build
      end
    end
  end

  describe "Per-file password (inline mapping `- {path: ..., password: ...}`)" do
    it "ouvre plusieurs PDFs sources avec des mots de passe différents" do
      dir = File.join(SpecHelper::TMP_DIR, "per-file-pwd")
      Dir.mkdir_p(dir)

      # Trois sources : deux chiffrées avec passwords différents +
      # une en clair.
      pdf_a = PDF::Document.new
      pdf_a.encrypt(user_password: "pwd-A", level: :aes_256)
      pdf_a.page { |p| p.font("Helvetica", size: 12); p.text("Source A", at: {72, 720}) }
      pdf_a.save(File.join(dir, "a.pdf"))

      pdf_b = PDF::Document.new
      pdf_b.encrypt(user_password: "pwd-B", level: :aes_128)
      pdf_b.page { |p| p.font("Helvetica", size: 12); p.text("Source B", at: {72, 720}) }
      pdf_b.save(File.join(dir, "b.pdf"))

      SpecHelper.write_a4(File.join(dir, "c.pdf"))

      File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
        output: out.pdf
        title: ""
        paper_size: a4
        cover: {mode: none}
        numbering: {enabled: false}
        files:
          - {path: a.pdf, password: pwd-A}
          - {name: b.pdf, pass: pwd-B, title: "Section B"}
          - c.pdf
        YAML

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      output = builder.build
      File.size(output).should be > 0

      # Le livret final est en clair (pas de section encrypt:)
      reader = PDF::Reader.open(output)
      reader.page_count.should eq(3)
    end

    it "entry.password l'emporte sur input_password global" do
      dir = File.join(SpecHelper::TMP_DIR, "per-file-vs-global")
      Dir.mkdir_p(dir)

      pdf = PDF::Document.new
      pdf.encrypt(user_password: "specific", level: :aes_256)
      pdf.page { |p| p.font("Helvetica", size: 12); p.text("X", at: {72, 720}) }
      pdf.save(File.join(dir, "specific.pdf"))

      # Le YAML déclare un input_password GLOBAL incorrect, mais
      # l'entrée surcharge avec le bon mot de passe.
      File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
        output: out.pdf
        title: ""
        paper_size: a4
        cover: {mode: none}
        numbering: {enabled: false}
        input_password: wrong-global
        files:
          - {path: specific.pdf, password: specific}
        YAML

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      output = builder.build
      File.size(output).should be > 0
    end

    it "accepte les alias name/file pour path et pass/pwd pour password" do
      dir = File.join(SpecHelper::TMP_DIR, "alias-syntax")
      Dir.mkdir_p(dir)

      pdf = PDF::Document.new
      pdf.encrypt(user_password: "k", level: :aes_128)
      pdf.page { |p| p.font("Helvetica", size: 12); p.text("X", at: {72, 720}) }
      pdf.save(File.join(dir, "doc.pdf"))

      # Toutes les variantes d'alias devraient fonctionner
      ["{name: doc.pdf, pwd: k}",
       "{file: doc.pdf, pass: k}",
       "{path: doc.pdf, password: k, label: \"Titre\"}"].each do |inline|
        File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
          output: out.pdf
          title: ""
          paper_size: a4
          cover: {mode: none}
          numbering: {enabled: false}
          files:
            - #{inline}
          YAML

        builder = CombinePDF::BookletBuilder.from_dir(dir)
        output = builder.build
        File.size(output).should be > 0
      end
    end

    it "FileEntry.password est nil pour une entrée simple" do
      dir = File.join(SpecHelper::TMP_DIR, "no-pwd-entry")
      Dir.mkdir_p(dir)
      File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
        output: out.pdf
        files:
          - foo.pdf
          - bar.pdf: "Title"
        YAML

      config = CombinePDF::ConfigLoader.load(File.join(dir, ".crystal-combine-pdf.yml"))
      config.files.size.should eq(2)
      config.files[0].path.should eq("foo.pdf")
      config.files[0].password.should be_nil
      config.files[1].path.should eq("bar.pdf")
      config.files[1].title.should eq("Title")
      config.files[1].password.should be_nil
    end
  end

  describe "ConfigRefresher avec inline mapping" do
    it "préserve une ligne `- {path: x, password: y}` lors d'un refresh" do
      dir = File.join(SpecHelper::TMP_DIR, "refresh-inline")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "secure.pdf"))

      original = <<-YAML
        output: out.pdf
        title: ""
        files:
          - {path: secure.pdf, password: secret}
        YAML
      File.write(File.join(dir, ".crystal-combine-pdf.yml"), original)

      CombinePDF::ConfigRefresher.refresh(dir)
      refreshed = File.read(File.join(dir, ".crystal-combine-pdf.yml"))
      # La ligne inline est préservée mot-pour-mot
      refreshed.should contain("- {path: secure.pdf, password: secret}")
    end

    it "commente une entrée inline disparue (préserve la syntaxe)" do
      dir = File.join(SpecHelper::TMP_DIR, "refresh-inline-gone")
      Dir.mkdir_p(dir)
      # Pas de fichier ; refresh va commenter

      File.write(File.join(dir, ".crystal-combine-pdf.yml"), <<-YAML)
        output: out.pdf
        title: ""
        files:
          - {path: ghost.pdf, password: secret}
        YAML

      CombinePDF::ConfigRefresher.refresh(dir)
      refreshed = File.read(File.join(dir, ".crystal-combine-pdf.yml"))
      refreshed.should contain("# - {path: ghost.pdf, password: secret}")
    end
  end

  describe "Sous-commande decrypt (round-trip via CombinePDF.load + save)" do
    {% for level in [:rc4_128, :aes_128, :aes_256] %}
      it "déchiffre un PDF {{ level.id }} (CombinePDF.load avec password puis save sans encrypt)" do
        dir = File.join(SpecHelper::TMP_DIR, "dec-rt-{{ level.id }}")
        Dir.mkdir_p(dir)

        # 1. Encrypt via le shard pdf
        plain_path = File.join(dir, "plain.pdf")
        SpecHelper.write_a4(plain_path)
        pdf = CombinePDF.load(plain_path)
        pdf.encrypt(user_password: "k", level: {{ level }})
        encrypted_path = File.join(dir, "enc.pdf")
        pdf.save(encrypted_path)

        # 2. Decrypt
        decrypted_path = File.join(dir, "dec.pdf")
        loaded = CombinePDF.load(encrypted_path, password: "k")
        loaded.save(decrypted_path)

        # 3. Vérifier qu'il s'ouvre SANS mot de passe
        reader = PDF::Reader.open(decrypted_path)
        reader.page_count.should eq(1)
      end
    {% end %}
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
