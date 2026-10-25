import XCTest
import AppKit
import PDFKit
import LemmaCore
@testable import Lemma

/// Opt-in measurements of the Library tree, the command palette and Look Up across books, on a library of 300 PDFs
/// (hard links to one PDF) in five watched folders. Run with LEMMA_LIBPERF_PDF (any PDF) and LEMMA_LIBPERF_OUTPUT
/// (a JSON file for the results); add LEMMA_LIBPERF_BOOK (an analysed PDF) and LEMMA_LIBPERF_ANALYSIS (its
/// analysis.json, from `LemmaIndexer --analyze`) to measure the palette and Look Up as well.
final class LibraryPerformanceTests: XCTestCase {
    private let keys = ["workbench.panes", "library.sort"]

    @MainActor
    func testMeasureLibraryTreePaletteAndLookUp() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let seed = env["LEMMA_LIBPERF_PDF"], let output = env["LEMMA_LIBPERF_OUTPUT"] else {
            throw XCTSkip("Opt-in library measurements.")
        }
        _ = NSApplication.shared
        var saved: [String: Any] = [:]
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key); UserDefaults.standard.removeObject(forKey: key) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LibPerf-\(UUID().uuidString)")
        defer {
            for key in keys { UserDefaults.standard.set(saved[key], forKey: key) }
            try? FileManager.default.removeItem(at: root)
        }
        let support = root.appendingPathComponent("support")
        var collections: [LibraryCollection] = []
        var pdfs: [URL] = []
        for library in 1...5 {
            let folder = root.appendingPathComponent("Library \(library)")
            for index in 1...60 {
                let sub = index <= 15 ? "" : "Part \((index - 1) / 15)/"
                let url = folder.appendingPathComponent("\(sub)Book \(library)-\(index).pdf")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.linkItem(at: URL(fileURLWithPath: seed), to: url)
                pdfs.append(url)
            }
            collections.append(LibraryCollection(id: "lib\(library)", title: "Library \(library)", kind: .books, sources: [LibrarySource(path: folder.path)]))
        }
        // Every fifth PDF has been studied: a workspace with a reading position and notes, one of them due.
        let repository = WorkspaceRepository(root: support)
        for (offset, url) in pdfs.enumerated() where offset % 5 == 0 {
            var book = StudyWorkspace(id: "book-\(offset)", title: "Studied \(offset)", sourcePath: url.path, sourceBookmark: nil, fingerprint: "book-\(offset)")
            book.pageCount = 300; book.reading.pageIndex = offset % 300
            for note in 0..<4 {
                var item = StudyNote(anchor: SourceAnchor(pageIndex: note, pageLabel: "\(note + 1)", region: PageRegion(x: 0, y: 0, width: 10, height: 10),
                                                          quote: "q", imageName: "x.png"), question: "Question \(note)")
                if note == 0 { item.review = ReviewSchedule(dueAt: .distantPast) }
                book.notes.append(item)
            }
            try repository.save(book)
        }
        UserDefaults.standard.set(["collection-lib1": true, "collection-lib2": true, "library-folder-lib1:Part 1": true], forKey: "workbench.panes")
        let store = StudyStore(app: AppModel(root: support))
        try store.libraries.replace(collections)
        store.libraries.start()
        let deadline = Date().addingTimeInterval(120)
        while (store.libraries.isScanning || store.libraries.entries.count < pdfs.count) && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(store.libraries.entries.count, pdfs.count)
        store.workspace = store.library.first
        var results: [String: Any] = ["pdfs": store.libraries.entries.count, "books": store.library.count]
        results["tree_first_ms"] = Self.ms { _ = store.libraryRows() }
        results["tree_unchanged_ms"] = Self.median((0..<40).map { _ in Self.ms { _ = store.libraryRows() } })
        // A save puts the book read back into `library` with its new position, as every page crossing does.
        results["tree_after_save_ms"] = Self.median((0..<30).map { step in
            store.library[1].reading.pageIndex = step
            return Self.ms { _ = store.libraryRows() }
        })
        results["pdf_count_ms"] = Self.median((0..<40).map { _ in Self.ms { _ = store.libraryPDFCount } })
        results["rows_visible"] = store.libraryRows().count
        var expanded = store.app.paneExpanded
        for collection in collections { expanded["collection-" + collection.id] = true }
        store.app.paneExpanded = expanded
        results["tree_expanded_ms"] = Self.median((0..<20).map { step in
            store.library[1].reading.pageIndex = 100 + step
            return Self.ms { _ = store.libraryRows() }
        })
        results["rows_expanded"] = store.libraryRows().count

        if let bookPath = env["LEMMA_LIBPERF_BOOK"], let analysisPath = env["LEMMA_LIBPERF_ANALYSIS"] {
            let book = URL(fileURLWithPath: bookPath)
            let id = try WorkspaceRepository.fingerprint(of: book)
            func install(_ id: String) throws {
                let folder = support.appendingPathComponent("Indexes/\(id)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: URL(fileURLWithPath: analysisPath), to: folder.appendingPathComponent("analysis.json"))
            }
            try install(id)
            // Other analysed books, for Look Up across the library.
            for other in store.library.prefix(8) { try install(other.id) }
            store.open(book)
            defer { store.analysis?.cancel() }
            let analysis = try XCTUnwrap(store.analysis?.analysis, "The analysis must load from its cache")
            results["corpus"] = ["index": analysis.index.count, "terms": analysis.terms.count, "definitions": analysis.definitions.count,
                                 "sections": store.outline.flatMap(\.flattened).count, "library_entries": store.libraries.entries.count]
            let typed = ["m", "ma", "mat", "matr", "matri", "matrix", "matrix ", "matrix d", "matrix de", "matrix dec"]
            let palette = typed.map { query in Self.ms { _ = PaletteProvider(store: store).items(mode: .goTo, query: query) } }
            results["palette_items_ms"] = palette
            results["palette_items_median_ms"] = Self.median(palette)
            let commands = ["c", "co", "col", "colo", "color"].map { query in Self.ms { _ = PaletteProvider(store: store).items(mode: .commands, query: query) } }
            results["palette_commands_median_ms"] = Self.median(commands)
            // The open palette keeps one session: candidates gathered and folded once, then each keystroke ranks.
            let session = PaletteSession(store: store)
            let opening = Self.ms { _ = session.items(mode: .goTo, query: "") }
            let keystrokes = typed.map { query in Self.ms { _ = session.items(mode: .goTo, query: query) } }
            results["palette_session_open_ms"] = opening
            results["palette_session_first_key_ms"] = keystrokes[0]
            results["palette_session_keystroke_median_ms"] = Self.median(Array(keystrokes.dropFirst()))

            let words = ["eig", "eige", "eigen", "eigenv", "eigenva", "eigenval", "eigenvalue"]
            results["lookup_book_unprepared_ms"] = Self.median(words.map { query in
                Self.ms { _ = BookTermSearch.find(query, in: analysis.terms, limit: 4); _ = BookIndexSearch.find(query, in: analysis.index, limit: 6) }
            })
            let current = try XCTUnwrap(store.workspace?.id)
            results["lookup_book_prepare_ms"] = Self.ms { _ = store.libraryGlossary.prepared(analysis, id: current) }
            results["lookup_book_ms"] = Self.median(words.map { query in
                Self.ms {
                    let prepared = store.libraryGlossary.prepared(analysis, id: current)
                    _ = BookTermSearch.find(query, in: prepared.terms, limit: 4); _ = BookIndexSearch.find(query, in: prepared.index, limit: 6)
                }
            })
            store.libraryGlossary.load(library: store.library, root: support)
            let loaded = Date().addingTimeInterval(120)
            while store.libraryGlossary.books.count < 8 && Date() < loaded { try await Task.sleep(for: .milliseconds(100)) }
            results["lookup_library_books"] = store.libraryGlossary.books.count
            results["lookup_library_ms"] = Self.median(words.map { query in
                Self.ms { _ = store.libraryGlossary.hits(for: query, excluding: store.workspace?.id) }
            })
        }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
    }

    private static func ms(_ operation: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        operation()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}
