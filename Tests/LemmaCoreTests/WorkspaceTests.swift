import XCTest
import LemmaCore

final class WorkspaceTests: XCTestCase {
    func testExportLinksPointToEachNotebookWhenTitlesCollide() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = WorkspaceRepository(root: root.appendingPathComponent("library"))
        var workspace = StudyWorkspace(id: "labs", title: "A book", sourcePath: "/a/source.pdf", sourceBookmark: nil, fingerprint: "labs")
        workspace.labs = ["Ridge path", "Ridge path", "Ridge path-2"].enumerated().map { index, title in
            LabNotebook(title: title, cells: [LabCell(source: "print(\(index))")])
        }
        let destination = root.appendingPathComponent("export")
        try repository.export(workspace, to: destination)
        let markdown = try String(contentsOf: destination.appendingPathComponent("Study notes.md"), encoding: .utf8)
        for (notebook, stem) in zip(workspace.labs, ["Ridge path", "Ridge path-2", "Ridge path-2-2"]) {
            let link = try XCTUnwrap(stem.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed))
            XCTAssertTrue(markdown.contains("[\(notebook.title)](labs/\(link).ipynb)"), "Each notebook needs its own exported link.")
            let data = try Data(contentsOf: destination.appendingPathComponent("labs/\(stem).ipynb"))
            let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let cells = try XCTUnwrap(exported["cells"] as? [[String: Any]])
            XCTAssertEqual(cells.first?["source"] as? [String], [notebook.cells[0].source])
            let script = try String(contentsOf: destination.appendingPathComponent("labs/\(stem).py"), encoding: .utf8)
            XCTAssertTrue(script.contains(notebook.cells[0].source))
        }
    }

    func testVersionOneWorkspaceMigratesWithoutLosingStudyAndExportsNewFields() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = WorkspaceRepository(root: root)
        let anchor = SourceAnchor(pageIndex: 3, pageLabel: "iv", region: PageRegion(x: 20, y: 30, width: 120, height: 50), quote: "Design matrix", imageName: "matrix.png")
        var original = StudyWorkspace(id: "legacy", title: "Linear algebra", sourcePath: "/a/source.pdf", sourceBookmark: nil, fingerprint: "legacy")
        var note = StudyNote(anchor: anchor, question: "Why rank?", body: "I checked the kernel.")
        note.explanation = SavedExplanation(body: "$X^\\top X$ is positive definite.")
        original.notes = [note]; original.pins = [ContextPin(label: "Matrix", anchor: anchor)]
        original = try WorkspaceRepository.decoder.decode(StudyWorkspace.self, from: WorkspaceRepository.encoder.encode(original))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: WorkspaceRepository.encoder.encode(original)) as? [String: Any])
        legacy["schemaVersion"] = 1; legacy.removeValue(forKey: "bookmarks"); legacy.removeValue(forKey: "highlights"); legacy.removeValue(forKey: "noteLinks")
        var legacyNote = try XCTUnwrap((legacy["notes"] as? [[String: Any]])?.first)
        for key in ["kind", "state", "assumptions", "notation", "scope", "lookupTerms", "reviewAnswer", "reviewCount", "lastReviewedAt", "sourceTextOrigin", "experiments"] { legacyNote.removeValue(forKey: key) }
        legacy["notes"] = [legacyNote]
        let migrated = try WorkspaceRepository.decoder.decode(StudyWorkspace.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated.notes, original.notes)
        XCTAssertEqual(migrated.pins, original.pins)
        XCTAssertTrue(migrated.bookmarks.isEmpty); XCTAssertTrue(migrated.highlights.isEmpty)
        var updated = migrated
        updated.schemaVersion = 2
        updated.notes[0].kind = .notation; updated.notes[0].state = .revisit
        updated.notes[0].notation = "$X \\in \\mathbb{R}^{n \\times p}$"
        updated.notes[0].scope = "Rows are observations."
        updated.notes[0].assumptions = "Full column rank."
        updated.notes[0].reviewAnswer = "The kernel must be trivial."
        updated.bookmarks = [ReadingBookmark(pageIndex: 3, pageLabel: "iv", title: "Notation")]
        updated.highlights = [StudyHighlight(pageIndex: 3, regions: [anchor.region], quote: anchor.quote, color: .green)]
        updated.reading.layout = .continuous
        try repository.saveImage(Data([1, 2, 3]), workspaceID: updated.id, name: anchor.imageName)
        try repository.save(updated)
        XCTAssertEqual(try repository.load(id: updated.id), updated)
        try repository.export(updated, to: root.appendingPathComponent("export"))
        let text = try String(contentsOf: root.appendingPathComponent("export/Study notes.md"), encoding: .utf8)
        for content in ["Notation", "Revisit", "Full column rank.", "Rows are observations.", "The kernel must be trivial.", "Design matrix", "label iv"] { XCTAssertTrue(text.contains(content), content) }
    }

    func testSavedStudyAndPortableExportLeaveSourceUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.pdf")
        let sourceBytes = Data("source must stay read-only".utf8)
        try sourceBytes.write(to: source)
        let fingerprint = try WorkspaceRepository.fingerprint(of: source)
        let repository = WorkspaceRepository(root: root.appendingPathComponent("library"))
        let anchor = SourceAnchor(pageIndex: 63, pageLabel: "64", region: PageRegion(x: 95, y: 310, width: 270, height: 50), quote: "a formula", imageName: "source.png")
        var workspace = StudyWorkspace(id: fingerprint, title: "A book", sourcePath: source.path, sourceBookmark: nil, fingerprint: fingerprint)
        var note = StudyNote(anchor: anchor, question: "Why is this invertible?", body: "I think rank matters.")
        note.explanation = SavedExplanation(body: "Full column rank is sufficient.", conversationURL: "https://chatgpt.com/c/test")
        note.pendingRequestID = UUID()
        workspace.notes = [note]
        workspace.pins = [ContextPin(label: "Definition", anchor: anchor)]
        workspace.reading.pageIndex = 82
        workspace.reading.positionX = 84
        workspace.reading.positionY = 330
        workspace.reading.returnNote = "Check the dimensions."
        let image = Data([1, 2, 3, 4])
        try repository.saveImage(image, workspaceID: fingerprint, name: anchor.imageName)
        try repository.save(workspace)
        let restored = try XCTUnwrap(repository.load(id: fingerprint))
        XCTAssertEqual(restored.notes[0].id, note.id)
        XCTAssertEqual(restored.notes[0].pendingRequestID, note.pendingRequestID)
        XCTAssertEqual(restored.notes[0].explanation?.body, note.explanation?.body)
        XCTAssertEqual(restored.pins, workspace.pins)
        XCTAssertEqual(restored.reading, workspace.reading)
        let export = root.appendingPathComponent("export")
        try repository.export(restored, to: export)
        XCTAssertEqual(try Data(contentsOf: export.appendingPathComponent("assets/source.png")), image)
        let markdown = try String(contentsOf: export.appendingPathComponent("Study notes.md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("PDF page 64"))
        XCTAssertTrue(markdown.contains("Full column rank"))
        XCTAssertTrue(markdown.contains("Check the dimensions"))
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
    }
}
