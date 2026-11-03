import XCTest
import AppKit
import PDFKit
@testable import Lemma

/// ← and → turn the page in the main and side editors, at any zoom, as in PDFgear.
final class PageTurnTests: XCTestCase {
    /// Twelve 4:3 slides, as a Beamer deck has.
    private func deck() throws -> PDFDocument {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 364, height: 273)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: data)), mediaBox: &box, nil))
        for _ in 0..<12 { context.beginPDFPage(nil); context.endPDFPage() }
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: data as Data))
    }

    @MainActor
    private func arrow(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], in view: NSView) throws -> NSEvent {
        let key = String(UnicodeScalar(keyCode == 123 ? NSLeftArrowFunctionKey : NSRightArrowFunctionKey)!)
        return try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers.union([.function, .numericPad]),
                                              timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil,
                                              characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode))
    }

    /// The page at the top of the view, the left one of a spread, and the point of it at the view's top left corner.
    @MainActor
    private func top(of view: PDFView) throws -> (page: Int, point: CGPoint) {
        let page = try XCTUnwrap(view.page(for: CGPoint(x: view.bounds.minX + view.bounds.width / 4, y: view.bounds.maxY - 1), nearest: true))
        return (try XCTUnwrap(view.document).index(for: page), view.convert(CGPoint(x: view.bounds.minX, y: view.bounds.maxY), to: page))
    }

    /// Scrolls `point` of a page to the view's top left corner, as far as the pages go, as the reader's scroll does: unlike
    /// PDFKit's `go(to:)`, without a place for Back to return to.
    @MainActor
    private func scroll(_ view: PDFView, toPage index: Int, at point: CGPoint) throws {
        let scrollView = try XCTUnwrap(view.documentView?.enclosingScrollView)
        let clip = scrollView.contentView
        let moved = clip.convert(view.convert(point, from: try XCTUnwrap(view.document?.page(at: index))), from: view)
        let held = clip.convert(CGPoint(x: view.bounds.minX, y: view.bounds.maxY), from: view)
        let origin = CGPoint(x: clip.bounds.minX + moved.x - held.x, y: clip.bounds.minY + moved.y - held.y)
        clip.scroll(to: clip.constrainBoundsRect(CGRect(origin: origin, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    @MainActor
    private func window(for view: PDFView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        view.frame = window.contentLayoutRect
        window.contentView = view
        return window
    }

    @MainActor
    func testArrowsTurnTheReadersPageInEveryLayoutAndAtAnyZoom() throws {
        let document = try deck()
        for (mode, step) in [(PDFDisplayMode.singlePage, 1), (.singlePageContinuous, 1), (.twoUp, 2), (.twoUpContinuous, 2)] {
            // Fitted, and zoomed past the width of the view, scrolled across it.
            for scale in [CGFloat(0), 2.5] {
                let view = RegionPDFView()
                let window = window(for: view)
                defer { window.close() }
                view.displayMode = mode
                view.displaysPageBreaks = true
                view.document = document
                if scale == 0 { view.autoScales = true } else { view.scaleFactor = scale }
                view.layoutDocumentView()
                try scroll(view, toPage: 0, at: CGPoint(x: scale == 0 ? 0 : 120, y: 273))
                let start = try top(of: view).point
                let label = "\(mode.rawValue) at \(scale == 0 ? "fit" : "250%")"

                view.keyDown(with: try arrow(124, in: view))
                XCTAssertEqual(try top(of: view).page, step, label)
                XCTAssertEqual(try top(of: view).point.y, start.y, accuracy: 2, "The next page's top is where the first one's was: \(label).")
                XCTAssertEqual(try top(of: view).point.x, start.x, accuracy: 2, "Scrolled as far across as before: \(label).")
                view.keyDown(with: try arrow(124, in: view))
                XCTAssertEqual(try top(of: view).page, 2 * step, label)
                view.keyDown(with: try arrow(123, in: view))
                XCTAssertEqual(try top(of: view).page, step, label)
                view.keyDown(with: try arrow(123, in: view))
                view.keyDown(with: try arrow(123, in: view))
                XCTAssertEqual(try top(of: view).page, 0, "← on the first page stays there: \(label).")
                if mode == .singlePageContinuous || mode == .twoUpContinuous {
                    XCTAssertFalse(view.canGoBack, "Turning a page as it scrolls leaves Back to the places jumped from: \(label).")
                }
            }
        }
    }

    @MainActor
    func testLeftArrowFromPartwayDownAPageGoesToThePageBefore() throws {
        let document = try deck()
        let view = RegionPDFView()
        let window = window(for: view)
        defer { window.close() }
        view.displayMode = .singlePageContinuous
        view.document = document
        view.scaleFactor = 4
        view.layoutDocumentView()
        try scroll(view, toPage: 3, at: CGPoint(x: 0, y: 150))
        XCTAssertEqual(try top(of: view).page, 3)

        view.keyDown(with: try arrow(123, in: view))
        XCTAssertEqual(try top(of: view).page, 2)
        XCTAssertEqual(try top(of: view).point.y, 273, accuracy: 2)
        try scroll(view, toPage: 3, at: CGPoint(x: 0, y: 150))
        view.keyDown(with: try arrow(124, in: view))
        XCTAssertEqual(try top(of: view).page, 4)
    }

    @MainActor
    func testArrowsWithAModifierAreLeftAlone() throws {
        let view = RegionPDFView()
        let window = window(for: view)
        defer { window.close() }
        view.displayMode = .singlePageContinuous
        view.document = try deck()
        view.autoScales = true
        view.layoutDocumentView()
        for modifiers: NSEvent.ModifierFlags in [.shift, .option, .command, .control] {
            XCTAssertNil(PDFView.pageTurn(for: try arrow(124, modifiers: modifiers, in: view)), "⌥⌘← is Back, and the others are not page turns.")
        }
        XCTAssertEqual(PDFView.pageTurn(for: try arrow(123, in: view)), -1)
        XCTAssertEqual(PDFView.pageTurn(for: try arrow(124, in: view)), 1)
    }

    @MainActor
    func testArrowsTurnTheSideEditorsPage() throws {
        let document = try deck()
        let view = SecondaryPDFView()
        let window = window(for: view)
        defer { window.close() }
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = document
        view.autoScales = true
        view.layoutDocumentView()

        view.keyDown(with: try arrow(124, in: view))
        XCTAssertEqual(try top(of: view).page, 1)
        view.keyDown(with: try arrow(123, in: view))
        XCTAssertEqual(try top(of: view).page, 0)
    }
}
