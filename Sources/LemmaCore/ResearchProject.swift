import Foundation

/// A question pursued across several books. Sources retain their own crop and book location;
/// the synthesis is the reader's writing, separate from the quoted material.
public struct ResearchProject: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var question: String
    public var synthesis: String
    public var bookIDs: [String]
    public var passages: [ProjectPassage]
    public var nextSourceNumber: Int
    public var archived: Bool
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String, question: String = "", bookIDs: [String] = []) {
        self.id = id; self.title = title; self.question = question; self.synthesis = ""
        self.bookIDs = bookIDs; self.passages = []; self.nextSourceNumber = 1
        self.archived = false; self.updatedAt = .now
    }

    public mutating func collect(_ passage: ProjectPassage) {
        passages.append(passage)
        if !bookIDs.contains(passage.bookID) { bookIDs.append(passage.bookID) }
        nextSourceNumber = max(nextSourceNumber, passage.number + 1)
        updatedAt = .now
    }
}

public struct ProjectPassage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Stable inside the project: deleting S2 does not rename S3 or break a written citation.
    public var number: Int
    public var bookID: String
    public var bookTitle: String
    public var title: String
    public var section: String
    public var anchor: SourceAnchor
    public var annotation: String

    public init(id: UUID = UUID(), number: Int, bookID: String, bookTitle: String,
                title: String, section: String, anchor: SourceAnchor, annotation: String = "") {
        self.id = id; self.number = number; self.bookID = bookID; self.bookTitle = bookTitle
        self.title = title; self.section = section; self.anchor = anchor; self.annotation = annotation
    }

    public var sourceLabel: String { "S\(number)" }
    public var link: URL {
        var parts = URLComponents()
        parts.scheme = "lemma"; parts.host = "open"
        parts.queryItems = [URLQueryItem(name: "book", value: bookID), URLQueryItem(name: "page", value: String(anchor.pageIndex + 1))]
        return parts.url!
    }
    public var citation: String { "[\(sourceLabel)](\(link.absoluteString))" }
}

public struct ProjectRepository: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root.appendingPathComponent("Projects", isDirectory: true) }
    private var manifest: URL { root.appendingPathComponent("projects.json") }
    public func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func imageURL(_ projectID: UUID, name: String) -> URL {
        directory(projectID).appendingPathComponent("assets", isDirectory: true).appendingPathComponent(name)
    }
    public func load() throws -> [ResearchProject] {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }
        return try JSONDecoder().decode([ResearchProject].self, from: Data(contentsOf: manifest))
    }
    public func save(_ projects: [ResearchProject]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(projects).write(to: manifest, options: .atomic)
    }
    public func saveImage(_ data: Data, projectID: UUID, name: String) throws {
        let url = imageURL(projectID, name: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// A portable dossier: the original crops, quoted text, the reader's annotations and synthesis.
    /// Lemma links also retain the exact physical page, independent of its printed label.
    public func export(_ project: ResearchProject, to folder: URL) throws {
        let assets = folder.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        for passage in project.passages {
            try Data(contentsOf: imageURL(project.id, name: passage.anchor.imageName))
                .write(to: assets.appendingPathComponent(passage.anchor.imageName), options: .atomic)
        }
        try markdown(project).write(to: folder.appendingPathComponent("Research.md"), atomically: true, encoding: .utf8)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(project).write(to: folder.appendingPathComponent("project.json"), options: .atomic)
    }

    public func markdown(_ project: ResearchProject) -> String {
        var sections = ["# \(project.title)"]
        if !project.question.isEmpty { sections.append("## Research question\n\n\(project.question)") }
        if !project.synthesis.isEmpty { sections.append("## Synthesis\n\n\(project.synthesis)") }
        sections.append("## Sources")
        for source in project.passages {
            let label = source.anchor.pageLabel
            var text = "### \(source.sourceLabel) · \(source.title)\n\n\(source.bookTitle) · p. \(label) · PDF page \(source.anchor.pageIndex + 1)\n\n[Open in Lemma](\(source.link.absoluteString))"
            if !source.section.isEmpty { text += "\n\nSection: \(source.section)" }
            text += "\n\n![Original passage](assets/\(source.anchor.imageName))"
            if !source.anchor.quote.isEmpty { text += "\n\n" + source.anchor.quote.components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n") }
            if !source.annotation.isEmpty { text += "\n\nReader's annotation:\n\n\(source.annotation)" }
            sections.append(text)
        }
        return sections.joined(separator: "\n\n") + "\n"
    }
}
