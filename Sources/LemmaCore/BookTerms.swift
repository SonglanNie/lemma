import Foundation
import NaturalLanguage

/// A term the book introduces in italic or bold (“the popular *cubic smoothing spline*”), at the place it is defined:
/// the occurrence with a definition cue, an explicitly titled definition, or corroboration from the book’s index.
public struct DefinedTerm: Codable, Equatable, Sendable, Identifiable {
    /// Folded key: lower case except acronyms and inner capitals (“AdaBoost”).
    public var term: String
    /// The words as printed.
    public var surface: String
    public var pageIndex: Int
    public var location: Int
    public var length: Int
    public var before: String
    public var after: String
    /// A definition cue surrounds the defining occurrence.
    public var definitional: Bool
    /// The back-of-book index has an entry with this term.
    public var inIndex: Bool
    /// How many times the book emphasises it.
    public var occurrences: Int
    public var id: String { term }
    public var range: NSRange { NSRange(location: location, length: length) }

    public init(term: String, surface: String, pageIndex: Int, range: NSRange, before: String, after: String,
                definitional: Bool, inIndex: Bool, occurrences: Int) {
        self.term = term; self.surface = surface; self.pageIndex = pageIndex
        location = range.location; length = range.length
        self.before = before; self.after = after
        self.definitional = definitional; self.inIndex = inIndex; self.occurrences = occurrences
    }
}

extension DefinedTerm {
    /// The term's range in a page's text. PDFKit can order a page's text differently in another document instance,
    /// so the stored range is checked and, when it no longer holds the term, the occurrence nearest to it is used.
    public func locate(in text: String) -> NSRange? {
        let string = text as NSString
        if NSMaxRange(range) <= string.length, Self.matches(string.substring(with: range), surface) { return range }
        let words = surface.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "‐" || $0 == "–" })
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !words.isEmpty, let expression = try? NSRegularExpression(pattern: words.joined(separator: #"[\s\-‐–]*"#), options: [.caseInsensitive]) else { return nil }
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: string.length))
        return matches.min { abs($0.range.location - location) < abs($1.range.location - location) }?.range
    }

    static func matches(_ found: String, _ surface: String) -> Bool {
        func letters(_ text: String) -> String { TextRepair.folded(text).filter { $0.isLetter || $0.isNumber } }
        return letters(found) == letters(surface)
    }
}

/// Builds the book's term table from emphasised candidates, page by page.
public enum BookTerms {
    /// One entry per term: the defining occurrence. A single word is kept when a definition cue surrounds it, or
    /// when it is a noun the back-of-book index lists on that very page · emphasised ordinary words (“*twice*”,
    /// “*values*”) are dropped. `printedPage` maps a page index to the number the index uses.
    public static func table(_ candidates: [(pageIndex: Int, candidate: TermCandidate)], index: [BookIndexEntry],
                             printedPage: (Int) -> Int? = { $0 + 1 }) -> [DefinedTerm] {
        var indexPages: [String: [ClosedRange<Int>]] = [:]
        for entry in index {
            let spans = entry.locators.compactMap { span -> ClosedRange<Int>? in
                guard let first = Int(span.first.filter(\.isNumber)) else { return nil }
                return first...max(first, span.last.flatMap { Int($0.filter(\.isNumber)) } ?? first)
            }
            for name in [entry.term, entry.parent.map { "\(entry.term) \($0)" }].compactMap({ $0 }) {
                indexPages[key(name), default: []] += spans
            }
        }
        var groups: [String: [(pageIndex: Int, candidate: TermCandidate)]] = [:]
        var order: [String] = []
        for item in candidates {
            let term = item.candidate.term
            if groups[term] == nil { order.append(term) }
            groups[term, default: []].append(item)
        }
        var table: [DefinedTerm] = []
        for term in order {
            guard let occurrences = groups[term] else { continue }
            let spans = indexPages[key(term)]
            let inIndex = spans != nil
            func indexedHere(_ item: (pageIndex: Int, candidate: TermCandidate)) -> Bool {
                printedPage(item.pageIndex).map { page in spans?.contains { $0.contains(page) } == true } ?? false
            }
            // Emphasis alone also marks book titles, dialogue and rhetorical phrases in ordinary prose.
            // Use a definition cue, or an occurrence corroborated by the book's own index.
            guard let site = occurrences.first(where: { $0.candidate.definitional })
                    ?? occurrences.first(where: indexedHere) else { continue }
            let words = term.split(separator: " ")
            if words.count == 1, !site.candidate.definitional {
                if !isNoun(site.candidate) { continue }
            }
            let candidate = site.candidate
            table.append(DefinedTerm(term: term, surface: candidate.surface, pageIndex: site.pageIndex, range: candidate.range,
                                     before: candidate.contextBefore, after: candidate.contextAfter,
                                     definitional: candidate.definitional, inIndex: inIndex, occurrences: occurrences.count))
        }
        return table
    }

    /// Folded comparison key, singular: “Smoothing splines” and “smoothing spline” meet.
    static func key(_ text: String) -> String {
        let folded = TextRepair.folded(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
        return folded.split(separator: " ").map { word in
            word.count > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") ? String(word.dropLast()) : String(word)
        }.joined(separator: " ")
    }

    /// Whether a single emphasised word reads as a noun in its sentence.
    static func isNoun(_ candidate: TermCandidate) -> Bool {
        let sentence = candidate.contextBefore + candidate.surface + candidate.contextAfter
        let start = sentence.index(sentence.startIndex, offsetBy: candidate.contextBefore.count, limitedBy: sentence.endIndex) ?? sentence.startIndex
        let end = sentence.index(start, offsetBy: candidate.surface.count, limitedBy: sentence.endIndex) ?? sentence.endIndex
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sentence
        var noun = false
        tagger.enumerateTags(in: start..<end, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            if tag == .noun || tag == .otherWord { noun = true }
            return true
        }
        return noun
    }
}

/// Finds the book's defined terms for a looked-up word or phrase.
public enum BookTermSearch {
    /// Exact terms first, then terms containing every word of the query, preferring definitions and indexed terms.
    /// Keys every term for this one search; for searches as the reader types, key them once (`PreparedTerms`).
    public static func find(_ query: String, in terms: [DefinedTerm], limit: Int = 8) -> [DefinedTerm] {
        guard BookTerms.key(query).count >= 2 else { return [] }
        return find(query, in: PreparedTerms(terms), limit: limit)
    }
}
