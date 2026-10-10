import XCTest
import AppKit
import PDFKit
@testable import Lemma

final class MinimapInteractionTests: XCTestCase {
    @MainActor
    func testSliderMovesWithThePointerAcrossALongBook() async throws {
        let fixture = try MinimapFixture()
        defer { fixture.close() }
        try await fixture.settle()
        fixture.scroll(to: 0.4)
        let before = fixture.sliderTop
        let start = before + fixture.sliderHeight / 2
        fixture.minimap.mouseDown(with: try fixture.event(.leftMouseDown, y: start))
        fixture.minimap.mouseDragged(with: try fixture.event(.leftMouseDragged, y: start + 40))
        try await fixture.waitForSlider(at: before + 40)
        XCTAssertEqual(fixture.sliderTop - before, 40, accuracy: 1,
                       "The moving miniature strip must be included in the drag's scale.")
        fixture.minimap.mouseDragged(with: try fixture.event(.leftMouseDragged, y: start - 25))
        try await fixture.waitForSlider(at: before - 25)
        XCTAssertEqual(fixture.sliderTop - before, -25, accuracy: 1, "Reversing a drag must track the pointer too.")
        fixture.minimap.mouseUp(with: try fixture.event(.leftMouseUp, y: start - 25))
    }

    @MainActor
    func testClickThenDragUsesOneAnchorInsteadOfRepeatedJumps() async throws {
        let fixture = try MinimapFixture()
        defer { fixture.close() }
        try await fixture.settle()
        fixture.scroll(to: 0.4)
        let click = min(650, fixture.sliderTop + fixture.sliderHeight + 120)
        fixture.minimap.mouseDown(with: try fixture.event(.leftMouseDown, y: click))
        let afterClick = fixture.sliderTop
        fixture.minimap.mouseDragged(with: try fixture.event(.leftMouseDragged, y: click + 20))
        try await fixture.waitForSlider(at: afterClick + 20)
        XCTAssertEqual(fixture.sliderTop - afterClick, 20, accuracy: 1)
        fixture.minimap.mouseDragged(with: try fixture.event(.leftMouseDragged, y: click + 40))
        try await fixture.waitForSlider(at: afterClick + 40)
        XCTAssertEqual(fixture.sliderTop - afterClick, 40, accuracy: 1)
        fixture.minimap.mouseUp(with: try fixture.event(.leftMouseUp, y: click + 40))
    }

    @MainActor
    func testSinglePageSliderDragChangesPages() async throws {
        let fixture = try MinimapFixture()
        defer { fixture.close() }
        fixture.view.displayMode = .singlePage
        try await fixture.settle()
        fixture.controller.goToPage(20)
        fixture.controller.updatePage()
        let start = fixture.sliderTop + fixture.sliderHeight / 2
        fixture.minimap.mouseDown(with: try fixture.event(.leftMouseDown, y: start))
        fixture.minimap.mouseDragged(with: try fixture.event(.leftMouseDragged, y: start + 60))
        // The drag navigates on the next frame's timer, which a busy or headless machine (CI) can fire late.
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(20))
            fixture.controller.updatePage()
            if fixture.controller.pageNumber > 21 { break }
        }
        XCTAssertGreaterThan(fixture.controller.pageNumber, 21,
                             "Single-page mode must navigate the book rather than scroll inside the current page.")
        fixture.minimap.mouseUp(with: try fixture.event(.leftMouseUp, y: start + 60))
    }

    @MainActor
    func testDragKeepsThePageAndReadingDestinationInTheVisiblePages() async throws {
        let fixture = try MinimapFixture()
        defer { fixture.close() }
        try await fixture.settle()
        fixture.scroll(to: 0.4)
        let start = fixture.sliderTop + fixture.sliderHeight / 2
        fixture.minimap.mouseDown(with: try fixture.event(.leftMouseDown, y: start))
        fixture.minimap.mouseDragged(with: try fixture.event(.leftMouseDragged, y: start + 40))
        fixture.minimap.mouseUp(with: try fixture.event(.leftMouseUp, y: start + 40))
        try await fixture.settle()
        let visible = Set(fixture.view.visiblePages.map { fixture.document.index(for: $0) })
        XCTAssertTrue(visible.contains(fixture.controller.pageNumber - 1), "The status bar must follow a minimap drag.")
        let page = try XCTUnwrap(fixture.view.currentDestination?.page)
        XCTAssertTrue(visible.contains(fixture.document.index(for: page)), "The saved destination must belong to a visible page.")
        XCTAssertEqual(fixture.view.scaleFactor, 1, accuracy: 0.001)
    }

    @MainActor
    func testFastInputIsCoalescedAndReleaseUsesTheLatestPoint() async throws {
        let fixture = try MinimapFixture()
        defer { fixture.close() }
        try await fixture.settle()
        fixture.scroll(to: 0.4)
        let before = fixture.sliderTop
        let start = before + fixture.sliderHeight / 2
        let destination = fixture.view.currentDestination?.point
        fixture.minimap.mouseDown(with: try fixture.event(.leftMouseDown, y: start))
        XCTAssertTrue(fixture.controller.isScrubbing)
        for step in 1...120 {
            fixture.minimap.mouseDragged(with: try fixture.event(.leftMouseDragged, y: start + CGFloat(step) / 3))
        }
        XCTAssertEqual(fixture.view.currentDestination?.point, destination,
                       "A burst before the next display update must not navigate through 120 intermediate destinations.")
        fixture.minimap.mouseUp(with: try fixture.event(.leftMouseUp, y: start + 65))
        XCTAssertFalse(fixture.controller.isScrubbing)
        XCTAssertEqual(fixture.sliderTop - before, 65, accuracy: 1,
                       "Release must apply its own position synchronously, even when the frame timer has not run.")
        try await fixture.settle()
        XCTAssertEqual(fixture.sliderTop - before, 65, accuracy: 1, "A pending timer must not undo the final position.")
    }
}

@MainActor
private final class MinimapFixture {
    let controller = ReaderController()
    let view = RegionPDFView(frame: CGRect(x: 0, y: 0, width: 700, height: 700))
    let minimap = MinimapView(frame: CGRect(x: 700, y: 0, width: 96, height: 700))
    let document = PDFDocument()
    let window: NSWindow

    init() throws {
        _ = NSApplication.shared
        let source = try XCTUnwrap(PDFDocument(url: Bundle.module.url(forResource: "book-chapters", withExtension: "pdf", subdirectory: "Fixtures")!))
        let page = try XCTUnwrap(source.page(at: 0))
        for index in 0..<40 { document.insert(try XCTUnwrap(page.copy() as? PDFPage), at: index) }
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 796, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: window.contentLayoutRect)
        window.contentView = content
        content.addSubview(view); content.addSubview(minimap)
        controller.view = view; view.controller = controller
        minimap.controller = controller
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        view.autoScales = false; view.scaleFactor = 1
        window.orderFront(nil)
        minimap.attach()
    }

    var clip: NSClipView { view.documentView!.enclosingScrollView!.contentView }
    var contentHeight: CGFloat {
        let size = document.page(at: 0)!.bounds(for: .cropBox).size
        return 40 * (84 * size.height / size.width + 4) + 4
    }
    var fractions: (top: CGFloat, span: CGFloat) {
        if view.displayMode == .singlePage { return (CGFloat(controller.pageNumber - 1) / 40, 1 / 40) }
        let height = view.documentView!.bounds.height
        return (view.documentView!.isFlipped ? clip.bounds.minY / height : 1 - clip.bounds.maxY / height, clip.bounds.height / height)
    }
    var sliderHeight: CGFloat { max(6, fractions.span * contentHeight) }
    var sliderTop: CGFloat {
        let (top, span) = fractions
        return top * contentHeight - top / (1 - span) * (contentHeight - minimap.bounds.height)
    }

    func scroll(to fraction: CGFloat) {
        let height = view.documentView!.bounds.height
        let y = view.documentView!.isFlipped ? fraction * height : height * (1 - fraction) - clip.bounds.height
        clip.scroll(to: CGPoint(x: clip.bounds.minX, y: y))
        view.documentView!.enclosingScrollView!.reflectScrolledClipView(clip)
    }

    func event(_ type: NSEvent.EventType, y: CGFloat) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: minimap.convert(CGPoint(x: 48, y: y), to: nil),
                                       modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    func settle() async throws {
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        view.layoutDocumentView(); controller.updatePage()
    }

    /// A drag navigates once per frame on a timer, which a busy or headless machine (CI) can fire late: wait for the
    /// slider to arrive, up to a second, rather than for a fixed time.
    func waitForSlider(at top: CGFloat) async throws {
        for _ in 0..<50 where abs(sliderTop - top) > 1 { try await Task.sleep(for: .milliseconds(20)) }
    }
    func close() { window.close() }
}
