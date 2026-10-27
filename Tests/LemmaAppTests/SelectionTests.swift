import XCTest
import AppKit
import PDFKit
@testable import Lemma

final class SelectionTests: XCTestCase {
    /// A one-page PDF with a line of text, in a reader view in a window.
    @MainActor
    private struct Reader {
        let page: PDFPage
        let controller = ReaderController()
        let view = RegionPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 700))
        let window: NSWindow
        let coordinator: PDFReaderSurface.Coordinator

        init() throws {
            _ = NSApplication.shared
            let data = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: 300, height: 400)
            let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: data)), mediaBox: &box, nil))
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSColor.white.setFill(); box.fill()
            ("A source passage" as NSString).draw(at: CGPoint(x: 30, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage(); context.closePDF()
            let document = try XCTUnwrap(PDFDocument(data: data as Data))
            page = try XCTUnwrap(document.page(at: 0))
            view.controller = controller; controller.view = view
            view.displayMode = .singlePage
            view.document = document
            view.autoScales = true
            window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            coordinator = PDFReaderSurface.Coordinator(controller: controller)
            coordinator.observe(view)
            view.layoutDocumentView()
            view.layoutSubtreeIfNeeded()
        }

        func close() { coordinator.stop(); window.close() }

        /// A mouse event at a point of the page.
        func event(_ type: NSEvent.EventType, at pagePoint: CGPoint, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(view.convert(pagePoint, from: page), to: nil),
                                             modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
                                             context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
    }

    @MainActor
    func testRegionDragReceivesInputOverThePDFPage() throws {
        let reader = try Reader()
        defer { reader.close() }
        let (page, controller, view, window) = (reader.page, reader.controller, reader.view, reader.window)

        controller.regionMode = true
        let point = view.convert(CGPoint(x: 70, y: 90), from: page)
        let target = try XCTUnwrap(view.hitTest(view.convert(point, to: view.superview)))
        XCTAssertTrue(target === view, "Capture input goes to \(type(of: target)), bypassing RegionPDFView.mouseDown.")

        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
                                          modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        let start = view.convert(CGPoint(x: 20, y: 65), from: page)
        let end = view.convert(CGPoint(x: 245, y: 115), from: page)
        target.mouseDown(with: try event(.leftMouseDown, at: start))
        target.mouseDragged(with: try event(.leftMouseDragged, at: end))
        let outline = try XCTUnwrap(view.subviews.compactMap { $0 as? RegionSelectionOverlay }.last)
        XCTAssertFalse(outline.isHidden)
        XCTAssertNotNil(outline.rectangle)
        XCTAssertTrue(view.subviews.last === outline, "The outline must draw above the PDF page.")
        target.mouseUp(with: try event(.leftMouseUp, at: end))
        XCTAssertTrue(controller.hasSelection)
        let (index, region, quote) = try XCTUnwrap(controller.selection)
        XCTAssertEqual(index, 0)
        XCTAssertEqual(region.minX, 20, accuracy: 0.01)
        XCTAssertEqual(region.minY, 65, accuracy: 0.01)
        XCTAssertEqual(region.width, 225, accuracy: 0.01)
        XCTAssertEqual(region.height, 50, accuracy: 0.01)
        XCTAssertTrue(quote.contains("A source passage"))
        XCTAssertNotNil(outline.rectangle, "The captured source stays visible after release.")

        controller.regionMode = false
        view.refreshCaptureOverlay()
        XCTAssertNil(outline.rectangle, "The capture outline goes with region mode (the overlay itself stays for the gutter's line numbers).")
        let nativeTarget = try XCTUnwrap(view.hitTest(view.convert(point, to: view.superview)))
        XCTAssertFalse(nativeTarget === view, "Normal text selection must still reach PDFKit's page.")
        let text = try XCTUnwrap(page.selection(for: region))
        view.setCurrentSelection(text, animate: false)
        XCTAssertTrue(controller.hasSelection)
        XCTAssertTrue(controller.selection?.2.contains("A source passage") == true)
    }

    @MainActor
    func testCommandScrollZoomsAroundThePointer() throws {
        let reader = try Reader()
        defer { reader.close() }
        let (view, controller) = (reader.view, reader.controller)
        controller.updatePage()
        let fitted = view.scaleFactor, middle = view.convert(CGPoint(x: 150, y: 200), from: reader.page)
        XCTAssertFalse(PDFView.zoomsByScrolling(try scrollEvent(3, at: middle, in: view, flags: [])), "A scroll without ⌘ scrolls.")
        let zoomIn = try (0..<3).map { _ in try scrollEvent(1, at: middle, in: view) }
        XCTAssertTrue(PDFView.zoomsByScrolling(zoomIn[0]))
        let pointer = view.convert(zoomIn[0].locationInWindow, from: nil)
        let page = try XCTUnwrap(view.page(for: pointer, nearest: true)), anchor = view.convert(pointer, to: page)
        zoomIn.forEach(view.scrollWheel)
        XCTAssertEqual(view.scaleFactor, fitted * pow(ScrollZoom.step, 3), accuracy: 0.01, "Three notches up the page zoom in a step each.")
        XCTAssertFalse(view.autoScales, "The page no longer fits itself to the window.")
        let held = view.convert(anchor, from: page)
        XCTAssertEqual(held.x, pointer.x, accuracy: 2, "The point under the pointer stays there.")
        XCTAssertEqual(held.y, pointer.y, accuracy: 2, "The point under the pointer stays there.")
        XCTAssertEqual(controller.scale, Double(fitted), accuracy: 0.001, "While the wheel turns, the reader keeps its zoom.")
        ScrollZoom.end()
        XCTAssertEqual(controller.scale, Double(view.scaleFactor), accuracy: 0.001, "Once it stops, the reader takes in the new zoom.")
        for _ in 0..<3 { view.scrollWheel(with: try scrollEvent(-1, at: pointer, in: view)) }
        ScrollZoom.end()
        XCTAssertEqual(view.scaleFactor, fitted, accuracy: 0.01, "Three notches back zoom out as far.")
        // A free spin to the largest zoom: the letters around the pointer stay where they are on the screen at every step,
        // where the clip view's rounding to a pixel, counted in points of the page, shook them by up to 50 points.
        let spinAnchor = view.convert(pointer, to: page)
        for _ in 0..<40 {
            view.scrollWheel(with: try scrollEvent(400, precise: true, lines: 60, at: middle, in: view))
            let held = view.convert(spinAnchor, from: page)
            XCTAssertEqual(hypot(held.x - pointer.x, held.y - pointer.y), 0, accuracy: 0.5, "At \(view.scaleFactor), the point under the pointer stays there.")
        }
        XCTAssertEqual(view.scaleFactor, view.maxScaleFactor, "The spin reaches the largest zoom.")
        ScrollZoom.end()
    }

    /// Each event of a wheel zooms one step, however far or fast it turns: as recorded from an MX Master 3S (13 points a
    /// notch, or 71 through LinearMouse, and 20 to 132 lines an event of its free spin), and as macOS reports a plain wheel
    /// (a tenth of a line or a line, and more lines the faster it turns).
    @MainActor
    func testScrollZoomStepsEvenlyForEveryKindOfWheel() throws {
        let step = ScrollZoom.step
        XCTAssertEqual(ScrollZoom.factor(for: try scrollEvent(1)), step, accuracy: 0.001, "A plain wheel's notch")
        XCTAssertEqual(ScrollZoom.factor(for: try scrollEvent(0.1)), step, accuracy: 0.001, "A slow notch reported as a tenth of a line")
        XCTAssertEqual(ScrollZoom.factor(for: try scrollEvent(12)), step, accuracy: 0.001, "A fast notch macOS counts as 12 lines")
        XCTAssertEqual(ScrollZoom.factor(for: try scrollEvent(-1)), 1 / step, accuracy: 0.001, "A notch back zooms out")
        XCTAssertEqual(ScrollZoom.factor(for: try scrollEvent(13, precise: true)), step, accuracy: 0.001, "An MX Master 3S's notch")
        XCTAssertEqual(ScrollZoom.factor(for: try scrollEvent(71, precise: true)), step, accuracy: 0.001, "The same notch through LinearMouse")
        XCTAssertEqual(ScrollZoom.factor(for: try scrollEvent(35, precise: true, phase: 2)), step, accuracy: 0.001, "A trackpad's 35 points")
        XCTAssertEqual(ScrollZoom.factor(for: try scrollEvent(30, precise: true, momentum: 2)), 1, "Momentum after the fingers lift does not zoom")
        // The free-spinning wheel of an MX Master: 60 events a second of 20 to 132 lines each, as recorded.
        let spin = try (0..<40).map { try scrollEvent(400, precise: true, lines: [20, 60, 132][$0 % 3]) }
        for event in spin { XCTAssertEqual(ScrollZoom.factor(for: event), step, accuracy: 0.001, "Every event of the spin zooms one step") }
        XCTAssertEqual(spin.reduce(CGFloat(1)) { $0 * ScrollZoom.factor(for: $1) }, 1024, accuracy: 1,
                       "Two thirds of a second of free spin zoom 1000×, from 10% to 10000%, as in PDFgear")
    }

    @MainActor
    func testCommandDragOpensABoxToTheSideAndCommandClickLooksUpOnRelease() throws {
        let reader = try Reader()
        defer { reader.close() }
        var opened: (BoxDestination, Int, CGRect)?
        var lookedUp: String?
        reader.controller.onBox = { opened = ($0, $1, $2) }
        reader.controller.onLookup = { _, _, text in lookedUp = text }

        reader.view.mouseDown(with: try reader.event(.leftMouseDown, at: CGPoint(x: 20, y: 65), modifiers: .command))
        reader.view.mouseDragged(with: try reader.event(.leftMouseDragged, at: CGPoint(x: 245, y: 115), modifiers: .command))
        XCTAssertNotNil(reader.view.dragRectangle, "A ⌘-drag draws its box as it goes.")
        XCTAssertTrue(reader.view.drawsWithCrosshair, "The pointer is a crosshair while the box is drawn.")
        reader.view.mouseUp(with: try reader.event(.leftMouseUp, at: CGPoint(x: 245, y: 115), modifiers: .command))
        let (destination, index, region) = try XCTUnwrap(opened)
        XCTAssertEqual(destination, .side)
        XCTAssertEqual(index, 0)
        XCTAssertEqual(region.minX, 20, accuracy: 0.01)
        XCTAssertEqual(region.minY, 65, accuracy: 0.01)
        XCTAssertEqual(region.width, 225, accuracy: 0.01)
        XCTAssertEqual(region.height, 50, accuracy: 0.01)
        XCTAssertNil(reader.view.dragRectangle)
        XCTAssertFalse(reader.view.drawsWithCrosshair)
        XCTAssertNil(lookedUp, "A ⌘-drag is not a lookup.")
        XCTAssertFalse(reader.controller.hasSelection, "The box opens beside the page; it does not become the selection.")

        opened = nil
        reader.view.mouseDown(with: try reader.event(.leftMouseDown, at: CGPoint(x: 60, y: 88), modifiers: .command))
        XCTAssertNil(lookedUp, "⌘-click waits for the release, which tells it from a ⌘-drag.")
        reader.view.mouseUp(with: try reader.event(.leftMouseUp, at: CGPoint(x: 60, y: 88), modifiers: .command))
        XCTAssertNotNil(lookedUp)
        XCTAssertNil(opened)

        lookedUp = nil
        reader.view.mouseDown(with: try reader.event(.leftMouseDown, at: CGPoint(x: 20, y: 65), modifiers: [.command, .shift]))
        reader.view.mouseDragged(with: try reader.event(.leftMouseDragged, at: CGPoint(x: 245, y: 115), modifiers: [.command, .shift]))
        reader.view.mouseUp(with: try reader.event(.leftMouseUp, at: CGPoint(x: 245, y: 115), modifiers: [.command, .shift]))
        XCTAssertEqual(opened?.0, .float, "⇧⌘-drag floats the box above the page.")
        XCTAssertEqual(opened?.2.width ?? 0, 225, accuracy: 0.01)
        XCTAssertNil(lookedUp)
    }

    @MainActor
    func testRegionDrawnToTheSideOpensThereAndEndsTheMode() throws {
        let reader = try Reader()
        defer { reader.close() }
        var opened: (BoxDestination, Int, CGRect)?
        reader.controller.onBox = { opened = ($0, $1, $2) }
        reader.controller.regionMode = true
        reader.controller.boxDestination = .side
        XCTAssertEqual(reader.controller.selectionPrompt, "Drag a box to open it beside the page")
        XCTAssertTrue(reader.view.drawsWithCrosshair, "Over text and references alike, the pointer stays a crosshair.")

        reader.view.mouseDown(with: try reader.event(.leftMouseDown, at: CGPoint(x: 20, y: 65)))
        reader.view.mouseDragged(with: try reader.event(.leftMouseDragged, at: CGPoint(x: 245, y: 115)))
        reader.view.mouseUp(with: try reader.event(.leftMouseUp, at: CGPoint(x: 245, y: 115)))
        XCTAssertEqual(opened?.0, .side)
        XCTAssertEqual(opened?.2.width ?? 0, 225, accuracy: 0.01)
        XCTAssertFalse(reader.controller.hasSelection)
        XCTAssertFalse(reader.controller.regionMode, "One box, then the page is back to text selection.")
        XCTAssertNil(reader.controller.boxDestination)
        XCTAssertFalse(reader.view.drawsWithCrosshair)

        reader.controller.regionMode = true
        reader.controller.boxDestination = .float
        XCTAssertEqual(reader.controller.selectionPrompt, "Drag a box to float it above the page")
        reader.controller.regionMode = false
        reader.controller.regionMode = true
        XCTAssertNil(reader.controller.boxDestination, "Capture a Region is the ordinary capture, not a box to open elsewhere.")
    }

    @MainActor
    func testEscapeStopsDrawingABox() throws {
        let reader = try Reader()
        defer { reader.close() }
        reader.controller.regionMode = true
        reader.controller.boxDestination = .float
        XCTAssertTrue(reader.window.firstResponder === reader.view, "The page takes the keyboard, so Escape reaches it.")
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: reader.window.windowNumber,
                                                    context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        reader.view.keyDown(with: escape)
        XCTAssertFalse(reader.controller.regionMode)
        XCTAssertNil(reader.controller.boxDestination)
    }
}

/// A scroll as macOS delivers it, up the page when `dy` is positive: lines from a plain wheel, or points from a trackpad
/// or a Magic Mouse (with a `phase`) or a wheel its driver smooths, which macOS counts as `lines` (one, by default, as
/// for a slow notch), with ⌘ held unless `flags` says otherwise. An event made outside a window reads its screen location
/// as its location in the window.
@MainActor
func scrollEvent(_ dy: Double, precise: Bool = false, lines: Int64 = 1, phase: Int64 = 0, momentum: Int64 = 0,
                 at point: CGPoint = .zero, in view: NSView? = nil, flags: CGEventFlags = .maskCommand) throws -> NSEvent {
    let notch = Int32(dy.rounded(.awayFromZero))
    let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 1,
                                      wheel1: precise ? Int32(dy) : notch, wheel2: 0, wheel3: 0))
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
    if precise { event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: dy < 0 ? -lines : lines) }
    event.setDoubleValueField(precise ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis1, value: dy)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
    let inWindow = view.map { $0.convert(point, to: nil) } ?? point
    event.location = CGPoint(x: inWindow.x, y: (NSScreen.screens.first?.frame.height ?? 0) - inWindow.y)
    event.flags = flags
    return try XCTUnwrap(NSEvent(cgEvent: event))
}
