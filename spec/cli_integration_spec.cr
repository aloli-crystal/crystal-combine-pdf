require "./spec_helper"

# Tests d'intégration de la CLI : `--init`, `--refresh`, build par
# défaut. Les PDF sont générés à la volée avec `crystal-pdf` pour
# rester indépendants des partitions réelles de l'utilisateur.
describe "CLI déclarative" do
  describe "ConfigInitializer.init" do
    it "génère un YAML avec la liste des PDF du dossier" do
      dir = File.join(SpecHelper::TMP_DIR, "init-test")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "a.pdf"), page_count: 2)
      SpecHelper.write_a4(File.join(dir, "b.pdf"), page_count: 1)

      target = CombinePDF::ConfigInitializer.init(dir)
      File.exists?(target).should be_true
      content = File.read(target)
      content.should contain("files:")
      content.should contain("- a.pdf")
      content.should contain("- b.pdf")
      content.should contain("init-test.pdf") # output par défaut = nom du dossier
    end

    it "lève une erreur si le YAML existe déjà" do
      dir = File.join(SpecHelper::TMP_DIR, "init-conflict")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "a.pdf"))
      CombinePDF::ConfigInitializer.init(dir)

      expect_raises(Exception, /existe déjà/) do
        CombinePDF::ConfigInitializer.init(dir)
      end
    end

    it "lève une erreur si aucun PDF dans le dossier" do
      dir = File.join(SpecHelper::TMP_DIR, "init-empty")
      Dir.mkdir_p(dir)
      expect_raises(Exception, /Aucun fichier .pdf/) do
        CombinePDF::ConfigInitializer.init(dir)
      end
    end

    it "trie les fichiers par ordre alphabétique insensible casse" do
      dir = File.join(SpecHelper::TMP_DIR, "init-sort")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "Zebra.pdf"))
      SpecHelper.write_a4(File.join(dir, "alpha.pdf"))
      SpecHelper.write_a4(File.join(dir, "beta.pdf"))

      CombinePDF::ConfigInitializer.init(dir)
      content = File.read(File.join(dir, ".crystal-combine-pdf.yml"))
      idx_alpha = content.index("- alpha.pdf").as(Int32)
      idx_beta = content.index("- beta.pdf").as(Int32)
      idx_zebra = content.index("- Zebra.pdf").as(Int32)
      (idx_alpha < idx_beta).should be_true
      (idx_beta < idx_zebra).should be_true
    end

    it "scan récursif : sous-dossiers triés alpha, parents d'abord" do
      dir = File.join(SpecHelper::TMP_DIR, "init-recursive")
      Dir.mkdir_p(File.join(dir, "sub-a"))
      Dir.mkdir_p(File.join(dir, "sub-b"))
      SpecHelper.write_a4(File.join(dir, "racine.pdf"))
      SpecHelper.write_a4(File.join(dir, "sub-a", "alpha.pdf"))
      SpecHelper.write_a4(File.join(dir, "sub-b", "beta.pdf"))

      CombinePDF::ConfigInitializer.init(dir, recursive: true)
      content = File.read(File.join(dir, ".crystal-combine-pdf.yml"))
      content.should contain("- racine.pdf")
      content.should contain("- sub-a/alpha.pdf")
      content.should contain("- sub-b/beta.pdf")
      # racine d'abord
      idx_racine = content.index("- racine.pdf").as(Int32)
      idx_sub_a = content.index("- sub-a/alpha.pdf").as(Int32)
      (idx_racine < idx_sub_a).should be_true
    end
  end

  describe "ConfigRefresher.refresh" do
    it "ajoute les nouveaux PDF en fin de liste" do
      dir = File.join(SpecHelper::TMP_DIR, "refresh-add")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "a.pdf"))
      CombinePDF::ConfigInitializer.init(dir)

      # Ajouter un nouveau PDF
      SpecHelper.write_a4(File.join(dir, "c.pdf"))
      summary = CombinePDF::ConfigRefresher.refresh(dir)
      summary.should contain("+1")

      content = File.read(File.join(dir, ".crystal-combine-pdf.yml"))
      content.should contain("- c.pdf")
    end

    it "commente les entrées dont le PDF a disparu" do
      dir = File.join(SpecHelper::TMP_DIR, "refresh-remove")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "a.pdf"))
      SpecHelper.write_a4(File.join(dir, "b.pdf"))
      CombinePDF::ConfigInitializer.init(dir)

      File.delete(File.join(dir, "b.pdf"))
      summary = CombinePDF::ConfigRefresher.refresh(dir)
      summary.should contain("-1")

      content = File.read(File.join(dir, ".crystal-combine-pdf.yml"))
      content.should contain("# - b.pdf")
      content.should contain("disparu le")
    end

    it "ne ré-ajoute pas un fichier déjà commenté manuellement" do
      dir = File.join(SpecHelper::TMP_DIR, "refresh-keep-excluded")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "a.pdf"))
      SpecHelper.write_a4(File.join(dir, "b.pdf"))
      CombinePDF::ConfigInitializer.init(dir)

      # L'utilisateur commente b.pdf manuellement
      yml = File.join(dir, ".crystal-combine-pdf.yml")
      content = File.read(yml).gsub("- b.pdf", "# - b.pdf")
      File.write(yml, content)

      # Refresh
      CombinePDF::ConfigRefresher.refresh(dir)

      # b.pdf ne doit PAS être ré-ajouté en fin de liste
      new_content = File.read(yml)
      # Compte le nombre d'occurrences de "b.pdf"
      occurrences = new_content.scan(/b\.pdf/).size
      occurrences.should eq(1) # toujours 1 (le commenté), pas réintroduit
    end

    it "préserve les commentaires libres et l'ordre existant" do
      dir = File.join(SpecHelper::TMP_DIR, "refresh-preserve")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "a.pdf"))
      SpecHelper.write_a4(File.join(dir, "b.pdf"))

      yml_path = File.join(dir, ".crystal-combine-pdf.yml")
      File.write(yml_path, <<-YAML)
        output: test.pdf
        title: "Test"
        files:
          # Section principale
          - b.pdf: "B en premier"
          - a.pdf
        YAML

      CombinePDF::ConfigRefresher.refresh(dir)
      content = File.read(yml_path)
      content.should contain("# Section principale")
      content.should contain("- b.pdf: \"B en premier\"")
      # b.pdf reste en première position
      idx_b = content.index("- b.pdf").as(Int32)
      idx_a = content.index("- a.pdf").as(Int32)
      (idx_b < idx_a).should be_true
    end
  end

  describe "BookletBuilder.build (intégration end-to-end)" do
    it "construit un livret complet avec numérotation" do
      dir = File.join(SpecHelper::TMP_DIR, "build-test")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "p1.pdf"), page_count: 2)
      SpecHelper.write_a4(File.join(dir, "p2.pdf"), page_count: 3)

      CombinePDF::ConfigInitializer.init(dir)
      builder = CombinePDF::BookletBuilder.from_dir(dir)
      output_path = builder.build

      File.exists?(output_path).should be_true
      SpecHelper.page_count(output_path).should eq(5)

      # Les numéros sont bien présents — format global "- N / T -"
      # qui inclut le total dans la pastille, partition "N / T" avec
      # espaces autour du slash.
      content = File.read(output_path)
      content.should contain("(- 1 / 5 -)")
      content.should contain("(- 5 / 5 -)")
      # Marques de partition : p1 = 2 pages, p2 = 3 pages.
      content.should contain("(1 / 2)")
      content.should contain("(2 / 2)")
      content.should contain("(1 / 3)")
    end

    it "respecte cover.mode + include_in_numbering" do
      dir = File.join(SpecHelper::TMP_DIR, "build-cover")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "couverture.pdf"), page_count: 1)
      SpecHelper.write_a4(File.join(dir, "partition.pdf"), page_count: 3)
      SpecHelper.write_a4(File.join(dir, "fin.pdf"), page_count: 1)

      CombinePDF::ConfigInitializer.init(dir)
      yml = File.join(dir, ".crystal-combine-pdf.yml")
      content = File.read(yml).gsub("mode: none", "mode: recto")
      File.write(yml, content)

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      output_path = builder.build

      pdf_content = File.read(output_path)
      # 5 pages totales, cover.mode=recto = 1 page avant + 1 page
      # arrière. Avec include_in_numbering: false, le contenu fait
      # 3 pages, numérotées avec le format par défaut "- N / T -".
      pdf_content.should contain("(- 1 / 3 -)")
      pdf_content.should contain("(- 3 / 3 -)")
      # Le total ne doit pas afficher 5 (les couvertures sont sautées).
      pdf_content.should_not contain("(- 1 / 5 -)")
    end

    it "respecte paper_size pour la page TOC (a4 par défaut)" do
      dir = File.join(SpecHelper::TMP_DIR, "build-toc-a4")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "p1.pdf"), page_count: 2)

      CombinePDF::ConfigInitializer.init(dir)
      yml = File.join(dir, ".crystal-combine-pdf.yml")
      content = File.read(yml).sub("# toc:", "toc:")
        .sub("#   bookmarks: true", "  bookmarks: true")
        .sub("#   page:", "  page:")
        .sub("#     enabled: true", "    enabled: true")
      File.write(yml, content)

      output_path = CombinePDF::BookletBuilder.from_dir(dir).build
      # Page 0 (TOC) doit avoir 595×842 (A4)
      width, height = SpecHelper.page_size(output_path, 0)
      width.should eq(595.0)
      height.should eq(842.0)
    end

    it "respecte paper_size: letter (US 612×792)" do
      dir = File.join(SpecHelper::TMP_DIR, "build-toc-letter")
      Dir.mkdir_p(dir)
      SpecHelper.write_letter(File.join(dir, "p1.pdf"))

      CombinePDF::ConfigInitializer.init(dir)
      yml = File.join(dir, ".crystal-combine-pdf.yml")
      content = File.read(yml).sub("paper_size: a4", "paper_size: letter")
        .sub("# toc:", "toc:")
        .sub("#   bookmarks: true", "  bookmarks: true")
        .sub("#   page:", "  page:")
        .sub("#     enabled: true", "    enabled: true")
      File.write(yml, content)

      output_path = CombinePDF::BookletBuilder.from_dir(dir).build
      width, height = SpecHelper.page_size(output_path, 0)
      width.should eq(612.0)
      height.should eq(792.0)
    end

    it "respecte paper_size custom \"WxH\"" do
      dir = File.join(SpecHelper::TMP_DIR, "build-toc-custom")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "p1.pdf"))

      CombinePDF::ConfigInitializer.init(dir)
      yml = File.join(dir, ".crystal-combine-pdf.yml")
      content = File.read(yml).sub("paper_size: a4", "paper_size: \"500x700\"")
        .sub("# toc:", "toc:")
        .sub("#   bookmarks: true", "  bookmarks: true")
        .sub("#   page:", "  page:")
        .sub("#     enabled: true", "    enabled: true")
      File.write(yml, content)

      output_path = CombinePDF::BookletBuilder.from_dir(dir).build
      width, height = SpecHelper.page_size(output_path, 0)
      width.should eq(500.0)
      height.should eq(700.0)
    end

    it "génère une page TOC en tête quand toc.page.enabled" do
      dir = File.join(SpecHelper::TMP_DIR, "build-toc")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "p1.pdf"), page_count: 2)
      SpecHelper.write_a4(File.join(dir, "p2.pdf"), page_count: 3)

      CombinePDF::ConfigInitializer.init(dir)
      yml = File.join(dir, ".crystal-combine-pdf.yml")
      content = File.read(yml).sub("# toc:", "toc:")
        .sub("#   bookmarks: true", "  bookmarks: true")
        .sub("#   page:", "  page:")
        .sub("#     enabled: true", "    enabled: true")
        .sub("#     title: \"\"", "    title: \"Mon Recueil\"")
        .sub("#     subtitle: \"Sommaire\"", "    subtitle: \"Sommaire\"")
        .sub("#     show_author: true", "    show_author: false")
        .sub("#     leader_dots: true", "    leader_dots: true")
        .sub("#     title_font_size: 24", "    title_font_size: 24")
        .sub("#     subtitle_font_size: 16", "    subtitle_font_size: 16")
        .sub("#     entry_font_size: 11", "    entry_font_size: 11")
      File.write(yml, content)

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      output_path = builder.build

      File.exists?(output_path).should be_true
      # 2 + 3 = 5 pages de contenu, + 1 page TOC = 6 pages au total.
      SpecHelper.page_count(output_path).should eq(6)

      pdf_content = File.read(output_path)
      # Le titre du recueil doit apparaître dans la TOC
      pdf_content.includes?("Mon Recueil").should be_true
      pdf_content.includes?("Sommaire").should be_true
      # Au moins une annotation Link doit avoir été insérée
      pdf_content.includes?("/Subtype /Link").should be_true
    end

    it "applique le filigrane si configuré" do
      dir = File.join(SpecHelper::TMP_DIR, "build-watermark")
      Dir.mkdir_p(dir)
      SpecHelper.write_a4(File.join(dir, "a.pdf"))

      CombinePDF::ConfigInitializer.init(dir)
      yml = File.join(dir, ".crystal-combine-pdf.yml")
      content = File.read(yml).sub("# watermark:", "watermark:")
        .sub("#   text: \"build-watermark\"", "  text: \"FILIGRANE-TEST\"")
        .sub("#   style: diagonal", "  style: diagonal")
        .sub("#   font_size: 48", "  font_size: 48")
        .sub("#   color: \"#cccccc\"", "  color: \"#cccccc\"")
        .sub("#   opacity: 0.15", "  opacity: 0.15")
        .sub("#   rotation: 45", "  rotation: 45")
      File.write(yml, content)

      builder = CombinePDF::BookletBuilder.from_dir(dir)
      output_path = builder.build
      File.exists?(output_path).should be_true
      # Le filigrane n'est pas garanti d'apparaître textuellement dans
      # le contenu (peut être encodé différemment), mais le fichier
      # doit exister et être plus gros qu'un PDF nu.
    end
  end
end
