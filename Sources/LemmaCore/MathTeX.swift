import Foundation

/// Reads the mathematics a reader types (LaTeX, or the Unicode a PDF or ChatGPT gives back) into an expression tree
/// that Lemma can evaluate: “\hat\beta = (X^TX)^{-1}X^Ty”, “\sum_{i=1}^N (y_i - \beta x_i)^2”, “βᵀβ ≤ t”.
/// It covers the algebra, calculus and linear algebra of a derivation, not all of LaTeX; what it cannot read is
/// reported with its position, so the editor can underline it.

// MARK: Tree

public enum MathRelation: String, Codable, Equatable, Sendable {
    case equal = "="
    case less = "<"
    case lessEqual = "≤"
    case greater = ">"
    case greaterEqual = "≥"
    case notEqual = "≠"
    case approx = "≈"
    /// “:=”, “\coloneqq”, “\triangleq”: the left side is defined by the right.
    case define = ":="

    /// Whether `left REL right` follows from comparing two numbers.
    public func holds(_ left: Double, _ right: Double, tolerance: Double) -> Bool {
        switch self {
        case .equal, .define, .approx: abs(left - right) <= tolerance
        case .less: left < right + tolerance
        case .lessEqual: left <= right + tolerance
        case .greater: left > right - tolerance
        case .greaterEqual: left >= right - tolerance
        case .notEqual: abs(left - right) > tolerance
        }
    }

    var isOrder: Bool { [.less, .lessEqual, .greater, .greaterEqual].contains(self) }
    /// The relation read the other way round: a ≤ b is b ≥ a.
    var flipped: MathRelation {
        switch self {
        case .less: .greater; case .lessEqual: .greaterEqual; case .greater: .less; case .greaterEqual: .lessEqual
        default: self
        }
    }
}

/// An expression. Symbols keep the reader's notation as a name: “x”, “β”, “β̂”, “β_0”, “x̄”, “β̂^ridge”.
public indirect enum MathNode: Equatable, Sendable {
    case number(Double)
    case symbol(String)
    /// `x_i`, `X_{ij}`: a symbol indexed by bound variables of a sum, product or integral.
    case indexed(String, [MathNode])
    case add(MathNode, MathNode)
    case subtract(MathNode, MathNode)
    case multiply(MathNode, MathNode)
    case divide(MathNode, MathNode)
    case negate(MathNode)
    case power(MathNode, MathNode)
    case transpose(MathNode)
    case inverse(MathNode)
    /// A named function of the language: exp, log, sin, tr, det, diag, max, min…
    case function(String, [MathNode])
    /// A function the reader has not defined (f, g, h): tested with arbitrary smooth functions.
    case apply(String, [MathNode])
    /// ‖x‖ or ‖x‖_p (p = 1, 2, ∞; nil is the Euclidean or Frobenius norm).
    case norm(MathNode, Double?)
    case absolute(MathNode)
    case factorial(MathNode)
    case binomial(MathNode, MathNode)
    case sum(index: String, lower: MathNode?, upper: MathNode?, body: MathNode)
    case product(index: String, lower: MathNode?, upper: MathNode?, body: MathNode)
    /// d/dx or ∂/∂x of the body (order 1 or 2), and ∇ₓ.
    case derivative(MathNode, variable: String, order: Int)
    case integral(lower: MathNode, upper: MathNode, variable: String, body: MathNode)
    case matrix([[MathNode]])
    /// The identity matrix, sized by its subscript (`I_p`) or by what it is added to.
    case identity(MathNode?)
    /// The vector of ones `\mathbf{1}` (optionally `\mathbf{1}_N`).
    case ones(MathNode?)
    /// The body evaluated with `variable` set to `value`: f′(x) is the derivative of f(t) at t = x.
    case at(MathNode, variable: String, value: MathNode)
    /// Something read but not evaluated: an expectation, a probability, a limit, a set.
    case unsupported(String)
}

/// One line of a derivation: expressions joined by relations (“a = b ≤ c”), possibly starting with a relation
/// that continues the previous line (“= c”, “&\le d”).
public struct MathChain: Equatable, Sendable {
    public var terms: [MathNode]
    public var relations: [MathRelation]
    public var leading: MathRelation?
    /// The source range (UTF-16 offsets) of each term, for diagnostics on one side of a relation.
    public var termRanges: [Range<Int>]
}

public struct MathParseError: Error, Equatable, Sendable, LocalizedError {
    public var message: String
    /// UTF-16 offsets in the line where the problem was found.
    public var range: Range<Int>
    public init(_ message: String, range: Range<Int>) { self.message = message; self.range = range }
    public var errorDescription: String? { message }
}

// MARK: Tokens

struct MathToken: Equatable {
    enum Kind: Equatable {
        case number(Double, String)
        case letter(Character)
        case command(String)
        case symbol(String)
        case end
    }
    var kind: Kind
    var range: Range<Int>

    var isEnd: Bool { kind == .end }
    func isSymbol(_ value: String) -> Bool { kind == .symbol(value) }
    func isCommand(_ value: String) -> Bool { kind == .command(value) }
    var commandName: String? { if case let .command(name) = kind { name } else { nil } }
    var letter: Character? { if case let .letter(c) = kind { c } else { nil } }
}

enum MathLexer {
    /// Unicode a PDF's text layer or a chat answer contains, as the LaTeX it stands for.
    static let unicode: [Character: String] = {
        var map: [Character: String] = [
            "≤": "\\le ", "≥": "\\ge ", "≠": "\\ne ", "≈": "\\approx ", "×": "\\times ", "·": "\\cdot ", "⋅": "\\cdot ", "∙": "\\cdot ",
            "−": "-", "–": "-", "∑": "\\sum ", "∏": "\\prod ", "∫": "\\int ", "√": "\\sqrt ", "∞": "\\infty ", "∂": "\\partial ",
            "∇": "\\nabla ", "∈": "\\in ", "ℝ": "\\mathbb{R}", "ℕ": "\\mathbb{N}", "ℤ": "\\mathbb{Z}", "ℚ": "\\mathbb{Q}",
            "‖": "\\|", "ᵀ": "^{T}", "⊤": "^{T}", "²": "^{2}", "³": "^{3}", "⁴": "^{4}", "ⁿ": "^{n}",
            "⁰": "^{0}", "¹": "^{1}", "₀": "_{0}", "₁": "_{1}", "₂": "_{2}", "₃": "_{3}", "₄": "_{4}", "₅": "_{5}", "₆": "_{6}",
            "₇": "_{7}", "₈": "_{8}", "₉": "_{9}", "ᵢ": "_{i}", "ⱼ": "_{j}", "ₖ": "_{k}", "ₙ": "_{n}", "ₚ": "_{p}",
            "⪯": "\\preceq ", "≻": "\\succ ", "⪰": "\\succeq ", "≺": "\\prec ", "≡": "\\equiv ", "≜": "\\triangleq ", "≔": "\\coloneqq ",
            "⇒": "\\Rightarrow ", "⟹": "\\Rightarrow ", "⇔": "\\iff ", "⟺": "\\iff ", "∼": "\\sim ", "±": "\\pm ", "∣": "|", "′": "'", "∗": "*",
            "ℓ": "\\ell ", "π": "\\pi ", "\u{00A0}": " "
        ]
        let greek: [(Character, String)] = [
            ("α", "alpha"), ("β", "beta"), ("γ", "gamma"), ("δ", "delta"), ("ε", "varepsilon"), ("ϵ", "epsilon"), ("ζ", "zeta"),
            ("η", "eta"), ("θ", "theta"), ("ϑ", "vartheta"), ("ι", "iota"), ("κ", "kappa"), ("λ", "lambda"), ("μ", "mu"), ("ν", "nu"),
            ("ξ", "xi"), ("ρ", "rho"), ("ϱ", "varrho"), ("σ", "sigma"), ("ς", "varsigma"), ("τ", "tau"), ("υ", "upsilon"),
            ("φ", "varphi"), ("ϕ", "phi"), ("χ", "chi"), ("ψ", "psi"), ("ω", "omega"), ("Γ", "Gamma"), ("Δ", "Delta"),
            ("Θ", "Theta"), ("Λ", "Lambda"), ("Ξ", "Xi"), ("Π", "Pi"), ("Σ", "Sigma"), ("Υ", "Upsilon"), ("Φ", "Phi"), ("Ψ", "Psi"), ("Ω", "Omega")
        ]
        for (character, name) in greek { map[character] = "\\\(name) " }
        return map
    }()

    /// The text with Unicode mathematics replaced by its LaTeX (“X ∈ ℝ^{N×p}” → “X \\in \\mathbb{R}^{N\\times p}”).
    public static func latex(_ source: String) -> String {
        var result = ""
        var characters = Array(source)[...]
        while let character = characters.first {
            characters = characters.dropFirst()
            if character == "⁻", characters.first == "¹" { result += "^{-1}"; characters = characters.dropFirst(); continue }
            if let replacement = unicode[character] { result += replacement; continue }
            if let letter = mathAlphanumeric(character) {
                if let name = MathNames.greek.first(where: { $0.value == String(letter) })?.key { result += "\\" + name + " " } else { result.append(letter) }
                continue
            }
            result.append(character)
        }
        return result
    }

    static func tokens(_ source: String) -> [MathToken] {
        var result: [MathToken] = []
        var offset = 0
        let characters = Array(source)
        var index = 0
        func push(_ kind: MathToken.Kind, _ range: Range<Int>) { result.append(MathToken(kind: kind, range: range)) }
        while index < characters.count {
            let character = characters[index]
            let width = character.utf16.count
            let start = offset
            // Superscript and subscript runs such as “⁻¹” come as two characters.
            if character == "⁻", index + 1 < characters.count, characters[index + 1] == "¹" {
                for token in tokens("^{-1}") where !token.isEnd { push(token.kind, start..<(start + width + 1)) }
                index += 2; offset += width + characters[index - 1].utf16.count; continue
            }
            if let replacement = unicode[character] ?? accented(character) {
                for token in tokens(replacement) where !token.isEnd { push(token.kind, start..<(start + width)) }
                index += 1; offset += width; continue
            }
            if let bold = mathAlphanumeric(character) {
                push(.letter(bold), start..<(start + width)); index += 1; offset += width; continue
            }
            if character.isWhitespace { index += 1; offset += width; continue }
            if character.isNumber || (character == "." && index + 1 < characters.count && characters[index + 1].isNumber) {
                var text = ""
                var end = index
                var seenPoint = false
                while end < characters.count, characters[end].isASCII, characters[end].isNumber || (characters[end] == "." && !seenPoint && end + 1 < characters.count && characters[end + 1].isNumber) {
                    if characters[end] == "." { seenPoint = true }
                    text.append(characters[end]); end += 1
                }
                if text.isEmpty { push(.symbol(String(character)), start..<(start + width)); index += 1; offset += width; continue }
                push(.number(Double(text) ?? .nan, text), start..<(start + text.utf16.count))
                offset += text.utf16.count; index = end; continue
            }
            if character == "\\" {
                var end = index + 1
                var name = ""
                while end < characters.count, characters[end].isASCII, characters[end].isLetter { name.append(characters[end]); end += 1 }
                if name.isEmpty, end < characters.count { name = String(characters[end]); end += 1 }
                let length = characters[index..<end].reduce(0) { $0 + $1.utf16.count }
                push(.command(name), start..<(start + length))
                offset += length; index = end; continue
            }
            if character.isLetter, character.isASCII {
                push(.letter(character), start..<(start + width)); index += 1; offset += width; continue
            }
            push(.symbol(String(character)), start..<(start + width))
            index += 1; offset += width
        }
        result.append(MathToken(kind: .end, range: offset..<offset))
        return result
    }

    /// A letter with a combining accent (“β̂”, “x̄”), as `\hat{\beta}`.
    static func accented(_ character: Character) -> String? {
        let scalars = Array(character.unicodeScalars)
        guard scalars.count >= 2 else { return nil }
        let marks: [UInt32: String] = [0x0302: "hat", 0x0304: "bar", 0x0305: "bar", 0x0303: "tilde", 0x0307: "dot", 0x0308: "ddot", 0x20D7: "vec", 0x030C: "check"]
        var base = String(String.UnicodeScalarView(scalars.prefix(1)))
        guard let first = base.first, first.isLetter else { return nil }
        if let replacement = unicode[first] { base = replacement.trimmingCharacters(in: .whitespaces) }
        var result = base
        for scalar in scalars.dropFirst() {
            guard let mark = marks[scalar.value] else { return nil }
            result = "\\\(mark){\(result)}"
        }
        return result
    }

    /// 𝑥, 𝐗, 𝜷 from a PDF's text layer, as the plain letter.
    static func mathAlphanumeric(_ character: Character) -> Character? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1, (0x1D400...0x1D7FF).contains(scalar.value) else { return nil }
        let folded = String(character).applyingTransform(.init("Any-Latin; Latin-ASCII"), reverse: false) ?? ""
        let decomposed = String(character).precomposedStringWithCompatibilityMapping
        if let first = decomposed.first, decomposed.count == 1, first.isLetter { return first }
        return folded.count == 1 ? folded.first : nil
    }
}

// MARK: Names

public enum MathNames {
    static let greek: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ", "eta": "η",
        "theta": "θ", "vartheta": "θ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "rho": "ρ",
        "varrho": "ρ", "sigma": "σ", "varsigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ", "chi": "χ",
        "psi": "ψ", "omega": "ω", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ",
        "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω", "ell": "ℓ"
    ]
    static let accents: [String: String] = [
        "hat": "\u{0302}", "widehat": "\u{0302}", "bar": "\u{0304}", "overline": "\u{0304}", "tilde": "\u{0303}", "widetilde": "\u{0303}",
        "dot": "\u{0307}", "ddot": "\u{0308}", "check": "\u{030C}", "breve": "\u{0306}", "vec": "\u{20D7}", "acute": "\u{0301}", "grave": "\u{0300}"
    ]
    private static let subscriptDigits: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
                                                                    "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "n": "ₙ", "p": "ₚ", "+": "₊", "-": "₋"]

    /// A symbol's name as a reader would write it: “β_0” → “β₀”, “x_{new}” → “x_new”.
    public static func display(_ name: String) -> String {
        guard let underscore = name.firstIndex(of: "_") else { return name }
        let base = name[..<underscore]
        var rest = String(name[name.index(after: underscore)...])
        if rest.hasPrefix("{"), rest.hasSuffix("}") { rest = String(rest.dropFirst().dropLast()) }
        if rest.allSatisfy({ subscriptDigits[$0] != nil }) { return base + String(rest.compactMap { subscriptDigits[$0] }) }
        return base + "_" + rest
    }
}

// MARK: Parser

public struct MathParser {
    private var tokens: [MathToken]
    private var position = 0
    /// Open |…| and ‖…‖ delimiters: a bar closes the innermost one instead of starting a factor.
    private var openBars: [String] = []
    /// Inside an integral, “dx” ends the integrand.
    private var integralDepth = 0
    /// Inside a matrix, “&” separates entries instead of being ignored.
    private var matrixDepth = 0

    /// Names longer than a letter that are read whole when written without a font command (“RSS(β)”, “MSE”):
    /// in LaTeX “RSS” is a product of three letters, but in a derivation it is a name.
    private let names: Set<String>
    /// Letters written as functions, “f(x)”: f, g and h, and those a derivation defines (“\\sigma(x) := …”).
    private let functions: Set<String>
    public static let commonNames: Set<String> = ["RSS", "PRSS", "MSE", "SSE", "SSR", "TSS", "AIC", "BIC", "KL", "ELBO", "EPE", "MAE", "RMSE", "LL", "NLL"]
    public static let commonFunctions: Set<String> = ["f", "g", "h"]

    init(_ source: String, names: Set<String> = MathParser.commonNames, functions: Set<String> = MathParser.commonFunctions) {
        tokens = MathLexer.tokens(source); self.names = names; self.functions = functions
    }

    /// Parses one line: a chain of expressions joined by relations.
    public static func chain(_ source: String, names: Set<String> = MathParser.commonNames, functions: Set<String> = MathParser.commonFunctions) throws -> MathChain {
        var parser = MathParser(source, names: names, functions: functions)
        return try parser.parseChain()
    }

    /// Parses a single expression (no relation).
    public static func expression(_ source: String, names: Set<String> = MathParser.commonNames) throws -> MathNode {
        var parser = MathParser(source, names: names)
        let chain = try parser.parseChain()
        guard chain.terms.count == 1, chain.leading == nil else {
            throw MathParseError("Expected one expression", range: 0..<source.utf16.count)
        }
        return chain.terms[0]
    }

    // MARK: Token helpers

    private var current: MathToken { tokens[min(position, tokens.count - 1)] }
    private func peek(_ ahead: Int = 1) -> MathToken { tokens[min(position + ahead, tokens.count - 1)] }
    private mutating func advance() { if position < tokens.count - 1 { position += 1 } }

    /// Spacing, alignment and sizing commands that carry no meaning for evaluation.
    private static let ignored: Set<String> = [",", ";", "!", ":", " ", "quad", "qquad", "displaystyle", "textstyle", "scriptstyle", "limits", "nolimits",
                                               "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "biggl", "biggr", "Biggl", "Biggr",
                                               "nonumber", "notag", "hfill", "medskip", "smallskip", "allowbreak", "nobreak", "phantom", "mathstrut", "strut"]

    private mutating func skipIgnorable() {
        while true {
            let token = current
            if let name = token.commandName, Self.ignored.contains(name) {
                advance()
                if name == "phantom", current.isSymbol("{") { _ = try? skipGroup() }
                continue
            }
            if token.isSymbol("&") && matrixDepth == 0 || token.isSymbol("~") { advance(); continue }
            if let name = token.commandName, ["label", "tag", "eqref"].contains(name) {
                advance(); if current.isSymbol("{") { _ = try? skipGroup() }; continue
            }
            return
        }
    }

    /// Skips a balanced `{…}` group, returning its tokens' source range.
    private mutating func skipGroup() throws -> Range<Int> {
        let start = current.range.lowerBound
        guard current.isSymbol("{") else { throw error("Expected {") }
        var depth = 0
        repeat {
            if current.isSymbol("{") { depth += 1 } else if current.isSymbol("}") { depth -= 1 }
            if current.isEnd { throw error("Missing }") }
            advance()
        } while depth > 0
        return start..<tokens[position - 1].range.upperBound
    }

    private func error(_ message: String, at token: MathToken? = nil) -> MathParseError {
        let token = token ?? current
        let range = token.isEnd ? max(0, token.range.lowerBound - 1)..<token.range.lowerBound : token.range
        return MathParseError(message, range: range)
    }

    // MARK: Relations

    private mutating func relation() -> MathRelation? {
        skipIgnorable()
        let token = current
        switch token.kind {
        case .symbol("="): advance(); return .equal
        case .symbol("<"): advance(); if current.isSymbol("=") { advance(); return .lessEqual }; return .less
        case .symbol(">"): advance(); if current.isSymbol("=") { advance(); return .greaterEqual }; return .greater
        case .symbol(":"):
            if peek().isSymbol("=") { advance(); advance(); return .define }
            return nil
        case let .command(name):
            switch name {
            case "le", "leq", "leqslant": advance(); return .lessEqual
            case "ge", "geq", "geqslant": advance(); return .greaterEqual
            case "lt": advance(); return .less
            case "gt": advance(); return .greater
            case "ne", "neq": advance(); return .notEqual
            case "approx", "simeq", "cong": advance(); return .approx
            case "coloneqq", "triangleq", "equiv", "eqqcolon", "doteq": advance(); return .define
            case "stackrel", "overset":
                // “\stackrel{\text{def}}{=}”: a definition.
                let save = position
                advance()
                if current.isSymbol("{"), (try? skipGroup()) != nil {
                    if current.isSymbol("{"), peek().isSymbol("="), peek(2).isSymbol("}") { advance(); advance(); advance(); return .define }
                    if current.isSymbol("=") { advance(); return .define }
                }
                position = save; return nil
            default: return nil
            }
        default: return nil
        }
    }

    mutating func parseChain() throws -> MathChain {
        skipIgnorable()
        var chain = MathChain(terms: [], relations: [], leading: nil, termRanges: [])
        if let leading = relation() { chain.leading = leading }
        while true {
            skipIgnorable()
            if current.isEnd { break }
            let start = current.range.lowerBound
            let term = try parseExpression()
            let end = tokens[max(0, position - 1)].range.upperBound
            chain.terms.append(term); chain.termRanges.append(start..<max(start, end))
            skipTrailing()
            if current.isEnd { break }
            if let next = relation() { chain.relations.append(next); continue }
            if let name = current.commandName, ["Rightarrow", "implies", "iff", "Leftrightarrow", "Longrightarrow", "therefore", "because", "to", "rightarrow", "mapsto", "sim", "in", "subset", "subseteq", "pm", "mp"].contains(name) {
                throw error(name == "in" ? "“∈” belongs on a line of its own, as a declaration" : "Lemma checks one relation at a time; put “\\\(name)” between lines")
            }
            throw error("Unexpected “\(source(of: current))”")
        }
        if chain.terms.isEmpty {
            if chain.leading != nil { throw error("Nothing after the relation") }
            throw error("Empty line")
        }
        if chain.terms.count != chain.relations.count + 1 { throw error("Missing expression after the relation") }
        for index in chain.terms.indices { chain.terms[index] = MathParser.resolveBinders(chain.terms[index], bound: []) }
        return chain
    }

    /// Punctuation that ends a displayed formula (“…,” or “….”) and `\text{…}` remarks such as “(by Cauchy–Schwarz)”.
    private mutating func skipTrailing() {
        while true {
            skipIgnorable()
            if current.isSymbol(",") || current.isSymbol(".") || current.isSymbol(";") {
                if peek().isEnd || peek().commandName == "text" || peek().commandName == "quad" || peek().commandName == "qquad" { advance(); continue }
            }
            if let name = current.commandName, ["text", "textrm", "mbox", "textit", "textbf", "intertext", "tag"].contains(name) {
                // A remark after the mathematics (“\quad\text{by (3.4)}”, “\text{since } x > 0”) is the reader's justification.
                while !current.isEnd { advance() }
                continue
            }
            return
        }
    }

    private func source(of token: MathToken) -> String {
        switch token.kind {
        case let .number(_, text): text
        case let .letter(c): String(c)
        case let .command(name): "\\" + name
        case let .symbol(s): s
        case .end: "end of line"
        }
    }

    // MARK: Expressions

    mutating func parseExpression() throws -> MathNode {
        var left = try parseTerm()
        while true {
            skipIgnorable()
            if current.isSymbol("+") { advance(); left = .add(left, try parseTerm()); continue }
            if current.isSymbol("-") { advance(); left = .subtract(left, try parseTerm()); continue }
            if current.isCommand("pm") || current.isCommand("mp") { throw error("“±” stands for two expressions; write each one") }
            return left
        }
    }

    /// A product: explicit (·, ×, *, /) or by juxtaposition (“2x”, “X^TX”, “(a+b)(a-b)”).
    mutating func parseTerm() throws -> MathNode {
        var left = try parseUnary()
        while true {
            skipIgnorable()
            if current.isCommand("cdot") || current.isCommand("times") || current.isSymbol("*") || current.isCommand("ast") {
                advance(); left = .multiply(left, try parseUnary()); continue
            }
            if current.isSymbol("/") || current.isCommand("div") { advance(); left = .divide(left, try parseUnary()); continue }
            if startsFactor() { left = .multiply(left, try parsePostfix()); continue }
            return left
        }
    }

    mutating func parseUnary() throws -> MathNode {
        skipIgnorable()
        if current.isSymbol("-") { advance(); return .negate(try parseUnary()) }
        if current.isSymbol("+") { advance(); return try parseUnary() }
        return try parsePostfix()
    }

    /// Whether the current token can begin another factor of an implicit product.
    private func startsFactor() -> Bool {
        let token = current
        switch token.kind {
        case .number: return true
        case let .letter(c):
            // “dx” ends an integrand.
            if integralDepth > 0, c == "d", isDifferential(at: position) { return false }
            return true
        case let .symbol(s):
            if s == "(" || s == "[" { return true }
            if s == "|" { return openBars.last != "|" }
            if s == "{" { return true }
            return false
        case let .command(name):
            if name == "|" || name == "Vert" || name == "lVert" { return openBars.last != "‖" || name == "lVert" }
            if name == "rVert" || name == "rvert" || name == "right" || name == "rbrace" || name == "rangle" { return false }
            if integralDepth > 0, name == "mathrm" || name == "operatorname", isDifferential(at: position) { return false }
            if name == "{" || name == "lbrace" || name == "left" || name == "lvert" || name == "langle" { return true }
            return Self.primaryCommands.contains(name) || MathNames.greek[name] != nil || MathNames.accents[name] != nil
        case .end: return false
        }
    }

    private static let functions: Set<String> = ["exp", "log", "ln", "lg", "sin", "cos", "tan", "sec", "csc", "cot", "sinh", "cosh", "tanh",
                                                 "arcsin", "arccos", "arctan", "det", "max", "min", "tr", "trace", "diag", "sgn", "sign", "Tr"]
    private static let primaryCommands: Set<String> = functions.union([
        "frac", "dfrac", "tfrac", "cfrac", "sqrt", "sum", "prod", "int", "iint", "binom", "dbinom", "tbinom", "pi", "infty", "partial", "nabla",
        "mathbf", "boldsymbol", "bm", "mathit", "mathrm", "mathsf", "mathcal", "mathbb", "mathfrak", "operatorname", "text", "textrm", "mbox",
        "begin", "lim", "Pr", "lvert", "lVert", "vert", "Vert", "langle", "ell", "mathbbm", "one"
    ])

    /// “d” followed by a variable (“dx”, “d\beta”) or `\mathrm{d}x`.
    private func isDifferential(at index: Int) -> Bool {
        let token = tokens[index]
        if token.letter == "d" {
            let next = tokens[min(index + 1, tokens.count - 1)]
            if next.letter != nil { return true }
            if let name = next.commandName, MathNames.greek[name] != nil { return true }
            return false
        }
        if token.commandName == "mathrm" || token.commandName == "operatorname" {
            let a = tokens[min(index + 1, tokens.count - 1)], b = tokens[min(index + 2, tokens.count - 1)], c = tokens[min(index + 3, tokens.count - 1)]
            return a.isSymbol("{") && b.letter == "d" && c.isSymbol("}")
        }
        return false
    }

    private mutating func parsePostfix() throws -> MathNode {
        var node = try parsePrimary()
        while true {
            // Spacing never separates a base from its exponent, but it may sit between them in pasted text.
            if current.isSymbol("^") {
                let caret = current
                advance()
                node = try superscript(on: node, caret: caret)
                continue
            }
            if current.isSymbol("_") {
                advance()
                let index = try argument()
                switch node {
                case let .symbol(name): node = .indexed(name, MathParser.indexList(index))
                case let .identity(nil): node = .identity(index)
                case let .ones(nil): node = .ones(index)
                default: throw error("A subscript on this expression is not supported")
                }
                continue
            }
            if current.isSymbol("'") || current.isCommand("prime") {
                advance()
                if case let .symbol(name) = node { node = .symbol(name + "′") } else { node = .transpose(node) }
                continue
            }
            if current.isSymbol("!") { advance(); node = .factorial(node); continue }
            return node
        }
    }

    /// `^T`, `^\top`, `^{-1}`, `^*`, `^{(k)}`, `^{\text{ridge}}` or a power.
    private mutating func superscript(on base: MathNode, caret: MathToken) throws -> MathNode {
        skipIgnorableInScript()
        // Transpose.
        if current.letter == "T" || current.isCommand("top") || current.isCommand("intercal") || current.isCommand("mathsf") && peekIsLetterGroup("T") || current.isCommand("mathrm") && peekIsLetterGroup("T") {
            if current.commandName != nil, current.commandName != "top", current.commandName != "intercal" { advance(); _ = try skipGroup() } else { advance() }
            return .transpose(base)
        }
        if current.isSymbol("{") {
            // {T}, {\top}, {-1}, {*}, {(k)}, {\text{ridge}}.
            let save = position
            advance()
            skipIgnorableInScript()
            if (current.letter == "T" || current.isCommand("top") || current.isCommand("intercal")) && peek().isSymbol("}") { advance(); advance(); return .transpose(base) }
            if current.isSymbol("-"), case let .number(value, _) = peek().kind, value == 1, peek(2).isSymbol("}") { advance(); advance(); advance(); return .inverse(base) }
            if current.isSymbol("*") || current.isCommand("ast") || current.isCommand("star") || current.isSymbol("+") || current.isCommand("dagger") || current.isCommand("prime") {
                let mark = current.isSymbol("+") || current.isCommand("dagger") ? "†" : current.isCommand("prime") ? "′" : "*"
                advance()
                if current.isSymbol("}") {
                    advance()
                    if case let .symbol(name) = base { return .symbol(name + mark) }
                    if mark == "†" { throw error("The pseudo-inverse is not supported; write (AᵀA)⁻¹Aᵀ", at: caret) }
                    throw error("“\(mark)” on an expression is not supported", at: caret)
                }
            }
            if case let .symbol(name) = base, let label = try superscriptLabel() {
                return .symbol(name + "^" + label)
            }
            position = save
        } else if current.isSymbol("*") || current.isCommand("ast") || current.isCommand("star") {
            advance()
            if case let .symbol(name) = base { return .symbol(name + "*") }
            throw error("“*” on an expression is not supported", at: caret)
        } else if current.isSymbol("-"), case let .number(value, _) = peek().kind, value == 1 {
            advance(); advance(); return .inverse(base)
        } else if current.isCommand("prime") {
            advance()
            if case let .symbol(name) = base { return .symbol(name + "′") }
            return .transpose(base)
        }
        let exponent = try argument()
        if case .number(-1) = exponent { return .inverse(base) }
        if case .negate(.number(1)) = exponent { return .inverse(base) }
        return .power(base, exponent)
    }

    /// `{(k)}`, `{\text{ridge}}` or `{ridge}` after a symbol: part of its name (“β̂^ridge”, “x^(k)”).
    private mutating func superscriptLabel() throws -> String? {
        // Two letters or more and nothing else: a label (“\hat\beta^{ridge}”, “x^{new}”), not a power.
        var probe = position
        var word = ""
        while probe < tokens.count, let c = tokens[probe].letter { word.append(c); probe += 1 }
        while probe < tokens.count, case let .number(_, digits) = tokens[probe].kind, !word.isEmpty { word += digits; probe += 1 }
        if word.count >= 2, tokens[probe].isSymbol("}") {
            position = probe + 1
            return word
        }
        if current.isSymbol("(") {
            var label = "("
            var probe = position + 1
            while probe < tokens.count, !tokens[probe].isSymbol(")") {
                guard let piece = Self.labelText(tokens[probe]) else { return nil }
                label += piece; probe += 1
            }
            guard probe + 1 < tokens.count, tokens[probe + 1].isSymbol("}") else { return nil }
            position = probe + 2
            return label + ")"
        }
        if let name = current.commandName, ["text", "textrm", "mathrm", "mbox", "rm", "operatorname", "textnormal"].contains(name), peek().isSymbol("{") {
            var probe = position + 2
            var label = ""
            while probe < tokens.count, !tokens[probe].isSymbol("}") {
                guard let piece = Self.labelText(tokens[probe]) else { return nil }
                label += piece; probe += 1
            }
            guard probe + 1 < tokens.count, tokens[probe + 1].isSymbol("}"), !label.isEmpty else { return nil }
            position = probe + 2
            return label
        }
        return nil
    }

    private static func labelText(_ token: MathToken) -> String? {
        switch token.kind {
        case let .letter(c): String(c)
        case let .number(_, text): text
        case let .symbol(s) where s == "-" || s == "+" || s == ",": s
        case let .command(name) where MathNames.greek[name] != nil: MathNames.greek[name]
        default: nil
        }
    }

    private func peekIsLetterGroup(_ letter: Character) -> Bool {
        peek().isSymbol("{") && peek(2).letter == letter && peek(3).isSymbol("}")
    }

    private mutating func skipIgnorableInScript() {
        while let name = current.commandName, Self.ignored.contains(name) { advance() }
    }

    /// The argument of a command or script: a braced group, or a single token (one digit of a number: “\frac12”).
    private mutating func argument() throws -> MathNode {
        skipIgnorableInScript()
        if current.isSymbol("{") {
            advance()
            let saveBars = openBars; openBars = []
            defer { openBars = saveBars }
            let inner = try parseExpression()
            skipIgnorable()
            guard current.isSymbol("}") else { throw error("Missing }") }
            advance()
            return inner
        }
        if case let .number(_, text) = current.kind, text.count > 1, !text.contains(".") {
            // “\frac12”, “x^23”: a script or argument without braces takes one digit.
            let digit = Double(String(text.first!))!
            let rest = String(text.dropFirst())
            let range = current.range
            tokens[position] = MathToken(kind: .number(Double(rest)!, rest), range: (range.lowerBound + 1)..<range.upperBound)
            return .number(digit)
        }
        if current.isEnd { throw error("Missing argument") }
        return try parsePrimary()
    }

    /// The text of a braced group of letters, such as `{RSS}` in `\operatorname{RSS}`.
    private mutating func letterGroup() throws -> String {
        guard current.isSymbol("{") else {
            if let c = current.letter { advance(); return String(c) }
            throw error("Expected {")
        }
        advance()
        var text = ""
        while !current.isSymbol("}") {
            switch current.kind {
            case let .letter(c): text.append(c)
            case let .number(_, digits): text += digits
            case .symbol(" "), .symbol("-"), .symbol("_"): text += " "
            case let .command(name) where Self.ignored.contains(name): text += " "
            case let .command(name) where MathNames.greek[name] != nil: text += MathNames.greek[name]!
            case .end: throw error("Missing }")
            default: text += "?"
            }
            advance()
        }
        advance()
        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Primaries

    private mutating func parsePrimary() throws -> MathNode {
        skipIgnorable()
        let token = current
        switch token.kind {
        case let .number(value, _):
            advance(); return .number(value)
        case let .letter(c):
            if let name = longName() {
                if current.isSymbol("(") || current.isCommand("left") && peek().isSymbol("(") { return .apply(name, try callArguments()) }
                return .symbol(name)
            }
            advance()
            if let call = try functionApplication(String(c)) { return call }
            if c == "E", current.isSymbol("[") || current.isCommand("left") && peek().isSymbol("[") {
                _ = try callArguments(open: "[", close: "]")
                return .unsupported("expectation")
            }
            if c == "P", current.isSymbol("(") {
                _ = try callArguments()
                return .unsupported("probability")
            }
            return .symbol(String(c))
        case let .symbol(s):
            switch s {
            case "(": return try group(open: "(", close: ")")
            case "[": return try group(open: "[", close: "]")
            case "{": return try group(open: "{", close: "}")
            case "|": return try bars(open: "|")
            default: throw error(s == ")" || s == "]" || s == "}" ? "Unbalanced “\(s)”" : "Unexpected “\(s)”")
            }
        case let .command(name):
            return try command(name, token: token)
        case .end:
            throw error("Missing expression")
        }
    }

    /// A known multi-letter name written as adjacent letters (“RSS”), consumed whole.
    private mutating func longName() -> String? {
        guard !names.isEmpty, current.letter != nil else { return nil }
        var letters = ""
        var probe = position
        var end = tokens[probe].range.lowerBound
        while probe < tokens.count, let c = tokens[probe].letter, tokens[probe].range.lowerBound == end, letters.count < 12 {
            letters.append(c); end = tokens[probe].range.upperBound; probe += 1
        }
        guard letters.count >= 2 else { return nil }
        // The longest known name at this position.
        for length in stride(from: letters.count, through: 2, by: -1) {
            let candidate = String(letters.prefix(length))
            if names.contains(candidate) {
                position += length
                return candidate
            }
        }
        return nil
    }

    private mutating func group(open: String, close: String) throws -> MathNode {
        advance()
        let saveBars = openBars; openBars = []
        defer { openBars = saveBars }
        let inner = try parseExpression()
        skipIgnorable()
        if close == "}" {
            guard current.isSymbol("}") || current.isCommand("}") || current.isCommand("rbrace") else { throw error("Missing }") }
        } else {
            guard current.isSymbol(close) else { throw error("Missing “\(close)”") }
        }
        advance()
        return inner
    }

    /// |x| (absolute value, or a determinant for a square matrix) and ‖x‖.
    private mutating func bars(open: String) throws -> MathNode {
        advance()
        openBars.append(open)
        defer { openBars.removeLast() }
        let inner = try parseExpression()
        skipIgnorable()
        if open == "|" {
            guard current.isSymbol("|") || current.isCommand("rvert") || current.isCommand("vert") else { throw error("Missing closing |") }
            advance()
            return .absolute(inner)
        }
        guard current.isCommand("|") || current.isCommand("rVert") || current.isCommand("Vert") else { throw error("Missing closing ‖") }
        advance()
        return .norm(inner, try normIndex())
    }

    /// The p of ‖x‖_p.
    private mutating func normIndex() throws -> Double? {
        guard current.isSymbol("_") else { return nil }
        advance()
        let index = try argument()
        switch index {
        case let .number(value): return value
        case .symbol("∞"): return .infinity
        case .unsupported("infinity"): return .infinity
        case .symbol("F"): return nil
        default: throw error("Only ‖·‖₁, ‖·‖₂ and ‖·‖∞ are supported")
        }
    }

    /// `\left( … \right)`, with any delimiter.
    private mutating func leftRight() throws -> MathNode {
        advance()
        let open = current
        advance()
        let saveBars = openBars; openBars = []
        defer { openBars = saveBars }
        let inner = try parseExpression()
        skipIgnorable()
        guard current.isCommand("right") else { throw error("Missing \\right") }
        advance()
        let close = current
        advance()
        if open.isSymbol("|") || open.isCommand("vert") || open.isCommand("lvert") {
            guard close.isSymbol("|") || close.isCommand("vert") || close.isCommand("rvert") else { throw error("Mismatched \\right", at: close) }
            return .absolute(inner)
        }
        if open.isCommand("|") || open.isCommand("Vert") || open.isCommand("lVert") { return .norm(inner, try normIndex()) }
        return inner
    }

    private mutating func callArguments(open: String = "(", close: String = ")") throws -> [MathNode] {
        var usesLeft = false
        if current.isCommand("left") { usesLeft = true; advance() }
        guard current.isSymbol(open) else { throw error("Expected “\(open)”") }
        advance()
        let saveBars = openBars; openBars = []
        defer { openBars = saveBars }
        var arguments = [try parseExpression()]
        while current.isSymbol(",") { advance(); arguments.append(try parseExpression()) }
        skipIgnorable()
        if usesLeft { guard current.isCommand("right") else { throw error("Missing \\right") }; advance() }
        guard current.isSymbol(close) else { throw error("Missing “\(close)”") }
        advance()
        return arguments
    }

    /// “f(x)”, “f'(x)”, “σ(t)” for a letter written as a function; nil when no call follows.
    private mutating func functionApplication(_ name: String) throws -> MathNode? {
        guard functions.contains(name) else { return nil }
        var probe = position
        var primes = 0
        while tokens[probe].isSymbol("'") || tokens[probe].isCommand("prime") { primes += 1; probe += 1 }
        let opens = tokens[probe].isSymbol("(") || tokens[probe].isCommand("left") && tokens[min(probe + 1, tokens.count - 1)].isSymbol("(")
        guard opens, primes <= 2 else { return nil }
        position = probe
        return .apply(name + String(repeating: "′", count: primes), try callArguments())
    }

    private mutating func command(_ name: String, token: MathToken) throws -> MathNode {
        if let letter = MathNames.greek[name] {
            advance()
            if let call = try functionApplication(letter) { return call }
            return .symbol(letter)
        }
        if let accent = MathNames.accents[name] {
            advance()
            let inner = try argument()
            // The accent goes on the letter, before any subscript or mark already in the name.
            func accented(_ symbol: String) -> String {
                let letterEnd = symbol.index(after: symbol.startIndex)
                return String(symbol[..<letterEnd]) + accent + String(symbol[letterEnd...])
            }
            switch inner {
            case let .symbol(symbol): return .symbol(accented(symbol))
            case let .indexed(symbol, index): return .indexed(accented(symbol), index)
            default: throw error("An accent on an expression is not supported", at: token)
            }
        }
        switch name {
        case "left": return try leftRight()
        case "{", "lbrace": return try group(open: "{", close: "}")
        case "langle":
            throw error("Inner products ⟨·,·⟩ are not supported; write xᵀy")
        case "|", "Vert", "lVert": return try bars(open: "‖")
        case "lvert", "vert": return try bars(open: "|")
        case "pi": advance(); return .symbol("π")
        case "infty": advance(); return .unsupported("infinity")
        case "ell": advance(); return .symbol("ℓ")
        case "frac", "dfrac", "tfrac", "cfrac": return try fraction()
        case "sqrt":
            advance()
            var degree: MathNode?
            if current.isSymbol("[") {
                advance(); degree = try parseExpression()
                guard current.isSymbol("]") else { throw error("Missing ]") }
                advance()
            }
            let radicand = try argument()
            if let degree { return .power(radicand, .divide(.number(1), degree)) }
            return .function("sqrt", [radicand])
        case "binom", "dbinom", "tbinom":
            advance()
            return .binomial(try argument(), try argument())
        case "sum", "prod": return try bigOperator(name)
        case "int", "iint": return try integral()
        case "nabla":
            advance()
            guard current.isSymbol("_") else { throw error("Write ∇ with its variable: \\nabla_\\beta") }
            advance()
            let variable = try argument()
            guard case let .symbol(v) = variable else { throw error("∇ needs a single variable") }
            return .derivative(try parseTerm(), variable: v, order: 1)
        case "partial":
            throw error("Write a partial derivative as \\frac{\\partial}{\\partial x}")
        case "mathbf", "boldsymbol", "bm", "mathit", "mathsf", "mathbbm":
            advance()
            if current.isSymbol("{"), peek().isSymbol("1") || peek().kind == .number(1, "1"), peek(2).isSymbol("}") { advance(); advance(); advance(); return .ones(nil) }
            if current.isSymbol("{"), peek().kind == .number(0, "0"), peek(2).isSymbol("}") { advance(); advance(); advance(); return .number(0) }
            let inner = try argument()
            if case .identity = inner { return inner }
            return inner
        case "one": advance(); return .ones(nil)
        case "mathbb":
            advance()
            let text = try letterGroup()
            if text == "1" { return .ones(nil) }
            if text == "E" { if current.isSymbol("[") || current.isSymbol("(") || current.isCommand("left") { _ = try? bracketArgument() }; return .unsupported("expectation") }
            if text == "P" { if current.isSymbol("(") || current.isSymbol("[") || current.isCommand("left") { _ = try? bracketArgument() }; return .unsupported("probability") }
            throw error("Sets such as ℝ belong in a declaration (“x \\in \\mathbb{R}^n”)", at: token)
        case "mathcal", "mathfrak", "mathscr":
            advance()
            let text = try letterGroup()
            return .symbol("𝒞" + text)
        case "mathrm", "operatorname", "text", "textrm", "mbox", "textit", "textnormal", "rm":
            advance()
            let text = try letterGroup()
            return try named(text, token: token)
        case "lim", "liminf", "limsup", "sup", "inf", "argmin", "argmax":
            throw error("“\\\(name)” cannot be checked numerically", at: token)
        case "Pr":
            advance()
            if current.isSymbol("(") || current.isSymbol("[") || current.isCommand("left") { _ = try? bracketArgument() }
            return .unsupported("probability")
        case "begin": return try environment()
        default:
            if Self.functions.contains(name) { advance(); return try functionCall(name == "Tr" || name == "trace" ? "tr" : name == "sgn" ? "sign" : name) }
            throw error("Unknown command \\\(name)", at: token)
        }
    }

    private mutating func bracketArgument() throws -> [MathNode] {
        if current.isCommand("left") {
            let open = peek()
            if open.isSymbol("[") { return try callArguments(open: "[", close: "]") }
            return try callArguments()
        }
        return current.isSymbol("[") ? try callArguments(open: "[", close: "]") : try callArguments()
    }

    /// A word in roman type: a function (“tr”, “diag”, “Var”), the differential “d”, or a multi-letter name (“RSS”).
    private mutating func named(_ text: String, token: MathToken) throws -> MathNode {
        let word = text.trimmingCharacters(in: .whitespaces)
        if word.isEmpty { return try parsePrimary() }
        let lower = word.lowercased()
        if ["tr", "trace", "diag", "det", "exp", "log", "sign", "sgn"].contains(lower) {
            return try functionCall(lower == "trace" ? "tr" : lower == "sgn" ? "sign" : lower)
        }
        if ["e", "var", "cov", "corr", "pr", "p"].contains(lower), current.isSymbol("[") || current.isSymbol("(") || current.isCommand("left") {
            _ = try bracketArgument()
            return .unsupported(lower == "e" ? "expectation" : lower == "pr" || lower == "p" ? "probability" : lower == "var" ? "variance" : lower)
        }
        if word == "e" { return .symbol("e") }
        if word.count == 1, let c = word.first, c.isLetter { return .symbol(String(c)) }
        guard word.allSatisfy({ $0.isLetter || $0.isNumber }) else { throw error("“\(word)” is text, not mathematics", at: token) }
        if current.isSymbol("(") || current.isCommand("left") && peek().isSymbol("(") { return .apply(word, try callArguments()) }
        return .symbol(word)
    }

    private mutating func functionCall(_ name: String) throws -> MathNode {
        // \log_2 x, \sin^2 x.
        var base: Double?
        if name == "log", current.isSymbol("_") {
            advance()
            let index = try argument()
            switch index {
            case let .number(value): base = value
            case .symbol("e"): base = nil
            default: throw error("Only numeric logarithm bases are supported")
            }
        }
        var power: MathNode?
        if current.isSymbol("^") {
            advance()
            if current.isSymbol("{"), peek().isSymbol("-"), peek(2).kind == .number(1, "1") { throw error("Write the inverse function explicitly (\\arcsin)") }
            power = try argument()
        }
        skipIgnorable()
        var arguments: [MathNode]
        if let delimited = try delimitedArguments() {
            arguments = delimited
        } else if current.isSymbol("{") {
            arguments = [try parsePrimary()]
        } else {
            // “\log 2x”, “\exp x^2”: the function takes the factors that follow, up to the next operator or function.
            var argument = try parsePostfix()
            while startsFactor(), !startsFunction() { argument = .multiply(argument, try parsePostfix()) }
            arguments = [argument]
        }
        var node: MathNode
        switch name {
        case "ln": node = .function("log", arguments)
        case "lg": node = .divide(.function("log", arguments), .function("log", [.number(2)]))
        case "log":
            node = .function("log", arguments)
            if let base { node = .divide(node, .function("log", [.number(base)])) }
        default: node = .function(name, arguments)
        }
        if (name == "max" || name == "min"), arguments.count < 1 { throw error("\\\(name) needs arguments") }
        if let power { node = .power(node, power) }
        return node
    }

    private func startsFunction() -> Bool {
        if let name = current.commandName { return Self.functions.contains(name) || name == "sum" || name == "prod" || name == "int" }
        return false
    }

    /// Arguments in (…), […], \{…\} or with \left…\right, separated by commas; nil when none open here.
    private mutating func delimitedArguments() throws -> [MathNode]? {
        var usesLeft = false
        var probe = current
        if probe.isCommand("left") { usesLeft = true; probe = peek() }
        let close: (MathToken) -> Bool
        if probe.isSymbol("(") { close = { $0.isSymbol(")") } }
        else if probe.isSymbol("[") { close = { $0.isSymbol("]") } }
        else if probe.isCommand("{") || probe.isCommand("lbrace") { close = { $0.isCommand("}") || $0.isCommand("rbrace") } }
        else { return nil }
        if usesLeft { advance() }
        advance()
        let saveBars = openBars; openBars = []
        defer { openBars = saveBars }
        var arguments = [try parseExpression()]
        while current.isSymbol(",") { advance(); arguments.append(try parseExpression()) }
        skipIgnorable()
        if usesLeft { guard current.isCommand("right") else { throw error("Missing \\right") }; advance() }
        guard close(current) else { throw error("Missing closing bracket") }
        advance()
        return arguments
    }

    /// `\frac{a}{b}`, and derivatives written as fractions: `\frac{d}{dx}`, `\frac{\partial f}{\partial \beta}`, `\frac{d^2}{dx^2}`.
    private mutating func fraction() throws -> MathNode {
        let token = current
        advance()
        if let derivative = try derivativeFraction(token: token) { return derivative }
        let numerator = try argument()
        let denominator = try argument()
        return .divide(numerator, denominator)
    }

    private mutating func derivativeFraction(token: MathToken) throws -> MathNode? {
        guard current.isSymbol("{") else { return nil }
        let save = position
        advance()
        let isPartial = current.isCommand("partial")
        let isD = current.letter == "d" || current.isCommand("mathrm") && peekIsLetterGroup("d")
        guard isPartial || isD else { position = save; return nil }
        if current.isCommand("mathrm") { advance(); _ = try skipGroup() } else { advance() }
        var order = 1
        if current.isSymbol("^") {
            advance()
            guard case let .number(value, _) = current.kind, value == 2 || value == 1 else { position = save; return nil }
            order = Int(value); advance()
        }
        // The numerator may contain the function: \frac{\partial f}{\partial x}.
        var body: MathNode?
        if !current.isSymbol("}") {
            // “dx” alone on top would be a differential, not a derivative: give up unless a denominator follows.
            let inner = try parseExpression()
            body = inner
        }
        guard current.isSymbol("}") else { position = save; return nil }
        advance()
        guard current.isSymbol("{") else { position = save; return nil }
        advance()
        if current.isCommand("partial") || current.letter == "d" { advance() }
        else if current.isCommand("mathrm"), peekIsLetterGroup("d") { advance(); _ = try skipGroup() }
        else { position = save; return nil }
        let variable = try parsePostfixVariable()
        if current.isSymbol("^") { advance(); _ = try argument() }
        guard current.isSymbol("}") else { throw error("Write the denominator as {\\partial x}", at: token) }
        advance()
        let operand: MathNode
        if let body { operand = body } else { operand = try parseTerm() }
        return .derivative(operand, variable: variable, order: order)
    }

    /// The variable of a derivative or integral: a letter, a Greek letter, possibly decorated or indexed.
    private mutating func parsePostfixVariable() throws -> String {
        let node: MathNode
        if current.isSymbol("{") { node = try argument() } else { node = try parsePrimaryVariable() }
        switch node {
        case let .symbol(name): return name
        case let .indexed(name, index): return name + "_" + MathParser.indexName(index)
        default: throw error("Expected a variable")
        }
    }

    private mutating func parsePrimaryVariable() throws -> MathNode {
        var node = try parsePrimary()
        if current.isSymbol("_") {
            advance()
            let index = try argument()
            if case let .symbol(name) = node { node = .indexed(name, MathParser.indexList(index)) }
        }
        return node
    }

    /// Σ and Π with their limits: `\sum_{i=1}^{N}`, `\sum_i`, `\sum_{j=1}^p`.
    private mutating func bigOperator(_ name: String) throws -> MathNode {
        let token = current
        advance()
        skipIgnorable()
        var index: String?
        var lower: MathNode?, upper: MathNode?
        for _ in 0..<2 {
            if current.isSymbol("_") {
                advance()
                if current.isSymbol("{") {
                    advance()
                    let variable = try parsePrimaryVariable()
                    guard case let .symbol(v) = variable else { throw error("Expected the index of the sum") }
                    index = v
                    if current.isSymbol("=") { advance(); lower = try parseExpression() }
                    else if current.isCommand("in") { throw error("Sums over sets are not supported; write \\sum_{i=1}^{n}", at: token) }
                    guard current.isSymbol("}") else { throw error("Missing }") }
                    advance()
                } else {
                    guard case let .symbol(v) = try parsePrimary() else { throw error("Expected the index of the sum") }
                    index = v
                }
            } else if current.isSymbol("^") {
                advance()
                upper = try argument()
            }
        }
        guard let index else { throw error("Write the index of the sum: \\\(name)_{i=1}^{n}", at: token) }
        let body = try parseSumBody()
        return name == "sum" ? .sum(index: index, lower: lower, upper: upper, body: body) : .product(index: index, lower: lower, upper: upper, body: body)
    }

    /// The summand: the product that follows, as in “\sum_i x_i y_i + c”.
    private mutating func parseSumBody() throws -> MathNode {
        skipIgnorable()
        if current.isSymbol("-") { advance(); return .negate(try parseTerm()) }
        return try parseTerm()
    }

    private mutating func integral() throws -> MathNode {
        let token = current
        advance()
        var lower: MathNode?, upper: MathNode?
        for _ in 0..<2 {
            if current.isSymbol("_") { advance(); lower = try argument() }
            else if current.isSymbol("^") { advance(); upper = try argument() }
        }
        guard let lower, let upper else { throw error("Only definite integrals \\int_a^b … dx can be checked", at: token) }
        integralDepth += 1
        defer { integralDepth -= 1 }
        skipIgnorable()
        let body = try parseExpression()
        skipIgnorable()
        guard isDifferential(at: position) else { throw error("End the integral with its differential (dx)", at: token) }
        if current.letter == "d" { advance() } else { advance(); _ = try skipGroup() }
        let variable = try parsePostfixVariable()
        return .integral(lower: lower, upper: upper, variable: variable, body: body)
    }

    /// `pmatrix`, `bmatrix`, `matrix`, `vmatrix` (a determinant), and `aligned`/`split` contents are handled by lines.
    private mutating func environment() throws -> MathNode {
        let token = current
        advance()
        let kind = try letterGroup()
        guard ["pmatrix", "bmatrix", "matrix", "vmatrix", "Bmatrix", "smallmatrix", "array"].contains(kind) else {
            throw error("The \(kind) environment is not supported here", at: token)
        }
        if kind == "array", current.isSymbol("{") { _ = try skipGroup() }
        matrixDepth += 1
        defer { matrixDepth -= 1 }
        var rows: [[MathNode]] = [[]]
        while true {
            skipIgnorable()
            if current.isCommand("end") { advance(); _ = try letterGroup(); break }
            if current.isEnd { throw error("Missing \\end{\(kind)}", at: token) }
            if current.isCommand("\\") { advance(); if !rows.last!.isEmpty { rows.append([]) }; continue }
            rows[rows.count - 1].append(try parseExpression())
            skipIgnorableExceptAlignment()
            if current.isSymbol("&") { advance() }
        }
        if rows.last?.isEmpty == true { rows.removeLast() }
        guard let width = rows.first?.count, width > 0, rows.allSatisfy({ $0.count == width }) else { throw error("Every row of the matrix needs the same number of entries", at: token) }
        let matrix = MathNode.matrix(rows)
        return kind == "vmatrix" ? .function("det", [matrix]) : matrix
    }

    private mutating func skipIgnorableExceptAlignment() {
        while let name = current.commandName, Self.ignored.contains(name) { advance() }
    }

    // MARK: Indices and binders

    static func indexList(_ node: MathNode) -> [MathNode] {
        // x_{ij}: two indices written together; x_{i,j}: separated by a comma (parsed as one product here).
        if case let .multiply(a, b) = node { return indexList(a) + indexList(b) }
        return [node]
    }

    static func indexName(_ indices: [MathNode]) -> String {
        let parts = indices.map(render)
        if parts.count == 1, parts[0].count == 1 { return parts[0] }
        return "{" + parts.joined() + "}"
    }

    /// A compact text form of an index expression: “0”, “i”, “i+1”, “new”.
    static func render(_ node: MathNode) -> String {
        switch node {
        case let .number(v): v == v.rounded() ? String(Int(v)) : String(v)
        case let .symbol(name): name
        case let .add(a, b): render(a) + "+" + render(b)
        case let .subtract(a, b): render(a) + "-" + render(b)
        case let .multiply(a, b): render(a) + render(b)
        case let .indexed(name, index): name + "_" + indexName(index)
        default: "?"
        }
    }

    /// An indexed symbol whose indices name no bound variable is a symbol of its own: β_0, x_{new}.
    static func resolveBinders(_ node: MathNode, bound: Set<String>) -> MathNode {
        func r(_ n: MathNode) -> MathNode { resolveBinders(n, bound: bound) }
        switch node {
        case let .indexed(name, indices):
            let uses = indices.contains { !symbols(in: $0).isDisjoint(with: bound) }
            if uses { return .indexed(name, indices.map(r)) }
            return .symbol(name + "_" + indexName(indices))
        case let .sum(index, lower, upper, body):
            return .sum(index: index, lower: lower.map(r), upper: upper.map(r), body: resolveBinders(body, bound: bound.union([index])))
        case let .product(index, lower, upper, body):
            return .product(index: index, lower: lower.map(r), upper: upper.map(r), body: resolveBinders(body, bound: bound.union([index])))
        case let .integral(lower, upper, variable, body):
            return .integral(lower: r(lower), upper: r(upper), variable: variable, body: resolveBinders(body, bound: bound))
        case let .add(a, b): return .add(r(a), r(b))
        case let .subtract(a, b): return .subtract(r(a), r(b))
        case let .multiply(a, b): return .multiply(r(a), r(b))
        case let .divide(a, b): return .divide(r(a), r(b))
        case let .negate(a): return .negate(r(a))
        case let .power(a, b): return .power(r(a), r(b))
        case let .transpose(a): return .transpose(r(a))
        case let .inverse(a): return .inverse(r(a))
        case let .function(name, args): return .function(name, args.map(r))
        case let .apply(name, args): return .apply(name, args.map(r))
        case let .norm(a, p): return .norm(r(a), p)
        case let .absolute(a): return .absolute(r(a))
        case let .factorial(a): return .factorial(r(a))
        case let .binomial(a, b): return .binomial(r(a), r(b))
        case let .derivative(body, variable, order): return .derivative(r(body), variable: variable, order: order)
        case let .matrix(rows): return .matrix(rows.map { $0.map(r) })
        case let .identity(size): return .identity(size.map(r))
        case let .ones(size): return .ones(size.map(r))
        case let .at(body, variable, value): return .at(resolveBinders(body, bound: bound.union([variable])), variable: variable, value: r(value))
        case .number, .symbol, .unsupported: return node
        }
    }

    /// The symbols an expression mentions (free or bound), by name.
    public static func symbols(in node: MathNode) -> Set<String> {
        var found: Set<String> = []
        func visit(_ n: MathNode) {
            switch n {
            case let .symbol(name): found.insert(name)
            case let .indexed(name, indices): found.insert(name); indices.forEach(visit)
            case let .add(a, b), let .subtract(a, b), let .multiply(a, b), let .divide(a, b), let .power(a, b), let .binomial(a, b): visit(a); visit(b)
            case let .negate(a), let .transpose(a), let .inverse(a), let .absolute(a), let .factorial(a), let .norm(a, _): visit(a)
            case let .function(_, args): args.forEach(visit)
            case let .apply(name, args): found.insert(name); args.forEach(visit)
            case let .sum(index, lower, upper, body), let .product(index, lower, upper, body):
                found.insert(index); lower.map(visit); upper.map(visit); visit(body)
            case let .derivative(body, variable, _): found.insert(variable); visit(body)
            case let .integral(lower, upper, variable, body): found.insert(variable); visit(lower); visit(upper); visit(body)
            case let .matrix(rows): rows.joined().forEach(visit)
            case let .identity(size), let .ones(size): size.map(visit)
            case let .at(body, variable, value): found.insert(variable); visit(body); visit(value)
            case .number, .unsupported: break
            }
        }
        visit(node)
        return found
    }
}
