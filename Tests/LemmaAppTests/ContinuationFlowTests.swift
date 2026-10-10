import XCTest
import AppKit
import PDFKit
import LemmaCore
@testable import Lemma

final class ContinuationFlowTests: XCTestCase {
    @MainActor
    func testScannedSourceLinkedStudyAndExperimentRemainWithTheirOriginalNotes() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldLastWorkspace = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(oldLastWorkspace, forKey: "lastWorkspaceID") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("scanned-study.pdf")
        let image = NSImage(size: NSSize(width: 600, height: 360), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black]
            ("Full column rank gives unique coefficients." as NSString).draw(at: CGPoint(x: 25, y: 230), withAttributes: attributes)
            ("Compare the source before using OCR text." as NSString).draw(at: CGPoint(x: 25, y: 185), withAttributes: attributes)
            return true
        }
        let pdf = PDFDocument()
        pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        XCTAssertTrue(pdf.write(to: source))
        let sourceBytes = try Data(contentsOf: source)
        let support = root.appendingPathComponent("support")
        let store = StudyStore(root: support)
        store.open(source)
        XCTAssertTrue(store.document?.page(at: 0)?.string?.isEmpty ?? true, "This fixture must need image recognition.")
        store.reader.selection = (0, CGRect(x: 15, y: 170, width: 570, height: 100), "")
        store.addNote()
        let originalID = try XCTUnwrap(store.currentNote?.id)
        store.updateNote { $0.question = "When is the coefficient unique?"; $0.body = "My original reasoning stays here." }
        let originalAnchor = try XCTUnwrap(store.currentNote?.anchor)
        store.prepareOCR(useSelection: true)
        let regionCapture = try XCTUnwrap(store.ocrCapture)
        XCTAssertEqual(regionCapture.anchor.region, originalAnchor.region)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.repository.assetURL(workspaceID: regionCapture.workspaceID, name: regionCapture.anchor.imageName).path), "Cancelling recognition must not save a source crop.")
        store.prepareOCR(useSelection: false)
        let fullPage = try XCTUnwrap(store.ocrCapture)
        XCTAssertGreaterThan(fullPage.anchor.region.height, regionCapture.anchor.region.height)
        let recognized = try await RegionTextRecognizer.recognize(png: fullPage.pngData)
        XCTAssertTrue(recognized.contains("Full column rank"))
        let reviewedText = recognized + "\nReader correction: check the coefficient condition."
        store.createNoteFromOCR(fullPage, text: reviewedText)
        let ocrNote = try XCTUnwrap(store.currentNote)
        XCTAssertNil(store.ocrCapture)
        XCTAssertEqual(ocrNote.sourceTextOrigin, .ocr)
        XCTAssertEqual(ocrNote.anchor.quote, reviewedText)
        XCTAssertTrue(ocrNote.body.isEmpty, "Source transcription must remain distinct from personal reasoning.")
        store.updateNote { $0.question = "Full column rank"; $0.kind = .definition }
        let link = try XCTUnwrap(store.addNoteLink(from: originalID, to: ocrNote.id, kind: .assumption, usage: "Check the premise for uniqueness."))
        XCTAssertEqual(link.targetNoteID, ocrNote.id)
        let record = ExperimentRecord(noteID: originalID, source: originalAnchor,
            prediction: "Regularization should shrink the coefficient norm.", observation: "The fit changed as lambda grew.",
            startingParameters: RidgeParameters(lambda: 0), parameters: RidgeParameters(lambda: 10),
            predictedAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertTrue(store.saveExperiment(record, workspaceID: try XCTUnwrap(store.workspace?.id)))
        XCTAssertEqual(store.selectedNoteID, ocrNote.id, "A saved experiment must not move selection.")
        XCTAssertTrue(store.currentNote?.experiments.isEmpty == true)
        let original = try XCTUnwrap(store.workspace?.notes.first { $0.id == originalID })
        XCTAssertEqual(original.body, "My original reasoning stays here.")
        XCTAssertEqual(original.experiments.first?.id, record.id)
        XCTAssertFalse(store.preparedPrompt.contains(record.prediction), "Experiments are not automatically sent to the provider.")
        store.flush()
        let restored = StudyStore(root: support); restored.open(source)
        let workspace = try XCTUnwrap(restored.workspace)
        XCTAssertEqual(workspace.schemaVersion, 10)
        XCTAssertEqual(workspace.noteLinks.map(\.id), [link.id])
        XCTAssertEqual(workspace.notes.first { $0.id == originalID }?.experiments.first?.parameters.lambda, 10)
        XCTAssertEqual(workspace.notes.first { $0.id == ocrNote.id }?.anchor.quote, reviewedText)
        XCTAssertTrue(workspace.notes.first { $0.id == ocrNote.id }?.matches("Reader correction") == true)
        let destination = root.appendingPathComponent("export")
        try restored.repository.export(workspace, to: destination)
        let markdown = try String(contentsOf: destination.appendingPathComponent("Study notes.md"), encoding: .utf8)
        for expected in ["Recognized source text (local OCR)", reviewedText, "#\(ocrNote.markdownAnchor)", record.prediction,
                         "Seed: 17", "RSS is a sum", "training MSE"] { XCTAssertTrue(markdown.contains(expected), expected) }
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("assets/\(ocrNote.anchor.imageName)")), fullPage.pngData)
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
        XCTAssertNil(store.error); XCTAssertNil(restored.error)
    }
}
