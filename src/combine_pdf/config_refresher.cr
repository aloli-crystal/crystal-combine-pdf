module CombinePDF
  # Met à jour la section `files:` d'un `.crystal-combine-pdf.yml`
  # existant après un ajout/retrait de PDF dans le dossier.
  #
  # Conserve scrupuleusement :
  # * tout le contenu hors-section `files:` (commentaires, valeurs)
  # * l'ordre courant des entrées `files:` (l'utilisateur a peut-être
  #   réordonné à la main)
  # * les entrées commentées (`# - foo.pdf`) — un fichier exclu
  #   manuellement reste exclu, même s'il n'existe plus sur disque
  # * les titres inline (`- foo.pdf: "Titre"`)
  #
  # Comportement :
  # * Tout PDF sur disque qui n'apparaît PAS du tout dans `files:`
  #   (ni actif, ni commenté) → ajouté en fin de section
  # * Toute entrée `- foo.pdf` active dont le fichier a disparu du
  #   disque → commentée avec annotation `# disparu le YYYY-MM-DD`
  # * Aucune autre modification
  module ConfigRefresher
    extend self

    # Rafraîchit le YAML dans `dir`. Renvoie un résumé textuel.
    def refresh(dir : String, recursive : Bool = false) : String
      target = File.join(dir, ConfigInitializer::CONFIG_FILENAME)
      unless File.exists?(target)
        raise "Aucun fichier #{ConfigInitializer::CONFIG_FILENAME} dans #{dir}. Lancez d'abord crystal-combine-pdf --init."
      end

      raw = File.read(target)
      pdfs_on_disk = ConfigInitializer.scan_pdfs(dir, recursive)
      new_raw, summary = update_files_section(raw, pdfs_on_disk)
      File.write(target, new_raw)
      summary
    end

    # Cœur de la logique, séparé pour faciliter les tests.
    # Renvoie le nouveau contenu du fichier + un résumé `"+N -M ~K"`.
    def update_files_section(
      raw : String,
      pdfs_on_disk : Array(String),
    ) : Tuple(String, String)
      lines = raw.lines
      files_idx = lines.index(&.starts_with?("files:"))

      unless files_idx
        # Pas de section files: → en ajouter une.
        new_lines = lines.dup
        new_lines << "\nfiles:\n"
        pdfs_on_disk.each do |path|
          new_lines << "  - #{ConfigInitializer.yaml_quote_if_needed(path)}\n"
        end
        return {new_lines.join, "+#{pdfs_on_disk.size} -0 ~0"}
      end

      # Délimite la section files: (du `files:` exclus jusqu'à la
      # prochaine section top-level OU fin de fichier).
      start_idx = files_idx + 1
      end_idx = start_idx
      while end_idx < lines.size
        line = lines[end_idx].chomp
        stripped = line.strip
        # Continue tant que : ligne vide, commentaire, ou entrée tableau
        if stripped.empty? || stripped.starts_with?("#") || line.match(/^\s*-\s+/)
          end_idx += 1
        else
          break
        end
      end

      header_lines = lines[0..files_idx]
      body_lines = lines[start_idx...end_idx]
      footer_lines = end_idx < lines.size ? lines[end_idx..] : [] of String

      # Indexer les chemins déjà présents (actifs ou commentés)
      known_paths = Set(String).new
      body_lines.each do |body_line|
        if md = body_line.match(/^\s*-\s+(.+)$/)
          path, _ = parse_entry_body_for_refresh(md[1])
          known_paths << path
        elsif md = body_line.match(/^\s*#\s*-\s+(.+)$/)
          path, _ = parse_entry_body_for_refresh(md[1])
          # Heuristique : ne considérer comme "known" qu'un chemin
          # plausible (avec extension ou /). Sinon c'est un commentaire libre.
          if path.includes?('.') || path.includes?('/')
            known_paths << path
          end
        end
      end

      # 1) Commenter les entrées actives dont le fichier a disparu
      disk_set = pdfs_on_disk.to_set
      removed = 0
      today = Time.local.to_s("%Y-%m-%d")
      body_lines = body_lines.map do |body_line|
        if md = body_line.match(/^(\s*)-\s+(.+)$/)
          indent = md[1]
          rest = md[2].rstrip
          path, _ = parse_entry_body_for_refresh(rest)
          if !disk_set.includes?(path) && (path.includes?('.') || path.includes?('/'))
            removed += 1
            "#{indent}# - #{rest}  # disparu le #{today}\n"
          else
            body_line
          end
        else
          body_line
        end
      end

      # 2) Ajouter en fin de section les fichiers du disque qui ne
      # sont pas déjà connus
      added = 0
      pdfs_on_disk.each do |path|
        next if known_paths.includes?(path)
        body_lines << "  - #{ConfigInitializer.yaml_quote_if_needed(path)}\n"
        added += 1
      end

      # Compter les inchangés
      unchanged = pdfs_on_disk.size - added

      new_raw = String.build do |s|
        header_lines.each { |l| s << l }
        body_lines.each { |l| s << l }
        footer_lines.each { |l| s << l }
      end

      summary = "+#{added} ajouté(s), -#{removed} retiré(s), ~#{unchanged} inchangé(s)"
      {new_raw, summary}
    end

    private def parse_entry_body_for_refresh(body : String) : Tuple(String, String?)
      body = body.rstrip
      # Strip everything after `  #` (commentaire trailing comme « # disparu le … »)
      if i = body.index("  #")
        body = body[0, i].rstrip
      end
      if i = body.index(':')
        path = body[0, i].strip
        rest = body[(i + 1)..].strip
        if rest.size >= 2 && rest[0]? == '"' && rest[-1]? == '"'
          rest = rest[1..-2]
        elsif rest.size >= 2 && rest[0]? == '\'' && rest[-1]? == '\''
          rest = rest[1..-2]
        end
        # Si le path lui-même est cité, retirer les guillemets
        if path.size >= 2 && (path[0]? == '"' || path[0]? == '\'')
          path = path[1..-2]
        end
        {path, rest.empty? ? nil : rest}
      else
        path = body.strip
        if path.size >= 2 && (path[0]? == '"' || path[0]? == '\'')
          path = path[1..-2]
        end
        {path, nil}
      end
    end
  end
end
