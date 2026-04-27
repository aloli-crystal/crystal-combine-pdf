module CombinePDF
  # Mapping Unicode → ZapfDingbats + table de largeurs.
  #
  # ZapfDingbats est un Type1 standard PDF (sans besoin d'embedding,
  # garanti présent dans tous les viewers). Sa table de glyphes
  # contient ~200 dingbats (étoiles, cœurs, flèches, croix, mains
  # pointant, …) accessibles par leurs codepoints ASCII (0x21-0xFE).
  #
  # Ce module donne :
  # * `unicode_to_zapf(cp)` : mappe les codepoints Unicode dingbats
  #   les plus courants (✦, ❖, ★, ♥, ♣, ♦, ♠, ✓, ✗, ➤, ✿…) vers
  #   leur position ZapfDingbats.
  # * `is_dingbat?(ch)` : vérifie si un caractère est mappable.
  # * `width(cp, font_size)` : largeur du glyphe à une taille donnée.
  #
  # Pour ne pas embarquer toute la table AFM (200 entrées, valeurs
  # variables), on utilise une largeur moyenne de 0.7em par dingbat,
  # qui est l'ordre de grandeur correct pour les glyphes de cette
  # police (entre 0.5 et 1.0 selon le glyphe).
  module ZapfDingbats
    extend self

    # Police standard Type1. Pas d'embedding, garantie de viewer.
    BASE_FONT     = "ZapfDingbats"
    PDF_FONT_KEY  = "__CCP_ZD__"
    DEFAULT_WIDTH = 0.7 # em

    # Mapping Unicode → codepoint ZapfDingbats (octet à mettre dans
    # le content stream avec /__CCP_ZD__ Tf).
    #
    # Les codepoints listés ici couvrent les besoins typiques de
    # numérotation décorative : étoiles, cœurs, flèches, croix,
    # encadrements, ornements floraux. Pour la liste complète des
    # 202 glyphes ZapfDingbats, voir Adobe Technical Note #5095.
    UNICODE_TO_ZAPF = {
      # ─── Étoiles ────────────────────────────────────────────────
      0x2605 => 0x48_u8, # ★ "black star" → H (shadowed white star)
      0x2606 => 0x4D_u8, # ☆ "white star" → M (lightweight 6-pointed)
      0x2726 => 0x77_u8, # ✦ "black four pointed star" → w
      0x2727 => 0x78_u8, # ✧ "white four pointed star" → x
      0x2729 => 0x49_u8, # ✩ "stress outlined white star" → I
      0x272A => 0x4A_u8, # ✪ "circled white star" → J
      0x272B => 0x4B_u8, # ✫ "open centre black star" → K
      0x272C => 0x4C_u8, # ✬ "black centre white star" → L
      0x272D => 0x4D_u8, # ✭ "outlined black star" → M
      0x272E => 0x4E_u8, # ✮ "heavy outlined black star" → N
      0x272F => 0x4F_u8, # ✯ "pinwheel star" → O
      0x2730 => 0x50_u8, # ✰ "shadowed white star" → P
      # ─── Cœurs ──────────────────────────────────────────────────
      0x2665 => 0xAA_u8, # ♥ "black heart" → ª (zapf 170)
      0x2661 => 0xAB_u8, # ♡ approx → variant
      0x2764 => 0xAA_u8, # ❤ "heavy black heart" → ª
      # ─── Pique / Trèfle / Carreau ──────────────────────────────
      0x2660 => 0xAB_u8, # ♠ "black spade suit" → «
      0x2663 => 0xA7_u8, # ♣ "black club suit" → §
      0x2666 => 0xA9_u8, # ♦ "black diamond suit" → ©
      # ─── Coches & croix ────────────────────────────────────────
      0x2713 => 0x34_u8, # ✓ check → 4
      0x2714 => 0x35_u8, # ✔ heavy check → 5
      0x2717 => 0x36_u8, # ✗ ballot X → 6
      0x2718 => 0x37_u8, # ✘ heavy ballot X → 7
      # ─── Croix ──────────────────────────────────────────────────
      0x2719 => 0x21_u8, # ✙ → !
      0x271A => 0x2B_u8, # ✚ heavy greek cross → +
      0x271B => 0x22_u8, # ✛ open centre cross → "
      0x271C => 0x23_u8, # ✜ heavy open centre cross → #
      0x271D => 0x24_u8, # ✝ Latin cross → $
      0x271E => 0x25_u8, # ✞ shadowed Latin cross → %
      0x271F => 0x26_u8, # ✟ outlined Latin cross → &
      0x2720 => 0x27_u8, # ✠ Maltese cross → '
      # ─── Flèches ───────────────────────────────────────────────
      0x2192 => 0xD5_u8, # → "rightwards arrow" → Õ (small)
      0x27A1 => 0xE0_u8, # ➡ heavy black rightwards arrow → à
      0x27A4 => 0xC4_u8, # ➤ black rightwards arrow head → Ä
      0x27A2 => 0xC5_u8, # ➢ three-d top-lighted right arrow → Å
      # ─── Ornements floraux et encadrements ─────────────────────
      0x273F => 0x6E_u8, # ✿ black florette → n
      0x2740 => 0x6F_u8, # ❀ white florette → o
      0x2741 => 0x70_u8, # ❁ eight petalled outlined → p
      0x2756 => 0x76_u8, # ❖ black diamond minus white X → v
      0x2767 => 0x83_u8, # ❧ rotated floral heart bullet → ƒ
      # ─── Coches numériques ─────────────────────────────────────
      0x2780 => 0xB6_u8, # ➀ circled digit 1 → ¶
      0x2781 => 0xB7_u8, # ➁ → ·
      0x2782 => 0xB8_u8, # ➂ → ¸
      0x2783 => 0xB9_u8, # ➃ → ¹
      0x2784 => 0xBA_u8, # ➄ → º
      0x2785 => 0xBB_u8, # ➅ → »
      0x2786 => 0xBC_u8, # ➆ → ¼
      0x2787 => 0xBD_u8, # ➇ → ½
      0x2788 => 0xBE_u8, # ➈ → ¾
      0x2789 => 0xBF_u8, # ➉ → ¿
    } of Int32 => UInt8

    # `true` si `ch` peut être rendu avec ZapfDingbats.
    def dingbat?(ch : Char) : Bool
      UNICODE_TO_ZAPF.has_key?(ch.ord)
    end

    # Renvoie le codepoint ZapfDingbats pour `ch`, ou `nil` si non
    # mappable.
    def codepoint_for(ch : Char) : UInt8?
      UNICODE_TO_ZAPF[ch.ord]?
    end

    # Largeur d'un glyphe ZapfDingbats à `font_size`. Approximation
    # par la moyenne de la police (0.7em) — ZapfDingbats étant
    # principalement décoratif, la précision exacte glyph-par-glyph
    # n'est pas critique pour des chaînes de 1-3 caractères.
    def width(font_size : Float64) : Float64
      DEFAULT_WIDTH * font_size
    end

    # Découpe `text` en runs alternant Helvetica (WinAnsi) et
    # ZapfDingbats. Renvoie une liste de tuples `{:helvetica | :zapf,
    # text_segment}`.
    #
    # Exemple :
    # ```
    # ZapfDingbats.split_runs("★ 6 / 12 ★")
    # # => [{:zapf, "★"}, {:helvetica, " 6 / 12 "}, {:zapf, "★"}]
    # ```
    def split_runs(text : String) : Array(Tuple(Symbol, String))
      runs = [] of Tuple(Symbol, String)
      buffer = String::Builder.new
      current_kind : Symbol? = nil

      text.each_char do |ch|
        kind = dingbat?(ch) ? :zapf : :helvetica
        if current_kind.nil?
          current_kind = kind
        elsif kind != current_kind
          runs << {current_kind.not_nil!, buffer.to_s}
          buffer = String::Builder.new
          current_kind = kind
        end
        buffer << ch
      end

      if current_kind
        runs << {current_kind, buffer.to_s}
      end

      runs
    end
  end
end
