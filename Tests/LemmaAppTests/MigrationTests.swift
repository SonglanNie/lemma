import XCTest
import LemmaCore
@testable import Lemma

/// Opt-in: a support folder written by an earlier Lemma opens in this one with every book, note, mark, library and tab,
/// and is saved again without losing any of them. The folder is copied first and never changed:
/// `LEMMA_MIGRATION_SOURCE=<support folder> swift test --filter MigrationTests`.
final class MigrationTests: XCTestCase {
    /// The parts of a saved book that must survive, read from the JSON so that any earlier schema can be compared.
    private struct Saved: Equatable {
        var title: String
        var counts: [String: Int]
        var pageIndex: Int?
        var readSeconds: Double
    }

    private static let lists = ["notes", "highlights", "inkStrokes", "bookmarks", "pins", "labs", "derivations", "exercises",
                                "noteLinks", "understood", "foldedProofs"]

    private func saved(_ root: URL) throws -> [String: Saved] {
        let folder = root.appendingPathComponent("Workspaces", isDirectory: true)
        var result: [String: Saved] = [:]
        for id in try FileManager.default.contentsOfDirectory(atPath: folder.path) where !id.hasPrefix(".") {
            let directory = folder.appendingPathComponent(id, isDirectory: true)
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("workspace.json")),
                  var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            // Since 3.0 the reading position and time live beside the book, in reading.json.
            if let data = try? Data(contentsOf: directory.appendingPathComponent("reading.json")),
               let reading = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (key, value) in reading { json[key] = value }
            }
            let counts = Dictionary(uniqueKeysWithValues: Self.lists.map { ($0, (json[$0] as? [Any])?.count ?? 0) })
            let pageIndex = (json["reading"] as? [String: Any])?["pageIndex"] as? Int
            let seconds = ((json["readingLog"] as? [String: Any])?["pageSeconds"] as? [String: Double])?.values.reduce(0, +) ?? 0
            result[id] = Saved(title: json["title"] as? String ?? "", counts: counts, pageIndex: pageIndex, readSeconds: seconds)
        }
        return result
    }

    @MainActor
    func testAnEarlierSupportFolderOpensAndSavesWithEverything() async throws {
        guard let source = ProcessInfo.processInfo.environment["LEMMA_MIGRATION_SOURCE"] else {
            throw XCTSkip("Set LEMMA_MIGRATION_SOURCE to a support folder written by an earlier Lemma.")
        }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lemma-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try saved(root)
        XCTAssertFalse(before.isEmpty, "The folder holds books.")
        let libraries = (try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Libraries.json"))) as? [Any])?.count
        let session = try? JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("workbench.json"))) as? [String: Any]
        let openBooks = (session?["bookIDs"] as? [String]) ?? []

        let store = StudyStore(root: root)
        store.restore()
        for _ in 0..<60 where store.libraries.updatedAt == nil { try await Task.sleep(for: .milliseconds(100)) }
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(Set(store.library.map(\.id)), Set(before.keys), "Every book is listed.")
        if let libraries { XCTAssertEqual(store.libraries.collections.count, libraries, "Every library is kept.") }
        let reopened = openBooks.filter { id in store.library.first { $0.id == id }.map { FileManager.default.fileExists(atPath: $0.sourcePath) } ?? false }
        XCTAssertEqual(store.tabs.map(\.id).filter(reopened.contains), reopened, "The books that were open are open again.")
        for (id, old) in before {
            let book = try XCTUnwrap(store.repository.load(id: id), "\(old.title) loads")
            XCTAssertEqual(book.title, old.title)
            XCTAssertEqual(book.notes.count, old.counts["notes"], "\(old.title): notes")
            XCTAssertEqual(book.highlights.count, old.counts["highlights"], "\(old.title): highlights")
            XCTAssertEqual(book.inkStrokes.count, old.counts["inkStrokes"], "\(old.title): ink")
            XCTAssertEqual(book.pins.count, old.counts["pins"], "\(old.title): pins")
            if let page = old.pageIndex { XCTAssertEqual(book.reading.pageIndex, page, "\(old.title): reading position") }
        }

        store.flush()
        let after = try saved(root)
        for (id, old) in before {
            let new = try XCTUnwrap(after[id], "\(old.title) is still saved")
            XCTAssertEqual(new.title, old.title)
            XCTAssertEqual(new.counts, old.counts, "\(old.title): nothing is lost when 3.0 saves it")
            XCTAssertEqual(new.pageIndex, old.pageIndex, "\(old.title): reading position")
            XCTAssertGreaterThanOrEqual(new.readSeconds, old.readSeconds, "\(old.title): reading time")
        }
        store.questions.shutdown()
    }
}
