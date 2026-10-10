import Foundation
import PDFKit
import NaturalLanguage

public enum IndexedTextOrigin: String, Codable, Sendable { case pdfText, ocr }

public struct TextEmbedding: Codable, Equatable, Sendable {
    public var language: String
    public var revision: Int
    public var vector: [Double]
    public init(language: String, revision: Int, vector: [Double]) { self.language = language; self.revision = revision; self.vector = vector }
}

public struct IndexedPassage: Codable, Equatable, Sendable {
    public var text: String
    public var embedding: TextEmbedding?
    public init(text: String, embedding: TextEmbedding? = nil) { self.text = text; self.embedding = embedding }
}

public struct IndexedPage: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { pageIndex }
    public var pageIndex: Int
    public var pageLabel: String
    public var origin: IndexedTextOrigin
    public var passages: [IndexedPassage]
    public var text: String
    public var reviewedAt: Date?
    public init(pageIndex: Int, pageLabel: String, origin: IndexedTextOrigin, passages: [IndexedPassage], text: String? = nil) {
        self.pageIndex = pageIndex; self.pageLabel = pageLabel; self.origin = origin; self.passages = passages
        self.text = text ?? passages.map(\.text).joined(separator: "\n")
    }
}

public struct IndexProgress: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable { case running, complete, cancelled, failed }
    public var status: Status
    public var completedPages: Int
    public var totalPages: Int
    /// The name of the indexing run that wrote this (kept under its earlier key, so saved indexes still read).
    public var jobName: String
    public var message: String?
    public var updatedAt: Date = .now
    public init(status: Status, completedPages: Int, totalPages: Int, jobName: String, message: String? = nil) {
        self.status = status; self.completedPages = completedPages; self.totalPages = totalPages
        self.jobName = jobName; self.message = message
    }
    private enum CodingKeys: String, CodingKey {
        case status, completedPages, totalPages, jobName = "guardName", message, updatedAt
    }
}

public struct DocumentIndexRepository: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public func directory(_ id: String) -> URL { root.appendingPathComponent("Indexes").appendingPathComponent(id) }
    public func pages(_ id: String) throws -> [IndexedPage] {
        let directory = directory(id)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("page-") && $0.pathExtension == "json" }
            .map { try WorkspaceRepository.decoder.decode(IndexedPage.self, from: Data(contentsOf: $0)) }
            .sorted { $0.pageIndex < $1.pageIndex }
    }
    /// How many pages are indexed, from the file names alone (decoding every page to count them is slow for long books).
    public func pageCount(_ id: String) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory(id).path)) ?? []
        return names.filter { $0.hasPrefix("page-") && $0.hasSuffix(".json") }.count
    }
    public func progress(_ id: String) throws -> IndexProgress? {
        let url = directory(id).appendingPathComponent("progress.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try WorkspaceRepository.decoder.decode(IndexProgress.self, from: Data(contentsOf: url))
    }
    public func save(_ page: IndexedPage, id: String) throws { try write(page, id: id, name: "page-\(page.pageIndex).json") }
    public func save(_ progress: IndexProgress, id: String) throws { try write(progress, id: id, name: "progress.json") }
    private func write<T: Encodable>(_ value: T, id: String, name: String) throws {
        try FileManager.default.createDirectory(at: directory(id), withIntermediateDirectories: true)
        try WorkspaceRepository.encoder.encode(value).write(to: directory(id).appendingPathComponent(name), options: .atomic)
    }
}

/// A local Apple sentence model, when the OS has one for the passage's language.
/// Equations and mathematical entailment are outside this text similarity measure.
public enum SemanticText {
    public static func embed(_ text: String) -> TextEmbedding? {
        let recognizer = NLLanguageRecognizer(); recognizer.processString(text)
        guard let language = recognizer.dominantLanguage,
              let model = NLEmbedding.sentenceEmbedding(for: language), let vector = model.vector(for: text) else { return nil }
        return TextEmbedding(language: language.rawValue, revision: model.revision, vector: vector)
    }
    public static func similarity(_ a: TextEmbedding, _ b: TextEmbedding) -> Double? {
        guard a.language == b.language, a.revision == b.revision, a.vector.count == b.vector.count, !a.vector.isEmpty else { return nil }
        let aa = a.vector.reduce(0) { $0 + $1 * $1 }, bb = b.vector.reduce(0) { $0 + $1 * $1 }
        guard aa > 0, bb > 0 else { return nil }
        return zip(a.vector, b.vector).reduce(0) { $0 + $1.0 * $1.1 } / sqrt(aa * bb)
    }
    public static func passages(_ text: String) -> [IndexedPassage] {
        let words = text.split(whereSeparator: \.isWhitespace)
        return stride(from: 0, to: words.count, by: 70).map { start in
            let end = min(start + 90, words.count)
            let chunk = words[start..<end].joined(separator: " ")
            return IndexedPassage(text: chunk, embedding: embed(chunk))
        }
    }
}

public enum DocumentIndexer {
    /// Each completed page is an atomic checkpoint. Resuming skips those pages. Whole documents are indexed in the
    /// packaged worker (`LemmaIndexer`), which Lemma runs at utility priority and pauses on battery and when the Mac
    /// is hot; `pageDone` reports each checkpoint (pages done, pages in all).
    @MainActor
    public static func index(source: URL, id: String, repository: DocumentIndexRepository, jobName: String,
                             pageDone: ((Int, Int) -> Void)? = nil) async throws {
        // A book whose PDF changed on disk keeps its workspace id and records the new bytes' fingerprint.
        let expected = (try? WorkspaceRepository(root: repository.root).load(id: id))?.fingerprint ?? id
        guard try WorkspaceRepository.fingerprint(of: source) == expected,
              let document = PDFDocument(url: source), document.pageCount > 0 else { throw CocoaError(.fileReadCorruptFile) }
        var completed = Set(try repository.pages(id).map(\.pageIndex))
        var progress = IndexProgress(status: .running, completedPages: completed.count, totalPages: document.pageCount, jobName: jobName)
        try repository.save(progress, id: id)
        pageDone?(completed.count, document.pageCount)
        do {
            for index in 0..<document.pageCount where !completed.contains(index) {
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { throw CocoaError(.fileReadCorruptFile) }
                var text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let origin: IndexedTextOrigin = text.isEmpty ? .ocr : .pdfText
                if origin == .ocr {
                    let box = page.bounds(for: .cropBox)
                    let png = try PDFRegionRenderer.png(page: page, region: PageRegion(x: box.minX, y: box.minY, width: box.width, height: box.height), scale: 2)
                    text = try await RegionTextRecognizer.recognize(png: png)
                }
                try Task.checkCancellation()
                try repository.save(IndexedPage(pageIndex: index, pageLabel: page.label ?? String(index + 1), origin: origin,
                    passages: SemanticText.passages(text), text: text), id: id)
                completed.insert(index)
                progress.completedPages = completed.count; progress.updatedAt = .now
                try repository.save(progress, id: id)
                pageDone?(completed.count, document.pageCount)
                await Task.yield()
            }
            progress.status = .complete
        } catch {
            progress.status = error is CancellationError ? .cancelled : .failed
            progress.message = error.localizedDescription; progress.updatedAt = .now
            try? repository.save(progress, id: id)
            throw error
        }
        progress.updatedAt = .now
        try repository.save(progress, id: id)
    }
}

public struct PassageSearchResult: Identifiable, Sendable {
    public var id: String { "\(workspaceID):\(pageIndex):\(passageIndex)" }
    public var workspaceID: String
    public var pageIndex: Int
    public var pageLabel: String
    public var passageIndex: Int
    public var text: String
    public var origin: IndexedTextOrigin
    public var exact: Bool
    public var similarity: Double?
}

public enum PassageSearch {
    public static func find(_ query: String, in indexes: [(String, [IndexedPage])], byMeaning: Bool) -> [PassageSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let queryEmbedding = byMeaning ? SemanticText.embed(query) : nil
        var results: [PassageSearchResult] = []
        for (workspaceID, pages) in indexes {
            for page in pages {
                for (index, passage) in page.passages.enumerated() {
                    if Task.isCancelled { return [] }
                    let exact = passage.text.localizedStandardContains(query)
                    let similarity = queryEmbedding.flatMap { query in passage.embedding.flatMap { SemanticText.similarity(query, $0) } }
                    // Similarity is a retrieval suggestion, never a mathematical verification.
                    guard exact || (byMeaning && (similarity ?? -1) >= 0.5) else { continue }
                    results.append(PassageSearchResult(workspaceID: workspaceID, pageIndex: page.pageIndex, pageLabel: page.pageLabel,
                        passageIndex: index, text: passage.text, origin: page.origin, exact: exact, similarity: similarity))
                }
            }
        }
        return Array(results.sorted { a, b in
            if a.exact != b.exact { return a.exact }
            if a.similarity != b.similarity { return (a.similarity ?? -1) > (b.similarity ?? -1) }
            if a.workspaceID != b.workspaceID { return a.workspaceID < b.workspaceID }
            if a.pageIndex != b.pageIndex { return a.pageIndex < b.pageIndex }
            return a.passageIndex < b.passageIndex
        }.prefix(40))
    }
}
