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
  # 1.0.31.2 = mode déclaratif `.crystal-combine-pdf.yml` :
  #            * `crystal-combine-pdf --init [-r]`    (génère le YAML)
  #            * `crystal-combine-pdf --refresh [-r]` (rafraîchit la liste)
  #            * `crystal-combine-pdf` sans argument  (build le livret)
  #            Refonte de la numérotation (positions cardinales +
  #            outer/inner duplex-aware, styles plain/badge/circle/
  #            square/oval), couverture (mode + include_in_numbering),
  #            filigrane via `crystal-watermark`.
  VERSION = "1.0.31.2"
end
