import XCTest
import AppKit
import PDFKit
import LemmaCore
@testable import Lemma

final class StudyFlowTests: XCTestCase {
    @MainActor
    func testCaptureEditReopenAndBrowserResultStayWithOriginalNote() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("public-fixture.pdf")
        let image = NSImage(size: NSSize(width: 300, height: 400), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("X transpose X" as NSString).draw(at: CGPoint(x: 30, y: 50), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black])
            return true
        }
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        XCTAssertTrue(document.write(to: source))
        let original = try Data(contentsOf: source)
        let store = StudyStore(app: AppModel(root: root.appendingPathComponent("support")))
        store.open(source)
        store.reader.selection = (0, CGRect(x: 20, y: 35, width: 240, height: 60), "X transpose X")
        store.addNote()
        let firstID = try XCTUnwrap(store.currentNote?.id)
        store.updateNote { $0.question = "Why full column rank?"; $0.body = "I checked the null space." }
        store.pinSelection()
        store.updateReturnNote("Check uniqueness next.")
        let request = BrowserPacket(noteID: firstID, mode: .askAndSave, prompt: store.preparedPrompt, images: [])
        try store.mailbox.prepare(request, imageData: [:])
        store.updateNote { $0.pendingRequestID = request.id }
        store.addNote() // Select another note before the first answer comes back.
        XCTAssertNotEqual(store.selectedNoteID, firstID)
        try store.mailbox.saveResult(BrowserResult(requestID: request.id, status: "complete", answer: "Full column rank makes $X^\\top X$ positive definite.", conversationURL: "https://chatgpt.com/c/fixture"))
        store.pollBrowser()
        store.flush()
        let restored = StudyStore(app: AppModel(root: root.appendingPathComponent("support")))
        restored.open(source)
        let first = try XCTUnwrap(restored.workspace?.notes.first { $0.id == firstID })
        XCTAssertEqual(first.question, "Why full column rank?")
        XCTAssertEqual(first.body, "I checked the null space.")
        XCTAssertNil(first.pendingRequestID)
        XCTAssertTrue(first.explanation?.body.contains("positive definite") == true)
        XCTAssertNil(restored.workspace?.notes.first { $0.id != firstID }?.explanation)
        XCTAssertEqual(restored.workspace?.pins.count, 1)
        XCTAssertEqual(restored.workspace?.reading.returnNote, "Check uniqueness next.")
        let workspace = try XCTUnwrap(restored.workspace)
        let crop = try Data(contentsOf: restored.repository.assetURL(workspaceID: workspace.id, name: first.anchor.imageName))
        XCTAssertNotNil(NSBitmapImageRep(data: crop))
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertNil(store.error)
        XCTAssertNil(restored.error)
    }
}
