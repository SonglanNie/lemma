import XCTest
import LemmaCore

final class DefinitionLookupTests: XCTestCase {
    func testLiteralNamesPreserveSymbolCaseWordBoundariesAndAmbiguousScopes() {
        var earlier = note("Design matrix", page: 3, kind: .notation)
        earlier.lookupTerms = "X\ndesign matrix"; earlier.scope = "Chapter 1"
        var later = note("State variable", page: 12, kind: .notation)
        later.lookupTerms = "X"; later.scope = "Chapter 2"
        let titleMatch = note("X — a matrix", page: 7, kind: .notation)
        let lower = note("x", page: 5, kind: .notation)
        let unrelated = note("Context", page: 6, body: "X occurs in this reasoning, not in the entry's name.")
        let question = note("X", page: 7, kind: .question)
        let notes = [question, unrelated, later, lower, titleMatch, earlier]
        let matches = DefinitionLookup.find(" X \n", in: notes, near: 8)
        XCTAssertEqual(matches.map(\.id), [earlier.id, later.id, titleMatch.id])
        XCTAssertEqual(matches.map(\.exact), [true, true, false])
        XCTAssertEqual(matches.map(\.note.scope).prefix(2), ["Chapter 1", "Chapter 2"], "Both conventions must remain visible to the reader.")
        XCTAssertEqual(DefinitionLookup.find("x", in: notes, near: 8).map(\.id), [lower.id])
        XCTAssertEqual(DefinitionLookup.find("DESIGN   MATRIX", in: notes, near: 8).map(\.id), [earlier.id])
        let rank = note("Full column rank", page: 2)
        let ranking = note("Ranking objective", page: 2)
        XCTAssertEqual(DefinitionLookup.find("rank", in: [ranking, rank], near: 8).map(\.id), [rank.id])
        var beta = note("$\\beta$", page: 1, kind: .notation)
        XCTAssertTrue(DefinitionLookup.find("β", in: [beta], near: 8).isEmpty, "Literal lookup must not imply formula equivalence.")
        beta.lookupTerms = "β\n\\beta"
        XCTAssertEqual(DefinitionLookup.find("β", in: [beta], near: 8).map(\.id), [beta.id])
        XCTAssertEqual(DefinitionLookup.find("\\beta", in: [beta], near: 8).map(\.id), [beta.id])
        var capital = note("Capital gamma", page: 1, kind: .notation)
        capital.lookupTerms = "\\Gamma\nX_j"
        var lowercase = note("Lowercase gamma", page: 1, kind: .notation)
        lowercase.lookupTerms = "\\gamma\nx_j"
        XCTAssertEqual(DefinitionLookup.find("\\Gamma", in: [lowercase, capital], near: 8).map(\.id), [capital.id])
        XCTAssertEqual(DefinitionLookup.find("X_j", in: [lowercase, capital], near: 8).map(\.id), [capital.id])
        XCTAssertEqual(DefinitionLookup.find("", in: notes, near: 8).count, 5)
    }

    func testSchemaFourLoadsAndLookupNamesReopenSearchAndExport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = WorkspaceRepository(root: root)
        var original = StudyWorkspace(id: "glossary", title: "Study", sourcePath: "/source.pdf", sourceBookmark: nil, fingerprint: "glossary")
        let entry = note("Design matrix", page: 3, kind: .notation, body: "Each row is an observation.")
        original.notes = [entry]; original.schemaVersion = 4
        original.inkStrokes = [InkStroke(pageIndex: 0, points: [InkPoint(x: 20, y: 30), InkPoint(x: 40, y: 50)])]
        original = try WorkspaceRepository.decoder.decode(StudyWorkspace.self, from: WorkspaceRepository.encoder.encode(original))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: WorkspaceRepository.encoder.encode(original)) as? [String: Any])
        var legacyNote = try XCTUnwrap((json["notes"] as? [[String: Any]])?.first)
        legacyNote.removeValue(forKey: "lookupTerms"); json["notes"] = [legacyNote]
        var migrated = try WorkspaceRepository.decoder.decode(StudyWorkspace.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated, original)
        XCTAssertEqual(migrated.notes[0].lookupTerms, "")
        migrated.notes[0].lookupTerms = "X\nmodel predictors\nβ\n\\beta"; migrated.schemaVersion = 5
        migrated.notes[0].question = "Renamed design"
        try repository.saveImage(Data([1, 2, 3]), workspaceID: migrated.id, name: entry.anchor.imageName)
        try repository.save(migrated)
        let restored = try XCTUnwrap(repository.load(id: migrated.id))
        XCTAssertEqual(restored, migrated)
        XCTAssertEqual(DefinitionLookup.find("X", in: restored.notes, near: 9).map(\.id), [entry.id])
        XCTAssertEqual(NoteSearch.find("model predictors", in: [restored], byMeaning: false).map(\.noteID), [entry.id])
        let exported = root.appendingPathComponent("export")
        try repository.export(restored, to: exported)
        XCTAssertEqual(try WorkspaceRepository.decoder.decode(StudyWorkspace.self, from: Data(contentsOf: exported.appendingPathComponent("workspace.json"))), restored)
        let markdown = try String(contentsOf: exported.appendingPathComponent("Study notes.md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("### Lookup names\n\nX\nmodel predictors\nβ\n\\beta"))
        XCTAssertEqual(try Data(contentsOf: exported.appendingPathComponent("assets/entry.png")), Data([1, 2, 3]))
    }

    private func note(_ title: String, page: Int, kind: NoteKind = .definition, body: String = "") -> StudyNote {
        StudyNote(anchor: SourceAnchor(pageIndex: page, pageLabel: String(page + 1),
            region: PageRegion(x: 20, y: 30, width: 100, height: 40), quote: title, imageName: "entry.png"),
            question: title, body: body, kind: kind)
    }
}
