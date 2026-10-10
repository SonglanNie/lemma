import Foundation

public struct NoteSearchHit: Sendable {
    public let workspaceID: String
    public let noteID: UUID
    public let exact: Bool
    public let similarity: Double?
    public var key: String { "\(workspaceID):\(noteID.uuidString)" }
}

public enum NoteSearch {
    public static func find(_ query: String, in library: [StudyWorkspace], byMeaning: Bool) -> [NoteSearchHit] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let embedding = byMeaning ? SemanticText.embed(query) : nil
        var hits: [NoteSearchHit] = []
        for workspace in library {
            for note in workspace.notes {
                if Task.isCancelled { return [] }
                let exact = note.matches(query)
                let text = [note.title, note.lookupTerms, note.notation, note.assumptions, note.body, note.anchor.quote, note.explanation?.body ?? ""].joined(separator: " ")
                let score = embedding.flatMap { query in SemanticText.embed(String(text.prefix(2000))).flatMap { SemanticText.similarity(query, $0) } }
                if exact || (byMeaning && (score ?? -1) >= 0.5) {
                    hits.append(NoteSearchHit(workspaceID: workspace.id, noteID: note.id, exact: exact, similarity: score))
                }
            }
        }
        return Array(hits.sorted {
            if $0.exact != $1.exact { return $0.exact }
            if $0.similarity != $1.similarity { return ($0.similarity ?? -1) > ($1.similarity ?? -1) }
            return $0.key < $1.key
        }.prefix(40))
    }
}
