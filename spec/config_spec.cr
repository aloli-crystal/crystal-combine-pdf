require "./spec_helper"

describe CombinePDF::Config do
  describe "défauts" do
    it "instancie une config vide cohérente" do
      c = CombinePDF::Config.new
      c.output.should eq("output.pdf")
      c.duplex.should be_false
      c.cover.mode.should eq("none")
      c.cover.front_pages.should eq(0)
      c.cover.back_pages.should eq(0)
      c.numbering.enabled.should be_true
      c.numbering.global.position.should eq("bottom-right")
      c.numbering.partition.hide_when_single.should be_true
      c.toc.should be_nil
      c.watermark.should be_nil
      c.files.empty?.should be_true
    end
  end

  describe CombinePDF::Config::Cover do
    it "calcule front_pages et back_pages selon mode" do
      none = CombinePDF::Config::Cover.new(mode: "none")
      none.front_pages.should eq(0)
      none.back_pages.should eq(0)

      recto = CombinePDF::Config::Cover.new(mode: "recto")
      recto.front_pages.should eq(1)
      recto.back_pages.should eq(1)

      rv = CombinePDF::Config::Cover.new(mode: "recto-verso")
      rv.front_pages.should eq(2)
      rv.back_pages.should eq(2)
    end

    it "front: et back: priment sur mode:" do
      asym = CombinePDF::Config::Cover.new(
        mode: "recto",
        front: "recto-verso",
        back: "none",
      )
      asym.front_pages.should eq(2) # surchargé
      asym.back_pages.should eq(0)  # surchargé
    end
  end

  describe CombinePDF::Config::FileEntry do
    it "display_title préfère le titre explicite" do
      entry = CombinePDF::Config::FileEntry.new(
        path: "si-le-pere.pdf",
        title: "Si le Père vous appelle",
      )
      entry.display_title.should eq("Si le Père vous appelle")
    end

    it "display_title dérive du nom de fichier sans extension si pas de titre" do
      entry = CombinePDF::Config::FileEntry.new(path: "si-le-pere.pdf")
      entry.display_title.should eq("si le pere")
    end

    it "remplace tirets et underscores par espaces" do
      entry = CombinePDF::Config::FileEntry.new(path: "notre_pere-final.pdf")
      entry.display_title.should eq("notre pere final")
    end
  end
end

describe CombinePDF::ConfigLoader do
  describe "parse YAML standard" do
    it "lit les champs top-level" do
      yaml = <<-YAML
        output: livret.pdf
        title: "Recueil 2026"
        author: "Philippe"
        duplex: true
        files:
          - a.pdf
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.output.should eq("livret.pdf")
      c.title.should eq("Recueil 2026")
      c.author.should eq("Philippe")
      c.duplex.should be_true
    end

    it "parse cover avec mode + include_in_numbering" do
      yaml = <<-YAML
        cover:
          mode: recto-verso
          include_in_numbering: true
        files:
          - a.pdf
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.cover.mode.should eq("recto-verso")
      c.cover.include_in_numbering.should be_true
      c.cover.front_pages.should eq(2)
    end

    it "parse cover avec front/back asymétriques" do
      yaml = <<-YAML
        cover:
          front: recto-verso
          back: recto
        files:
          - a.pdf
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.cover.front_pages.should eq(2)
      c.cover.back_pages.should eq(1)
    end

    it "parse numbering avec global/partition surchargés" do
      yaml = <<-YAML
        numbering:
          enabled: true
          global:
            format: "- %page% -"
            style: badge
            position: outer-bottom
            font_size: 12
            color: "#444444"
            margin: 30
          partition:
            enabled: false
        files:
          - a.pdf
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.numbering.global.format.should eq("- %page% -")
      c.numbering.global.style.should eq("badge")
      c.numbering.global.position.should eq("outer-bottom")
      c.numbering.global.font_size.should eq(12.0)
      c.numbering.global.color.should eq({0x44/255.0, 0x44/255.0, 0x44/255.0})
      c.numbering.global.margin.should eq(30.0)
      c.numbering.partition.enabled.should be_false
    end

    it "parse couleur format R,G,B" do
      yaml = <<-YAML
        numbering:
          global:
            color: "0.5, 0.6, 0.7"
        files: []
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.numbering.global.color.should eq({0.5, 0.6, 0.7})
    end

    it "parse skip_pages comme tableau d'entiers" do
      yaml = <<-YAML
        numbering:
          skip_pages: [1, 2, 14]
        files: []
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.numbering.skip_pages.should eq([1, 2, 14])
    end

    it "parse toc.bookmarks" do
      yaml = <<-YAML
        toc:
          bookmarks: true
        files: []
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.toc.should_not be_nil
      c.toc.not_nil!.bookmarks.should be_true
    end

    it "parse watermark complet" do
      yaml = <<-YAML
        watermark:
          text: "Recueil 2026"
          style: tiled
          font_size: 60
          color: "#cccccc"
          opacity: 0.2
          rotation: 30
        files: []
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      wm = c.watermark.not_nil!
      wm.text.should eq("Recueil 2026")
      wm.style.should eq("tiled")
      wm.font_size.should eq(60)
      wm.opacity.should eq(0.2)
      wm.rotation.should eq(30.0)
    end

    it "watermark sans texte = nil (rien à filigraner)" do
      yaml = <<-YAML
        watermark:
          style: diagonal
        files: []
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.watermark.should be_nil
    end
  end

  describe "parse files: ligne-par-ligne" do
    it "lit une liste simple de chemins" do
      yaml = <<-YAML
        files:
          - couverture.pdf
          - partition1.pdf
          - notre-pere.pdf
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.files.size.should eq(3)
      c.files.map(&.path).should eq(["couverture.pdf", "partition1.pdf", "notre-pere.pdf"])
      c.files.all? { |f| !f.excluded }.should be_true
      c.files.all? { |f| f.title.nil? }.should be_true
    end

    it "lit la forme `- foo.pdf: \"Titre\"`" do
      yaml = <<-YAML
        files:
          - couverture.pdf
          - si-le-pere.pdf: "Si le Père vous appelle"
          - notre-pere.pdf: "Notre Père"
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.files.size.should eq(3)
      c.files[0].title.should be_nil
      c.files[1].path.should eq("si-le-pere.pdf")
      c.files[1].title.should eq("Si le Père vous appelle")
      c.files[2].title.should eq("Notre Père")
    end

    it "lit les entrées commentées comme `excluded: true`" do
      yaml = <<-YAML
        files:
          - couverture.pdf
          # - ancien-brouillon.pdf
          - partition1.pdf
          # - vieux-titre.pdf: "Ancien titre"
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.files.size.should eq(4)
      c.files.map(&.path).should eq(["couverture.pdf", "ancien-brouillon.pdf", "partition1.pdf", "vieux-titre.pdf"])
      c.files.map(&.excluded).should eq([false, true, false, true])
      c.files[3].title.should eq("Ancien titre")
    end

    it "ignore les commentaires libres dans la section files:" do
      yaml = <<-YAML
        files:
          # Section couverture
          - couverture.pdf
          # Partitions principales
          - partition1.pdf
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      # Les commentaires libres ("Section couverture") ne sont pas
      # confondus avec des entrées commentées (pas de "- " après le #).
      c.files.size.should eq(2)
      c.files.map(&.path).should eq(["couverture.pdf", "partition1.pdf"])
    end

    it "retire les guillemets autour des noms de fichiers cités" do
      yaml = <<-YAML
        files:
          - "Messe Signe d'amour Kyrie.pdf"
          - 'Tout vient de toi.pdf'
          - "Avec un titre.pdf": "Titre Personnalisé"
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.files.size.should eq(3)
      c.files[0].path.should eq("Messe Signe d'amour Kyrie.pdf")
      c.files[1].path.should eq("Tout vient de toi.pdf")
      c.files[2].path.should eq("Avec un titre.pdf")
      c.files[2].title.should eq("Titre Personnalisé")
    end

    it "s'arrête à la section suivante" do
      yaml = <<-YAML
        files:
          - a.pdf
          - b.pdf
        author: "Quelqu'un"
        YAML
      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.files.size.should eq(2)
      c.author.should eq("Quelqu'un")
    end
  end

  describe "intégration : fichier complet" do
    it "lit un YAML représentatif sans erreur" do
      yaml = <<-YAML
        output: laguiole-messe.pdf
        title: "Laguiole — Messe du 26 avril"
        author: "Philippe Nénert"
        duplex: true

        cover:
          mode: recto-verso
          include_in_numbering: false

        numbering:
          enabled: true
          global:
            format: "- %page% -"
            style: badge
            position: outer-bottom
            font_size: 10
            color: "#333333"
            margin: 24
          partition:
            enabled: true
            format: "%page%/%total%"
            position: outer-top
            font_size: 9
            color: "#666666"
            hide_when_single: true
          skip_pages: []

        toc:
          bookmarks: true

        files:
          - 2026-04-26--laguiole-messe-feuille.pdf: "Déroulé"
          - "Messe Signe d'amour Kyrie.pdf": "Kyrie"
          # - "Messe Signe d'amour Kyrie copie.pdf"
          - "si-le-pere-vous-appelle--0154-1 T154-1.pdf": "Si le Père vous appelle"
        YAML

      c = CombinePDF::ConfigLoader.load_string(yaml)
      c.output.should eq("laguiole-messe.pdf")
      c.duplex.should be_true
      c.cover.mode.should eq("recto-verso")
      c.cover.front_pages.should eq(2)
      c.cover.back_pages.should eq(2)
      c.numbering.global.format.should eq("- %page% -")
      c.numbering.global.style.should eq("badge")
      c.toc.not_nil!.bookmarks.should be_true
      c.files.size.should eq(4)
      c.files[0].title.should eq("Déroulé")
      c.files[2].excluded.should be_true
      c.files[3].title.should eq("Si le Père vous appelle")
    end
  end
end
