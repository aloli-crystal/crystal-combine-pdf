require "option_parser"
require "./combine_pdf"

# crystal-combine-pdf CLI.
#
# v0.2 ships three sub-commands :
#
#   number    — number the pages of an existing PDF
#   merge     — concatenate several PDFs into one
#   assemble  — merge + number in one shot (booklet workflow)
#
# Examples (shell):
#   $ crystal-combine-pdf number booklet.pdf
#   $ crystal-combine-pdf merge p1.pdf p2.pdf p3.pdf -o out.pdf
#   $ crystal-combine-pdf assemble p1.pdf p2.pdf p3.pdf -o livret.pdf

# Common options.
output_path = ""
# `number` / `assemble` only.
partitions : Array(Int32)? = nil
skip_pages = [] of Int32
font_size = 10.0
margin = 24.0
color_str = "0.2,0.2,0.2"
global_format = "%page%/%total%"
partition_format = "%page%/%total%"
hide_partition_when_single = true

parser = OptionParser.new do |p|
  p.banner = <<-BANNER
    Usage : crystal-combine-pdf SOUS-COMMANDE [options] FICHIERS...

    Sous-commandes :
      number FICHIER                Numérote chaque page d'un PDF (A4-aware)
      merge FICHIER1 FICHIER2 ...   Concatène plusieurs PDF en un seul
      assemble FICHIER1 FICHIER2 .. Merge + numérotation auto (livret de partitions)

    Options communes :
    BANNER

  p.on("-o FICHIER", "--output FICHIER", "Fichier de sortie") { |v| output_path = v }

  p.separator ""
  p.separator "Options spécifiques à `number` et `assemble` :"

  p.on("--partitions LIST", "Tailles de partitions séparées par des virgules (ex: 4,2,1). Ignoré pour `assemble` qui les détecte automatiquement") do |v|
    partitions = v.split(',').map(&.strip.to_i)
  end
  p.on("--skip PAGES", "Pages à ne pas numéroter, séparées par des virgules (ex: 1,2)") do |v|
    skip_pages = v.split(',').map(&.strip.to_i)
  end
  p.on("--font-size SIZE", "Taille de police en points (défaut : 10)") { |v| font_size = v.to_f }
  p.on("--margin PT", "Marge depuis le bord de la page en points (défaut : 24)") { |v| margin = v.to_f }
  p.on("--color R,G,B", "Couleur RGB du texte (défaut : 0.2,0.2,0.2)") { |v| color_str = v }
  p.on("--global-format FMT", "Format global (défaut : '%page%/%total%')") { |v| global_format = v }
  p.on("--partition-format FMT", "Format intra-partition (défaut : '%page%/%total%')") { |v| partition_format = v }
  p.on("--show-single-partitions", "Toujours afficher le numéro intra-partition, même quand la partition fait 1 seule page") do
    hide_partition_when_single = false
  end

  p.separator ""
  p.separator "Aide :"

  p.on("-v", "--version", "Afficher la version") do
    puts "crystal-combine-pdf #{CombinePDF::VERSION}"
    exit 0
  end
  p.on("-h", "--help", "Afficher l'aide") do
    puts p
    exit 0
  end

  p.invalid_option do |flag|
    STDERR.puts "Option inconnue : #{flag}"
    STDERR.puts p
    exit 1
  end
end

# Collect positional arguments via `unknown_args` since OptionParser
# in Crystal does not return them from `parse`.
positional = [] of String
parser.unknown_args { |args| positional = args }
parser.parse(ARGV)

if positional.empty?
  STDERR.puts "Erreur : aucune sous-commande spécifiée"
  STDERR.puts parser
  exit 1
end

subcommand = positional.first
remaining = positional[1..]

# Helper : builds the Options object from the CLI flags.
def build_options(font_size, margin, color_str, global_format, partition_format,
                  hide_partition_when_single, skip_pages) : CombinePDF::Options
  color_parts = color_str.split(',').map(&.to_f)
  if color_parts.size != 3
    STDERR.puts "Erreur : la couleur doit être au format R,G,B (ex : 0.2,0.2,0.2)"
    exit 1
  end
  color = {color_parts[0], color_parts[1], color_parts[2]}

  CombinePDF::Options.new(
    font_size: font_size,
    color: color,
    margin: margin,
    global_format: global_format,
    partition_format: partition_format,
    hide_partition_when_single: hide_partition_when_single,
    skip_pages: skip_pages,
  )
end

case subcommand
when "number"
  if remaining.empty?
    STDERR.puts "Erreur : la sous-commande `number` attend un fichier PDF en argument"
    STDERR.puts parser
    exit 1
  end
  input_path = remaining.first

  unless File.exists?(input_path)
    STDERR.puts "Erreur : fichier introuvable : #{input_path}"
    exit 1
  end

  if output_path.empty?
    base = File.basename(input_path, File.extname(input_path))
    dir = File.dirname(input_path)
    output_path = File.join(dir, "#{base}-numbered.pdf")
  end

  options = build_options(font_size, margin, color_str, global_format,
    partition_format, hide_partition_when_single, skip_pages)

  begin
    CombinePDF.number(
      input: input_path,
      output: output_path,
      partitions: partitions,
      options: options,
    )
    puts "PDF numéroté : #{output_path}"
  rescue ex
    STDERR.puts "Erreur : #{ex.message}"
    exit 1
  end
when "merge"
  if remaining.size < 2
    STDERR.puts "Erreur : la sous-commande `merge` attend au moins deux fichiers PDF en argument"
    STDERR.puts parser
    exit 1
  end

  remaining.each do |path|
    unless File.exists?(path)
      STDERR.puts "Erreur : fichier introuvable : #{path}"
      exit 1
    end
  end

  if output_path.empty?
    output_path = "merged.pdf"
  end

  begin
    CombinePDF.merge(inputs: remaining, output: output_path)
    puts "PDF fusionné : #{output_path}"
  rescue ex
    STDERR.puts "Erreur : #{ex.message}"
    exit 1
  end
when "assemble"
  if remaining.size < 2
    STDERR.puts "Erreur : la sous-commande `assemble` attend au moins deux fichiers PDF en argument"
    STDERR.puts parser
    exit 1
  end

  remaining.each do |path|
    unless File.exists?(path)
      STDERR.puts "Erreur : fichier introuvable : #{path}"
      exit 1
    end
  end

  if output_path.empty?
    output_path = "livret.pdf"
  end

  options = build_options(font_size, margin, color_str, global_format,
    partition_format, hide_partition_when_single, skip_pages)

  begin
    CombinePDF.assemble(inputs: remaining, output: output_path, options: options)
    puts "Livret assemblé : #{output_path}"
  rescue ex
    STDERR.puts "Erreur : #{ex.message}"
    exit 1
  end
else
  STDERR.puts "Erreur : sous-commande inconnue « #{subcommand} »"
  STDERR.puts parser
  exit 1
end
