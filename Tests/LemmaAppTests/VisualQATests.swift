import XCTest
import AppKit
import PDFKit
import SwiftUI
import LemmaCore
@testable import Lemma

/// Optional snapshots of real windows for visual review. Skipped unless LEMMA_VISUAL_QA_DIR is set.
/// LEMMA_VISUAL_QA_PDF selects the document; support data stays in a temporary directory.
final class VisualQATests: XCTestCase {
    @MainActor
    func testCaptureReaderStatesForReview() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["LEMMA_VISUAL_QA_DIR"] else { throw XCTSkip("Set LEMMA_VISUAL_QA_DIR to capture visual QA snapshots.") }
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let pdf = URL(fileURLWithPath: environment["LEMMA_VISUAL_QA_PDF"] ?? "")
        guard FileManager.default.fileExists(atPath: pdf.path) else { throw XCTSkip("Set LEMMA_VISUAL_QA_PDF to a readable PDF.") }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(previous, forKey: "lastWorkspaceID"); try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(root: root)
        store.urlOpener = { _ in }
        store.open(pdf)
        let window = NSWindow(contentRect: CGRect(x: 40, y: 40, width: 1440, height: 900), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ReaderWindow(store: store).tint(.lemmaOlive))
        window.orderFront(nil)
        defer { store.referencePeek = nil; store.quickAsk = nil; window.close() }
        try await settle(500)

        let page = Int(environment["LEMMA_VISUAL_QA_PAGE"] ?? "34") ?? 34
        store.reader.goToPage(page); store.reader.updatePage()
        try await settle(500)
        snapshot(window.contentView, to: output.appendingPathComponent("01-reader.png"))

        if let index = store.references, let mention = index.mentions(onPage: page - 1).first(where: { !$0.isDefinition && $0.key.kind == .equation })
            ?? index.mentions(onPage: page - 1).first(where: { !$0.isDefinition }) {
            let request = ReferencePeekRequest(workspaceID: store.workspace!.id, mention: mention, pageIndex: page - 1)
            let sizing = PeekSizing(reading: try XCTUnwrap(store.reader.view), popover: true)
            try await capturePane(ReferencePeekPane(store: store, request: request, sizing: sizing, frame: PeekPreviewFrame()), named: "02-peek.png", in: output)
        }

        if let document = store.document, let pdfPage = document.page(at: page - 1) {
            let box = pdfPage.bounds(for: .cropBox)
            let region = CGRect(x: box.minX + 60, y: box.minY + 250, width: box.width - 120, height: 70)
            let request = QuickAskRequest(workspaceID: store.workspace!.id, pageIndex: page - 1, region: region, quote: pdfPage.selection(for: region)?.string ?? "")
            try await capturePane(QuickAskPane(store: store, request: request), named: "04-quick-ask.png", in: output)

            // A note with a cloze mask, due for review.
            store.reader.selection = (page - 1, region, pdfPage.selection(for: region)?.string ?? "")
            store.addNote()
            if let id = store.currentNote?.id {
                store.updateNote(id: id) {
                    $0.question = "Why does k-NN with k = 1 have zero training error?"
                    let half = Double(region.width) / 2
                    $0.masks = [PageRegion(x: Double(region.midX), y: Double(region.minY) + 10, width: half - 10, height: 30)]
                }
                store.addToReview(id: id)
                try await capturePane(ReviewPane(store: store).frame(width: 380, height: 760), named: "05-review.png", in: output)
                store.studySection = .notes
                try await capturePane(StudyPane(store: store).frame(width: 380, height: 1500), named: "06-notebook.png", in: output)
                // Margin cards beside the page in a wide reader.
                store.reader.notes = store.workspace?.notes ?? []; store.reader.selectedNoteID = id
                store.toggleFocus()
                try await settle(600)
                snapshot(window.contentView, to: output.appendingPathComponent("07-focus-margin-cards.png"))
                store.toggleFocus()
            }
            if let note = store.currentNote {
                let parameters = RidgeParameters(lambda: 0, correlation: 0, seed: NeighborsExperimentPane.bookLikeSeed, sampleCount: 200)
                var record = ExperimentRecord(kind: .nearestNeighbors, noteID: note.id, source: note.anchor, prediction: "Training error rises with k; test error is U-shaped.",
                                              observation: "", startingParameters: parameters, parameters: parameters, predictedAt: .now)
                record.neighbors = NeighborsSettings(classifier: .neighbors, k: 15, showBayes: true)
                let pane = NeighborsExperimentPane(noteID: note.id, noteTitle: note.title, source: note.anchor, storedRecord: record) { _ in true }
                try await capturePane(pane.frame(width: 900, height: 1180), named: "10-neighbours.png", in: output, wait: 9000)
            }
            store.closeBook()
            try await settle(400)
            snapshot(window.contentView, to: output.appendingPathComponent("08-home.png"))
            try await capturePane(LibraryHome(store: store).frame(width: 900, height: 760), named: "09-home-pane.png", in: output)
        }
    }

    /// Renders a pane in an opaque dark window: popover materials do not survive cacheDisplay.
    @MainActor
    private func capturePane<Content: View>(_ pane: Content, named name: String, in output: URL, wait: Int = 1200) async throws {
        let host = NSHostingView(rootView: pane.tint(.lemmaOlive).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: CGRect(x: 80, y: 80, width: 640, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.setFrameSize(host.fittingSize)
        window.setContentSize(host.fittingSize)
        window.orderFront(nil)
        defer { window.close() }
        try await settle(wait)
        host.setFrameSize(host.fittingSize)
        window.setContentSize(host.fittingSize)
        try await settle(200)
        snapshot(host, to: output.appendingPathComponent(name))
    }

    @MainActor
    private func settle(_ milliseconds: Int) async throws {
        // Sleeping on the main actor lets the run loop lay out, present popovers and resolve references.
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    /// cacheDisplay draws AppKit and SwiftUI views; PDFKit's tiled page layers and window materials need help.
    @MainActor
    private func snapshot(_ view: NSView?, to url: URL) {
        guard let view, view.bounds.width > 0, view.bounds.height > 0 else { return }
        view.layoutSubtreeIfNeeded()
        guard let cached = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: cached)
        let size = view.bounds.size
        guard let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cached.pixelsWide, pixelsHigh: cached.pixelsHigh, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: output) else { return }
        output.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(cached.pixelsWide) / size.width, y: CGFloat(cached.pixelsHigh) / size.height)
        view.effectiveAppearance.performAsCurrentDrawingAppearance { NSColor.windowBackgroundColor.setFill() }
        CGRect(origin: .zero, size: size).fill()
        // Pages first: the cached bitmap is transparent over PDF views, so the reader's overlay draws on top.
        for pdfView in Self.pdfViews(in: view) {
            var visible = view.convert(pdfView.bounds, from: pdfView)
            if view.isFlipped { visible.origin.y = size.height - visible.maxY }
            pdfView.effectiveAppearance.performAsCurrentDrawingAppearance { pdfView.backgroundColor.setFill() }
            visible.fill()
            for page in pdfView.visiblePages {
                let box = page.bounds(for: .cropBox)
                var rect = view.convert(pdfView.convert(box, from: page), from: pdfView)
                if view.isFlipped { rect.origin.y = size.height - rect.maxY }
                let cg = context.cgContext
                cg.saveGState()
                cg.clip(to: visible)
                cg.setFillColor(NSColor.white.cgColor); cg.fill(rect)
                cg.translateBy(x: rect.minX, y: rect.minY)
                cg.scaleBy(x: rect.width / box.width, y: rect.height / box.height)
                page.draw(with: .cropBox, to: cg)
                cg.restoreGState()
            }
        }
        cached.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? output.representation(using: .png, properties: [:])?.write(to: url)
    }

    @MainActor
    private static func pdfViews(in view: NSView) -> [PDFView] {
        (view as? PDFView).map { [$0] } ?? view.subviews.flatMap { pdfViews(in: $0) }
    }
}
