import Foundation

public enum NoteLinkKind: String, Codable, CaseIterable, Sendable {
    case definition, assumption, related

    public var label: String {
        switch self {
        case .definition: "Definition"
        case .assumption: "Assumption"
        case .related: "Related"
        }
    }

    public var symbol: String {
        switch self {
        case .definition: "text.book.closed"
        case .assumption: "checklist"
        case .related: "link"
        }
    }
}

/// A relationship supplied by the reader, between notes in one workspace.
public struct NoteLink: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sourceNoteID: UUID
    public var targetNoteID: UUID
    public var kind: NoteLinkKind
    public var usage: String

    public init(id: UUID = UUID(), sourceNoteID: UUID, targetNoteID: UUID, kind: NoteLinkKind, usage: String = "") {
        self.id = id
        self.sourceNoteID = sourceNoteID
        self.targetNoteID = targetNoteID
        self.kind = kind
        self.usage = usage
    }
}

extension StudyNote {
    /// Stable even when the note's title changes.
    public var markdownAnchor: String { "note-\(id.uuidString.lowercased())" }
}

extension StudyWorkspace {
    @discardableResult
    public mutating func addNoteLink(from sourceID: UUID, to targetID: UUID, kind: NoteLinkKind, usage: String = "") -> NoteLink? {
        guard sourceID != targetID,
              notes.contains(where: { $0.id == sourceID }),
              notes.contains(where: { $0.id == targetID }),
              !noteLinks.contains(where: { $0.sourceNoteID == sourceID && $0.targetNoteID == targetID && $0.kind == kind }) else { return nil }
        let link = NoteLink(sourceNoteID: sourceID, targetNoteID: targetID, kind: kind, usage: usage.trimmingCharacters(in: .whitespacesAndNewlines))
        noteLinks.append(link)
        return link
    }

    public func outgoingLinks(from noteID: UUID) -> [NoteLink] {
        guard notes.contains(where: { $0.id == noteID }) else { return [] }
        let noteIDs = Set(notes.map(\.id))
        return noteLinks.filter { $0.sourceNoteID == noteID && noteIDs.contains($0.targetNoteID) }
    }

    public func incomingLinks(to noteID: UUID) -> [NoteLink] {
        guard notes.contains(where: { $0.id == noteID }) else { return [] }
        let noteIDs = Set(notes.map(\.id))
        return noteLinks.filter { $0.targetNoteID == noteID && noteIDs.contains($0.sourceNoteID) }
    }

    public func markdownLinks(for note: StudyNote) -> String {
        var output = ""
        let outgoing = outgoingLinks(from: note.id)
        if !outgoing.isEmpty {
            output += "### Linked notes (reader supplied)\n\n"
            for link in outgoing {
                guard let target = notes.first(where: { $0.id == link.targetNoteID }) else { continue }
                output += "- \(link.kind.label): [\(Self.linkText(target.title))](#\(target.markdownAnchor))\(Self.usageText(link.usage))\n"
            }
            output += "\n"
        }
        let incoming = incomingLinks(to: note.id)
        if !incoming.isEmpty {
            output += "### Referenced by\n\n"
            for link in incoming {
                guard let source = notes.first(where: { $0.id == link.sourceNoteID }) else { continue }
                output += "- \(link.kind.label) in [\(Self.linkText(source.title))](#\(source.markdownAnchor))\(Self.usageText(link.usage))\n"
            }
            output += "\n"
        }
        return output
    }

    private static func linkText(_ text: String) -> String {
        var output = text.components(separatedBy: .newlines).joined(separator: " ")
        for character in ["\\", "[", "]", "<", ">"] {
            output = output.replacingOccurrences(of: character, with: "\\" + character)
        }
        return output
    }

    private static func usageText(_ usage: String) -> String {
        let text = usage.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "" : " · \(linkText(text))"
    }
}
