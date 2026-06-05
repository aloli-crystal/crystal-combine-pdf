require "./combine_pdf/cli"

# Standalone `crystal-combine-pdf` binary. All the logic lives in
# `CombinePDF::Cli.run` (in `src/combine_pdf/cli.cr`) so it can also be
# called in-process from the unified `alolipdf` binary
# (aloli-crystal/pdf-tools).
exit CombinePDF::Cli.run(ARGV)
