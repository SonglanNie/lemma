import AppKit
import SwiftUI

struct NativeResizeSash: NSViewRepresentable {
    let axis: VSSash.Axis
    let line: Color
    let accent: Color
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> ResizeSashView { ResizeSashView() }
    func updateNSView(_ view: ResizeSashView, context: Context) {
        view.axis = axis; view.line = NSColor(line); view.accent = NSColor(accent)
        view.onDrag = onDrag; view.onEnd = onEnd; view.onDoubleClick = onDoubleClick
        view.needsDisplay = true
    }
}

/// Native cursor rectangles cover the whole handle. Window coordinates keep a drag stable as the divider moves.
final class ResizeSashView: NSView {
    nonisolated static let thickness: CGFloat = 12
    var axis: VSSash.Axis = .vertical
    var line = NSColor.separatorColor
    var accent = NSColor.controlAccentColor
    var onDrag: (CGFloat) -> Void = { _ in }
    var onEnd: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    private var hovered = false
    private var previousPoint: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: axis == .vertical ? .resizeLeftRight : .resizeUpDown)
    }
    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { previousPoint = nil; onDoubleClick(); return }
        previousPoint = event.locationInWindow; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let previousPoint else { return }
        let point = event.locationInWindow
        self.previousPoint = point
        onDrag(axis == .vertical ? point.x - previousPoint.x : previousPoint.y - point.y)
    }
    override func mouseUp(with event: NSEvent) {
        guard previousPoint != nil else { return }
        previousPoint = nil; needsDisplay = true; onEnd()
    }
    override func draw(_ dirtyRect: NSRect) {
        let active = hovered || previousPoint != nil
        (active ? accent : line).setFill()
        let width: CGFloat = active ? 4 : 1
        let rect = axis == .vertical
            ? NSRect(x: bounds.midX - width / 2, y: 0, width: width, height: bounds.height)
            : NSRect(x: 0, y: bounds.midY - width / 2, width: bounds.width, height: width)
        rect.fill()
    }
}
