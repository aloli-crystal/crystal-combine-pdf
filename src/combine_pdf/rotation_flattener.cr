module CombinePDF
  # Détecte les pages d'un PDF source dont l'attribut `/Rotate`
  # n'est pas 0 et, le cas échéant, applique la rotation aux flux
  # de contenu (« flatten ») via `qpdf --flatten-rotation`.
  #
  # Pourquoi : Aperçu macOS et la plupart des viewers PDF tournent
  # une page via le tag `/Rotate` du dict de page, sans réécrire
  # les opérateurs de contenu. Visuellement correct dans le viewer,
  # mais un assemblage naïf qui ignore le tag réincorpore la page
  # à l'envers dans le PDF final, et l'extraction de texte rend
  # le contenu inversé. Ce module sert de garde-fou en amont du
  # merger.
  #
  # Politique par défaut : si `qpdf` est installé et que le PDF
  # source contient au moins une page rotatée, on cuit la
  # rotation dans un fichier temporaire et on utilise ce dernier
  # pour la suite. Sans `qpdf`, on émet un avertissement sur
  # `STDERR` mais on poursuit avec le fichier original — l'utilisateur
  # est ainsi informé du risque sans que le pipeline plante.
  module RotationFlattener
    extend self

    class Error < Exception
    end

    record DetectResult,
      rotated_pages : Array(Int32) do
      def any? : Bool
        !rotated_pages.empty?
      end
    end

    # Recense les indices (1-based) des pages dont `/Rotate` n'est
    # pas un multiple de 360. Lecture seule, aucun I/O au-delà du
    # `PDF::Reader`.
    def detect(path : String, password : String = "") : DetectResult
      reader = ::PDF::Reader.open(path, password: password)
      rotated = [] of Int32
      reader.pages.each_with_index do |page, idx|
        rotated << idx + 1 if page.rotate != 0
      end
      DetectResult.new(rotated)
    end

    # Applique `qpdf --flatten-rotation` sur `path` et écrit le
    # résultat dans `output`. Lève `Error` si `qpdf` n'est pas
    # installé ou si la conversion échoue.
    def flatten!(path : String, output : String) : Nil
      unless qpdf_available?
        raise Error.new(
          "qpdf binary not found in PATH (requis pour cuire " \
          "la rotation /Rotate). Install : `brew install qpdf` " \
          "(macOS), `pkg install qpdf` (FreeBSD), " \
          "`apt install qpdf` (Debian/Ubuntu)."
        )
      end

      err_buf = IO::Memory.new
      status = Process.run(
        "qpdf",
        ["--flatten-rotation", path, output],
        output: Process::Redirect::Close,
        error: err_buf,
      )
      unless status.success?
        File.delete(output) if File.exists?(output)
        raise Error.new(
          "qpdf --flatten-rotation a échoué (exit #{status.exit_code}). " \
          "stderr : #{err_buf.to_s.lines.first?.try(&.strip)}"
        )
      end
    end

    # Pré-traite `path` si l'une de ses pages porte `/Rotate ≠ 0`.
    # Retourne le chemin à utiliser pour la suite : le fichier
    # original si rien à faire, sinon un fichier temporaire dont
    # l'appelant est responsable de la suppression (cf. le bloc
    # `ensure` des callers).
    #
    # Politique de fallback :
    # * `enabled = false`           → no-op, retourne `path`
    # * pas de page rotatée         → no-op, retourne `path`
    # * qpdf disponible             → cuit dans un temp, retourne temp
    # * qpdf absent + warn_io != nil → message + retourne `path`
    # * qpdf absent + warn_io == nil → lève `Error`
    def preprocess(
      path : String,
      password : String = "",
      enabled : Bool = true,
      warn_io : IO? = STDERR,
    ) : String
      return path unless enabled
      result = detect(path, password: password)
      return path if result.rotated_pages.empty?

      unless qpdf_available?
        msg = "⚠ #{path} : #{result.rotated_pages.size} page(s) " \
              "avec /Rotate ≠ 0 (#{result.rotated_pages.join(", ")}). " \
              "qpdf absent — la rotation ne sera pas cuite ; " \
              "le PDF assemblé risque d'avoir ces pages à l'envers. " \
              "Install : `brew install qpdf`."
        if io = warn_io
          io.puts msg
          return path
        else
          raise Error.new(msg)
        end
      end

      tmp = "#{path}.flatten-rotation.tmp.#{Process.pid}.pdf"
      flatten!(path, tmp)
      if io = warn_io
        io.puts "✓ #{path} : cuit /Rotate sur #{result.rotated_pages.size} " \
                "page(s) (#{result.rotated_pages.join(", ")})."
      end
      tmp
    end

    @@qpdf_available : Bool? = nil

    def qpdf_available? : Bool
      if cached = @@qpdf_available
        return cached
      end
      result = !Process.find_executable("qpdf").nil?
      @@qpdf_available = result
      result
    end

    # Reset du cache, utile dans les specs pour simuler l'absence
    # de qpdf indépendamment de la présence réelle sur le système.
    def reset_qpdf_cache! : Nil
      @@qpdf_available = nil
    end
  end
end
