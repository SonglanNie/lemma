import Foundation

/// A derivation the reader works through beside the page, one step per line, checked as it is typed.
public struct Derivation: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    /// One step per line, in LaTeX (or the Unicode a PDF or chat answer gives).
    public var source: String
    /// The passage it works on, when it started from the page.
    public var origin: LabSource?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String, source: String = "", origin: LabSource? = nil) {
        self.id = id; self.title = title; self.source = source; self.origin = origin
        createdAt = .now; updatedAt = .now
    }

    private enum CodingKeys: String, CodingKey { case id, title, source, origin, createdAt, updatedAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Derivation"
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        origin = try c.decodeIfPresent(LabSource.self, forKey: .origin)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

/// What Lemma found on one step.
public struct DerivationLineReport: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        /// The step holds on every random draw (or no draw contradicts an inequality).
        case holds
        /// A draw contradicts the step.
        case fails
        /// An equation taken as given: a hypothesis, or an expression set to zero.
        case given
        case definition
        case declaration
        case comment
        case blank
        /// Read, but not checkable by drawing numbers (an expectation, a limit).
        case unchecked
        /// Not readable: the message says where.
        case error

        public var isProblem: Bool { self == .fails || self == .error }
    }

    /// The source line (0-based) and the part of it this report covers (UTF-16, in the whole source).
    public var line: Int
    public var range: NSRange
    public var status: Status
    /// One line for the gutter's tooltip and the Problems panel: “Holds on 8 random draws”, “Off by a factor of 2”.
    public var message: String
    /// The counterexample, when there is one: values drawn and both sides.
    public var detail: String?
    /// Where to underline (UTF-16, in the whole source).
    public var errorRange: NSRange?
}

public struct DerivationSymbol: Equatable, Sendable, Identifiable {
    public enum Origin: String, Equatable, Sendable { case declared, inferred, defined, size }
    public var id: String { name }
    public var name: String
    /// “vector of length N”, “a number”, “defined on line 2”.
    public var detail: String
    public var origin: Origin
    public var type: MathType?
}

public struct DerivationReport: Equatable, Sendable {
    public var lines: [DerivationLineReport] = []
    public var symbols: [DerivationSymbol] = []
    public var holds: Int { lines.filter { $0.status == .holds }.count }
    public var fails: Int { lines.filter { $0.status.isProblem }.count }
    public var unchecked: Int { lines.filter { $0.status == .unchecked }.count }
    public init() {}

    /// The worst status of each source line, for the gutter.
    public func status(ofLine line: Int) -> DerivationLineReport.Status? {
        let reports = lines.filter { $0.line == line }
        let order: [DerivationLineReport.Status] = [.error, .fails, .unchecked, .holds, .given, .definition, .declaration, .comment, .blank]
        return order.first { status in reports.contains { $0.status == status } }
    }
}

/// Splits, reads and checks a derivation.
public enum DerivationChecker {
    /// One step of the source: a line, or a part of an aligned line separated by “\\”.
    struct Segment {
        var line: Int
        var text: String
        /// Where `text` starts in the whole source (UTF-16).
        var offset: Int
        var length: Int
    }

    enum Kind {
        case blank, comment
        case declaration(String)
        /// `offset` is where the parsed text starts in the line, when positions in it match the line (no Unicode was rewritten).
        case math(MathChain, explicitDefinition: Bool, given: Bool, offset: Int?)
        case error(MathParseError)
    }

    // MARK: Segments

    static func segments(_ source: String) -> [Segment] {
        var result: [Segment] = []
        var offset = 0
        for (number, line) in source.components(separatedBy: "\n").enumerated() {
            let ns = line as NSString
            // “\\” ends a row of an aligned display; split there, outside braces.
            var start = 0, depth = 0, index = 0
            var parts: [(Int, Int)] = []
            while index < ns.length {
                let c = ns.character(at: index)
                if c == 123 { depth += 1 } else if c == 125 { depth = max(0, depth - 1) }
                if c == 92, index + 1 < ns.length, ns.character(at: index + 1) == 92, depth == 0 {
                    parts.append((start, index - start)); index += 2; start = index; continue
                }
                index += 1
            }
            parts.append((start, ns.length - start))
            for (s, l) in parts {
                result.append(Segment(line: number, text: ns.substring(with: NSRange(location: s, length: l)), offset: offset + s, length: l))
            }
            offset += ns.length + 1
        }
        return result
    }

    /// Display wrappers that carry no step: `$$`, `\[`, `\begin{align*}`…
    static let wrappers = ["$$", "\\[", "\\]", "\\(", "\\)"]
    static let environments = ["align", "align*", "aligned", "equation", "equation*", "split", "gather", "gather*", "eqnarray", "eqnarray*", "multline", "multline*", "alignat", "alignat*", "flalign", "flalign*", "displaymath", "math"]

    /// Blanks display wrappers, keeping every other character where it was (positions stay valid for diagnostics).
    public static func strip(_ text: String) -> String {
        var t = text
        func blank(_ piece: String) { t = t.replacingOccurrences(of: piece, with: String(repeating: " ", count: piece.count)) }
        for env in environments { blank("\\begin{\(env)}"); blank("\\end{\(env)}") }
        for wrapper in wrappers { blank(wrapper) }
        // Inline $…$ around a whole line.
        let trimmed = t.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("$"), trimmed.hasSuffix("$"), trimmed.count >= 2 { t = t.replacingOccurrences(of: "$", with: " ") }
        return t
    }

    /// Words that introduce a declaration or a definition: “Let X ∈ ℝ^{N×p}”, “Assume λ > 0”, “where S = XᵀX”.
    static let declarationWords = ["let", "assume", "assuming", "suppose", "given", "where", "with", "for", "define", "set", "take", "fix", "declare"]

    static func classify(_ raw: String, names: Set<String>, functions: Set<String> = MathParser.commonFunctions) -> Kind {
        let stripped = strip(raw)
        var offset = stripped.prefix { $0 == " " || $0 == "\t" }.utf16.count
        var text = stripped.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return .blank }
        if text.hasPrefix("%") || text.hasPrefix("//") || text.hasPrefix("#") { return .comment }
        var introduced = false
        // “Let …”, “\text{Assume } …”.
        search: for word in declarationWords {
            for form in [word + " ", "\\text{" + word + " }", "\\text{" + word + "}", "\\text{" + word + "} ", "\\mathrm{" + word + "}~",
                         "\\text{" + word.capitalized + " }", "\\text{" + word.capitalized + "}", word.capitalized + " "] where text.hasPrefix(form) {
                let rest = String(text.dropFirst(form.count))
                offset += form.utf16.count + rest.prefix { $0 == " " }.utf16.count
                text = rest.trimmingCharacters(in: .whitespaces); introduced = true
                break search
            }
        }
        let latex = MathLexer.latex(text)
        if isDeclaration(latex) { return .declaration(latex) }
        if isProse(text) { return .comment }
        let exact = latex == text
        do {
            var chain = try MathParser.chain(latex, names: names, functions: functions)
            let explicitDefinition = chain.relations.first == .define && chain.leading == nil
            if chain.leading == .define { chain.leading = .equal }
            return .math(chain, explicitDefinition: explicitDefinition || (introduced && chain.relations.first == .equal && chain.leading == nil),
                         given: introduced, offset: exact ? offset : nil)
        } catch let error as MathParseError {
            var adjusted = error
            adjusted.range = exact ? (error.range.lowerBound + offset)..<(error.range.upperBound + offset) : 0..<raw.utf16.count
            return .error(adjusted)
        } catch {
            return .error(MathParseError(error.localizedDescription, range: 0..<raw.utf16.count))
        }
    }

    /// “x ∈ ℝ^n”, “λ > 0”, “0 < p < 1”, “A ≻ 0”, “N > p”: a line that says what symbols are rather than a step.
    static func isDeclaration(_ latex: String) -> Bool {
        if latex.contains("\\in ") || latex.contains("\\in\\") || latex.hasSuffix("\\in") || latex.contains("\\succ") { return true }
        // One symbol compared with numbers (“λ > 0”, “0 < p < 1”): an assumption, not a step to check.
        guard let chain = try? MathParser.chain(latex), chain.leading == nil, !chain.relations.isEmpty,
              chain.relations.allSatisfy({ $0.isOrder || $0 == .notEqual }) else { return false }
        var symbols = 0
        for term in chain.terms {
            switch term {
            case .number, .negate(.number): continue
            case .symbol, .power(.symbol, .number): symbols += 1
            default: return false
            }
        }
        return symbols == 1
    }

    private static let functionWords: Set<String> = ["exp", "log", "sin", "cos", "tan", "max", "min", "det", "diag", "sqrt", "sinh", "cosh", "tanh"]

    /// A line of words (“Taking derivatives with respect to β:”) rather than mathematics: three or more lower-case words.
    static func isProse(_ text: String) -> Bool {
        if text.contains("\\") && !text.contains("\\text") { return false }
        let words = text.split(whereSeparator: { " ,:;.()".contains($0) })
        let english = words.filter { $0.count >= 3 && $0.allSatisfy { $0.isASCII && $0.isLowercase && $0.isLetter } && !functionWords.contains(String($0)) }
        return english.count >= 3
    }

    // MARK: Declarations

    /// Reads “X \in \mathbb{R}^{N\times p}”, “x, y \in \mathbb{R}^n”, “\lambda > 0”, “0 < p < 1”, “A \succ 0”, “N > p”.
    static func declare(_ latex: String, into context: inout MathContext) -> (summary: String, error: String?) {
        var described: [String] = []
        var pending: [String] = []
        for clause in topLevelSplit(latex) {
            let part = clause.trimmingCharacters(in: .whitespaces)
            if part.isEmpty { continue }
            if let range = part.range(of: "\\in") {
                let left = String(part[..<range.lowerBound])
                let right = String(part[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let symbols = pending + topLevelSplit(left).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                pending = []
                guard let type = setType(right) else { return (described.joined(separator: " · "), "Lemma reads ℝ, ℝⁿ, ℝ^{n×p}, ℕ, [a, b] and 𝕊ⁿ here") }
                for symbol in symbols {
                    guard let node = try? MathParser.expression(symbol) else { return (described.joined(separator: " · "), "“\(symbol)” is not a symbol") }
                    switch node {
                    case let .symbol(name):
                        // “x_i ∈ ℝ^p”: one vector for each value of an index.
                        if let underscore = name.lastIndex(of: "_"), ["i", "j", "k", "l", "m", "n", "t"].contains(String(name[name.index(after: underscore)...])) {
                            let base = String(name[..<underscore])
                            context.families[base] = type; described.append("\(MathNames.display(name)): \(type.description) for each \(name[name.index(after: underscore)...])")
                        } else {
                            context.declared[name] = type; described.append("\(MathNames.display(name)): \(type.description)")
                        }
                    default: return (described.joined(separator: " · "), "“\(symbol)” is not a symbol")
                    }
                }
                continue
            }
            if part.contains("\\succ") {
                let pd = !part.contains("\\succeq")
                let name = part.components(separatedBy: "\\succ").first?.trimmingCharacters(in: .whitespaces) ?? ""
                guard case let .symbol(symbol)? = try? MathParser.expression(name) else { return (described.joined(separator: " · "), "“\(name)” is not a symbol") }
                let structure: MathMatrixStructure = pd ? .positiveDefinite : .positiveSemidefinite
                if case let .matrix(r, c, _)? = context.declared[symbol] { context.declared[symbol] = .matrix(r, c, structure) }
                else { let n = MathDim.param("#\(symbol).n"); context.declared[symbol] = .matrix(n, n, structure) }
                described.append("\(MathNames.display(symbol)) \(pd ? "≻" : "⪰") 0")
                continue
            }
            if let chain = try? MathParser.chain(part), chain.leading == nil, !chain.relations.isEmpty {
                if let text = constrain(chain, into: &context) { described.append(text); continue }
                return (described.joined(separator: " · "), "Lemma reads assumptions such as λ > 0, 0 < p < 1 or N > p")
            }
            // A bare symbol before “x, y ∈ …”.
            pending.append(part)
        }
        if !pending.isEmpty { return (described.joined(separator: " · "), "Say what \(pending.joined(separator: ", ")) is: “\(pending[0]) \\in \\mathbb{R}^n”") }
        return (described.joined(separator: " · "), nil)
    }

    /// Splits at commas, semicolons and \quad that are not inside braces, brackets or parentheses.
    static func topLevelSplit(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var characters = Array(text)[...]
        while let c = characters.first {
            characters = characters.dropFirst()
            if c == "{" || c == "(" || c == "[" { depth += 1 }
            if c == "}" || c == ")" || c == "]" { depth = max(0, depth - 1) }
            if depth == 0, c == "," || c == ";" { parts.append(current); current = ""; continue }
            if depth == 0, c == "\\", String(characters.prefix(5)) == "quad " || String(characters.prefix(4)) == "quad" && characters.count == 4 {
                parts.append(current); current = ""; characters = characters.dropFirst(4); continue
            }
            current.append(c)
        }
        parts.append(current)
        // Interval brackets “[0, 1]” contain a comma at depth 1, so they survive; “(0, 1)” likewise.
        return parts
    }

    /// The type a set gives its elements.
    static func setType(_ set: String) -> MathType? {
        var s = set.replacingOccurrences(of: " ", with: "")
        if s.hasSuffix(".") { s.removeLast() }
        func dims(_ exponent: String) -> (MathDim, MathDim)? {
            var e = exponent
            if e.hasPrefix("{"), e.hasSuffix("}") { e = String(e.dropFirst().dropLast()) }
            let pieces = e.replacingOccurrences(of: "\\times", with: "×").replacingOccurrences(of: "\\cdot", with: "×")
                .split(separator: "×").map(String.init)
            let parsed = pieces.compactMap { (try? MathParser.expression($0)).flatMap(MathDim.from) }
            guard parsed.count == pieces.count else { return nil }
            if parsed.count == 1 { return (parsed[0], .constant(1)) }
            if parsed.count == 2 { return (parsed[0], parsed[1]) }
            return nil
        }
        func exponent(after prefix: String) -> String? {
            guard s.hasPrefix(prefix) else { return nil }
            var rest = String(s.dropFirst(prefix.count))
            // Subscripts such as ℝ_+ or 𝕊^n_{++} may come before or after the exponent.
            rest = rest.replacingOccurrences(of: "_{++}", with: "").replacingOccurrences(of: "_{+}", with: "").replacingOccurrences(of: "_+", with: "")
                .replacingOccurrences(of: "_{\\geq0}", with: "").replacingOccurrences(of: "_{\\ge0}", with: "").replacingOccurrences(of: "_{>0}", with: "")
            guard rest.hasPrefix("^") else { return rest.isEmpty ? "" : nil }
            return String(rest.dropFirst())
        }
        for real in ["\\mathbb{R}", "\\mathbf{R}", "\\Bbb{R}", "\\mathbb R", "\\R"] {
            guard let e = exponent(after: real) else { continue }
            let positive = s.contains("_{++}") || s.contains("_{>0}") || s.contains("_{+}") || s.contains("_+")
            let nonnegative = s.contains("\\geq0") || s.contains("\\ge0")
            if e.isEmpty { return .scalar(positive ? .positive : nonnegative ? .nonnegative : .real) }
            guard let (r, c) = dims(e) else { return nil }
            return .matrix(r, c, .general)
        }
        for natural in ["\\mathbb{N}", "\\mathbb{Z}_{+}", "\\mathbb{Z}_+", "\\mathbb{Z}", "\\mathbb{N}^*", "\\mathbb{N}_{>0}"] where s == natural {
            return .scalar(.integer)
        }
        for symmetric in ["\\mathbb{S}", "\\mathcal{S}"] {
            guard let e = exponent(after: symmetric), !e.isEmpty else { continue }
            var inner = e
            if inner.hasPrefix("{"), inner.hasSuffix("}") { inner = String(inner.dropFirst().dropLast()) }
            guard let n = (try? MathParser.expression(inner)).flatMap(MathDim.from) else { return nil }
            let structure: MathMatrixStructure = s.contains("++") ? .positiveDefinite : s.contains("_+") || s.contains("_{+}") ? .positiveSemidefinite : .symmetric
            return .matrix(n, n, structure)
        }
        // Intervals: [a, b], (a, b), (0, \infty).
        if let first = s.first, let last = s.last, "[(".contains(first), "])".contains(last) {
            let inner = s.dropFirst().dropLast().split(separator: ",", maxSplits: 1).map(String.init)
            guard inner.count == 2 else { return nil }
            let a = Double(inner[0].replacingOccurrences(of: "-\\infty", with: "-inf")) ?? (inner[0] == "-\\infty" ? -.infinity : nil)
            let b = Double(inner[1]) ?? (inner[1] == "\\infty" || inner[1] == "+\\infty" ? .infinity : nil)
            guard let a, let b else { return nil }
            if a == 0, b.isInfinite { return .scalar(first == "(" ? .positive : .nonnegative) }
            if a.isInfinite || b.isInfinite { return .scalar(.real) }
            let pad = first == "(" ? 1e-3 * (b - a) : 0
            return .scalar(.interval(a + pad, b - (last == ")" ? 1e-3 * (b - a) : 0)))
        }
        return nil
    }

    /// “λ > 0”, “0 < p < 1”, “σ^2 > 0”, “N > p”.
    static func constrain(_ chain: MathChain, into context: inout MathContext) -> String? {
        func symbolName(_ node: MathNode) -> String? {
            switch node {
            case let .symbol(name): return name
            case let .power(.symbol(name), .number): return name
            default: return nil
            }
        }
        func number(_ node: MathNode) -> Double? {
            switch node {
            case let .number(v): return v
            case let .negate(.number(v)): return -v
            default: return nil
            }
        }
        // Two sizes: N > p (single Latin letters; Greek letters are numbers).
        if chain.terms.count == 2, let a = symbolName(chain.terms[0]), let b = symbolName(chain.terms[1]),
           a.count == 1, b.count == 1, a.first!.isASCII, b.first!.isASCII {
            context.sizeConstraints.append(MathSizeConstraint(left: .param(a), relation: chain.relations[0], right: .param(b)))
            return "\(MathNames.display(a)) \(chain.relations[0].rawValue) \(MathNames.display(b))"
        }
        var low = -Double.infinity, high = Double.infinity, strictLow = false
        var name: String?
        for (index, relation) in chain.relations.enumerated() {
            let a = chain.terms[index], b = chain.terms[index + 1]
            let (left, rel, right): (MathNode, MathRelation, MathNode) = symbolName(a) != nil ? (a, relation, b) : (b, relation.flipped, a)
            guard let symbol = symbolName(left), let bound = number(right) else { return nil }
            if name != nil, name != symbol { return nil }
            name = symbol
            switch rel {
            case .greater: low = max(low, bound); strictLow = true
            case .greaterEqual: low = max(low, bound)
            case .less, .lessEqual: high = min(high, bound)
            case .notEqual: break
            default: return nil
            }
        }
        guard let name else { return nil }
        let domain: MathScalarDomain
        if low == 0, high.isInfinite { domain = strictLow ? .positive : .nonnegative }
        else if low.isFinite, high.isFinite { let pad = 1e-3 * (high - low); domain = .interval(low + pad, high - pad) }
        else if low.isFinite { domain = low >= 0 ? .positive : .real }
        else { domain = .real }
        if case .matrix? = context.declared[name] { return nil }
        context.declared[name] = .scalar(domain)
        return "\(MathNames.display(name)): \(MathType.scalar(domain).description)"
    }

    // MARK: Checking

    struct Step {
        var segment: Segment
        var left: MathNode
        var right: MathNode
        var relation: MathRelation
        /// Indices of the two sides in the typed expression list.
        var leftIndex: Int
        var rightIndex: Int
        var leftRange: Range<Int>?
        var rightRange: Range<Int>?
        var continuesPrevious: Bool
    }

    /// Checks every step of a derivation. Runs in a few milliseconds for a page of algebra.
    public static func check(_ source: String) -> DerivationReport {
        var report = DerivationReport()
        let segments = segments(source)
        // Names defined in the text are read whole (“RSS(β)”).
        var names = MathParser.commonNames
        for segment in segments {
            let latex = MathLexer.latex(strip(segment.text))
            // \text{NAME}, \mathrm{NAME}, or a bare name of three letters or more called like a function (“RSS(β)”).
            for pattern in [#"\\(?:text|mathrm|operatorname)\{([A-Za-z]{2,})\}"#, #"(?<![A-Za-z\\])([A-Za-z]{3,})\s*\("#] {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                for match in regex.matches(in: latex, range: NSRange(location: 0, length: (latex as NSString).length)) {
                    let name = (latex as NSString).substring(with: match.range(at: 1))
                    if !declarationWords.contains(name.lowercased()) { names.insert(name) }
                }
            }
        }
        // Letters defined as functions (“\\sigma(x) := …”, “φ(t) = …”) are read as calls.
        var functions = MathParser.commonFunctions
        for segment in segments {
            let latex = MathLexer.latex(strip(segment.text))
            guard let regex = try? NSRegularExpression(pattern: #"^\s*(?:[Ll]et\s+|[Dd]efine\s+)?(\\[A-Za-z]+|[A-Za-z])\s*\(\s*((?:\\[A-Za-z]+|[A-Za-z])(?:\s*,\s*(?:\\[A-Za-z]+|[A-Za-z]))*)\s*\)\s*(:=|\\coloneqq|=)"#),
                  let match = regex.firstMatch(in: latex, range: NSRange(location: 0, length: (latex as NSString).length)) else { continue }
            var head = (latex as NSString).substring(with: match.range(at: 1))
            let relation = (latex as NSString).substring(with: match.range(at: 3))
            let greek = head.hasPrefix("\\")
            if greek { head = MathNames.greek[String(head.dropFirst())] ?? head }
            if relation != "=" || greek { functions.insert(head) }
        }
        var kinds = segments.map { classify($0.text, names: names, functions: functions) }
        var context = MathContext()
        // Declarations apply to the whole derivation, wherever they are written.
        var declarationReports: [Int: (String, String?)] = [:]
        for (index, kind) in kinds.enumerated() { if case let .declaration(latex) = kind { declarationReports[index] = declare(latex, into: &context) } }
        // “N > p” between two sizes of the declarations constrains the sizes drawn.
        var sizes = Set<String>()
        for type in Array(context.declared.values) + Array(context.families.values) { if case let .matrix(r, c, _) = type { sizes.formUnion(r.params); sizes.formUnion(c.params) } }
        for (index, kind) in kinds.enumerated() {
            guard case let .math(chain, _, _, _) = kind, chain.leading == nil, chain.relations.count == 1, chain.relations[0].isOrder,
                  case let .symbol(a) = chain.terms[0], case let .symbol(b) = chain.terms[1], sizes.contains(a), sizes.contains(b) else { continue }
            context.sizeConstraints.append(MathSizeConstraint(left: .param(a), relation: chain.relations[0], right: .param(b)))
            kinds[index] = .declaration("")
            declarationReports[index] = ("\(MathNames.display(a)) \(chain.relations[0].rawValue) \(MathNames.display(b))", nil)
        }

        // Definitions and steps, in order: a definition applies from its line on.
        var expressions: [MathNode] = []
        var relations: [(Int, Int)] = []
        var steps: [Int: [Step]] = [:]
        var notes: [Int: DerivationLineReport] = [:]
        var previous: (node: MathNode, index: Int)?
        var seen = Set<String>()
        var definitionLines: [String: Int] = [:]
        /// A definition's name and body by segment, to see whether a defined β̂ solves an earlier equation for β.
        var definitionBodies: [Int: (name: String, body: MathNode)] = [:]
        /// A lone expression's index, so a size mismatch inside it is still reported.
        var loneExpressions: [Int: Int] = [:]

        func add(_ node: MathNode) throws -> Int {
            expressions.append(try MathExpansion.expand(node, context.definitions))
            return expressions.count - 1
        }

        for (index, kind) in kinds.enumerated() {
            let segment = segments[index]
            let range = NSRange(location: segment.offset, length: segment.length)
            func note(_ status: DerivationLineReport.Status, _ message: String, error: NSRange? = nil) {
                notes[index] = DerivationLineReport(line: segment.line, range: range, status: status, message: message, detail: nil, errorRange: error)
            }
            switch kind {
            case .blank: note(.blank, "")
            case .comment: note(.comment, "")
            case .declaration:
                let (summary, error) = declarationReports[index] ?? ("", nil)
                if let error { note(.error, error, error: range) } else { note(.declaration, summary) }
            case let .error(parseError):
                let start = min(parseError.range.lowerBound, segment.length)
                note(.error, parseError.message, error: NSRange(location: segment.offset + start, length: max(1, min(parseError.range.count, segment.length - start))))
                previous = nil
            case let .math(chain, explicitDefinition, given, offset):
                // Positions of each term in the whole source, when they can be trusted.
                var ranges: [Range<Int>?] = []
                for r in chain.termRanges {
                    if let offset { ranges.append((r.lowerBound + offset + segment.offset)..<(r.upperBound + offset + segment.offset)) } else { ranges.append(nil) }
                }
                do {
                    let terms = chain.terms
                    var lineSteps: [Step] = []
                    var start = 0
                    var definition: String?
                    // A definition: a new name on the left (“RSS(β) = …”, “S := XᵀX”, “Let S = XᵀX”).
                    if chain.leading == nil, let first = chain.relations.first, first == .equal || first == .define,
                       let (name, parameters) = definitionHead(terms[0]), context.declared[name] == nil, name != "I",
                       !isDerivativeOfKnownFunction(name, context: context, functions: functions),
                       explicitDefinition || (!seen.contains(name) && context.definitions[name] == nil && !MathExpansion.freeSymbols(terms[1]).contains(name)) {
                        let body = try MathExpansion.expand(terms[1], context.definitions)
                        context.definitions[name] = MathDefinition(parameters: parameters, body: body, line: segment.line)
                        definitionLines[name] = segment.line
                        if parameters.isEmpty { definitionBodies[index] = (name, body) }
                        let shown = parameters.isEmpty ? MathNames.display(name) : "\(MathNames.display(name))(\(parameters.map(MathNames.display).joined(separator: ", ")))"
                        definition = "Defines \(shown)"
                        start = 1
                    }
                    for term in terms { seen.formUnion(MathParser.symbols(in: term)) }
                    var leftIndex: Int
                    var leftNode: MathNode
                    if let leading = chain.leading {
                        guard let previous else { note(.error, "Nothing to continue: this step starts with “\(leading.rawValue)”", error: range); continue }
                        let rightIndex = try add(terms[0])
                        relations.append((previous.index, rightIndex))
                        lineSteps.append(Step(segment: segment, left: expressions[previous.index], right: expressions[rightIndex], relation: leading,
                                              leftIndex: previous.index, rightIndex: rightIndex, leftRange: nil, rightRange: ranges[0], continuesPrevious: true))
                        leftIndex = rightIndex; leftNode = terms[0]
                    } else {
                        leftIndex = try add(terms[start]); leftNode = terms[start]
                    }
                    for k in start..<chain.relations.count {
                        let rightIndex = try add(terms[k + 1])
                        relations.append((leftIndex, rightIndex))
                        let relation: MathRelation = chain.relations[k] == .define ? .equal : chain.relations[k]
                        let step = Step(segment: segment, left: expressions[leftIndex], right: expressions[rightIndex], relation: relation,
                                        leftIndex: leftIndex, rightIndex: rightIndex, leftRange: ranges[k], rightRange: ranges[k + 1], continuesPrevious: false)
                        lineSteps.append(step)
                        leftIndex = rightIndex; leftNode = terms[k + 1]
                    }
                    previous = (leftNode, leftIndex)
                    if !lineSteps.isEmpty { steps[index] = lineSteps } else { loneExpressions[index] = leftIndex }
                    if let definition { note(.definition, definition) }
                    else if lineSteps.isEmpty { note(.comment, "") }
                    else if given { note(.given, "Given") }
                } catch {
                    note(.error, (error as? MathEvalError).map(describe) ?? error.localizedDescription, error: range)
                    previous = nil
                }
            }
        }

        let typing = MathTyping.infer(expressions: expressions, relations: relations, context: context)

        // Equations in force (given or derived), most recent last: what later equations may follow from.
        var conditions: [Condition] = []
        var firstStep = true
        for index in kinds.indices {
            let segment = segments[index]
            let range = NSRange(location: segment.offset, length: segment.length)
            guard let lineSteps = steps[index] else {
                guard var note = notes[index] else { continue }
                if let lone = loneExpressions[index], let issue = typing.issues[lone] {
                    note = DerivationLineReport(line: segment.line, range: range, status: .fails, message: issue, detail: nil, errorRange: range)
                }
                // “β̂ = (XᵀX)⁻¹Xᵀy” after an equation in β: does the defined value solve it?
                if note.status == .definition, let (name, body) = definitionBodies[index], let condition = conditions.last,
                   let base = name.unicodeScalars.first.map({ String($0) }), base != name,
                   MathExpansion.freeSymbols(condition.left).union(MathExpansion.freeSymbols(condition.right)).contains(base) {
                    let left = MathExpansion.substitute(condition.left, [base: body]), right = MathExpansion.substitute(condition.right, [base: body])
                    let step = Step(segment: segment, left: left, right: right, relation: .equal, leftIndex: -1, rightIndex: -1, leftRange: nil, rightRange: nil, continuesPrevious: false)
                    let checked = checkStep(step, typing: typing, conditions: [], first: false, segment: segment, range: range)
                    let shown = MathNames.display(name), variable = MathNames.display(base)
                    if checked.report.status == .holds {
                        note.status = .holds
                        note.message = "Defines \(shown), which solves line \(condition.line + 1) for \(variable)"
                    } else if checked.report.status == .fails {
                        note.status = .fails
                        note.message = "\(shown) does not solve line \(condition.line + 1) for \(variable)"
                        note.detail = checked.report.detail
                        note.errorRange = range
                    }
                }
                report.lines.append(note)
                continue
            }
            let lineNote = notes[index]
            var worst: DerivationLineReport?
            for step in lineSteps {
                var outcome: DerivationLineReport
                if let issue = typing.issues[step.rightIndex] ?? typing.issues[step.leftIndex] {
                    outcome = DerivationLineReport(line: segment.line, range: range, status: .fails, message: issue, detail: nil, errorRange: errorRange(step, segment))
                } else if lineNote?.status == .given {
                    conditions.append(Condition(left: step.left, right: step.right, line: segment.line))
                    outcome = DerivationLineReport(line: segment.line, range: range, status: .given, message: "Given")
                } else {
                    let checked = checkStep(step, typing: typing, conditions: conditions, first: firstStep && !step.continuesPrevious, segment: segment, range: range)
                    outcome = checked.report
                    if checked.isCondition { conditions.append(Condition(left: step.left, right: step.right, line: segment.line)) }
                }
                if worst == nil || rank(outcome.status) > rank(worst!.status) { worst = outcome }
            }
            firstStep = false
            if var worst {
                if lineNote?.status == .definition, worst.status == .holds { worst.message = (lineNote?.message ?? "") + " · " + worst.message }
                report.lines.append(worst)
            }
        }

        // The symbols strip: what each symbol is, and how Lemma knows. Sizes Lemma inferred get letters of their own.
        var symbols: [DerivationSymbol] = []
        let taken = Set(typing.types.keys).union(typing.sizeNames)
        var letters = ["n", "m", "k", "q", "r", "s", "d", "l"].filter { !taken.contains($0) }[...]
        var freeNames: [String: String] = [:]
        func rename(_ dim: MathDim) -> MathDim {
            switch typing.solver.normalize(dim) {
            case let .param(name) where name.hasPrefix("#"):
                if let known = freeNames[name] { return .param(known) }
                let letter = letters.popFirst() ?? "n"
                freeNames[name] = letter
                return .param(letter)
            case let .sum(a, b): return .sum(rename(a), rename(b))
            case let .difference(a, b): return .difference(rename(a), rename(b))
            case let .product(a, b): return .product(rename(a), rename(b))
            case let other: return other
            }
        }
        func shown(_ type: MathType) -> MathType {
            if case let .matrix(r, c, structure) = type { return .matrix(rename(r), rename(c), structure) }
            return type
        }
        for (name, type) in typing.types.sorted(by: { $0.key < $1.key }) where context.definitions[name] == nil {
            let display = shown(type)
            symbols.append(DerivationSymbol(name: name, detail: display.description, origin: context.declared[name] != nil ? .declared : .inferred, type: display))
        }
        for name in typing.sizeNames.sorted() where typing.types[name] == nil {
            symbols.append(DerivationSymbol(name: name, detail: "a size", origin: .size, type: nil))
        }
        for (name, type) in context.families.sorted(by: { $0.key < $1.key }) {
            symbols.append(DerivationSymbol(name: name + "_i", detail: type.description + " for each i", origin: .declared, type: type))
        }
        for (name, line) in definitionLines.sorted(by: { $0.value < $1.value }) {
            symbols.append(DerivationSymbol(name: name, detail: "defined on line \(line + 1)", origin: .defined, type: nil))
        }
        report.symbols = symbols
        return report
    }

    struct Condition {
        var left: MathNode
        var right: MathNode
        var line: Int
    }

    public static func rank(_ status: DerivationLineReport.Status) -> Int {
        switch status {
        case .error: 6
        case .fails: 5
        case .unchecked: 4
        case .holds: 3
        case .given: 2
        case .definition: 1
        default: 0
        }
    }

    /// σ′ when σ is defined or written as a function: its derivative, never a new name.
    static func isDerivativeOfKnownFunction(_ name: String, context: MathContext, functions: Set<String>) -> Bool {
        guard name.hasSuffix("′") else { return false }
        let base = String(name.drop(while: { _ in false }).reversed().drop(while: { $0 == "′" }).reversed())
        return context.definitions[base] != nil || functions.contains(base)
    }

    /// “f(x)”, “RSS(β)”, “β̂”, “S”: a name being defined, with its parameters.
    static func definitionHead(_ node: MathNode) -> (String, [String])? {
        switch node {
        case let .symbol(name): return (name, [])
        case let .apply(name, args):
            var parameters: [String] = []
            for arg in args { guard case let .symbol(p) = arg else { return nil }; parameters.append(p) }
            return (name, parameters)
        default: return nil
        }
    }

    static func errorRange(_ step: Step, _ segment: Segment) -> NSRange {
        if let range = step.rightRange { return NSRange(location: range.lowerBound, length: max(1, range.count)) }
        return NSRange(location: segment.offset, length: segment.length)
    }

    static func describe(_ error: MathEvalError) -> String {
        switch error {
        case let .unsupported(what): "Not checkable: \(what)"
        case let .shape(what): what
        case let .domain(what): "Undefined: \(what)"
        case let .singular(what): "Not invertible: \(what)"
        }
    }

    // MARK: One step

    static let identityTrials = 8
    static let orderTrials = 120

    static func tolerance(for nodes: [MathNode]) -> Double {
        var order = 0, integral = false
        for node in nodes { let c = MathExpansion.containsCalculus(node); order = max(order, c.derivative); integral = integral || c.integral }
        if order >= 2 { return 2e-3 }
        if order == 1 { return 2e-6 }
        if integral { return 1e-7 }
        return 1e-9
    }

    struct Comparison {
        var holds: Bool
        var shapeMessage: String?
        var transposed = false
    }

    static func compare(_ a: MathValue, _ b: MathValue, _ relation: MathRelation, tolerance: Double) -> Comparison {
        switch (a.normalized, b.normalized) {
        case let (.scalar(x), .scalar(y)):
            let scale = max(1, abs(x), abs(y))
            return Comparison(holds: relation.holds(x, y, tolerance: tolerance * scale))
        case let (.matrix(m), .matrix(n)):
            guard m.rows == n.rows, m.columns == n.columns else {
                if m.rows == n.columns, m.columns == n.rows {
                    let t = n.transposed
                    let scale = max(1, m.maxAbs, t.maxAbs)
                    let same = zip(m.values, t.values).allSatisfy { relation.holds($0, $1, tolerance: tolerance * scale) }
                    return Comparison(holds: false, shapeMessage: "The left side is \(MathValue.matrix(m).shapeText), the right side \(MathValue.matrix(n).shapeText)", transposed: same)
                }
                return Comparison(holds: false, shapeMessage: "The left side is \(MathValue.matrix(m).shapeText), the right side \(MathValue.matrix(n).shapeText)")
            }
            let scale = max(1, m.maxAbs, n.maxAbs)
            return Comparison(holds: zip(m.values, n.values).allSatisfy { relation.holds($0, $1, tolerance: tolerance * scale) })
        case let (.matrix(m), .scalar(y)) where y == 0:
            let scale = max(1, m.maxAbs)
            return Comparison(holds: m.values.allSatisfy { relation.holds($0, 0, tolerance: tolerance * scale) })
        case let (.scalar(x), .matrix(n)) where x == 0:
            let scale = max(1, n.maxAbs)
            return Comparison(holds: n.values.allSatisfy { relation.holds(0, $0, tolerance: tolerance * scale) })
        case let (.matrix(m), .identity(c)), let (.identity(c), .matrix(m)):
            guard m.isSquare else { return Comparison(holds: false, shapeMessage: "Comparing a \(m.shapeText) matrix with I") }
            let i = MathMatrix.identity(m.rows, scale: c)
            let scale = max(1, m.maxAbs, abs(c))
            return Comparison(holds: zip(m.values, i.values).allSatisfy { relation.holds($0, $1, tolerance: tolerance * scale) })
        case let (.identity(c), .identity(d)):
            return Comparison(holds: relation.holds(c, d, tolerance: tolerance * max(1, abs(c), abs(d))))
        default:
            return Comparison(holds: false, shapeMessage: "Comparing \(a.shapeText) with \(b.shapeText)")
        }
    }

    struct Draw {
        var world: MathWorld
        var left: MathValue
        var right: MathValue
    }

    /// Evaluates both sides in a fresh world; nil when the world is unusable (a singular matrix, a domain error even with positive numbers).
    static func draw(_ left: MathNode, _ right: MathNode, typing: MathTyping, seed: UInt64, positiveFirst: Bool, lastError: inout MathEvalError?) -> Draw? {
        for positive in positiveFirst ? [true] : [false, true] {
            guard let world = MathWorld(typing: typing, seed: seed, positive: positive) else { lastError = .shape("the sizes cannot satisfy the declarations"); return nil }
            do {
                let a = try world.evaluate(left), b = try world.evaluate(right)
                guard a.isFinite, b.isFinite else { lastError = .domain("a value is not finite"); continue }
                return Draw(world: world, left: a, right: b)
            } catch let error as MathEvalError {
                lastError = error
                if case .domain = error { continue }
                return nil
            } catch { return nil }
        }
        return nil
    }

    static func checkStep(_ step: Step, typing: MathTyping, conditions: [Condition], first: Bool, segment: Segment, range: NSRange) -> (report: DerivationLineReport, isCondition: Bool) {
        var result = DerivationLineReport(line: segment.line, range: range, status: .holds, message: "", detail: nil, errorRange: nil)
        let tolerance = tolerance(for: [step.left, step.right])
        let isOrder = step.relation.isOrder || step.relation == .notEqual
        let wanted = isOrder ? orderTrials : identityTrials
        let seedText = "\(step.left)|\(step.right)|\(step.relation.rawValue)"
        var draws: [Draw] = []
        var lastError: MathEvalError?
        var attempts = 0
        var positiveFirst = false
        var failure: (Draw, Comparison)?
        while draws.count < wanted, attempts < wanted * 3 + 12 {
            let seed = MathRandom.seed(seedText, attempts)
            attempts += 1
            guard let d = draw(step.left, step.right, typing: typing, seed: seed, positiveFirst: positiveFirst, lastError: &lastError) else {
                if case .shape? = lastError { break }
                if case .unsupported? = lastError { break }
                continue
            }
            if d.world.positive { positiveFirst = true }
            let comparison = compare(d.left, d.right, step.relation, tolerance: tolerance)
            if !comparison.holds, failure == nil { failure = (d, comparison) }
            draws.append(d)
            // One counterexample settles an inequality; an equation gets a few more draws to name the slip.
            if failure != nil, isOrder || draws.count >= 4 { break }
        }
        if draws.isEmpty {
            if let lastError, case .shape = lastError {
                result.status = .fails; result.message = describe(lastError); result.errorRange = errorRange(step, segment)
            } else {
                result.status = .unchecked
                result.message = lastError.map(describe) ?? "Could not draw values for this step"
            }
            return (result, false)
        }
        let positiveNote = positiveFirst ? " (with positive values)" : ""
        guard let (failed, comparison) = failure else {
            result.message = isOrder ? "No counterexample in \(draws.count) random draws\(positiveNote)" : "Holds on \(draws.count) random draws\(positiveNote)"
            return (result, false)
        }
        // An equation that is not an identity: it may set an expression to a value, follow from an earlier
        // equation, or be a hypothesis.
        if step.relation == .equal, comparison.shapeMessage == nil {
            if step.continuesPrevious, isConstant(step.right) {
                result.status = .given
                let value = MathParser.render(step.right)
                result.message = "Sets the expression to \(value == "?" ? "a constant" : value)"
                return (result, true)
            }
            for condition in conditions.reversed() {
                switch implication(condition: condition, goal: step, typing: typing, tolerance: tolerance) {
                case let .holds(message):
                    result.message = message
                    return (result, true)
                case let .fails(detail):
                    result.status = .fails
                    result.message = "Does not follow from line \(condition.line + 1)"
                    result.detail = detail
                    result.errorRange = errorRange(step, segment)
                    return (result, false)
                case .unknown: continue
                }
            }
            // An equation set to a value (“x² − 5x + 6 = 0”, “∇RSS = 0”): an equation to solve from here on.
            if !step.continuesPrevious, isConstant(step.right) || isConstant(step.left) {
                result.status = .given
                result.message = first ? "Given: an equation to solve" : "An equation to solve: the expression is set to \(MathParser.render(isConstant(step.right) ? step.right : step.left))"
                return (result, true)
            }
        }
        result.status = .fails
        result.errorRange = errorRange(step, segment)
        if let shape = comparison.shapeMessage {
            result.message = comparison.transposed ? "Transposed: one side is the transpose of the other" : shape
        } else if let named = diagnosis(draws, relation: step.relation, tolerance: tolerance) ?? termDiagnosis(step, typing: typing, tolerance: tolerance) {
            result.message = named
        } else if isOrder {
            result.message = "Fails for some values"
        } else if step.continuesPrevious {
            result.message = "Not equal to the previous expression"
        } else {
            result.message = first ? "Not an identity: start the line with “Assume” if it is a hypothesis" : "The two sides differ"
        }
        result.detail = counterexample(failed, step: step, typing: typing)
        return (result, false)
    }

    static func isConstant(_ node: MathNode) -> Bool {
        switch node {
        case .number: true
        case let .negate(a): isConstant(a)
        case let .divide(a, b), let .multiply(a, b): isConstant(a) && isConstant(b)
        default: false
        }
    }

    /// Recognises the usual slips: a sign, a constant factor, an additive constant.
    static func diagnosis(_ draws: [Draw], relation: MathRelation, tolerance: Double) -> String? {
        guard relation == .equal else { return nil }
        var ratios: [Double] = [], differences: [Double] = []
        for d in draws {
            switch (d.left.normalized, d.right.normalized) {
            case let (.scalar(x), .scalar(y)):
                if abs(y) > 1e-9 { ratios.append(x / y) }
                differences.append(x - y)
            case let (.matrix(m), .matrix(n)) where m.rows == n.rows && m.columns == n.columns:
                for (x, y) in zip(m.values, n.values) where abs(y) > 1e-6 * max(1, n.maxAbs) { ratios.append(x / y) }
                differences.append(contentsOf: zip(m.values, n.values).map(-))
            default: return nil
            }
        }
        func constant(_ values: [Double]) -> Double? {
            guard let first = values.first, values.count >= 2 else { return nil }
            let spread = values.reduce(0) { max($0, abs($1 - first)) }
            return spread <= max(1e-6, 100 * tolerance) * max(1, abs(first)) ? first : nil
        }
        if let k = constant(ratios), abs(k - 1) > 1e-6 {
            if abs(k + 1) < 1e-6 { return "Sign error: the two sides are opposite" }
            if abs(k) < 1e-9 { return "The left side is 0" }
            return "Off by a factor of \(nice(k)): the left side is \(nice(k)) × the right side"
        }
        if let d = constant(differences), abs(d) > 1e-9 {
            return "Off by a constant: the left side exceeds the right by \(nice(d))"
        }
        return nil
    }

    /// The additive terms of an expression with their signs: a − b + c → [(+, a), (−, b), (+, c)].
    static func terms(_ node: MathNode, sign: Double = 1) -> [(Double, MathNode)] {
        switch node {
        case let .add(a, b): return terms(a, sign: sign) + terms(b, sign: sign)
        case let .subtract(a, b): return terms(a, sign: sign) + terms(b, sign: -sign)
        case let .negate(a): return terms(a, sign: -sign)
        default: return [(sign, node)]
        }
    }

    /// When one side differs from the other by a multiple of one of its terms, the slip is in that term:
    /// “−2Xᵀy + 2XᵀXβ + λβ” for “… + 2λβ” is reported as “the term λβ should be 2 times as large”.
    static func termDiagnosis(_ step: Step, typing: MathTyping, tolerance: Double) -> String? {
        guard step.relation == .equal else { return nil }
        for (side, other) in [(step.right, step.left), (step.left, step.right)] {
            let parts = terms(side)
            guard parts.count >= 2, parts.count <= 12 else { continue }
            for (sign, term) in parts {
                var ratio: Double?
                var consistent = true
                var draws = 0
                for attempt in 0..<6 {
                    var lastError: MathEvalError?
                    guard let d = draw(other, side, typing: typing, seed: MathRandom.seed("term|\(side)|\(term)", attempt), positiveFirst: false, lastError: &lastError),
                          let value = try? d.world.evaluate(term) else { continue }
                    // (other − side) / (sign · term): constant when only this term is off.
                    let difference: [Double], base: [Double]
                    switch (d.left.normalized, d.right.normalized, value.normalized) {
                    case let (.scalar(a), .scalar(b), .scalar(t)): difference = [a - b]; base = [sign * t]
                    case let (.matrix(a), .matrix(b), .matrix(t)) where a.values.count == b.values.count && b.values.count == t.values.count:
                        difference = zip(a.values, b.values).map(-); base = t.values.map { sign * $0 }
                    default: consistent = false
                        difference = []; base = []
                    }
                    if !consistent { break }
                    let scale = max(1, base.reduce(0) { max($0, abs($1)) })
                    for (x, y) in zip(difference, base) where abs(y) > 1e-6 * scale {
                        let r = x / y
                        if let ratio, abs(r - ratio) > max(1e-6, 1000 * tolerance) * max(1, abs(ratio)) { consistent = false; break }
                        ratio = ratio ?? r
                    }
                    if !consistent { break }
                    draws += 1
                }
                guard consistent, draws >= 3, let k = ratio, abs(k) > 1e-6 else { continue }
                let factor = 1 + k
                let shown = MathText.render(term)
                if abs(factor) < 1e-6 { return "The term \(shown) should not be there" }
                if abs(factor + 1) < 1e-6 { return "The term \(shown) has the wrong sign" }
                return "The term \(shown) should be \(nice(factor)) times as large"
            }
        }
        return nil
    }

    /// 2, 1/2, −3/4, or four significant digits.
    static func nice(_ value: Double) -> String {
        for denominator in 1...12 {
            let numerator = value * Double(denominator)
            if abs(numerator - numerator.rounded()) < 1e-6 * max(1, abs(numerator)) {
                let n = Int(numerator.rounded())
                return denominator == 1 ? MathFormat.number(Double(n)) : "\(n < 0 ? "−" : "")\(abs(n))/\(denominator)"
            }
        }
        return MathFormat.number(value)
    }

    /// The values that break a step: the sizes, the symbols it uses, and both sides.
    static func counterexample(_ draw: Draw, step: Step, typing: MathTyping) -> String {
        let used = MathExpansion.freeSymbols(step.left).union(MathExpansion.freeSymbols(step.right))
        var parts: [String] = []
        let sizes = used.filter { typing.sizeNames.contains($0) }.sorted()
        for name in sizes { if let v = draw.world.dims[name] ?? draw.world.dims[typing.solver.root(name)] { parts.append("\(MathNames.display(name)) = \(v)") } }
        for name in used.sorted() where !typing.sizeNames.contains(name) {
            guard let value = draw.world.overrides[name] ?? draw.world.values[name] else { continue }
            switch value.normalized {
            case let .scalar(v): parts.append("\(MathNames.display(name)) = \(MathFormat.number(v))")
            case let .matrix(m): parts.append("\(MathNames.display(name)) \(m.shapeText)")
            case .identity: break
            }
            if parts.count >= 7 { break }
        }
        let values = "left = \(draw.left.summary), right = \(draw.right.summary)"
        return parts.isEmpty ? values : parts.joined(separator: ", ") + " → " + values
    }

    // MARK: Implication

    enum Implication {
        case holds(String)
        case fails(String)
        case unknown
    }

    /// Whether an equation follows from an earlier one: by substituting a solved variable (“β = (XᵀX)⁻¹Xᵀy” solves
    /// “XᵀXβ = Xᵀy”), or by solving the earlier equation numerically for one of its symbols and testing the new one there.
    static func implication(condition: Condition, goal: Step, typing: MathTyping, tolerance: Double) -> Implication {
        let conditionSymbols = MathExpansion.freeSymbols(condition.left).union(MathExpansion.freeSymbols(condition.right))
        // A solved variable.
        for (variable, expression) in [(goal.left, goal.right), (goal.right, goal.left)] {
            guard case let .symbol(name) = variable, conditionSymbols.contains(name), !MathExpansion.freeSymbols(expression).contains(name) else { continue }
            let left = MathExpansion.substitute(condition.left, [name: expression]), right = MathExpansion.substitute(condition.right, [name: expression])
            var holds = 0, lastError: MathEvalError?
            var broken: Draw?
            for attempt in 0..<(identityTrials * 3) where holds < identityTrials {
                guard let d = draw(left, right, typing: typing, seed: MathRandom.seed("solve|\(name)|\(left)", attempt), positiveFirst: false, lastError: &lastError) else { continue }
                if compare(d.left, d.right, .equal, tolerance: tolerance).holds { holds += 1 } else { broken = d; break }
            }
            if broken == nil, holds >= 3 { return .holds("Solves line \(condition.line + 1) for \(MathNames.display(name))") }
        }
        // Solve the earlier equation numerically for one of its symbols.
        let goalSymbols = MathExpansion.freeSymbols(goal.left).union(MathExpansion.freeSymbols(goal.right))
        let candidates = conditionSymbols.subtracting(typing.sizeNames).subtracting(["π", "e", "I"])
            .sorted { (goalSymbols.contains($0) ? 0 : 1, $0) < (goalSymbols.contains($1) ? 0 : 1, $1) }
        var counterexample: String?
        for name in candidates.prefix(6) {
            var solved = 0, failures = 0
            for attempt in 0..<6 {
                guard let world = MathWorld(typing: typing, seed: MathRandom.seed("implies|\(name)|\(goal.left)", attempt)) else { break }
                guard solve(condition.left, condition.right, for: name, in: world) else { continue }
                do {
                    let a = try world.evaluate(goal.left), b = try world.evaluate(goal.right)
                    solved += 1
                    if !compare(a, b, .equal, tolerance: max(tolerance, 1e-7)).holds {
                        failures += 1
                        if counterexample == nil {
                            counterexample = self.counterexample(Draw(world: world, left: a, right: b), step: goal, typing: typing)
                                + " (where line \(condition.line + 1) holds)"
                        }
                        break
                    }
                } catch { continue }
            }
            if solved >= 3, failures == 0 { return .holds("Follows from line \(condition.line + 1)") }
        }
        if let counterexample { return .fails(counterexample) }
        return .unknown
    }

    /// Newton's method with a numerical Jacobian: finds a value of `name` for which left = right, keeping the other
    /// symbols of the draw. The solution stays in the world for evaluating what follows.
    static func solve(_ left: MathNode, _ right: MathNode, for name: String, in world: MathWorld) -> Bool {
        guard let start = try? world.symbol(name, [:]) else { return false }
        let shape: (Int, Int)
        var x: [Double]
        switch start.normalized {
        case let .scalar(v): shape = (1, 1); x = [v]
        case let .matrix(m): shape = (m.rows, m.columns); x = m.values
        case .identity: return false
        }
        func value(_ values: [Double]) -> MathValue {
            shape == (1, 1) ? .scalar(values[0]) : .matrix(MathMatrix(rows: shape.0, columns: shape.1, values: values))
        }
        func residual(_ values: [Double]) -> [Double]? {
            world.overrides[name] = value(values)
            guard let a = try? world.evaluate(left), let b = try? world.evaluate(right) else { return nil }
            switch (a.normalized, b.normalized) {
            case let (.scalar(p), .scalar(q)): return [p - q]
            case let (.matrix(m), .matrix(n)) where m.rows == n.rows && m.columns == n.columns: return zip(m.values, n.values).map(-)
            case let (.matrix(m), .scalar(q)) where q == 0: return m.values
            case let (.scalar(p), .matrix(n)) where p == 0: return n.values.map { -$0 }
            default: return nil
            }
        }
        func norm(_ v: [Double]) -> Double { v.reduce(0) { $0 + $1 * $1 }.squareRoot() }
        guard var f = residual(x) else { world.overrides[name] = nil; return false }
        for _ in 0..<60 {
            let scale = max(1, x.reduce(0) { max($0, abs($1)) })
            if norm(f) <= 1e-10 * scale { world.overrides[name] = value(x); return true }
            var jacobian = MathMatrix(rows: f.count, columns: x.count)
            for j in 0..<x.count {
                let h = 1e-6 * max(1, abs(x[j]))
                var plus = x, minus = x
                plus[j] += h; minus[j] -= h
                guard let fp = residual(plus), let fm = residual(minus), fp.count == f.count else { world.overrides[name] = nil; return false }
                for i in 0..<f.count { jacobian[i, j] = (fp[i] - fm[i]) / (2 * h) }
            }
            guard let delta = MathMatrix.leastSquares(jacobian, MathMatrix(rows: f.count, columns: 1, values: f.map { -$0 }), ridge: 1e-12) else { break }
            var t = 1.0
            var improved = false
            while t > 1e-6 {
                let candidate = zip(x, delta.values).map { $0 + t * $1 }
                if let g = residual(candidate), norm(g) < norm(f) { x = candidate; f = g; improved = true; break }
                t /= 2
            }
            if !improved { break }
        }
        let scale = max(1, x.reduce(0) { max($0, abs($1)) })
        if let g = residual(x), norm(g) <= 1e-9 * scale { world.overrides[name] = value(x); return true }
        world.overrides[name] = nil
        return false
    }
}

/// Starting points for a derivation: declarations read from the book's notation, and the displayed steps of an answer.
public enum DerivationTemplate {
    /// `\beta` for β, `X` for X: how a symbol is written in a declaration.
    public static func latex(_ symbol: String) -> String {
        if let name = MathNames.greek.first(where: { $0.value == symbol && !$0.key.hasPrefix("var") })?.key { return "\\" + name }
        return symbol
    }

    /// A declaration for a symbol the book describes with a size: “the N × p input matrix” → “X \in \mathbb{R}^{N \times p}”,
    /// “a vector of length p” or “p-vector” → “\mathbb{R}^{p}”, “a positive constant” → “λ > 0”.
    public static func declaration(symbol: String, meaning: String) -> String? {
        let name = latex(symbol)
        let text = meaning.replacingOccurrences(of: "\u{00A0}", with: " ")
        func match(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
            return (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : (text as NSString).substring(with: m.range(at: $0)) }
        }
        // A size: one letter or number, or “(p + 1)”, standing alone (not the end of “finite”).
        let dim = #"(?<![\p{L}\d])(\(?[A-Za-z0-9](?:\s*[+−-]\s*\d+)?\)?)"#
        // Spaces and sets are not vectors: “an n-dimensional vector space”.
        if match(#"\b(?:space|spaces|subspace|subspaces|manifold)\b"#) != nil, match(#"\bmatrix\b"#) == nil { return nil }
        if let parts = match(dim + #"\s*[×x]\s*"# + dim + #"\s+(?:[\p{L}-]+\s+){0,3}(?:matrix|array)"#) {
            let rows = clean(parts[0]), columns = clean(parts[1])
            if columns == "1" { return "\(name) \\in \\mathbb{R}^{\(rows)}" }
            // A square symmetric matrix: 𝕊ⁿ (positive definite: 𝕊ⁿ₊₊).
            if rows == columns, match(#"\bsymmetric\b"#) != nil || match(#"\bpositive\s+(?:semi-?)?definite\b"#) != nil {
                let suffix = match(#"\bpositive\s+definite\b"#) != nil ? "_{++}" : match(#"\bpositive\s+semi-?definite\b"#) != nil ? "_{+}" : ""
                return "\(name) \\in \\mathbb{S}^{\(rows)}\(suffix)"
            }
            return "\(name) \\in \\mathbb{R}^{\(grouped(rows)) \\times \(grouped(columns))}"
        }
        if let parts = match(#"(?:vector|array)\s+of\s+(?:length|size|dimension)\s+"# + dim) ?? match(dim + #"-(?:vector|dimensional\s+(?:\p{L}+\s+)?vector)\b"#) {
            return "\(name) \\in \\mathbb{R}^{\(clean(parts[0]))}"
        }
        // Positive quantities, when the meaning says what the symbol is (not what it is the variance of).
        if match(#"\b(?:matrix|vector|variable|function|distribution|process|point)\b"#) == nil || match(#"^(?:an?|the|some|a\s+fixed)?\s*(?:positive|strictly\s+positive)\b"#) != nil,
           match(#"^(?:(?:an?|the|some|any|a\s+fixed|fixed)\s+)?(?:(?:small|large|fixed|given|real|strictly)\s+)*(?:positive|non-?negative)\s+(?:real\s+)?(?:constant|number|numbers|parameter|parameters|scalar|real|integer)"#) != nil
            || match(#"^(?:(?:an?|the)\s+)?(?:standard\s+deviation|variance|bandwidth|smoothing\s+parameter|step\s+size|learning\s+rate|temperature)\b(?!\s*[–-]?\s*covariance)"#) != nil {
            if match(#"\bintegers?\b"#) != nil { return "\(name) \\in \\mathbb{N}" }
            return match(#"non-?negative"#) != nil ? "\(name) \\ge 0" : "\(name) > 0"
        }
        return nil
    }

    /// “p+1” as “(p+1)” beside a ×, so the size reads as one.
    private static func grouped(_ dim: String) -> String { dim.contains("+") || dim.contains("-") ? "(\(dim))" : dim }

    private static func clean(_ dim: String) -> String {
        var d = dim.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "−", with: "-")
        if d.hasPrefix("("), d.hasSuffix(")") { d = String(d.dropFirst().dropLast()) }
        return d
    }

    /// The displayed equations of a Markdown answer, one step per line: `$$…$$`, `\[…\]` and aligned environments,
    /// split at `\\`. Inline mathematics is left out: it is rarely a step.
    public static func steps(fromAnswer markdown: String) -> [String] {
        var lines: [String] = []
        let pattern = #"\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\begin\{(align\*?|aligned|equation\*?|gather\*?|split|eqnarray\*?)\}([\s\S]+?)\\end\{\3\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = markdown as NSString
        for match in regex.matches(in: markdown, range: NSRange(location: 0, length: text.length)) {
            let body = [1, 2, 4].compactMap { index -> String? in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : text.substring(with: range)
            }.first ?? ""
            var inner = body
            for env in ["aligned", "align*", "align", "split", "gathered", "equation*", "equation"] {
                inner = inner.replacingOccurrences(of: "\\begin{\(env)}", with: "").replacingOccurrences(of: "\\end{\(env)}", with: "")
            }
            let rows = inner.components(separatedBy: "\\\\").map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let relations = rows.filter { row in ["=", "\\le", "\\ge", "<", ">", "\\leq", "\\geq"].contains { row.contains($0) } }
            guard !relations.isEmpty else { continue }
            if !lines.isEmpty { lines.append("") }
            lines.append(contentsOf: rows)
        }
        return lines
    }
}

/// Expressions as a reader writes them, for messages: “λβ”, “−2Xᵀy”, “(XᵀX + λI)⁻¹Xᵀy”.
public enum MathText {
    private static let superscripts: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻", "n": "ⁿ", "i": "ⁱ"]

    public static func render(_ node: MathNode) -> String {
        switch node {
        case let .number(v): return MathFormat.number(v)
        case let .symbol(name): return MathNames.display(name)
        case let .indexed(name, indices): return MathNames.display(name + "_" + MathParser.indexName(indices))
        case let .add(a, b): return render(a) + " + " + render(b)
        case let .subtract(a, b): return render(a) + " − " + wrapped(b, sum: true)
        case let .multiply(a, b):
            let left = wrapped(a, sum: true), right = wrapped(b, sum: true)
            if case .number = b { return left + "·" + right }
            return left + right
        case let .divide(a, b): return wrapped(a, sum: true) + "/" + wrapped(b, sum: true, product: true)
        case let .negate(a): return "−" + wrapped(a, sum: true)
        case let .power(a, b):
            let exponent = render(b)
            if exponent.allSatisfy({ superscripts[$0] != nil }) { return wrapped(a, sum: true, product: true) + String(exponent.compactMap { superscripts[$0] }) }
            return wrapped(a, sum: true, product: true) + "^(" + exponent + ")"
        case let .transpose(a): return wrapped(a, sum: true, product: true) + "ᵀ"
        case let .inverse(a): return wrapped(a, sum: true, product: true) + "⁻¹"
        case let .function(name, args): return name + "(" + args.map(render).joined(separator: ", ") + ")"
        case let .apply(name, args): return MathNames.display(name) + "(" + args.map(render).joined(separator: ", ") + ")"
        case let .norm(a, _): return "‖" + render(a) + "‖"
        case let .absolute(a): return "|" + render(a) + "|"
        case let .factorial(a): return wrapped(a, sum: true, product: true) + "!"
        case let .binomial(a, b): return "C(" + render(a) + ", " + render(b) + ")"
        case let .sum(index, _, _, body): return "Σ_" + index + " " + wrapped(body, sum: true)
        case let .product(index, _, _, body): return "Π_" + index + " " + wrapped(body, sum: true)
        case let .derivative(body, variable, _): return "∂/∂" + MathNames.display(variable) + " " + wrapped(body, sum: true)
        case let .integral(_, _, variable, body): return "∫ " + render(body) + " d" + variable
        case let .matrix(rows): return "[" + rows.map { $0.map(render).joined(separator: " ") }.joined(separator: "; ") + "]"
        case .identity: return "I"
        case .ones: return "𝟏"
        case let .at(body, variable, value): return render(body) + "|" + variable + "=" + render(value)
        case let .unsupported(what): return what
        }
    }

    private static func wrapped(_ node: MathNode, sum: Bool, product: Bool = false) -> String {
        switch node {
        case .add, .subtract: return sum ? "(" + render(node) + ")" : render(node)
        case .multiply, .divide, .negate: return product ? "(" + render(node) + ")" : render(node)
        default: return render(node)
        }
    }
}
