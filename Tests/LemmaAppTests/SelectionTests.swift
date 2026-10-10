import XCTest
import AppKit
import PDFKit
@testable import Lemma

final class SelectionTests: XCTestCase {
    @MainActor
    func testRegionDragReceivesInputOverThePDFPage() throws {
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
        let page = try XCTUnwrap(document.page(at: 0))
        let controller = ReaderController()
        let view = RegionPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 700))
        view.controller = controller; controller.view = view
        view.displayMode = .singlePage
        view.document = document
        view.autoScales = true
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        let coordinator = PDFReaderSurface.Coordinator(controller: controller)
        coordinator.observe(view)
        defer { coordinator.stop() }
        view.layoutDocumentView()
        view.layoutSubtreeIfNeeded()

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
}
