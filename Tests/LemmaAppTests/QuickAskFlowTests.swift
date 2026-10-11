import XCTest
import AppKit
import PDFKit
import LemmaCore
@testable import Lemma

final class QuickAskFlowTests: XCTestCase {
    @MainActor
    func testQuickAskSavesTheSourceAndSendsTheChosenContextOnly() async throws {
        let (store, source) = try openFixture()
        var opened: [URL] = []
        store.urlOpener = { opened.append($0) }
        let original = try Data(contentsOf: source)

        // A glossary entry from page 1, whose name appears in the later passage.
        store.reader.selection = (0, CGRect(x: 240, y: 498, width: 120, height: 22), "y = Xβ + ε,")
        store.reader.hasSelection = true
        store.addNote(kind: .notation)
        let glossaryID = try XCTUnwrap(store.currentNote?.id)
        store.updateNote { $0.question = "Linear model"; $0.lookupTerms = "coefficients"; $0.notation = "β ∈ ℝᵖ"; $0.body = "Private: I still doubt this." }
        store.reader.selection = (1, CGRect(x: 72, y: 372, width: 420, height: 34), "FIGURE 1.1. A fitted line")
        store.pinSelection()
        store.toggleFocus()

        let quote = "Returning to the general case, the model (1.1) is linear in its coefficients"
        store.reader.selection = (2, CGRect(x: 70, y: 596, width: 470, height: 18), quote)
        store.reader.hasSelection = true
        store.prepareQuickAsk()
        let request = try XCTUnwrap(store.quickAsk)
        XCTAssertEqual(store.workspace?.notes.count, 1, "Opening the quick question saves nothing yet.")

        let candidates = await store.contextCandidates(pageIndex: request.pageIndex, region: PageRegion(request.region), quote: request.quote, noteID: nil)
        XCTAssertEqual(candidates.cited.map(\.target.key.spokenTitle), ["Equation (1.1)"])
        XCTAssertEqual(candidates.cited.first?.target.pageIndex, 0)
        XCTAssertNotNil(NSBitmapImageRep(data: try XCTUnwrap(candidates.cited.first?.png)))
        XCTAssertEqual(candidates.glossary.map(\.id), [glossaryID])
        var selection = ContextSelection.defaults(for: candidates)
        XCTAssertEqual(selection.imageCount, 3, "Source, the cited equation and the pin.")
        selection.pins = []

        store.sendQuickAsk(request, question: "", style: .nextStep, candidates: candidates, selection: selection, mode: .draft)
        XCTAssertNil(store.quickAsk)
        let note = try XCTUnwrap(store.currentNote)
        XCTAssertEqual(note.question, QuestionStyle.nextStep.defaultQuestion)
        XCTAssertEqual(note.anchor.pageIndex, 2)
        XCTAssertEqual(note.anchor.quote, quote)
        let requestID = try XCTUnwrap(note.pendingRequestID)
        XCTAssertEqual(opened.map(\.absoluteString), ["https://chatgpt.com/#lemma=\(requestID.uuidString)"])
        let packet = try store.mailbox.packet(requestID)
        XCTAssertEqual(packet.mode, .draft)
        XCTAssertEqual(packet.images.map(\.label), ["Source A", "Cited: Equation (1.1)"])
        for expected in ["Text of Source A", quote, "Image 2: Equation (1.1), PDF page 1", "Linear model (written coefficients): β ∈ ℝᵖ", QuestionStyle.nextStep.instruction] {
            XCTAssertTrue(packet.prompt.contains(expected), expected)
        }
        XCTAssertFalse(packet.prompt.contains("Private: I still doubt this."), "Glossary reasoning stays local.")
        XCTAssertFalse(packet.prompt.contains("FIGURE 1.1"), "An unticked pin is not shared.")
        XCTAssertTrue(store.focusMode, "A quick question keeps the reading layout.")
        XCTAssertFalse(store.showStudy)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    @MainActor
    func testSelectedEquationIsNotItsOwnCitationAndFullDraftCarriesTheChoices() async throws {
        let (store, _) = try openFixture()
        store.urlOpener = { _ in XCTFail("Preparing a full draft must not open Chrome.") }
        let region = CGRect(x: 230, y: 495, width: 320, height: 30)
        let quote = store.document?.page(at: 0)?.selection(for: region)?.string ?? ""
        XCTAssertTrue(quote.contains("(1.1)"))
        let candidates = await store.contextCandidates(pageIndex: 0, region: PageRegion(region), quote: quote, noteID: nil)
        XCTAssertTrue(candidates.cited.isEmpty, "A selected equation contains its own label; it is the source, not a citation.")

        store.reader.selection = (0, region, quote); store.reader.hasSelection = true
        store.prepareQuickAsk()
        let request = try XCTUnwrap(store.quickAsk)
        var selection = ContextSelection.defaults(for: candidates)
        selection.sourceText = false
        store.openFullDraft(request, question: "Why is ε additive?", style: .assumptions, candidates: candidates, selection: selection)
        XCTAssertTrue(store.showQuestion)
        let preset = try XCTUnwrap(store.questionPreset)
        XCTAssertEqual(preset.noteID, store.currentNote?.id)
        XCTAssertEqual(preset.style, .assumptions)
        XCTAssertFalse(preset.selection.sourceText)
        XCTAssertEqual(store.currentNote?.question, "Why is ε additive?")
        XCTAssertNil(store.currentNote?.pendingRequestID)
    }

    @MainActor
    private func openFixture() throws -> (StudyStore, URL) {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        addTeardownBlock {
            UserDefaults.standard.set(previous, forKey: "lastWorkspaceID")
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("quick.pdf")
        let bytes = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: bytes)), mediaBox: &box, nil))
        let font = NSFont(name: "Times New Roman", size: 12) ?? NSFont.systemFont(ofSize: 12)
        func page(_ lines: [(String, Double, Double, Bool)]) {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSColor.white.setFill(); box.fill()
            for (string, x, y, right) in lines {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
                let width = (string as NSString).size(withAttributes: attributes).width
                (string as NSString).draw(at: CGPoint(x: right ? x - width : x, y: y), withAttributes: attributes)
            }
            NSGraphicsContext.restoreGraphicsState(); context.endPDFPage()
        }
        page([("Linear models describe the response as a weighted sum of the inputs, and", 72, 580, false),
              ("we estimate the weights by least squares. The model is written as", 72, 564, false),
              ("y = Xβ + ε,", 250, 505, false), ("(1.1)", 540, 505, true),
              ("where the noise has mean zero and the inputs are measured without error", 72, 450, false)])
        page([("FIGURE 1.1. A fitted line through simulated data. The line is the least", 72, 390, false),
              ("squares fit of the response on a single input.", 72, 376, false)])
        page([("Returning to the general case, the model (1.1) is linear in its coefficients", 72, 600, false),
              ("and Figure 1.1 shows a fitted example, which we revisit in the exercises", 72, 584, false)])
        context.closePDF()
        try (bytes as Data).write(to: source)
        let store = StudyStore(root: root.appendingPathComponent("support"))
        store.open(source)
        return (store, source)
    }
}

final class ReviewFlowTests: XCTestCase {
    @MainActor
    func testReviewDeckSchedulingAndClozeMasksOnThePage() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(previous, forKey: "lastWorkspaceID"); try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("review.pdf")
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 400, height: 300), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("RSS(β) = (y − Xβ)ᵀ(y − Xβ)" as NSString).draw(at: CGPoint(x: 30, y: 150), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
            return true
        }
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        XCTAssertTrue(document.write(to: source))
        let store = StudyStore(root: root.appendingPathComponent("support"))
        store.open(source)
        store.reader.selection = (0, CGRect(x: 20, y: 140, width: 330, height: 40), "")
        store.addNote()
        let id = try XCTUnwrap(store.currentNote?.id)
        XCTAssertTrue(store.reviewNotes.isEmpty)

        store.addToReview(id: id)
        XCTAssertEqual(store.reviewNotes.map(\.id), [id])
        XCTAssertEqual(store.currentNote?.state, .revisit)
        let anchor = try XCTUnwrap(store.currentNote?.anchor)
        let right = PageRegion(x: 190, y: 145, width: 150, height: 30)
        store.updateNote(id: id) { $0.masks = [right]; $0.recallPrompt = "Write RSS in matrix form." }

        let view = RegionPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
        view.controller = store.reader; store.reader.view = view; view.document = store.document
        view.displayMode = .singlePage; view.autoScales = true
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close() }
        view.layoutDocumentView(); view.layoutSubtreeIfNeeded()
        store.reader.recallMaskRegions = [right]; store.reader.recallMask = anchor
        let overlay = try XCTUnwrap(view.subviews.compactMap { $0 as? RegionSelectionOverlay }.first)
        XCTAssertEqual(overlay.recallRectangles.count, 1)
        let page = try XCTUnwrap(store.document?.page(at: 0))
        XCTAssertEqual(overlay.recallRectangles.first, view.convert(right.rect, from: page), "Only the cloze part is hidden on the page.")
        store.reader.recallMaskRegions = []
        XCTAssertEqual(overlay.recallRectangles.first, view.convert(anchor.region.rect, from: page), "Without masks the whole source is hidden.")
        store.reader.recallMask = nil
        XCTAssertTrue(overlay.recallRectangles.isEmpty)

        store.grade(id: id, .good)
        XCTAssertTrue(store.reviewNotes.isEmpty, "A good recall schedules the note for later.")
        XCTAssertEqual(store.reviewDeck.map(\.id), [id])
        XCTAssertEqual(store.currentNote?.state, .understood)
        let reopened = StudyStore(root: root.appendingPathComponent("support"))
        reopened.open(source)
        let saved = try XCTUnwrap(reopened.workspace?.notes.first)
        XCTAssertEqual(saved.masks, [right])
        XCTAssertEqual(saved.recallPrompt, "Write RSS in matrix form.")
        XCTAssertEqual(saved.review?.interval, 1)
        store.removeFromReview(id: id)
        XCTAssertTrue(store.reviewDeck.isEmpty)

        let size = CGSize(width: 330, height: 40)
        let drawn = CGRect(x: 170, y: 5, width: 150, height: 30)
        let region = MaskGeometry.pageRegion(for: drawn, in: anchor.region, size: size)
        let back = MaskGeometry.viewRect(for: region, in: anchor.region, size: size)
        XCTAssertEqual(back.minX, drawn.minX, accuracy: 0.001); XCTAssertEqual(back.minY, drawn.minY, accuracy: 0.001)
        XCTAssertEqual(back.width, drawn.width, accuracy: 0.001); XCTAssertEqual(back.height, drawn.height, accuracy: 0.001)
        XCTAssertEqual(region.y + region.height, anchor.region.y + anchor.region.height - 5, accuracy: 0.001, "The top of the crop is the top of the page region.")
    }
}
