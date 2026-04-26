module CombinePDF
  # Versioning convention :
  # X.Y.Z      = Ruby gem version we are ISO-compatible with
  # .N (4th)   = our additive iteration on top of that gem version
  #
  # 1.0.31.1 = first release synchronised with combine_pdf 1.0.31
  #            (Ruby gem of 2025-04-XX) — covers the high-level
  #            `CombinePDF.new`, `CombinePDF.load`, `CombinePDF.parse`,
  #            and `CombinePDF::PDF` instance API (`<<`, `>>`,
  #            `insert`, `remove`, `pages`, `page_count`, `new_page`,
  #            `title=`, `author=`, `number_pages`, `save`, `to_pdf`).
  VERSION = "1.0.31.1"
end
