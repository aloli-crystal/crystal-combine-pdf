module CombinePDF
  # Helpers d'encodage WinAnsi (Windows-1252).
  #
  # Les polices Type1 standards qu'on utilise dans nos content streams
  # injectés (`Helvetica`, `Helvetica-Bold`, …) sont déclarées avec
  # `/Encoding /WinAnsiEncoding`. Cela impose que les chaînes de
  # caractères dans les opérateurs `(text) Tj` soient encodées en
  # Windows-1252, byte-pour-byte. Or les chaînes Crystal sont en UTF-8.
  #
  # Cette routine convertit une chaîne UTF-8 vers WinAnsi en écrivant
  # directement les octets sur un IO.
  #
  # ## Caractères supportés
  #
  # * **ASCII** (0x00-0x7F) — encodés directement, avec échappement
  #   des caractères PDF réservés `\`, `(`, `)`.
  # * **Latin-1 supplément** (0xA0-0xFF) — encodés directement
  #   (Latin-1 = WinAnsi sur cette plage). Couvre les accents
  #   français : à á â ä ç é è ê ë í î ï ñ ó ô ö ú û ü ÿ et leurs
  #   variantes majuscules.
  # * **Caractères typographiques** mappés sur les positions WinAnsi
  #   0x80-0x9F :
  #
  # [cols="1,1,3"]
  # |===
  # | Glyph | Code | Description
  # | €     | 0x80 | euro
  # | …     | 0x85 | ellipsis
  # | †     | 0x86 | dagger
  # | ‡     | 0x87 | double dagger
  # | ‰     | 0x89 | per mille
  # | ‹     | 0x8B | single left angle quote
  # | Œ     | 0x8C | OE ligature
  # | '     | 0x91 | left single quote
  # | '     | 0x92 | right single quote (apostrophe typographique)
  # | "     | 0x93 | left double quote
  # | "     | 0x94 | right double quote
  # | •     | 0x95 | bullet
  # | –     | 0x96 | en dash
  # | —     | 0x97 | em dash
  # | ™     | 0x99 | trademark
  # | ›     | 0x9B | single right angle quote
  # | œ     | 0x9C | oe ligature
  # |===
  #
  # ## Caractères non supportés
  #
  # Tout caractère hors WinAnsi est remplacé par `?` (glyphe `.notdef`
  # de WinAnsi). Cela inclut : la plupart des dingbats Unicode (✦, ❖,
  # ♥, ★, ♪…), les symboles mathématiques étendus (∞, ≠, ≤…), les
  # caractères CJK, les emojis, les caractères cyrilliques/grecs/etc.
  #
  # Pour ces glyphes-là il faudrait charger ZapfDingbats (Type1
  # standard PDF) ou embarquer une police TTF — non implémenté dans
  # ce shard.
  module WinAnsi
    extend self

    # Écrit `text` (UTF-8 Crystal) sur `io`, encodé en Windows-1252,
    # avec échappement PDF des caractères réservés `\\`, `(`, `)`.
    def write(io : IO, text : String) : Nil
      text.each_char do |ch|
        cp = ch.ord
        case cp
        when 0x5C then io.write_byte(0x5C_u8); io.write_byte(0x5C_u8) # `\` → `\\`
        when 0x28 then io.write_byte(0x5C_u8); io.write_byte(0x28_u8) # `(` → `\(`
        when 0x29 then io.write_byte(0x5C_u8); io.write_byte(0x29_u8) # `)` → `\)`
        when 0x00..0x7F
          io.write_byte(cp.to_u8)
        when 0xA0..0xFF
          # Latin-1 supplément = WinAnsi direct
          io.write_byte(cp.to_u8)
        when 0x20AC then io.write_byte(0x80_u8) # €
        when 0x201A then io.write_byte(0x82_u8) # ‚
        when 0x0192 then io.write_byte(0x83_u8) # ƒ
        when 0x201E then io.write_byte(0x84_u8) # „
        when 0x2026 then io.write_byte(0x85_u8) # …
        when 0x2020 then io.write_byte(0x86_u8) # †
        when 0x2021 then io.write_byte(0x87_u8) # ‡
        when 0x02C6 then io.write_byte(0x88_u8) # ˆ
        when 0x2030 then io.write_byte(0x89_u8) # ‰
        when 0x0160 then io.write_byte(0x8A_u8) # Š
        when 0x2039 then io.write_byte(0x8B_u8) # ‹
        when 0x0152 then io.write_byte(0x8C_u8) # Œ
        when 0x017D then io.write_byte(0x8E_u8) # Ž
        when 0x2018 then io.write_byte(0x91_u8) # '
        when 0x2019 then io.write_byte(0x92_u8) # '
        when 0x201C then io.write_byte(0x93_u8) # "
        when 0x201D then io.write_byte(0x94_u8) # "
        when 0x2022 then io.write_byte(0x95_u8) # •
        when 0x2013 then io.write_byte(0x96_u8) # –
        when 0x2014 then io.write_byte(0x97_u8) # —
        when 0x02DC then io.write_byte(0x98_u8) # ˜
        when 0x2122 then io.write_byte(0x99_u8) # ™
        when 0x0161 then io.write_byte(0x9A_u8) # š
        when 0x203A then io.write_byte(0x9B_u8) # ›
        when 0x0153 then io.write_byte(0x9C_u8) # œ
        when 0x017E then io.write_byte(0x9E_u8) # ž
        when 0x0178 then io.write_byte(0x9F_u8) # Ÿ
        else
          io.write_byte('?'.ord.to_u8)
        end
      end
    end

    # Approximation de la largeur en points d'un texte à taille de
    # police donnée. **Approximation grossière** : `text.size × 0.55`
    # ne marche que pour des chaînes de longueur représentative. Pour
    # les pastilles de numérotation ou la TOC, utilisez plutôt
    # `text_width` qui consulte une table de largeurs Helvetica par
    # caractère.
    def approx_width(text : String, font_size : Float64, bold : Bool = false) : Float64
      ratio = bold ? 0.58 : 0.55
      text.size * font_size * ratio
    end

    # Calcule la largeur en points d'un texte rendu dans une police
    # Helvetica Type1 (regular ou bold) à `font_size`.
    #
    # Précision : ~1 pt sur les textes courts (chiffres + séparateurs),
    # bien meilleur que `approx_width`. Indispensable pour le centrage
    # horizontal des pastilles ovales — l'approximation grossière
    # produit un rectangle décalé.
    #
    # Les largeurs viennent des fichiers AFM officiels Adobe pour
    # Helvetica et Helvetica-Bold (Type1 standards garantis présents
    # dans tout viewer PDF).
    def text_width(text : String, font_size : Float64, bold : Bool = false) : Float64
      table = bold ? HELVETICA_BOLD_WIDTHS : HELVETICA_WIDTHS
      total = 0.0
      text.each_char do |ch|
        cp = ch.ord
        # Mapping UTF-8 → WinAnsi pour les caractères typographiques
        # (cf. `write` ci-dessus). Si le caractère n'est pas dans la
        # table, on tombe sur 0.5em (approximation neutre).
        winansi_cp = winansi_codepoint_for(cp)
        total += table[winansi_cp]? || 0.5
      end
      total * font_size
    end

    # Renvoie le codepoint WinAnsi (0-255) correspondant à un
    # codepoint Unicode. Renvoie -1 si non représentable (= sera
    # rendu comme `?`, largeur 0.278).
    private def winansi_codepoint_for(cp : Int32) : Int32
      case cp
      when 0x00..0x7F then cp
      when 0xA0..0xFF then cp
      when 0x20AC     then 0x80
      when 0x201A     then 0x82
      when 0x0192     then 0x83
      when 0x201E     then 0x84
      when 0x2026     then 0x85
      when 0x2020     then 0x86
      when 0x2021     then 0x87
      when 0x02C6     then 0x88
      when 0x2030     then 0x89
      when 0x0160     then 0x8A
      when 0x2039     then 0x8B
      when 0x0152     then 0x8C
      when 0x017D     then 0x8E
      when 0x2018     then 0x91
      when 0x2019     then 0x92
      when 0x201C     then 0x93
      when 0x201D     then 0x94
      when 0x2022     then 0x95
      when 0x2013     then 0x96
      when 0x2014     then 0x97
      when 0x02DC     then 0x98
      when 0x2122     then 0x99
      when 0x0161     then 0x9A
      when 0x203A     then 0x9B
      when 0x0153     then 0x9C
      when 0x017E     then 0x9E
      when 0x0178     then 0x9F
      else
        # Glyphe `.notdef` (rendu `?`)
        0x3F
      end
    end

    # Largeurs Helvetica regular en em (em = 1.0 = font_size en pt).
    # Source : AFM officiel Adobe Helvetica.afm. Couvre l'ASCII
    # imprimable + Latin-1 + symboles WinAnsi 0x80-0x9F.
    HELVETICA_WIDTHS = {
      0x20 => 0.278, 0x21 => 0.278, 0x22 => 0.355, 0x23 => 0.556,
      0x24 => 0.556, 0x25 => 0.889, 0x26 => 0.667, 0x27 => 0.191,
      0x28 => 0.333, 0x29 => 0.333, 0x2A => 0.389, 0x2B => 0.584,
      0x2C => 0.278, 0x2D => 0.333, 0x2E => 0.278, 0x2F => 0.278,
      0x30 => 0.556, 0x31 => 0.556, 0x32 => 0.556, 0x33 => 0.556,
      0x34 => 0.556, 0x35 => 0.556, 0x36 => 0.556, 0x37 => 0.556,
      0x38 => 0.556, 0x39 => 0.556, 0x3A => 0.278, 0x3B => 0.278,
      0x3C => 0.584, 0x3D => 0.584, 0x3E => 0.584, 0x3F => 0.556,
      0x40 => 1.015, 0x41 => 0.667, 0x42 => 0.667, 0x43 => 0.722,
      0x44 => 0.722, 0x45 => 0.667, 0x46 => 0.611, 0x47 => 0.778,
      0x48 => 0.722, 0x49 => 0.278, 0x4A => 0.500, 0x4B => 0.667,
      0x4C => 0.556, 0x4D => 0.833, 0x4E => 0.722, 0x4F => 0.778,
      0x50 => 0.667, 0x51 => 0.778, 0x52 => 0.722, 0x53 => 0.667,
      0x54 => 0.611, 0x55 => 0.722, 0x56 => 0.667, 0x57 => 0.944,
      0x58 => 0.667, 0x59 => 0.667, 0x5A => 0.611, 0x5B => 0.278,
      0x5C => 0.278, 0x5D => 0.278, 0x5E => 0.469, 0x5F => 0.556,
      0x60 => 0.222, 0x61 => 0.556, 0x62 => 0.556, 0x63 => 0.500,
      0x64 => 0.556, 0x65 => 0.556, 0x66 => 0.278, 0x67 => 0.556,
      0x68 => 0.556, 0x69 => 0.222, 0x6A => 0.222, 0x6B => 0.500,
      0x6C => 0.222, 0x6D => 0.833, 0x6E => 0.556, 0x6F => 0.556,
      0x70 => 0.556, 0x71 => 0.556, 0x72 => 0.333, 0x73 => 0.500,
      0x74 => 0.278, 0x75 => 0.556, 0x76 => 0.500, 0x77 => 0.722,
      0x78 => 0.500, 0x79 => 0.500, 0x7A => 0.500, 0x7B => 0.334,
      0x7C => 0.260, 0x7D => 0.334, 0x7E => 0.584,
      # 0x80-0x9F WinAnsi extras
      0x80 => 0.556, 0x82 => 0.222, 0x83 => 0.556, 0x84 => 0.333,
      0x85 => 1.000, 0x86 => 0.556, 0x87 => 0.556, 0x88 => 0.333,
      0x89 => 1.000, 0x8A => 0.667, 0x8B => 0.333, 0x8C => 1.000,
      0x8E => 0.611, 0x91 => 0.222, 0x92 => 0.222, 0x93 => 0.333,
      0x94 => 0.333, 0x95 => 0.350, 0x96 => 0.556, 0x97 => 1.000,
      0x98 => 0.333, 0x99 => 1.000, 0x9A => 0.500, 0x9B => 0.333,
      0x9C => 0.944, 0x9E => 0.500, 0x9F => 0.667,
      # Latin-1 supplément (accents français notamment)
      0xA0 => 0.278, 0xA1 => 0.333, 0xA2 => 0.556, 0xA3 => 0.556,
      0xA4 => 0.556, 0xA5 => 0.556, 0xA6 => 0.260, 0xA7 => 0.556,
      0xA8 => 0.333, 0xA9 => 0.737, 0xAA => 0.370, 0xAB => 0.556,
      0xAC => 0.584, 0xAD => 0.333, 0xAE => 0.737, 0xAF => 0.333,
      0xB0 => 0.400, 0xB1 => 0.584, 0xB2 => 0.333, 0xB3 => 0.333,
      0xB4 => 0.333, 0xB5 => 0.556, 0xB6 => 0.537, 0xB7 => 0.278,
      0xB8 => 0.333, 0xB9 => 0.333, 0xBA => 0.365, 0xBB => 0.556,
      0xBC => 0.834, 0xBD => 0.834, 0xBE => 0.834, 0xBF => 0.611,
      0xC0 => 0.667, 0xC1 => 0.667, 0xC2 => 0.667, 0xC3 => 0.667,
      0xC4 => 0.667, 0xC5 => 0.667, 0xC6 => 1.000, 0xC7 => 0.722,
      0xC8 => 0.667, 0xC9 => 0.667, 0xCA => 0.667, 0xCB => 0.667,
      0xCC => 0.278, 0xCD => 0.278, 0xCE => 0.278, 0xCF => 0.278,
      0xD0 => 0.722, 0xD1 => 0.722, 0xD2 => 0.778, 0xD3 => 0.778,
      0xD4 => 0.778, 0xD5 => 0.778, 0xD6 => 0.778, 0xD7 => 0.584,
      0xD8 => 0.778, 0xD9 => 0.722, 0xDA => 0.722, 0xDB => 0.722,
      0xDC => 0.722, 0xDD => 0.667, 0xDE => 0.667, 0xDF => 0.611,
      0xE0 => 0.556, 0xE1 => 0.556, 0xE2 => 0.556, 0xE3 => 0.556,
      0xE4 => 0.556, 0xE5 => 0.556, 0xE6 => 0.889, 0xE7 => 0.500,
      0xE8 => 0.556, 0xE9 => 0.556, 0xEA => 0.556, 0xEB => 0.556,
      0xEC => 0.278, 0xED => 0.278, 0xEE => 0.278, 0xEF => 0.278,
      0xF0 => 0.556, 0xF1 => 0.556, 0xF2 => 0.556, 0xF3 => 0.556,
      0xF4 => 0.556, 0xF5 => 0.556, 0xF6 => 0.556, 0xF7 => 0.584,
      0xF8 => 0.611, 0xF9 => 0.556, 0xFA => 0.556, 0xFB => 0.556,
      0xFC => 0.556, 0xFD => 0.500, 0xFE => 0.556, 0xFF => 0.500,
    } of Int32 => Float64

    # Largeurs Helvetica-Bold en em. Source AFM officiel Adobe.
    HELVETICA_BOLD_WIDTHS = {
      0x20 => 0.278, 0x21 => 0.333, 0x22 => 0.474, 0x23 => 0.556,
      0x24 => 0.556, 0x25 => 0.889, 0x26 => 0.722, 0x27 => 0.238,
      0x28 => 0.333, 0x29 => 0.333, 0x2A => 0.389, 0x2B => 0.584,
      0x2C => 0.278, 0x2D => 0.333, 0x2E => 0.278, 0x2F => 0.278,
      0x30 => 0.556, 0x31 => 0.556, 0x32 => 0.556, 0x33 => 0.556,
      0x34 => 0.556, 0x35 => 0.556, 0x36 => 0.556, 0x37 => 0.556,
      0x38 => 0.556, 0x39 => 0.556, 0x3A => 0.333, 0x3B => 0.333,
      0x3C => 0.584, 0x3D => 0.584, 0x3E => 0.584, 0x3F => 0.611,
      0x40 => 0.975, 0x41 => 0.722, 0x42 => 0.722, 0x43 => 0.722,
      0x44 => 0.722, 0x45 => 0.667, 0x46 => 0.611, 0x47 => 0.778,
      0x48 => 0.722, 0x49 => 0.278, 0x4A => 0.556, 0x4B => 0.722,
      0x4C => 0.611, 0x4D => 0.833, 0x4E => 0.722, 0x4F => 0.778,
      0x50 => 0.667, 0x51 => 0.778, 0x52 => 0.722, 0x53 => 0.667,
      0x54 => 0.611, 0x55 => 0.722, 0x56 => 0.667, 0x57 => 0.944,
      0x58 => 0.667, 0x59 => 0.667, 0x5A => 0.611, 0x5B => 0.333,
      0x5C => 0.278, 0x5D => 0.333, 0x5E => 0.584, 0x5F => 0.556,
      0x60 => 0.333, 0x61 => 0.556, 0x62 => 0.611, 0x63 => 0.556,
      0x64 => 0.611, 0x65 => 0.556, 0x66 => 0.333, 0x67 => 0.611,
      0x68 => 0.611, 0x69 => 0.278, 0x6A => 0.278, 0x6B => 0.556,
      0x6C => 0.278, 0x6D => 0.889, 0x6E => 0.611, 0x6F => 0.611,
      0x70 => 0.611, 0x71 => 0.611, 0x72 => 0.389, 0x73 => 0.556,
      0x74 => 0.333, 0x75 => 0.611, 0x76 => 0.556, 0x77 => 0.778,
      0x78 => 0.556, 0x79 => 0.556, 0x7A => 0.500, 0x7B => 0.389,
      0x7C => 0.280, 0x7D => 0.389, 0x7E => 0.584,
      # WinAnsi 0x80-0x9F (fallback à 0.5 pour les manquants)
      0x80 => 0.556, 0x82 => 0.278, 0x83 => 0.556, 0x84 => 0.500,
      0x85 => 1.000, 0x86 => 0.556, 0x87 => 0.556, 0x88 => 0.333,
      0x89 => 1.000, 0x8A => 0.667, 0x8B => 0.333, 0x8C => 1.000,
      0x8E => 0.611, 0x91 => 0.278, 0x92 => 0.278, 0x93 => 0.500,
      0x94 => 0.500, 0x95 => 0.350, 0x96 => 0.556, 0x97 => 1.000,
      0x98 => 0.333, 0x99 => 1.000, 0x9A => 0.556, 0x9B => 0.333,
      0x9C => 0.944, 0x9E => 0.500, 0x9F => 0.722,
      # Latin-1 — pour les accents français principalement
      0xA0 => 0.278, 0xA1 => 0.333, 0xA2 => 0.556, 0xA3 => 0.556,
      0xA4 => 0.556, 0xA5 => 0.556, 0xA6 => 0.280, 0xA7 => 0.556,
      0xA8 => 0.333, 0xA9 => 0.737, 0xAA => 0.370, 0xAB => 0.556,
      0xAC => 0.584, 0xAD => 0.333, 0xAE => 0.737, 0xAF => 0.333,
      0xB0 => 0.400, 0xB1 => 0.584, 0xB2 => 0.333, 0xB3 => 0.333,
      0xB4 => 0.333, 0xB5 => 0.611, 0xB6 => 0.556, 0xB7 => 0.278,
      0xB8 => 0.333, 0xB9 => 0.333, 0xBA => 0.365, 0xBB => 0.556,
      0xBC => 0.834, 0xBD => 0.834, 0xBE => 0.834, 0xBF => 0.611,
      0xC0 => 0.722, 0xC1 => 0.722, 0xC2 => 0.722, 0xC3 => 0.722,
      0xC4 => 0.722, 0xC5 => 0.722, 0xC6 => 1.000, 0xC7 => 0.722,
      0xC8 => 0.667, 0xC9 => 0.667, 0xCA => 0.667, 0xCB => 0.667,
      0xCC => 0.278, 0xCD => 0.278, 0xCE => 0.278, 0xCF => 0.278,
      0xD0 => 0.722, 0xD1 => 0.722, 0xD2 => 0.778, 0xD3 => 0.778,
      0xD4 => 0.778, 0xD5 => 0.778, 0xD6 => 0.778, 0xD7 => 0.584,
      0xD8 => 0.778, 0xD9 => 0.722, 0xDA => 0.722, 0xDB => 0.722,
      0xDC => 0.722, 0xDD => 0.667, 0xDE => 0.667, 0xDF => 0.611,
      0xE0 => 0.556, 0xE1 => 0.556, 0xE2 => 0.556, 0xE3 => 0.556,
      0xE4 => 0.556, 0xE5 => 0.556, 0xE6 => 0.889, 0xE7 => 0.556,
      0xE8 => 0.556, 0xE9 => 0.556, 0xEA => 0.556, 0xEB => 0.556,
      0xEC => 0.278, 0xED => 0.278, 0xEE => 0.278, 0xEF => 0.278,
      0xF0 => 0.611, 0xF1 => 0.611, 0xF2 => 0.611, 0xF3 => 0.611,
      0xF4 => 0.611, 0xF5 => 0.611, 0xF6 => 0.611, 0xF7 => 0.584,
      0xF8 => 0.611, 0xF9 => 0.611, 0xFA => 0.611, 0xFB => 0.611,
      0xFC => 0.611, 0xFD => 0.556, 0xFE => 0.611, 0xFF => 0.556,
    } of Int32 => Float64
  end
end
