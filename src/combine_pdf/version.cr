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
  VERSION = "1.0.31.4"
end
