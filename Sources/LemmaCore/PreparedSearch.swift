import Foundation

/// A book's index with each entry's term and title folded once. Folding (`TextRepair.folded`) is most of the cost of
/// an index search, and Look Up and the palette search as the reader types.
public struct PreparedBookIndex: Sendable {
    public let entries: [BookIndexEntry]
    let terms: [String]
    let singularTerms: [String]
    let titles: [String]

    public init(_ entries: [BookIndexEntry]) {
        self.entries = entries
        terms = entries.map { TextRepair.folded($0.term) }
        singularTerms = terms.map(BookIndexSearch.singularForm)
        titles = entries.map { TextRepair.folded($0.title) }
    }

    public var isEmpty: Bool { entries.isEmpty }
}

extension BookIndexSearch {
    /// Index entries for a term or phrase, as `find(_:in:limit:)` ranks them, over an index folded beforehand.
    public static func find(_ query: String, in index: PreparedBookIndex, limit: Int = 60) -> [Match] {
        let folded = TextRepair.folded(query).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()"))
        guard !folded.isEmpty else { return [] }
        let words = folded.split(separator: " ").map(String.init)
        let singular = singularForm(folded)
        let space = folded + " ", comma = folded + ",", parenthesis = folded + " ("
        var matches: [Match] = []
        for position in index.entries.indices {
            let term = index.terms[position], title = index.titles[position]
            let rank: Int
            if term == folded || index.singularTerms[position] == singular { rank = index.entries[position].parent == nil ? 0 : 1 }
            else if term.hasPrefix(space) || term.hasPrefix(comma) || term.hasPrefix(parenthesis) { rank = 2 }
            else if containsWord(folded, in: title) { rank = 3 }
            else if words.count > 1, words.allSatisfy({ containsWord($0, in: title) }) { rank = 4 }
            else if words.count == 1, folded.count >= 4, title.contains(folded) { rank = 5 }
            else { continue }
            matches.append(Match(entry: index.entries[position], rank: rank))
        }
        return Array(matches.sorted { $0.rank == $1.rank ? $0.entry.id < $1.entry.id : $0.rank < $1.rank }.prefix(limit))
    }
}

/// A book's defined terms with each one's comparison key (`BookTerms.key`) worked out once.
public struct PreparedTerms: Sendable {
    public let terms: [DefinedTerm]
    let keys: [String]
    let keyWords: [Set<String>]

    public init(_ terms: [DefinedTerm]) {
        self.terms = terms
        keys = terms.map { BookTerms.key($0.term) }
        keyWords = keys.map { Set($0.split(separator: " ").map(String.init)) }
    }

    public var isEmpty: Bool { terms.isEmpty }
}

extension BookTermSearch {
    /// The book's defined terms for a looked-up word or phrase, as `find(_:in:limit:)` ranks them, over terms
    /// prepared beforehand.
    public static func find(_ query: String, in prepared: PreparedTerms, limit: Int = 8) -> [DefinedTerm] {
        let wanted = BookTerms.key(query)
        guard wanted.count >= 2 else { return [] }
        let words = Set(wanted.split(separator: " ").map(String.init))
        var scored: [(term: DefinedTerm, score: Int)] = []
        for position in prepared.terms.indices {
            let term = prepared.terms[position], key = prepared.keys[position], keyWords = prepared.keyWords[position]
            var score: Int
            if key == wanted { score = 0 }
            else if words.isSubset(of: keyWords) { score = 10 + keyWords.count - words.count }
            // A shorter term inside a longer query (“smoothing spline” for “cubic smoothing spline”), never a lone word.
            else if keyWords.isSubset(of: words), keyWords.count >= 2 { score = 20 }
            else { continue }
            if !term.definitional { score += 2 }
            if !term.inIndex { score += 1 }
            scored.append((term, score))
        }
        return scored.sorted { $0.score == $1.score ? $0.term.pageIndex < $1.term.pageIndex : $0.score < $1.score }.prefix(limit).map(\.term)
    }
}
