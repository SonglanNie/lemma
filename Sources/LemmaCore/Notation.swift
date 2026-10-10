import Foundation

/// A sentence that says what a symbol stands for: “where λ ≥ 0 is a complexity parameter”, “Let X denote the
/// N × p input matrix”, “the hat matrix H”. Read from the text layer; a reading aid, not a semantic analysis.
public struct SymbolDefinition: Codable, Equatable, Sendable {
    /// The symbol as Lemma compares it: “λ”, “X”, “x” (Unicode math italic folded to plain letters).
    public var symbol: String
    /// What the sentence says it is: “a complexity parameter that controls the amount of shrinkage”.
    public var meaning: String
    public var pageIndex: Int
    /// The symbol's UTF-16 offset in the page's text.
    public var location: Int
    /// How the text says it: an explicit statement (“denotes”, “let … be”) or a noun placed before it (“the matrix X”).
    public var explicit: Bool
    public init(symbol: String, meaning: String, pageIndex: Int, location: Int, explicit: Bool) {
        self.symbol = symbol; self.meaning = meaning; self.pageIndex = pageIndex; self.location = location; self.explicit = explicit
    }
    public var point: TextPoint { TextPoint(pageIndex: pageIndex, location: location) }
}

/// Reads symbol definitions from a page's text and finds the one in force at a place in the book.
public enum Notation {
    // A symbol: a Greek letter, a Unicode mathematical letter, or a Latin letter standing alone.
    private static let symbol = #"(?:[α-ωΑ-Ωϕϵϑϱϖς]|[\x{1D400}-\x{1D7FF}]|(?<![\p{L}\p{N}'’])[A-Za-z](?![\p{L}'’]))"#
    private static let phrase = #"([^.;:?!]{3,160}?)(?=[.;:?!]|$|\n\n)"#
    private static let condition = #"(?:\s*[≥≤<>=∈⊂⊆≠]\s*[^\s,;]{1,15})?"#

    private struct Pattern { let expression: NSRegularExpression; let explicit: Bool }

    private static let patterns: [Pattern] = [
        // “Let X denote the input matrix”, “let λ be a positive constant”.
        Pattern(expression: try! NSRegularExpression(pattern: #"\b[Ll]et\s+("# + symbol + #")"# + condition + #"\s+(?:be|denote|denotes|represent|stand\s+for|be\s+called)\s+"# + phrase), explicit: true),
        // “where λ ≥ 0 is a complexity parameter”, “Here λ is…”, “and N denotes the number of observations”.
        Pattern(expression: try! NSRegularExpression(pattern: #"\b(?:[Ww]here|[Ww]ith|and|[Hh]ere|[Nn]ow)\s+("# + symbol + #")"# + condition + #"\s+(?:is|are|denotes|represents|stands\s+for|is\s+called|refers\s+to)\s+"# + phrase), explicit: true),
        // “X denotes the matrix”, at the start of a sentence or clause.
        Pattern(expression: try! NSRegularExpression(pattern: #"(?:^|[.;:]\s+|\n)("# + symbol + #")\s+(?:denotes|represents|stands\s+for|is\s+called|is\s+defined\s+as)\s+"# + phrase,
                                                     options: [.anchorsMatchLines]), explicit: true),
        // “denote by H the hat matrix”.
        Pattern(expression: try! NSRegularExpression(pattern: #"\b[Dd]enoted?\s+by\s+("# + symbol + #")\s+(?:for\s+|to\s+denote\s+|as\s+)?"# + phrase), explicit: true),
        // “we write ε for the noise”, “we use R to denote the real numbers” · the symbol alone, then its meaning: in
        // “we write x ⪰K y for y ⪯K x” the notation is a relation, not x.
        Pattern(expression: try! NSRegularExpression(pattern: #"\b(?:[Ww]e\s+write|[Ww]e\s+use|[Ww]rite)\s+("# + symbol + #")\s+(?:for|to\s+denote|as)\s+"# + phrase), explicit: true),
        // “the N × p input matrix X”, “the complexity parameter λ”: a singular noun with a mathematical head just before
        // the symbol, on the same line, with prose continuing after it (not a display's subscript).
        Pattern(expression: try! NSRegularExpression(pattern: #"\b(?:the|a|an|our|its|each)[ \t]+((?:[\p{L}×\-]+[ \t]+){0,3}(?:matrix|vector|parameter|function|variable|set|space|estimator|estimate|operator|distribution|density|constant|coefficient|loss|risk|kernel|map|mapping|norm|sequence|sample|statistic|probability|measure|process|error|rate|class|model|subspace|basis|eigenvalue|eigenvector|dimension|index|field|graph|weight|penalty|threshold|bandwidth|response|output|input|label|target|noise|mean|variance|covariance|prior|posterior|likelihood|activation|layer|state|action|policy|reward))[ \t]+("# + symbol + #")(?=[ \t]*[,.;:)]|[ \t]+\p{Ll}{2,})"#),
                explicit: false)
    ]

    /// Words that look like a lone letter but are English: “a”, “A”, “I”.
    private static let englishLetters: Set<String> = ["a", "A", "I"]

    /// Definitions on one page, in text order.
    public static func definitions(in text: String, pageIndex: Int) -> [SymbolDefinition] {
        let string = text as NSString
        let whole = NSRange(location: 0, length: string.length)
        var found: [SymbolDefinition] = []
        for pattern in patterns {
            for match in pattern.expression.matches(in: text, range: whole) {
                let symbolGroup = pattern.explicit ? 1 : 2, meaningGroup = pattern.explicit ? 2 : 1
                let symbolRange = match.range(at: symbolGroup)
                guard symbolRange.location != NSNotFound, match.range(at: meaningGroup).location != NSNotFound else { continue }
                let raw = string.substring(with: symbolRange)
                guard !englishLetters.contains(raw) else { continue }
                // A lone lower-case Latin letter is usually an index (i, j, k); only an explicit statement defines it.
                if !pattern.explicit, raw.count == 1, raw.first?.isASCII == true, raw.first?.isLowercase == true { continue }
                let meaning = clean(string.substring(with: match.range(at: meaningGroup)))
                guard meaning.count >= 3, meaning.contains(where: \.isLetter) else { continue }
                found.append(SymbolDefinition(symbol: key(raw), meaning: meaning, pageIndex: pageIndex, location: symbolRange.location, explicit: pattern.explicit))
            }
        }
        // One definition per place: an explicit statement wins over a noun before the same symbol.
        var byPlace: [Int: SymbolDefinition] = [:]
        for definition in found where byPlace[definition.location].map({ !$0.explicit && definition.explicit }) ?? true {
            byPlace[definition.location] = definition
        }
        return byPlace.values.sorted { $0.location < $1.location }
    }

    /// The comparison key of a symbol: mathematical alphanumerics fold to their plain letter (𝑥 → x).
    public static func key(_ symbol: String) -> String {
        guard let scalar = symbol.unicodeScalars.first else { return symbol }
        // NFKC maps mathematical letters to their base letters (𝑥 → x, 𝛽 → β).
        if (0x1D400...0x1D7FF).contains(scalar.value) { return String(String(scalar).precomposedStringWithCompatibilityMapping.prefix(1)) }
        return String(symbol.prefix(1))
    }

    /// Whether a character of the page can be a symbol that Lemma knows definitions for.
    public static func isSymbolCharacter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        if (0x1D400...0x1D7FF).contains(scalar.value) { return true }
        if ("α"..."ω").contains(character) || ("Α"..."Ω").contains(character) || "ϕϵϑϱϖς".contains(character) { return true }
        return character.isASCII && character.isLetter
    }

    static func clean(_ text: String) -> String {
        // “shrink-⏎age” → “shrinkage”: a word broken across a line.
        let joined = text.replacingOccurrences(of: #"(\p{Ll})-[ \t]*\n[ \t]*(\p{Ll})"#, with: "$1$2", options: .regularExpression)
        var result = TextRepair.repaired(joined).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for article in ["the ", "a ", "an "] where result.lowercased().hasPrefix(article) {
            result = String(result.dropFirst(article.count)); break
        }
        // The meaning ends where the sentence moves on: a parenthesis it did not open (“its dimension), and therefore…”),
        // a clause (“convex set, with x1, …”) or the next symbol's definition (“real numbers, R+ to denote…”).
        var depth = 0
        for (offset, character) in result.enumerated() {
            if character == "(" { depth += 1 }
            if character == ")" { if depth == 0 { result = String(result.prefix(offset)); break }; depth -= 1 }
        }
        if let range = result.range(of: #",\s+(?:with|where|and|which|so|then|but|since|because|while|i\.e\.|e\.g\.)\s|,\s+(?:[A-Za-zα-ωΑ-Ω][+*′']?|[\x{1D400}-\x{1D7FF}])\s"#,
                                    options: .regularExpression) {
            result = String(result[..<range.lowerBound])
        }
        // A long clause keeps its first part.
        if result.count > 120, let cut = result.prefix(120).lastIndex(of: " ") { result = String(result[..<cut]) + "…" }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
    }
}

/// Position-sensitive lookups over a book's symbol definitions: the meaning in force at a place is the latest
/// definition before it, as a reader would remember it; a symbol defined only later is offered as such.
public struct NotationIndex: Sendable {
    public let bySymbol: [String: [SymbolDefinition]]

    public init(_ definitions: [SymbolDefinition]) {
        bySymbol = Dictionary(grouping: definitions, by: \.symbol).mapValues { $0.sorted { $0.point < $1.point } }
    }

    public var isEmpty: Bool { bySymbol.isEmpty }

    /// How far ahead a definition may be offered for a symbol not yet defined: a sentence or two later on the same
    /// spread (“…(3.41). Here λ ≥ 0 is…”), not a different use a hundred pages on.
    public static let lookahead = 3

    /// The definition in force at `point`: the latest explicit statement before it (a noun naming the symbol counts
    /// when it is more recent and close), else one just after it.
    public func definition(of symbol: String, at point: TextPoint) -> (definition: SymbolDefinition, later: Bool)? {
        guard let all = bySymbol[Notation.key(symbol)], !all.isEmpty else { return nil }
        let before = all.filter { $0.point <= point }
        let soon = all.filter { $0.point > point && $0.point.pageIndex - point.pageIndex <= Self.lookahead }
        // A definition on the same page just after the use (“Here λ ≥ 0 is…” under the display) beats an older one elsewhere.
        if let next = soon.first(where: { $0.explicit && $0.pageIndex == point.pageIndex }),
           before.last.map({ point.pageIndex - $0.pageIndex > 1 }) ?? true { return (next, true) }
        if let explicit = before.last(where: \.explicit) ?? before.last {
            if let latest = before.last, !latest.explicit, latest.point.pageIndex - explicit.point.pageIndex <= 2 { return (latest, false) }
            return (explicit, false)
        }
        return (soon.first(where: \.explicit) ?? soon.first).map { ($0, true) }
    }

    /// Other meanings to list beside the one in force: explicit statements first, nearest pages first.
    public func otherMeanings(of symbol: String, near pageIndex: Int, excluding current: SymbolDefinition?, limit: Int = 4) -> [SymbolDefinition] {
        meanings(of: symbol).filter { $0 != current }
            .sorted { ($0.explicit ? 0 : 1, abs($0.pageIndex - pageIndex)) < ($1.explicit ? 0 : 1, abs($1.pageIndex - pageIndex)) }
            .prefix(limit).map { $0 }
    }

    /// Every meaning a symbol takes in the book, one per page, in order.
    public func meanings(of symbol: String) -> [SymbolDefinition] { bySymbol[Notation.key(symbol)] ?? [] }

    /// The symbols with a definition in force on a page that its text uses, for a notation “watch” beside the page.
    public func symbols(usedIn text: String, pageIndex: Int) -> [(symbol: String, definition: SymbolDefinition, later: Bool)] {
        var seen: Set<String> = []
        var result: [(String, SymbolDefinition, Bool)] = []
        // Swift's characters, not NSString's composed sequences: PDF text can put a combining mark after a line break
        // ("\n" + U+0338, the slash of ∉), one sequence for NSString but two characters for Swift, and building a
        // Character from it stopped the app. Locations stay UTF-16 offsets, as the definitions record them.
        let characters = Array(text)
        var location = 0
        for (offset, character) in characters.enumerated() {
            defer { location += character.utf16.count }
            guard Notation.isSymbolCharacter(character) else { continue }
            // A Latin letter counts only on its own: “X” in “X denotes”, not the x of “matrix”.
            if character.isASCII {
                let before: Character = offset > 0 ? characters[offset - 1] : " "
                let after: Character = offset + 1 < characters.count ? characters[offset + 1] : " "
                if before.isLetter || after.isLetter || ["a", "A", "I"].contains(String(character)) { continue }
            }
            let key = Notation.key(String(character))
            guard !seen.contains(key), let found = definition(of: key, at: TextPoint(pageIndex: pageIndex, location: location)) else { continue }
            seen.insert(key)
            result.append((key, found.definition, found.later))
        }
        return result
    }
}
