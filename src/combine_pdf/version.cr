module CombinePDF
  # Versioning convention :
  # X.Y.Z      = Ruby gem version we are ISO-compatible with
  # .N (4th)   = our additive iteration on top of that gem version
  #
  # 1.0.31.1 = first release ISO with combine_pdf 1.0.31
  #            (Ruby gem of 2025-04-XX). High-level `CombinePDF.new`,
  #            `CombinePDF.load`, `CombinePDF.parse`, and
  #            `CombinePDF::PDF` instance API (`<<`, `>>`, `insert`,
  #            `remove`, `pages`, `page_count`, `new_page`, `title=`,
  #            `author=`, `number_pages`, `save`, `to_pdf`).
  #
  # 1.0.31.8 = polish du rendu de la pastille `oval` :
  #            * Centrage vertical correct du texte dans la
  #              pastille (formule `cap_height/2` pour Helvetica
  #              au lieu de l'approximation par `descender`).
  #            * Format global par défaut : `- %page% / %total% -`
  #              (avec le total) au lieu de `- %page% -` — utile
  #              quand on tient juste une page du livret.
  #
  # 1.0.31.7 = rendu de la numérotation aligné sur le doc de
  #            référence laguiole-messe :
  #            * Couches `bold:` et `italic:` sur Layer (Helvetica
  #              Type1 standard, 4 variants).
  #            * Style `oval` enrichi : pastille pill gris pâle
  #              avec bordure noire fine — « ça marque l'œil ».
  #            * Défauts du template revus : partition en
  #              Helvetica-Bold 27pt format `%page% / %total%` ;
  #              global en style oval format `- %page% -`.
  #            * Section `files:` placée en haut du YAML (juste
  #              après title/author) — c'est la section la plus
  #              éditée.
  #
  # 1.0.31.6 = trois fix critiques :
  #            1. Numérotation visible : la police Helvetica est
  #               désormais injectée dans `/Resources /Font` de chaque
  #               page avant l'écriture du content stream. Sans ce
  #               correctif, certains viewers (Preview macOS, mupdf,
  #               viewers Web) refusaient de tracer le texte.
  #            2. `--refresh` ne corrompt plus le YAML : `String#lines`
  #               retire les `\n` par défaut en Crystal (différence
  #               avec Ruby) — `chomp: false` ajouté.
  #            3. Sous-commandes `init` / `refresh` / `build` en plus
  #               des flags `--init` / `--refresh`. Plus naturelles
  #               à taper.
  #
  # 1.0.31.5 = format de page configurable pour les pages générées
  #            par le shard (TOC, pages blanches, futurs entêtes/
  #            pieds-de-page) via le réglage `paper_size:` du YAML.
  #            Standards reconnus : a4, letter, legal, a3, a5, b5,
  #            executive ; format libre `WxH` en points. Override
  #            par-section disponible via `toc.page.paper_size`.
  #            Les PDF d'entrée gardent leur MediaBox d'origine.
  #
  # 1.0.31.4 = page de titre + sommaire cliquable insérée en tête
  #            du livret. La page TOC est générée à la volée
  #            (TocBuilder + Merger#insert_toc_page) avec
  #            annotations PDF /Link pointant vers chaque première
  #            page de partition. Encodage WinAnsi pour le rendu
  #            correct des caractères accentués.
  #
  # 1.0.31.3 = compatibilité PDF étendue via crystal-pdf v0.3.6 :
  #            tous les PDF du marché lisibles (xref streams 1.5+,
  #            object streams, scans CCITTFaxDecode, JPEG DCTDecode,
  #            LilyPond, MS Word, Finale, Sibelius). Le Merger
  #            respecte le drapeau `Stream#decoded` pour préserver
  #            `/Filter` et `/DecodeParms` sur les streams non
  #            décodables → les images ne se corrompent plus en
  #            pavés gris à la fusion.
  #
  # 1.0.31.2 = mode déclaratif `.crystal-combine-pdf.yml` :
  #            * `crystal-combine-pdf --init [-r]`    (génère le YAML)
  #            * `crystal-combine-pdf --refresh [-r]` (rafraîchit la liste)
  #            * `crystal-combine-pdf` sans argument  (build le livret)
  #            Refonte de la numérotation (positions cardinales +
  #            outer/inner duplex-aware, styles plain/badge/circle/
  #            square/oval), couverture (mode + include_in_numbering),
  #            filigrane via `crystal-watermark`.
  VERSION = "1.0.31.8"
end
