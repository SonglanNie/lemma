import XCTest
import LemmaCore

/// The library's storage: unreadable files reported one by one, saves in order off the main thread, reading positions
/// saved beside the workspace, and fingerprints read once per file.
final class WorkspaceStorageTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func workspace(_ id: String, title: String, opened: TimeInterval = 0) -> StudyWorkspace {
        var workspace = StudyWorkspace(id: id, title: title, sourcePath: "/\(id).pdf", sourceBookmark: nil, fingerprint: id)
        workspace.lastOpenedAt = Date(timeIntervalSince1970: 1_800_000_000 + opened)
        return workspace
    }

    func testListingSkipsAnUnreadableWorkspaceAndNamesIt() throws {
        let repository = WorkspaceRepository(root: root)
        try repository.save(workspace("good", title: "Good book", opened: 10))
        try repository.save(workspace("older", title: "Older book"))
        try repository.save(workspace("bad", title: "Damaged book"))
        let damaged = repository.directory(for: "bad").appendingPathComponent("workspace.json")
        try Data(#"{"title": "Damaged book", "notes": 3}"#.utf8).write(to: damaged)
        let empty = repository.directory(for: "garbage").appendingPathComponent("workspace.json")
        try FileManager.default.createDirectory(at: empty.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: empty)

        let listing = try repository.listing()
        XCTAssertEqual(listing.workspaces.map(\.id), ["good", "older"], "Readable workspaces, most recently opened first.")
        XCTAssertEqual(Set(listing.failures.map(\.id)), ["bad", "garbage"])
        XCTAssertEqual(listing.failures.first { $0.id == "bad" }?.label, "“Damaged book”")
        XCTAssertTrue(listing.failures.first { $0.id == "garbage" }?.label.contains("garbage") == true)
        XCTAssertEqual(try repository.list().map(\.id), ["good", "older"], "list() no longer fails as a whole.")
        XCTAssertEqual(try Data(contentsOf: damaged), Data(#"{"title": "Damaged book", "notes": 3}"#.utf8), "Unreadable files are left alone.")
        XCTAssertThrowsError(try repository.load(id: "bad"), "Loading it on its own still says it cannot be read.")
    }

    func testQueuedSavesLandInOrderAndReadsWaitForThem() throws {
        let repository = WorkspaceRepository(root: root)
        var book = workspace("book", title: "Book")
        for index in 0..<60 {
            book.reading.returnNote = "Version \(index)"
            book.notes = (0..<index % 7).map { StudyNote(anchor: SourceAnchor(pageIndex: $0, pageLabel: "\($0 + 1)",
                region: PageRegion(x: 0, y: 0, width: 10, height: 10), quote: "", imageName: "\($0).png")) }
            repository.saveLater(book)
        }
        // Another repository value for the same folder shares the queue: the read waits for every save before it.
        let loaded = try XCTUnwrap(WorkspaceRepository(root: root).load(id: "book"))
        XCTAssertEqual(loaded.reading.returnNote, "Version 59")
        XCTAssertEqual(loaded.notes.count, 59 % 7)
    }

    func testTheReadingPositionIsSavedBesideTheWorkspace() throws {
        let repository = WorkspaceRepository(root: root)
        var book = workspace("book", title: "Book")
        book.notes = [StudyNote(anchor: SourceAnchor(pageIndex: 0, pageLabel: "1", region: PageRegion(x: 0, y: 0, width: 5, height: 5), quote: "", imageName: "a.png"))]
        try repository.save(book)
        let manifest = repository.directory(for: "book").appendingPathComponent("workspace.json")
        let stamp = FileStamp(manifest)
        var reading = ReadingState(); reading.pageIndex = 41; reading.positionY = 512
        var log = ReadingLog(); log.record(30, onPage: 41, at: Date(timeIntervalSince1970: 1_800_000_100))
        let opened = Date(timeIntervalSince1970: 1_800_000_200)
        repository.saveReadingLater(reading, lastOpenedAt: opened, readingLog: log, id: "book")
        let loaded = try XCTUnwrap(repository.load(id: "book"))
        XCTAssertEqual(FileStamp(manifest), stamp, "The notes are not written again for a new position.")
        XCTAssertEqual(loaded.reading.pageIndex, 41)
        XCTAssertEqual(loaded.reading.positionY, 512)
        XCTAssertEqual(loaded.lastOpenedAt, opened)
        XCTAssertEqual(loaded.readingLog.seconds(onPage: 41), 30)
        XCTAssertEqual(try repository.list().first?.reading.pageIndex, 41, "Lists see the latest position too.")

        // A full save carries the position it was given, and the older sidecar goes.
        var edited = loaded; edited.reading.pageIndex = 7; edited.title = "Renamed"
        try repository.save(edited)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.directory(for: "book").appendingPathComponent("reading.json").path))
        XCTAssertEqual(try repository.load(id: "book")?.reading.pageIndex, 7)
        XCTAssertEqual(try repository.load(id: "book")?.title, "Renamed")
        // A position for a book never saved is not written on its own.
        repository.saveReadingLater(reading, lastOpenedAt: opened, readingLog: log, id: "unsaved")
        repository.writer.waitUntilIdle()
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.directory(for: "unsaved").path))
    }

    func testTwoPagesContinuousIsSavedSoOlderVersionsStillOpenTheBook() throws {
        let repository = WorkspaceRepository(root: root)
        var book = workspace("book", title: "Book"); book.reading.layout = .twoPagesContinuous
        try repository.save(book)
        XCTAssertEqual(try repository.load(id: "book")?.reading.layout, .twoPagesContinuous)
        var reading = book.reading; reading.pageIndex = 12
        repository.saveReadingLater(reading, lastOpenedAt: book.lastOpenedAt, readingLog: book.readingLog, id: "book")
        XCTAssertEqual(try repository.load(id: "book")?.reading.layout, .twoPagesContinuous, "The position saved beside it keeps the layout.")

        // Lemma 3.3.0 knew three layouts and refused a workspace naming another one.
        struct OlderWorkspace: Decodable {
            struct Reading: Decodable { enum Layout: String, Decodable { case singlePage, continuous, twoPages }; var layout: Layout? }
            var reading: Reading
        }
        let manifest = try Data(contentsOf: repository.directory(for: "book").appendingPathComponent("workspace.json"))
        XCTAssertEqual(try JSONDecoder().decode(OlderWorkspace.self, from: manifest).reading.layout, .twoPages)
        for layout in ReadingLayout.allCases where layout != .twoPagesContinuous {
            book.reading.layout = layout
            try repository.save(book)
            let saved = try Data(contentsOf: repository.directory(for: "book").appendingPathComponent("workspace.json"))
            XCTAssertEqual(try JSONDecoder().decode(OlderWorkspace.self, from: saved).reading.layout?.rawValue, layout.rawValue)
            XCTAssertEqual(try repository.load(id: "book")?.reading.layout, layout)
        }

        // A layout added by a later version reads as none, and the book still opens.
        let newer = try JSONDecoder().decode(ReadingState.self, from: Data(#"{"pageIndex": 3, "scale": 1, "returnNote": "", "layout": "threePages"}"#.utf8))
        XCTAssertNil(newer.layout)
        XCTAssertEqual(newer.pageIndex, 3)
    }

    func testFingerprintsAreReadOnceAndForgottenWhenTheFileChanges() throws {
        let file = root.appendingPathComponent("book.pdf")
        try Data("first bytes".utf8).write(to: file)
        let read = try SourceFingerprint.read(file, coordinated: true)
        XCTAssertEqual(read.fingerprint, try WorkspaceRepository.fingerprint(of: file), "The same SHA-256 that names existing workspaces.")
        let stamp = try XCTUnwrap(read.stamp)
        let cache = FingerprintCache(root: root)
        XCTAssertNil(cache.fingerprint(for: stamp))
        cache.record(read.fingerprint, for: stamp)
        XCTAssertEqual(cache.fingerprint(for: stamp), read.fingerprint)
        WorkspaceRepository(root: root).writer.waitUntilIdle()
        XCTAssertEqual(FingerprintCache(root: root).fingerprint(for: stamp), read.fingerprint, "Kept with the library across launches.")

        // Renamed: the same file and bytes, still known.
        let renamed = root.appendingPathComponent("renamed.pdf")
        try FileManager.default.moveItem(at: file, to: renamed)
        XCTAssertEqual(FileStamp(renamed).flatMap(cache.fingerprint(for:)), read.fingerprint)
        // Rewritten: other bytes, not taken for the old ones.
        try Data("other bytes, longer".utf8).write(to: renamed)
        XCTAssertNil(FileStamp(renamed).flatMap(cache.fingerprint(for:)))
        XCTAssertNil(FileStamp(root.appendingPathComponent("missing.pdf")))
        XCTAssertTrue(SourceFingerprint.wantsBackground(root.appendingPathComponent("missing.pdf")))
        XCTAssertFalse(SourceFingerprint.wantsBackground(renamed), "A small local file is read at once.")
    }
}
