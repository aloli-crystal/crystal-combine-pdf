require "option_parser"
require "./combine_pdf"

# crystal-combine-pdf CLI.
#
# v0.1 ships a single sub-command: `number`. Multi-PDF merging will
# come in v0.2.
#
# ```
# # Number an A4 booklet, format "N/T" in the bottom-right corner.
# crystal-combine-pdf number booklet.pdf
#
# # Same but mark intra-partition pages too. Partition sizes are
# # given in 1-based page order — sum must equal the total page
# # count.
# crystal-combine-pdf number booklet.pdf --partitions 4,2,1
#
# # Skip page 1 (the cover) and write to a custom path.
# crystal-combine-pdf number booklet.pdf --output out.pdf --skip 1
# ```

input_path = ""
output_path = ""
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
    Usage : crystal-combine-pdf SUBCOMMAND [options]

    Sous-commandes :
      number FICHIER       Numérote chaque page du PDF (format A4-aware)

    Options de la sous-commande `number` :
    BANNER

  p.on("-o FICHIER", "--output FICHIER", "Fichier de sortie (défaut : <input>-numbered.pdf)") { |v| output_path = v }
  p.on("--partitions LIST", "Tailles de partitions séparées par des virgules (ex: 4,2,1)") do |v|
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

  color_parts = color_str.split(',').map(&.to_f)
  if color_parts.size != 3
    STDERR.puts "Erreur : la couleur doit être au format R,G,B (ex : 0.2,0.2,0.2)"
    exit 1
  end
  color = {color_parts[0], color_parts[1], color_parts[2]}

  options = CombinePDF::Options.new(
    font_size: font_size,
    color: color,
    margin: margin,
    global_format: global_format,
    partition_format: partition_format,
    hide_partition_when_single: hide_partition_when_single,
    skip_pages: skip_pages,
  )

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
else
  STDERR.puts "Erreur : sous-commande inconnue « #{subcommand} »"
  STDERR.puts parser
  exit 1
end
