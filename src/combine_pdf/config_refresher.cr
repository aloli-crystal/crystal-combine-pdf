require "yaml"

module CombinePDF
  # Met à jour la section `files:` d'un `.combine-pdf.yml`
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
        raise "Aucun fichier #{ConfigInitializer::CONFIG_FILENAME} dans #{dir}. Lancez d'abord `combine-pdf init`."
      end

      raw = File.read(target)

      # 1) Capturer le `output:` AVANT le renommage — il peut survivre
      # sur disque (cas d'un dossier renommé : le PDF buildé sous
      # l'ancien nom traîne) et doit être exclu des inputs.
      old_output_basename = parse_output(raw)

      # 2) Mise à jour de output: et title: si le dossier a été
      # renommé.
      raw = maybe_update_output_and_title(raw, dir)
      new_output_basename = parse_output(raw)

      # 3) Exclure le PDF de sortie (ancien ET nouveau) de la liste
      # des fichiers d'entrée — sinon refresh l'ajouterait à files:
      # et le build se boucle.
      excluded = [old_output_basename, new_output_basename].reject(&.empty?).to_set
      pdfs_on_disk = ConfigInitializer.scan_pdfs(dir, recursive)
      pdfs_on_disk = pdfs_on_disk.reject { |p| excluded.includes?(File.basename(p)) }

      new_raw, summary = update_files_section(raw, pdfs_on_disk)
      File.write(target, new_raw)
      summary
    end

    # Parse la valeur de la clé top-level `output:` du YAML brut.
    # Retourne juste le basename (sans guillemets ni espaces).
    # Note : `[^\n]+` plutôt que `.+` car en Crystal, le flag `m`
    # rend `.` glouton ET match les newlines — `.+$` capture
    # jusqu'à la fin du fichier au lieu de la fin de ligne.
    private def parse_output(raw : String) : String
      if md = raw.match(/^output:\s*([^\n]+?)\s*$/m)
        File.basename(md[1].strip.gsub(/^["']|["']$/, ""))
      else
        ""
      end
    end

    # Met à jour `output:` pour qu'il suive le basename du dossier
    # (renommage du dossier → renommage du PDF de sortie).
    #
    # `title:` est mis à jour SEULEMENT s'il était auto-généré (égal
    # à l'ancien basename, déduit du `output:` actuel sans `.pdf`).
    # Si l'utilisateur a customisé `title:`, on le laisse intact.
    private def maybe_update_output_and_title(raw : String, dir : String) : String
      basename = File.basename(File.expand_path(dir))

      title_md = raw.match(/^title:\s*([^\n]+?)\s*$/m)
      output_md = raw.match(/^output:\s*([^\n]+?)\s*$/m)
      return raw unless title_md && output_md

      old_title = title_md[1].strip.gsub(/^["']|["']$/, "")
      old_output = output_md[1].strip.gsub(/^["']|["']$/, "")

      # Vérification de forme : output = "<X>.pdf" sans chemin ni espace.
      # Si ce n'est pas le cas (utilisateur a passé un chemin custom),
      # on ne touche à rien.
      return raw unless old_output.ends_with?(".pdf") &&
                        !old_output.includes?('/') &&
                        !old_output.includes?(' ')
      old_basename = old_output[0, old_output.size - 4]

      return raw if old_basename == basename # déjà aligné

      # Le dossier a été renommé → mettre à jour `output:`.
      raw = raw.sub(/^output:\s*[^\n]+$/m, "output: #{basename}.pdf")
      # `title:` mis à jour seulement s'il était l'ancien basename.
      if old_title == old_basename
        raw = raw.sub(/^title:\s*[^\n]+$/m, "title:  \"#{basename}\"")
      end
      raw
    end

    # Cœur de la logique, séparé pour faciliter les tests.
    # Renvoie le nouveau contenu du fichier + un résumé `"+N -M ~K"`.
    def update_files_section(
      raw : String,
      pdfs_on_disk : Array(String),
    ) : Tuple(String, String)
      # `chomp: false` PRÉSERVE le `\n` final de chaque ligne. En
      # Crystal (différemment de Ruby), `String#lines` supprime les
      # `\n` par défaut (`chomp: true`) ; sans cette option toutes
      # les lignes seraient ré-écrites sans séparateur et le YAML
      # ressortirait en une seule ligne géante.
      lines = raw.lines(chomp: false)
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

      # Délimite la section files: : la section s'arrête après la
      # DERNIÈRE entrée (active `- foo` ou commentée `# - foo.pdf`).
      # Les commentaires libres (en particulier les délimiteurs de
      # section type `# ─── Format de page ──`) marquent la sortie.
      # Les blancs entre entrées sont préservés ; ceux qui suivent la
      # dernière entrée vont au footer.
      start_idx = files_idx + 1
      last_entry_idx = start_idx - 1 # -1 si aucune entrée
      i = start_idx
      while i < lines.size
        line = lines[i].chomp
        stripped = line.strip

        if stripped.empty?
          # Ligne blanche : peut être inter-entrée ou trailing.
          # On regarde devant : si une entrée arrive, on continue ;
          # sinon, on s'arrête (la blanche fait partie du footer).
          j = i + 1
          next_is_entry = false
          while j < lines.size
            jline = lines[j].chomp
            jstripped = jline.strip
            if jstripped.empty?
              j += 1
            elsif jline.match(/^\s*-\s+/) || file_entry_comment?(jline)
              next_is_entry = true
              break
            else
              break
            end
          end
          break unless next_is_entry
          i += 1
        elsif line.match(/^\s*-\s+/)
          # Entrée active
          last_entry_idx = i
          i += 1
        elsif file_entry_comment?(line)
          # Entrée commentée plausible (« # - foo.pdf »)
          last_entry_idx = i
          i += 1
        elsif stripped.starts_with?("#") && (line.size - line.lstrip.size >= 2)
          # Commentaire libre INDENTÉ (intra-section, ex. « # Note »).
          # Préservé dans le body sans modifier last_entry_idx.
          i += 1
        else
          # Commentaire libre à colonne 0 (délimiteur de section type
          # « # ─── Format de page ──── ») OU autre ligne (clé YAML
          # top-level) → fin de la section files:
          break
        end
      end

      header_lines = lines[0..files_idx]
      body_lines = (last_entry_idx >= start_idx) ? lines[start_idx..last_entry_idx] : [] of String
      footer_start = (last_entry_idx >= start_idx) ? last_entry_idx + 1 : start_idx
      footer_lines = footer_start < lines.size ? lines[footer_start..] : [] of String

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

    # Vrai si la ligne ressemble à une entrée commentée de fichier
    # (« # - foo.pdf » ou « # - foo.pdf: "Titre" »), faux pour les
    # commentaires libres comme « # ─── Section ──── ».
    private def file_entry_comment?(line : String) : Bool
      md = line.match(/^\s*#\s*-\s+(.+)$/)
      return false unless md
      body = md[1].rstrip
      # Strip trailing inline comment « # disparu le … »
      if i = body.index("  #")
        body = body[0, i].rstrip
      end
      path, _ = parse_entry_body_for_refresh(body)
      path.includes?('.') || path.includes?('/')
    end

    private def parse_entry_body_for_refresh(body : String) : Tuple(String, String?)
      body = body.rstrip
      # Strip everything after `  #` (commentaire trailing comme « # disparu le … »)
      if i = body.index("  #")
        body = body[0, i].rstrip
      end

      # Forme inline mapping `{path: x, title: y, password: z}` :
      # on délègue au parseur YAML pour extraire le path proprement.
      if body.starts_with?('{') && body.ends_with?('}')
        return extract_path_from_inline(body)
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

    # Extrait `path` d'un inline mapping pour les besoins du refresh.
    # Retourne `{path, title}` ; `title` est ignoré par le refresh,
    # mais on respecte la signature du tuple.
    private def extract_path_from_inline(body : String) : Tuple(String, String?)
      data = YAML.parse(body)
      mapping = data.as_h?
      return {body, nil} unless mapping
      ["path", "name", "file"].each do |k|
        if v = mapping[YAML::Any.new(k)]?
          if s = v.as_s?
            return {s, nil}
          end
        end
      end
      {body, nil}
    rescue
      # YAML invalide → pas une inline mapping, traiter comme path nu
      {body, nil}
    end
  end
end
