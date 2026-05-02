require "yaml"

module CombinePDF
  # Préférences utilisateur partagées entre tous les projets (par
  # opposition au `.crystal-combine-pdf.yml` qui est par projet).
  #
  # Cas d'usage : « tous mes documents sont en duplex » ou « tous mes
  # livrets sont profile=book sauf indication contraire ». Évite de
  # passer les mêmes flags à chaque `init`.
  #
  # **Chemin par défaut** : `~/.crystal-combine-pdf.yml`.
  # Surchargeable via `--user-config PATH` (utile pour les tests).
  #
  # **Précédence** (faible → fort) :
  # 1. Défauts du profil (`booklet` si rien n'est demandé).
  # 2. Valeurs de la config user (ce module).
  # 3. Drapeaux CLI passés explicitement.
  #
  # **Format YAML** (toutes les clés sont optionnelles) :
  #
  # ```yaml
  # # ~/.crystal-combine-pdf.yml
  # default_profile: book          # profil par défaut quand --profile absent
  # author: "Philippe Nénert"      # override de l'auteur déduit (git config)
  # paper_size: a4                 # préférence de format de page
  # duplex: true                   # préférence recto-verso
  # ```
  module UserConfig
    extend self

    DEFAULT_PATH = File.join(Path.home.to_s, ".crystal-combine-pdf.yml")

    # Résultat du chargement : nom du profil à appliquer + procédure
    # qui RETOURNE des `InitOptions` enrichies des surcharges du
    # fichier. La proc retourne une copie modifiée plutôt que de
    # muter en place — `InitOptions` est un struct (semantique de
    # valeur), donc une mutation à travers un Proc serait perdue.
    #
    # Quand le fichier n'existe pas, retourne un résultat « neutre »
    # avec le profil par défaut (`booklet`) et un applier identité.
    struct Loaded
      getter profile : String
      getter overrides : Proc(ConfigInitializer::InitOptions, ConfigInitializer::InitOptions)

      def initialize(
        @profile : String,
        @overrides : Proc(ConfigInitializer::InitOptions, ConfigInitializer::InitOptions),
      )
      end
    end

    # Charge la config user depuis `path`. Tolérante : un fichier
    # absent ou un YAML invalide ne lève pas, retourne juste un
    # résultat neutre. Utile car la grande majorité des utilisateurs
    # n'aura pas de fichier de préférences.
    def load(path : String = DEFAULT_PATH) : Loaded
      identity = ->(o : ConfigInitializer::InitOptions) { o }
      neutral = Loaded.new("booklet", identity)
      return neutral unless File.exists?(path)

      raw =
        begin
          YAML.parse(File.read(path))
        rescue
          return neutral
        end

      hash = raw.as_h?
      return neutral unless hash

      profile = "booklet"
      if v = hash["default_profile"]?
        if s = v.as_s?
          profile = s
        end
      end

      captured_hash = hash
      Loaded.new(profile, ->(opts : ConfigInitializer::InitOptions) {
        UserConfig.apply_overrides(opts, captured_hash)
      })
    end

    # Applique les surcharges de la config sur des `InitOptions`
    # déjà initialisées (typiquement par un profil).
    #
    # Liste blanche des clés interprétables : on ignore silencieusement
    # toute clé inconnue pour permettre l'évolution du format sans
    # casser les anciens fichiers.
    #
    # Public car appelée depuis un Proc (les Procs Crystal ne capturent
    # pas `self`, donc les méthodes privées du module ne sont pas
    # accessibles depuis le corps du Proc).
    #
    # Retourne une copie modifiée des options. `InitOptions` étant un
    # struct (semantique de valeur), on ne peut pas muter en place
    # à travers un Proc — il faut renvoyer la valeur transformée.
    def apply_overrides(opts : ConfigInitializer::InitOptions, h) : ConfigInitializer::InitOptions
      if v = h["author"]?
        if s = v.as_s?
          opts.author = s
        end
      end
      if v = h["paper_size"]?
        if s = v.as_s?
          opts.paper_size = s
        end
      end
      if v = h["duplex"]?
        # ⚠ piège Crystal : `if b = v.as_bool?` n'entre pas dans
        # le bloc quand la valeur YAML est `false` (false est falsy).
        # On teste explicitement contre `nil`.
        b = v.as_bool?
        opts.duplex = b unless b.nil?
      end
      if v = h["title"]?
        if s = v.as_s?
          opts.title = s
        end
      end
      if v = h["output"]?
        if s = v.as_s?
          opts.output = s
        end
      end
      opts
    end
  end
end
