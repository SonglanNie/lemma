import XCTest
import AppKit
import PDFKit
import SwiftUI
import Observation
import os
import LemmaCore
@testable import Lemma

final class PerformanceRegressionTests: XCTestCase {
    @MainActor
    func testScrubbingDefersColdTextGeometryAndKeepsRecallMasked() async throws {
        let fixture = try WorkbenchFixture(hosted: true)
        defer { fixture.close() }
        fixture.store.open(fixture.book)
        try await fixture.waitForAnalysis()
        try await fixture.settle()
        let store = fixture.store
        let view = try XCTUnwrap(store.reader.view)
        let page = try XCTUnwrap(store.document?.page(at: 3))
        store.reader.beginScrubbing()
        XCTAssertTrue(store.reader.readingLines(onPage: 3).isEmpty,
                      "Unvisited pages should not extract PDF text on the input path.")
        let anchor = SourceAnchor(pageIndex: 3, pageLabel: "3", region: PageRegion(CGRect(x: 72, y: 480, width: 180, height: 60)),
                                  quote: "hidden answer", imageName: "")
        store.reader.recallMask = anchor
        view.go(to: page)
        try await fixture.settle(100)
        view.refreshCaptureOverlay()
        XCTAssertTrue(view.visiblePages.contains(page))
        let overlay = try XCTUnwrap(view.subviews.compactMap { $0 as? RegionSelectionOverlay }.first)
        XCTAssertNotNil(overlay.recallRectangle, "Recall masks must still follow the page during the drag.")
        store.reader.endScrubbing()
        XCTAssertFalse(store.reader.readingLines(onPage: 3).isEmpty)
        XCTAssertNotNil(overlay.recallRectangle)
    }

    @MainActor
    func testUnchangedInkDoesNotInvalidateDependentViews() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        fixture.store.open(fixture.book)
        let document = try XCTUnwrap(fixture.store.document)
        let reader = fixture.store.reader
        reader.syncInk([], in: document)
        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking { _ = reader.inkStrokes } onChange: { changes.withLock { $0 += 1 } }
        for _ in 0..<100 { reader.syncInk([], in: document) }
        XCTAssertEqual(changes.withLock { $0 }, 0)
    }

    @MainActor
    func testClosedNotebookEditorIsReleasedAndRunStillPublishesItsText() async throws {
        _ = NSApplication.shared
        weak var released: LabTextView?
        var text = "print(3)"
        var ran = false
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 200), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var host: NSHostingView<AnyView>? = NSHostingView(rootView: AnyView(LabCodeEditor(
            text: Binding(get: { text }, set: { text = $0 }), onRun: { _ in ran = true })))
        window.contentView = host
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        autoreleasepool {
            guard let editor = findEditor(in: host!) else { XCTFail("The notebook's native editor must be mounted."); return }
            editor.onRun?(.run)
            XCTAssertEqual(text, "print(3)")
            XCTAssertTrue(ran)
            released = editor
        }
        host?.rootView = AnyView(EmptyView())
        host?.layoutSubtreeIfNeeded()
        window.makeFirstResponder(nil)
        window.contentView = nil
        window.close()
        host = nil
        // AppKit and SwiftUI finish removing the text input/layout graph asynchronously.
        let deadline = Date.now.addingTimeInterval(6)
        while released != nil, Date.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNil(released, "The editor must release after AppKit finishes closing it.")
    }

    @MainActor private func findEditor(in view: NSView) -> LabTextView? {
        if let editor = view as? LabTextView { return editor }
        return view.subviews.lazy.compactMap { self.findEditor(in: $0) }.first
    }

    @MainActor
    func testNotebookHeightStaysCorrectAfterTextWidthAndFontChanges() {
        let editor = LabTextView(usingTextLayoutManager: false)
        editor.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.string = "prediction = model.predict(X_test)"
        let first = editor.height(forWidth: 400)
        XCTAssertEqual(editor.height(forWidth: 400), first)
        editor.string += String(repeating: "\n# a longer line describing how predictions compare against the observations", count: 12)
        let longer = editor.height(forWidth: 400)
        XCTAssertGreaterThan(longer, first)
        let narrow = editor.height(forWidth: 170)
        XCTAssertGreaterThan(narrow, longer, "A cached measurement must not clip newly wrapped lines.")
        editor.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)
        XCTAssertGreaterThan(editor.height(forWidth: 170), narrow)
        let expected = LabTextView(usingTextLayoutManager: false)
        expected.font = editor.font
        expected.textStorage?.setAttributedString(editor.textStorage!)
        XCTAssertEqual(editor.height(forWidth: 170), expected.height(forWidth: 170))
    }

    @MainActor
    func testScrollingWithinAPageKeepsTheWorkspaceQuietAndStillSaves() async throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        let before = try XCTUnwrap(store.workspace).reading
        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking { _ = store.workspace } onChange: { changes.withLock { $0 += 1 } }
        for _ in 0..<20 { store.reader.onReadingChanged?(before.pageIndex, before.scale) }
        XCTAssertEqual(changes.withLock { $0 }, 0, "A scroll within the same page must not rebuild the workspace's views.")
        XCTAssertTrue(store.isSaving)
        store.reader.onReadingChanged?(2, 1.8)
        XCTAssertEqual(store.workspace?.reading.pageIndex, 2)
        XCTAssertEqual(store.workspace?.reading.scale, 1.8)
        try await fixture.settle(500)
        let saved = try XCTUnwrap(try store.repository.load(id: store.workspace!.id))
        XCTAssertEqual(saved.reading.pageIndex, 2)
        XCTAssertEqual(saved.reading.scale, 1.8)
        XCTAssertFalse(store.isSaving)
    }

    @MainActor
    func testBackgroundThumbnailKeepsRotationAnnotationsAndNightRendering() async throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let previous = PageThemeState.shared.theme
        defer { PageThemeState.shared.theme = previous }
        fixture.store.open(fixture.book)
        let page = try XCTUnwrap(fixture.store.document?.page(at: 1))
        let size = CGSize(width: 168, height: 224)
        PageThemeState.shared.theme = .paper
        page.rotation = 90
        let annotation = PDFAnnotation(bounds: CGRect(x: 150, y: 400, width: 90, height: 60), forType: .square, withProperties: nil)
        annotation.interiorColor = .red
        page.addAnnotation(annotation)
        let expected = try XCTUnwrap(page.thumbnail(of: size, for: .cropBox).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let snapshot = try XCTUnwrap(MinimapPageSnapshot(page: page))
        // Mutating the live page while the worker runs must not mutate the captured page.
        page.rotation = 0
        page.removeAnnotation(annotation)
        let rendered = await Task.detached { snapshot.render(size: size) }.value
        let result = try XCTUnwrap(rendered)
        XCTAssertEqual(png(result.image), png(expected))

        PageThemeState.shared.theme = .night
        let nightExpected = try XCTUnwrap(page.thumbnail(of: size, for: .cropBox).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let nightSnapshot = try XCTUnwrap(MinimapPageSnapshot(page: page))
        let nightRendered = await Task.detached { nightSnapshot.render(size: size) }.value
        let night = try XCTUnwrap(nightRendered)
        XCTAssertEqual(png(night.image), png(nightExpected))
    }

    @MainActor private func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
