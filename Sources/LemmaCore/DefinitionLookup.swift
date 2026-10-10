import Foundation

public struct DefinitionMatch: Identifiable, Equatable, Sendable {
    public let note: StudyNote
    public let exact: Bool
    public var id: UUID { note.id }
}

/// Literal lookup in reader-named glossary entries. Page proximity orders candidates;
/// it does not infer which mathematical convention or scope applies.
public enum DefinitionLookup {
    public static func find(_ query: String, in notes: [StudyNote], near pageIndex: Int) -> [DefinitionMatch] {
        let query = normalized(query)
        let symbol = query.count == 1 || query.contains("\\") || query.contains("_") || query.contains("^")
        let options: String.CompareOptions = symbol ? [] : [.caseInsensitive, .diacriticInsensitive]
        let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: query) + "(?![\\p{L}\\p{N}_])"
        let expression = query.isEmpty ? nil : try? NSRegularExpression(pattern: pattern, options: symbol ? [] : [.caseInsensitive])
        return notes.filter { $0.kind.isGlossary }.compactMap { note -> DefinitionMatch? in
            let title = normalized(note.question)
            let names = note.lookupTerms.split(whereSeparator: \.isNewline).map { normalized(String($0)) }
            let exact = !query.isEmpty && ([title] + names).contains { $0.compare(query, options: options) == .orderedSame }
            let titleMatch = expression?.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
            guard query.isEmpty || exact || titleMatch else { return nil }
            return DefinitionMatch(note: note, exact: exact)
        }.sorted {
            if $0.exact != $1.exact { return $0.exact }
            let lhsEarlier = $0.note.anchor.pageIndex <= pageIndex, rhsEarlier = $1.note.anchor.pageIndex <= pageIndex
            if lhsEarlier != rhsEarlier { return lhsEarlier }
            let lhsDistance = abs($0.note.anchor.pageIndex - pageIndex), rhsDistance = abs($1.note.anchor.pageIndex - pageIndex)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
