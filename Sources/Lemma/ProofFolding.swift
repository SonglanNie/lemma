import AppKit
import LemmaCore

/// A folded proof on the page: the proof's lines hidden behind a paper panel naming what it proves, as an editor
/// folds a function body. A click unfolds it. Drawn on the white page in either appearance, into a layer of its own
/// (a long fold scrolling into view is not drawn again strip by strip).
@MainActor final class ProofFoldBar: WholeLayerView {
    private let proof: ProofBlock
    private let first: Bool
    private let toggle: () -> Void
    private var hovering = false { didSet { if hovering != oldValue { redraw() } } }
    private var tracking: NSTrackingArea?

    init(proof: ProofBlock, first: Bool, toggle: @escaping () -> Void) {
        self.proof = proof; self.first = first; self.toggle = toggle
        super.init(frame: .zero)
        // Its layer is its own: a detail too long for a narrow bar is cut at its edge.
        clipsToBounds = true
        toolTip = "Click to unfold the proof"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(first ? "Folded proof of \(proof.statement?.title ?? "the statement above"), \(proof.lineCount) lines. Unfold" : "Folded proof, continued. Unfold")
    }
    required init?(coder: NSCoder) { nil }

    override func drawContents(in dirtyRect: CGRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        NSColor.lemmaPagePaper.setFill(); shape.fill()
        if hovering { NSColor.lemmaOliveOnPage.withAlphaComponent(0.06).setFill(); shape.fill() }
        NSColor.lemmaOliveOnPage.withAlphaComponent(hovering ? 0.65 : 0.35).setStroke()
        shape.lineWidth = 1
        shape.setLineDash([3, 2], count: 2, phase: 0)
        shape.stroke()
        let height = bounds.height
        let size: CGFloat = min(11.5, max(9, height * 0.5))
        let title: String
        let detail: String
        if first {
            title = "Proof" + (proof.statement.map { " of \($0.title)" } ?? "") + " · folded"
            detail = "\(proof.lineCount) \(proof.lineCount == 1 ? "line" : "lines") · try it yourself, then click to unfold"
        } else {
            title = "Proof continued · folded"
            detail = ""
        }
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor.lemmaOliveOnPage]
        let detailAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size - 0.5), .foregroundColor: NSColor.lemmaPageSecondary]
        let chevron = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size - 1, weight: .bold))
        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        // One line when the panel is short; the explanation goes below when there is room.
        let top = height >= titleSize.height * 2.6 ? height - 8 - titleSize.height : (height - titleSize.height) / 2
        var x: CGFloat = 8
        if let chevron {
            let tinted = chevron.tinted(NSColor.lemmaOliveOnPage)
            tinted.draw(in: CGRect(x: x, y: top + (titleSize.height - tinted.size.height) / 2, width: tinted.size.width, height: tinted.size.height))
            x += tinted.size.width + 6
        }
        (title as NSString).draw(at: CGPoint(x: x, y: top), withAttributes: titleAttributes)
        guard !detail.isEmpty else { return }
        let detailSize = (detail as NSString).size(withAttributes: detailAttributes)
        if height >= titleSize.height * 2.6 {
            (detail as NSString).draw(at: CGPoint(x: x, y: top - detailSize.height - 2), withAttributes: detailAttributes)
        } else if x + titleSize.width + 12 + detailSize.width < bounds.width - 8 {
            (detail as NSString).draw(at: CGPoint(x: x + titleSize.width + 12, y: top + (titleSize.height - detailSize.height) / 2), withAttributes: detailAttributes)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { toggle() }
    override func accessibilityPerformPress() -> Bool { toggle(); return true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// The fold control in the page's gutter beside a proof's first line: a chevron, pointing right when folded.
@MainActor final class GutterFoldControl: NSView {
    private let folded: Bool
    private let toggle: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    init(folded: Bool, title: String?, toggle: @escaping () -> Void) {
        self.folded = folded; self.toggle = toggle
        super.init(frame: .zero)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        clipsToBounds = true
        let name = title.map { "the proof of \($0)" } ?? "this proof"
        toolTip = folded ? "Unfold \(name)" : "Fold \(name) · try it yourself first"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(folded ? "Unfold \(name)" : "Fold \(name)")
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        if hovering || folded {
            (folded ? NSColor.lemmaOliveOnPage.withAlphaComponent(0.14) : NSColor(white: 0.5, alpha: 0.12)).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let color = folded ? NSColor.lemmaOliveOnPage : NSColor(white: hovering ? 0.25 : 0.55, alpha: 1)
        guard let symbol = NSImage(systemSymbolName: folded ? "chevron.right" : "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))?.tinted(color) else { return }
        symbol.draw(in: CGRect(x: (bounds.width - symbol.size.width) / 2, y: (bounds.height - symbol.size.height) / 2,
                               width: symbol.size.width, height: symbol.size.height))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { toggle() }
    override func accessibilityPerformPress() -> Bool { toggle(); return true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

extension NSImage {
    /// A template symbol drawn in one colour.
    func tinted(_ color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }
}
