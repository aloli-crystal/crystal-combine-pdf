require "option_parser"
require "./combine_pdf"

# crystal-combine-pdf CLI.
#
# v1.0.31.2 ajoute le mode déclaratif :
#
#   crystal-combine-pdf --init [--recursive]   crée .crystal-combine-pdf.yml
#   crystal-combine-pdf --refresh [--recursive]  rafraîchit la liste files:
#   crystal-combine-pdf                          construit le livret depuis le YAML
#
# Conserve les sous-commandes historiques :
#
#   number    — numérote les pages d'un PDF existant
#   merge     — concatène plusieurs PDF en un seul
#   assemble  — merge + numérotation auto (workflow livret en CLI)

# ─── Drapeaux globaux du mode déclaratif ──────────────────────────
mode_init = false
mode_refresh = false
recursive = false
target_dir = "."

# ─── Drapeaux des sous-commandes historiques ──────────────────────
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
    Usage : crystal-combine-pdf [options]                  (mode déclaratif)
            crystal-combine-pdf SOUS-COMMANDE [options] FICHIERS...

    Mode déclaratif (recommandé pour les livrets) :
      crystal-combine-pdf --init [--recursive]
        Crée un fichier .crystal-combine-pdf.yml dans le dossier courant,
        peuplé avec la liste des PDF présents.

      crystal-combine-pdf --refresh [--recursive]
        Met à jour la liste `files:` du YAML : ajoute en fin les nouveaux
        PDF, commente les entrées dont le fichier a disparu. Préserve
        commentaires, ordre et titres existants.

      crystal-combine-pdf
        Construit le livret depuis .crystal-combine-pdf.yml du dossier
        courant : assemble, numérote, ajoute filigrane et bookmarks.

    Sous-commandes historiques :
      number FICHIER                Numérote les pages d'un PDF existant
      merge FICHIER1 FICHIER2 ...   Concatène plusieurs PDF
      assemble FICHIER1 FICHIER2 .. Merge + numérotation en une commande

    Options :
    BANNER

  # Mode déclaratif
  p.on("-i", "--init", "Initialise un .crystal-combine-pdf.yml") { mode_init = true }
  p.on("-R", "--refresh", "Rafraîchit la liste `files:` du YAML existant") { mode_refresh = true }
  p.on("-r", "--recursive", "Mode récursif (avec --init ou --refresh)") { recursive = true }
  p.on("-d DIR", "--dir=DIR", "Dossier cible (défaut : .)") { |v| target_dir = v }

  p.separator ""
  p.separator "Options des sous-commandes historiques :"
  p.on("-o FICHIER", "--output=FICHIER", "Fichier de sortie") { |v| output_path = v }
  p.on("--partitions=LIST", "Tailles séparées par virgules (ex: 4,2,1)") do |v|
    partitions = v.split(',').map(&.strip.to_i)
  end
  p.on("--skip=PAGES", "Pages à ne pas numéroter (1-based, virgules)") do |v|
    skip_pages = v.split(',').map(&.strip.to_i)
  end
  p.on("--font-size=SIZE", "Taille de police (défaut : 10)") { |v| font_size = v.to_f }
  p.on("--margin=PT", "Marge en points (défaut : 24)") { |v| margin = v.to_f }
  p.on("--color=R,G,B", "Couleur RGB du texte (défaut : 0.2,0.2,0.2)") { |v| color_str = v }
  p.on("--global-format=FMT", "Format global (défaut : '%page%/%total%')") { |v| global_format = v }
  p.on("--partition-format=FMT", "Format intra-partition") { |v| partition_format = v }
  p.on("--show-single-partitions", "Affiche le numéro intra-partition même pour 1 page") do
    hide_partition_when_single = false
  end

  p.separator ""
  p.separator "Aide :"
  p.on("-v", "--version", "Affiche la version") do
    puts "crystal-combine-pdf #{CombinePDF::VERSION}"
    exit 0
  end
  p.on("-h", "--help", "Affiche l'aide") do
    puts p
    exit 0
  end

  p.invalid_option do |flag|
    STDERR.puts "Option inconnue : #{flag}"
    STDERR.puts p
    exit 1
  end
end

positional = [] of String
parser.unknown_args { |args| positional = args }
parser.parse(ARGV)

# ────────────────────────────────────────────────────────────────────
# Routing : déclaratif d'abord (--init / --refresh / build par défaut),
# sous-commandes historiques ensuite.
# ────────────────────────────────────────────────────────────────────

# Mode --init
if mode_init
  begin
    target = CombinePDF::ConfigInitializer.init(target_dir, recursive)
    puts "✓ Créé : #{target}"
    pdfs = CombinePDF::ConfigInitializer.scan_pdfs(target_dir, recursive)
    puts "  #{pdfs.size} fichier(s) PDF listé(s)#{recursive ? " (récursif)" : ""}"
    puts "  Éditez ce fichier puis lancez `crystal-combine-pdf` pour construire."
    exit 0
  rescue ex
    STDERR.puts "Erreur : #{ex.message}"
    exit 1
  end
end

# Mode --refresh
if mode_refresh
  begin
    summary = CombinePDF::ConfigRefresher.refresh(target_dir, recursive)
    puts "✓ Rafraîchi : #{summary}"
    exit 0
  rescue ex
    STDERR.puts "Erreur : #{ex.message}"
    exit 1
  end
end

# Mode déclaratif sans drapeau = build (lit le YAML et produit le PDF)
if positional.empty?
  yml = File.join(target_dir, CombinePDF::ConfigInitializer::CONFIG_FILENAME)
  if File.exists?(yml)
    begin
      builder = CombinePDF::BookletBuilder.from_dir(target_dir)
      output = builder.build
      puts "✓ Livret construit : #{output}"
      exit 0
    rescue ex
      STDERR.puts "Erreur : #{ex.message}"
      exit 1
    end
  else
    STDERR.puts "Erreur : aucune sous-commande spécifiée et aucun #{CombinePDF::ConfigInitializer::CONFIG_FILENAME} trouvé dans #{target_dir}."
    STDERR.puts ""
    STDERR.puts "Pour démarrer : crystal-combine-pdf --init"
    STDERR.puts parser
    exit 1
  end
end

subcommand = positional.first
remaining = positional[1..]

# ────────────────────────────────────────────────────────────────────
# Sous-commandes historiques
# ────────────────────────────────────────────────────────────────────

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
    STDERR.puts "Erreur : `number` attend un fichier PDF en argument"
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
    CombinePDF.number(input: input_path, output: output_path, partitions: partitions, options: options)
    puts "PDF numéroté : #{output_path}"
  rescue ex
    STDERR.puts "Erreur : #{ex.message}"
    exit 1
  end
when "merge"
  if remaining.size < 2
    STDERR.puts "Erreur : `merge` attend au moins deux fichiers PDF"
    STDERR.puts parser
    exit 1
  end
  remaining.each do |path|
    unless File.exists?(path)
      STDERR.puts "Erreur : fichier introuvable : #{path}"
      exit 1
    end
  end
  output_path = "merged.pdf" if output_path.empty?
  begin
    CombinePDF.merge(inputs: remaining, output: output_path)
    puts "PDF fusionné : #{output_path}"
  rescue ex
    STDERR.puts "Erreur : #{ex.message}"
    exit 1
  end
when "assemble"
  if remaining.size < 2
    STDERR.puts "Erreur : `assemble` attend au moins deux fichiers PDF"
    STDERR.puts parser
    exit 1
  end
  remaining.each do |path|
    unless File.exists?(path)
      STDERR.puts "Erreur : fichier introuvable : #{path}"
      exit 1
    end
  end
  output_path = "livret.pdf" if output_path.empty?
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
