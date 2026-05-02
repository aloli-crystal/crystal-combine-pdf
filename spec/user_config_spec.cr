require "./spec_helper"

describe CombinePDF::UserConfig do
  describe ".load" do
    it "renvoie un résultat neutre quand le fichier n'existe pas" do
      result = CombinePDF::UserConfig.load("/tmp/nonexistent-#{Random.rand(10000)}.yml")
      result.profile.should eq("booklet")

      # L'override identité ne change rien
      opts = CombinePDF::ConfigInitializer.options_for_profile("booklet")
      out = result.overrides.call(opts)
      out.author.should be_nil
      out.paper_size.should eq("a4")
    end

    it "renvoie un résultat neutre quand le fichier est invalide YAML" do
      path = File.join(SpecHelper::TMP_DIR, "user-config-invalid.yml")
      Dir.mkdir_p(File.dirname(path))
      File.write(path, "{[invalid yaml")
      result = CombinePDF::UserConfig.load(path)
      result.profile.should eq("booklet")
    end

    it "lit default_profile" do
      path = File.join(SpecHelper::TMP_DIR, "user-config-profile.yml")
      Dir.mkdir_p(File.dirname(path))
      File.write(path, "default_profile: report\n")
      result = CombinePDF::UserConfig.load(path)
      result.profile.should eq("report")
    end

    it "applique author / paper_size / duplex / title / output" do
      path = File.join(SpecHelper::TMP_DIR, "user-config-overrides.yml")
      Dir.mkdir_p(File.dirname(path))
      File.write(path, <<-YAML)
        default_profile: book
        author: "Test User"
        paper_size: letter
        duplex: false
        title: "Override Title"
        output: override.pdf
        YAML

      result = CombinePDF::UserConfig.load(path)
      result.profile.should eq("book")

      opts = CombinePDF::ConfigInitializer.options_for_profile(result.profile)
      out = result.overrides.call(opts)
      out.author.should eq("Test User")
      out.paper_size.should eq("letter")
      out.duplex.should be_false
      out.title.should eq("Override Title")
      out.output.should eq("override.pdf")
    end

    it "applique duplex: false même quand le profil défaut est duplex: true" do
      # Régression : `if b = v.as_bool?` est falsy quand b est false.
      # On vérifie que `duplex: false` est bien lu.
      path = File.join(SpecHelper::TMP_DIR, "user-config-duplex-false.yml")
      Dir.mkdir_p(File.dirname(path))
      File.write(path, <<-YAML)
        default_profile: book
        duplex: false
        YAML

      result = CombinePDF::UserConfig.load(path)
      opts = CombinePDF::ConfigInitializer.options_for_profile(result.profile)
      opts.duplex.should be_true # book par défaut → duplex true
      out = result.overrides.call(opts)
      out.duplex.should be_false # surcharge appliquée
    end

    it "ignore les clés inconnues sans lever" do
      path = File.join(SpecHelper::TMP_DIR, "user-config-unknown.yml")
      Dir.mkdir_p(File.dirname(path))
      File.write(path, <<-YAML)
        default_profile: book
        author: "Known"
        zorblax: "future-extension"
        nested:
          key: value
        YAML

      result = CombinePDF::UserConfig.load(path)
      opts = CombinePDF::ConfigInitializer.options_for_profile(result.profile)
      out = result.overrides.call(opts)
      out.author.should eq("Known") # known field appliqué
    end
  end
end
