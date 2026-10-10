//
//  FormulaSymbols.swift · what a glyph of a formula is: its LaTeX, its role (letter, relation, opening
//  delimiter, big operator, accent…) and its alphabet (italic, bold, calligraphic…), from the glyph's name in
//  its font or, for fonts that only give Unicode, from its character.
//

import CoreGraphics
import Foundation

/// The role a symbol plays in a formula's layout.
enum InkKind: Equatable {
    case letter, digit, ordinary
    case binary, relation, punctuation
    case open, close
    /// A vertical bar, which opens or closes depending on its neighbours.
    case bar
    case bigOperator
    case accent
    case radical
    case prime
    /// A piece of a delimiter built from parts (top, extension, bottom).
    case piece
    /// Roman letters read together: a word of text or an operator's name.
    case word
    case structure
}

/// The alphabet a letter is set in.
enum InkStyle: Equatable {
    case italic, roman, bold, boldItalic, calligraphic, blackboard, fraktur, script, sans, typewriter
}

struct InkSymbol: Equatable {
    var latex: String
    var kind: InkKind
    /// The plain character for letters and digits (“X”, “β”, “3”), used to build words and numbers.
    var plain: String? = nil
}

enum FormulaSymbols {
    // MARK: Styles

    /// The alphabet of a font, from its name: CMMI is math italic, CMBX bold, MSBM blackboard bold…
    static func style(ofFont font: String) -> InkStyle {
        let family = InkGlyph.family(of: font)
        switch family {
        case "CMMI", "LMMI": return .italic
        case "CMMIB", "LMMIB": return .boldItalic
        case "CMSY", "LMSY", "CMBSY", "LMBSY": return .calligraphic
        case "MSBM", "BBM", "BBOLD", "DSROM": return .blackboard
        case "EUFM", "EUFB": return .fraktur
        case "RSFS", "EUSM", "EUSB": return .script
        case "CMTT", "CMITT", "CMSLTT": return .typewriter
        default: break
        }
        if family.hasPrefix("CMBX") || family == "CMB" || family.hasPrefix("CMSSBX") { return family.hasSuffix("TI") || family.hasSuffix("SL") ? .boldItalic : .bold }
        if family.hasPrefix("CMSS") { return .sans }
        if family.hasPrefix("CMTI") || family.hasPrefix("CMSL") { return .italic }
        if family.hasPrefix("CM") { return .roman }
        let lower = font.lowercased()
        let bold = lower.contains("bold") || lower.contains("-bd") || lower.contains("semibold") || lower.contains("heavy") || lower.contains("black")
        let italic = lower.contains("ital") || lower.contains("oblique") || lower.hasSuffix("-it") || lower.contains("slant") || lower.contains("mi") && lower.contains("px")
        if lower.contains("blackboard") || lower.contains("bbold") || lower.contains("msbm") { return .blackboard }
        if lower.contains("calligra") || lower.contains("-cal") || lower.contains("rsfs") { return .calligraphic }
        if lower.contains("fraktur") || lower.contains("frak") { return .fraktur }
        if bold && italic { return .boldItalic }
        if bold { return .bold }
        if italic || lower.contains("math") && lower.contains("letters") { return .italic }
        return .roman
    }

    /// Fonts whose glyphs hang below their origin and are centred on the math axis: TeX's extension fonts.
    static func isExtensionFont(_ font: String) -> Bool {
        let family = InkGlyph.family(of: font)
        if ["CMEX", "LMEX", "EUEX", "TXEX", "PXEX", "MTEX", "TXEXS", "TXEXA", "PXEXA"].contains(family) { return true }
        let lower = font.lowercased()
        return lower.contains("extension") || lower.hasPrefix("txex") || lower.hasPrefix("pxex")
    }

    // MARK: Glyph names

    static func symbol(named name: String) -> InkSymbol? {
        if let symbol = named[name] { return symbol }
        if name.count == 1, let c = name.first {
            if c.isLetter { return InkSymbol(latex: name, kind: .letter, plain: name) }
            if c.isNumber { return InkSymbol(latex: name, kind: .digit, plain: name) }
        }
        // Size variants of delimiters and operators: “parenleftbig”, “bracketrightBigg”, “summationdisplay”.
        for suffix in ["Bigg", "bigg", "Big", "big"] where name.hasSuffix(suffix) {
            if let base = named[String(name.dropLast(suffix.count))] { return base }
        }
        for suffix in ["display", "text"] where name.hasSuffix(suffix) {
            if let big = bigOperators[String(name.dropLast(suffix.count))] { return InkSymbol(latex: big, kind: .bigOperator) }
        }
        if name == "radicalbt" || name == "radicalvertex" || name == "radicaltp" { return InkSymbol(latex: "radical", kind: .piece) }
        for suffix in ["tp", "bt", "ex", "mid"] where name.hasSuffix(suffix) {
            let base = String(name.dropLast(suffix.count))
            if named[base] != nil || base == "brace" || base == "arrowvert" || base == "radical" { return InkSymbol(latex: base, kind: .piece) }
        }
        if name.hasPrefix("uni"), name.count == 7, let value = UInt32(name.dropFirst(3), radix: 16), let scalar = Unicode.Scalar(value) { return symbol(for: Character(scalar)) }
        if name.hasSuffix(".alt") || name.hasSuffix(".sc") || name.hasSuffix(".oldstyle"), let dot = name.firstIndex(of: ".") { return symbol(named: String(name[..<dot])) }
        return nil
    }

    private static let bigOperators: [String: String] = [
        "summation": "\\sum", "product": "\\prod", "integral": "\\int", "contintegral": "\\oint", "union": "\\bigcup", "intersection": "\\bigcap",
        "unionmulti": "\\biguplus", "logicaland": "\\bigwedge", "logicalor": "\\bigvee", "coproduct": "\\coprod", "circledot": "\\bigodot",
        "circleplus": "\\bigoplus", "circlemultiply": "\\bigotimes", "unionsq": "\\bigsqcup"
    ]

    private static let named: [String: InkSymbol] = {
        var table: [String: InkSymbol] = [:]
        func add(_ kind: InkKind, _ pairs: [String: String]) { for (name, latex) in pairs { table[name] = InkSymbol(latex: latex, kind: kind) } }
        // Greek. In Computer Modern “epsilon1” is the lunate ϵ that LaTeX calls \epsilon, and “epsilon” its \varepsilon.
        let greek = ["alpha", "beta", "gamma", "delta", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau",
                     "upsilon", "phi", "chi", "psi", "omega", "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon", "Phi", "Psi", "Omega"]
        for name in greek { table[name] = InkSymbol(latex: "\\" + name, kind: .letter, plain: MathNames.greek[name]) }
        for (name, latex, plain) in [("epsilon1", "\\epsilon", "ϵ"), ("epsilon", "\\varepsilon", "ε"), ("theta1", "\\vartheta", "ϑ"), ("pi1", "\\varpi", "ϖ"), ("omega1", "\\varpi", "ϖ"),
                                     ("rho1", "\\varrho", "ϱ"), ("sigma1", "\\varsigma", "ς"), ("phi1", "\\varphi", "φ"), ("omicron", "o", "o"), ("Upsilon1", "\\Upsilon", "Υ"),
                                     ("lscript", "\\ell", "ℓ"), ("weierstrass", "\\wp", "℘"), ("dotlessi", "\\imath", "ı"), ("dotlessj", "\\jmath", "ȷ"), ("aleph", "\\aleph", "ℵ"),
                                     ("Rfractur", "\\Re", "ℜ"), ("Ifractur", "\\Im", "ℑ"), ("hbar", "\\hbar", "ℏ"), ("hslash", "\\hbar", "ℏ")] {
            table[name] = InkSymbol(latex: latex, kind: .letter, plain: plain)
        }
        let digits = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        for (value, name) in digits.enumerated() {
            table[name] = InkSymbol(latex: "\(value)", kind: .digit, plain: "\(value)")
            table[name + "oldstyle"] = InkSymbol(latex: "\(value)", kind: .digit, plain: "\(value)")
        }
        for (name, text) in ["ff": "ff", "fi": "fi", "fl": "fl", "ffi": "ffi", "ffl": "ffl", "germandbls": "ß", "ae": "æ", "oe": "œ", "AE": "Æ", "OE": "Œ", "oslash": "ø", "Oslash": "Ø"] {
            table[name] = InkSymbol(latex: text, kind: .letter, plain: text)
        }
        add(.ordinary, [
            "partialdiff": "\\partial", "infinity": "\\infty", "nabla": "\\nabla", "gradient": "\\nabla", "universal": "\\forall", "existential": "\\exists", "notexistential": "\\nexists",
            "logicalnot": "\\neg", "emptyset": "\\emptyset", "latticetop": "\\top", "triangle": "\\triangle", "triangleinv": "\\bigtriangledown", "trianglesolid": "\\blacktriangle",
            "section": "\\S", "paragraph": "\\P", "club": "\\clubsuit", "diamond": "\\diamondsuit", "heart": "\\heartsuit", "spade": "\\spadesuit", "flat": "\\flat",
            "natural": "\\natural", "sharp": "\\sharp", "integral": "\\smallint", "slash": "/", "exclam": "!", "question": "?", "numbersign": "\\#", "percent": "\\%",
            "ampersand": "\\&", "dollar": "\\$", "at": "@", "degree": "^{\\circ}", "square": "\\square", "squaresolid": "\\blacksquare", "lozenge": "\\lozenge", "check": "\\checkmark",
            "therefore": "\\therefore", "because": "\\because", "angle": "\\angle", "quotedblright": "''", "quotedblleft": "``", "quoteright": "'", "quoteleft": "`",
            "quotesingle": "'", "hyphen": "-", "endash": "-", "emdash": "-", "underscore": "\\_", "slashbig": "/", "backslashbig": "\\backslash", "ellipsis": "\\ldots",
            "dagger": "\\dagger", "daggerdbl": "\\ddagger", "asterisk": "*", "copyright": "\\copyright", "bullet": "\\bullet"
        ])
        add(.binary, [
            "plus": "+", "minus": "-", "multiply": "\\times", "periodcentered": "\\cdot", "dotmath": "\\cdot", "asteriskmath": "*", "divide": "\\div", "diamondmath": "\\diamond",
            "plusminus": "\\pm", "minusplus": "\\mp", "circleplus": "\\oplus", "circleminus": "\\ominus", "circlemultiply": "\\otimes", "circledivide": "\\oslash",
            "circledot": "\\odot", "circlecopyrt": "\\bigcirc", "openbullet": "\\circ", "union": "\\cup", "intersection": "\\cap", "unionmulti": "\\uplus",
            "logicaland": "\\wedge", "logicalor": "\\vee", "backslash": "\\setminus", "wreathproduct": "\\wr", "coproduct": "\\amalg", "unionsq": "\\sqcup",
            "intersectionsq": "\\sqcap", "star": "\\star", "triangleright": "\\triangleright", "triangleleft": "\\triangleleft", "multicloseleft": "\\ltimes",
            "multicloseright": "\\rtimes"
        ])
        add(.relation, [
            "equal": "=", "less": "<", "greater": ">", "lessequal": "\\le", "greaterequal": "\\ge", "notequal": "\\ne", "equivalence": "\\equiv", "equivasymptotic": "\\asymp",
            "reflexsubset": "\\subseteq", "reflexsuperset": "\\supseteq", "precedesequal": "\\preceq", "followsequal": "\\succeq", "similar": "\\sim", "approxequal": "\\approx",
            "propersubset": "\\subset", "propersuperset": "\\supset", "lessmuch": "\\ll", "greatermuch": "\\gg", "precedes": "\\prec", "follows": "\\succ",
            "arrowleft": "\\leftarrow", "arrowright": "\\to", "arrowup": "\\uparrow", "arrowdown": "\\downarrow", "arrowboth": "\\leftrightarrow",
            "arrownortheast": "\\nearrow", "arrowsoutheast": "\\searrow", "similarequal": "\\simeq", "arrowdblleft": "\\Leftarrow", "arrowdblright": "\\Rightarrow",
            "arrowdblup": "\\Uparrow", "arrowdbldown": "\\Downarrow", "arrowdblboth": "\\Leftrightarrow", "arrownorthwest": "\\nwarrow", "arrowsouthwest": "\\swarrow",
            "proportional": "\\propto", "element": "\\in", "owner": "\\ni", "notelement": "\\notin", "perpendicular": "\\perp", "turnstileleft": "\\vdash",
            "turnstileright": "\\dashv", "subsetsqequal": "\\sqsubseteq", "supersetsqequal": "\\sqsupseteq", "arrowbothv": "\\updownarrow", "arrowdblbothv": "\\Updownarrow",
            "lessorequalslant": "\\leqslant", "greaterorequalslant": "\\geqslant", "lessorsimilar": "\\lesssim", "greaterorsimilar": "\\gtrsim", "defines": "\\triangleq",
            "subsetnoteql": "\\subsetneq", "supersetnoteql": "\\supsetneq", "notsubseteql": "\\nsubseteq", "notsuperseteql": "\\nsupseteq", "notlessequal": "\\nleq",
            "notgreaterequal": "\\ngeq", "notdivides": "\\nmid", "congruent": "\\cong", "squiggleright": "\\rightsquigarrow", "mapsto": "\\mapsto",
            "arrowhookleft": "\\hookleftarrow", "arrowhookright": "\\hookrightarrow", "parallel": "\\parallel"
        ])
        add(.punctuation, ["comma": ",", "period": ".", "semicolon": ";", "colon": ":"])
        add(.open, ["parenleft": "(", "bracketleft": "[", "braceleft": "\\{", "angbracketleft": "\\langle", "floorleft": "\\lfloor", "ceilingleft": "\\lceil"])
        add(.close, ["parenright": ")", "bracketright": "]", "braceright": "\\}", "angbracketright": "\\rangle", "floorright": "\\rfloor", "ceilingright": "\\rceil"])
        add(.bar, ["bar": "|", "bardbl": "\\|", "vextendsingle": "|", "vextenddouble": "\\|", "brokenbar": "|"])
        add(.accent, [
            "circumflex": "hat", "asciicircum": "hat", "tilde": "tilde", "asciitilde": "tilde", "macron": "bar", "dotaccent": "dot", "dieresis": "ddot", "caron": "check",
            "breve": "breve", "acute": "acute", "grave": "grave", "ring": "mathring", "vector": "vec", "hatwide": "widehat", "hatwider": "widehat", "hatwidest": "widehat",
            "tildewide": "widetilde", "tildewider": "widetilde", "tildewidest": "widetilde"
        ])
        add(.radical, ["radical": "\\sqrt", "radicalbig": "\\sqrt", "radicalBig": "\\sqrt", "radicalbigg": "\\sqrt", "radicalBigg": "\\sqrt"])
        table["prime"] = InkSymbol(latex: "\\prime", kind: .prime)
        table["negationslash"] = InkSymbol(latex: "\\not", kind: .ordinary)
        return table
    }()

    // MARK: Unicode

    static func symbol(for character: Character) -> InkSymbol? {
        if let symbol = unicode[character] { return symbol }
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            // A base letter with combining marks, as some fonts' ToUnicode maps give.
            if let first = character.unicodeScalars.first, first.properties.isAlphabetic { return symbol(for: Character(first)) }
            return nil
        }
        if scalar.isASCII {
            if character.isLetter { return InkSymbol(latex: String(character), kind: .letter, plain: String(character)) }
            if character.isNumber { return InkSymbol(latex: String(character), kind: .digit, plain: String(character)) }
            return nil
        }
        if (0x1D400...0x1D7FF).contains(scalar.value) || scalar.value == 0x210E {
            // Mathematical alphanumerics: the letter, in the alphabet its block says.
            let folded = String(character).precomposedStringWithCompatibilityMapping
            if let base = folded.first, folded.count == 1, base != character { return symbol(for: base) }
        }
        if let name = greekNames[character] { return InkSymbol(latex: "\\" + name, kind: .letter, plain: String(character)) }
        if character.isLetter { return InkSymbol(latex: String(character), kind: .letter, plain: String(character)) }
        return nil
    }

    /// The LaTeX name of a Greek letter as Unicode writes it.
    private static let greekNames: [Character: String] = {
        var names: [Character: String] = [:]
        let pairs: [(Character, String)] = [("α", "alpha"), ("β", "beta"), ("γ", "gamma"), ("δ", "delta"), ("ζ", "zeta"), ("η", "eta"), ("θ", "theta"), ("ι", "iota"), ("κ", "kappa"),
                                             ("λ", "lambda"), ("μ", "mu"), ("µ", "mu"), ("ν", "nu"), ("ξ", "xi"), ("π", "pi"), ("ρ", "rho"), ("σ", "sigma"), ("τ", "tau"), ("υ", "upsilon"),
                                             ("χ", "chi"), ("ψ", "psi"), ("ω", "omega"), ("Γ", "Gamma"), ("Δ", "Delta"), ("∆", "Delta"), ("Θ", "Theta"), ("Λ", "Lambda"), ("Ξ", "Xi"),
                                             ("Π", "Pi"), ("Σ", "Sigma"), ("Υ", "Upsilon"), ("Φ", "Phi"), ("Ψ", "Psi"), ("Ω", "Omega"), ("Ω", "Omega")]
        for (character, name) in pairs { names[character] = name }
        return names
    }()

    /// The alphabet a mathematical alphanumeric character belongs to (𝐗 bold, 𝑥 italic, ℝ blackboard).
    static func style(ofUnicode character: Character) -> InkStyle? {
        guard let value = character.unicodeScalars.first?.value else { return nil }
        if "ℝℂℕℤℚℙℍ𝟙".contains(character) { return .blackboard }
        if "ℋℒℱℬℰℐℳℛℯℊℴ".contains(character) { return .script }
        switch value {
        case 0x1D400...0x1D433, 0x1D6A8...0x1D6E1, 0x1D7CE...0x1D7D7: return .bold
        case 0x1D434...0x1D467, 0x1D6E2...0x1D71B, 0x210E: return .italic
        case 0x1D468...0x1D49B, 0x1D71C...0x1D755: return .boldItalic
        case 0x1D49C...0x1D503: return .script
        case 0x1D504...0x1D537, 0x1D56C...0x1D59F: return .fraktur
        case 0x1D538...0x1D56B, 0x1D7D8...0x1D7E1: return .blackboard
        case 0x1D5A0...0x1D66F, 0x1D756...0x1D7C9, 0x1D7E2...0x1D7F5: return .sans
        case 0x1D670...0x1D6A3, 0x1D7F6...0x1D7FF: return .typewriter
        default: return nil
        }
    }

    private static let unicode: [Character: InkSymbol] = {
        var table: [Character: InkSymbol] = [:]
        func add(_ kind: InkKind, _ pairs: [Character: String]) { for (character, latex) in pairs { table[character] = InkSymbol(latex: latex, kind: kind) } }
        add(.ordinary, ["∂": "\\partial", "∞": "\\infty", "∇": "\\nabla", "∀": "\\forall", "∃": "\\exists", "∄": "\\nexists", "¬": "\\neg", "∅": "\\emptyset", "⊤": "\\top",
                        "△": "\\triangle", "/": "/", "!": "!", "?": "?", "#": "\\#", "%": "\\%", "&": "\\&", "$": "\\$", "@": "@", "°": "^{\\circ}", "□": "\\square", "■": "\\blacksquare",
                        "∎": "\\blacksquare", "…": "\\ldots", "⋯": "\\cdots", "⋮": "\\vdots", "⋱": "\\ddots", "†": "\\dagger", "‡": "\\ddagger", "∠": "\\angle", "’": "'", "‘": "`",
                        "”": "''", "“": "``", "-": "-", "‐": "-", "–": "-", "\u{2014}": "-", "_": "\\_", "∴": "\\therefore", "∵": "\\because", "•": "\\bullet", "✓": "\\checkmark",
                        "⊥": "\\perp", "ð": "\\eth", "∖": "\\setminus", "\\": "\\backslash"])
        add(.binary, ["+": "+", "−": "-", "×": "\\times", "·": "\\cdot", "⋅": "\\cdot", "∙": "\\cdot", "∗": "*", "*": "*", "÷": "\\div", "±": "\\pm", "∓": "\\mp", "⊕": "\\oplus",
                      "⊖": "\\ominus", "⊗": "\\otimes", "⊘": "\\oslash", "⊙": "\\odot", "∘": "\\circ", "∪": "\\cup", "∩": "\\cap", "⊎": "\\uplus", "∧": "\\wedge", "∨": "\\vee",
                      "⋆": "\\star", "⊔": "\\sqcup", "⊓": "\\sqcap", "⋄": "\\diamond", "≀": "\\wr", "⋉": "\\ltimes", "⋊": "\\rtimes"])
        add(.relation, ["=": "=", "<": "<", ">": ">", "≤": "\\le", "≥": "\\ge", "≠": "\\ne", "≡": "\\equiv", "≍": "\\asymp", "⊆": "\\subseteq", "⊇": "\\supseteq", "⪯": "\\preceq",
                        "⪰": "\\succeq", "≼": "\\preceq", "≽": "\\succeq", "∼": "\\sim", "~": "\\sim", "≈": "\\approx", "⊂": "\\subset", "⊃": "\\supset", "≪": "\\ll", "≫": "\\gg",
                        "≺": "\\prec", "≻": "\\succ", "←": "\\leftarrow", "→": "\\to", "↑": "\\uparrow", "↓": "\\downarrow", "↔": "\\leftrightarrow", "↗": "\\nearrow", "↘": "\\searrow",
                        "≃": "\\simeq", "≅": "\\cong", "⇐": "\\Leftarrow", "⇒": "\\Rightarrow", "⇔": "\\Leftrightarrow", "⟹": "\\Longrightarrow", "⟸": "\\Longleftarrow",
                        "⟺": "\\Longleftrightarrow", "⟶": "\\longrightarrow", "⟵": "\\longleftarrow", "∝": "\\propto", "∈": "\\in", "∋": "\\ni", "∉": "\\notin", "⊢": "\\vdash",
                        "⊣": "\\dashv", "⊑": "\\sqsubseteq", "⊒": "\\sqsupseteq", "⩽": "\\leqslant", "⩾": "\\geqslant", "≲": "\\lesssim", "≳": "\\gtrsim", "≜": "\\triangleq",
                        "≔": "\\coloneqq", "⊊": "\\subsetneq", "⊋": "\\supsetneq", "⊈": "\\nsubseteq", "≰": "\\nleq", "≱": "\\ngeq", "∤": "\\nmid", "↦": "\\mapsto", "⟼": "\\longmapsto",
                        "∥": "\\parallel", "↩": "\\hookleftarrow", "↪": "\\hookrightarrow", "⇝": "\\rightsquigarrow", "≐": "\\doteq", "⊨": "\\models", "∣": "\\mid", "≢": "\\not\\equiv"])
        add(.punctuation, [",": ",", ".": ".", ";": ";", ":": ":"])
        add(.open, ["(": "(", "[": "[", "{": "\\{", "⟨": "\\langle", "〈": "\\langle", "⌊": "\\lfloor", "⌈": "\\lceil"])
        add(.close, [")": ")", "]": "]", "}": "\\}", "⟩": "\\rangle", "〉": "\\rangle", "⌋": "\\rfloor", "⌉": "\\rceil"])
        add(.bar, ["|": "|", "‖": "\\|", "∥": "\\|", "⎮": "|", "⏐": "|"])
        add(.bigOperator, ["∑": "\\sum", "∏": "\\prod", "∫": "\\int", "∮": "\\oint", "⋃": "\\bigcup", "⋂": "\\bigcap", "⨄": "\\biguplus", "⋀": "\\bigwedge", "⋁": "\\bigvee",
                           "∐": "\\coprod", "⨀": "\\bigodot", "⨁": "\\bigoplus", "⨂": "\\bigotimes", "⨆": "\\bigsqcup", "∬": "\\iint", "∭": "\\iiint"])
        add(.accent, ["ˆ": "hat", "^": "hat", "˜": "tilde", "¯": "bar", "ˉ": "bar", "˙": "dot", "¨": "ddot", "ˇ": "check", "˘": "breve", "´": "acute", "`": "grave", "˚": "mathring",
                      "\u{0302}": "hat", "\u{0303}": "tilde", "\u{0304}": "bar", "\u{0305}": "bar", "\u{0307}": "dot", "\u{0308}": "ddot", "\u{030C}": "check", "\u{0306}": "breve",
                      "\u{0301}": "acute", "\u{0300}": "grave", "\u{030A}": "mathring", "\u{20D7}": "vec"])
        table["√"] = InkSymbol(latex: "\\sqrt", kind: .radical)
        table["′"] = InkSymbol(latex: "\\prime", kind: .prime)
        table["″"] = InkSymbol(latex: "\\prime\\prime", kind: .prime)
        table["ℓ"] = InkSymbol(latex: "\\ell", kind: .letter, plain: "ℓ")
        table["ℏ"] = InkSymbol(latex: "\\hbar", kind: .letter, plain: "ℏ")
        table["ı"] = InkSymbol(latex: "\\imath", kind: .letter, plain: "ı")
        table["ȷ"] = InkSymbol(latex: "\\jmath", kind: .letter, plain: "ȷ")
        table["ℜ"] = InkSymbol(latex: "\\Re", kind: .letter, plain: "ℜ")
        table["ℑ"] = InkSymbol(latex: "\\Im", kind: .letter, plain: "ℑ")
        table["ℵ"] = InkSymbol(latex: "\\aleph", kind: .letter, plain: "ℵ")
        table["℘"] = InkSymbol(latex: "\\wp", kind: .letter, plain: "℘")
        for (character, latex) in [("ϵ", "\\epsilon"), ("ε", "\\varepsilon"), ("ϑ", "\\vartheta"), ("ϖ", "\\varpi"), ("ϱ", "\\varrho"), ("ς", "\\varsigma"), ("φ", "\\varphi"), ("ϕ", "\\phi"),
                                   ("ϰ", "\\varkappa")] as [(Character, String)] {
            table[character] = InkSymbol(latex: latex, kind: .letter, plain: String(character))
        }
        // The pieces of tall delimiters as Unicode names them.
        for (character, base) in [("⎛", "parenleft"), ("⎜", "parenleft"), ("⎝", "parenleft"), ("⎞", "parenright"), ("⎟", "parenright"), ("⎠", "parenright"),
                                  ("⎡", "bracketleft"), ("⎢", "bracketleft"), ("⎣", "bracketleft"), ("⎤", "bracketright"), ("⎥", "bracketright"), ("⎦", "bracketright"),
                                  ("⎧", "braceleft"), ("⎨", "braceleft"), ("⎩", "braceleft"), ("⎪", "brace"), ("⎫", "braceright"), ("⎬", "braceright"), ("⎭", "braceright")] as [(Character, String)] {
            table[character] = InkSymbol(latex: base, kind: .piece)
        }
        return table
    }()

    // MARK: Words

    /// Names TeX sets in roman type as operators.
    static let operatorNames: Set<String> = ["arccos", "arcsin", "arctan", "arg", "cos", "cosh", "cot", "coth", "csc", "deg", "det", "dim", "exp", "gcd", "hom", "inf", "ker", "lg",
                                             "lim", "liminf", "limsup", "ln", "log", "max", "min", "Pr", "sec", "sin", "sinh", "sup", "tan", "tanh"]
    /// Operators whose limits TeX sets underneath in a display.
    static let limitOperators: Set<String> = ["lim", "liminf", "limsup", "max", "min", "sup", "inf", "argmax", "argmin", "det", "gcd", "Pr", "maximize", "minimize"]
    /// Words of prose that appear inside displays.
    static let proseWords: Set<String> = ["a", "an", "the", "and", "or", "for", "all", "any", "some", "each", "every", "if", "iff", "then", "else", "otherwise", "where", "when", "with", "such",
                                          "that", "is", "are", "be", "as", "in", "on", "of", "to", "by", "at", "from", "subject", "st", "so", "we", "have", "has", "not", "only", "implies",
                                          "since", "because", "hence", "thus", "therefore", "while", "but", "over", "under", "given", "let", "note", "here", "there", "which", "this",
                                          "these", "those", "it", "its", "can", "may", "must", "will", "also", "both", "either", "neither", "nor", "no", "yes", "true", "false",
                                          "almost", "surely", "everywhere", "times", "terms", "term", "odd", "even", "large", "small", "constant", "const"]
}
