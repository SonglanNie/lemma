import AppKit
import PDFKit
import LemmaCore

/// A PDF view whose text selection keeps to what the book's pages allow.
///
/// PDFKit's own mouse tracking and Select All go straight to CoreGraphics, past `TextGuardedPage`, and drawing their
/// selection can trap as well: a wide drag across a bad page ends Lemma. So in a book with a refused page, a drag, a double
/// click and a triple click use the page's guarded selections instead. Such a selection stays on the page it began on, and
/// Select All does nothing: PDFKit's selection would reach every page.
class GuardedPDFView: PDFView {
    private var textDrag: (page: PDFPage, start: CGPoint)?

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let document, let page = page(for: local, nearest: true) else { super.mouseDown(with: event); return }
        guard !document.admitsEveryPage else {
            ThemedPageProvider.shared.holdingPageInUse(page, in: document) { super.mouseDown(with: event) }
            return
        }
        let point = convert(local, to: page)
        // PDFKit follows a link without selecting.
        if page.annotation(at: point)?.action != nil { super.mouseDown(with: event); return }
        window?.makeFirstResponder(self)
        clearSelection()
        switch event.clickCount {
        case 1: textDrag = (page, point)
        case 2: setCurrentSelection(page.selectionForWord(at: point), animate: false)
        default: setCurrentSelection(page.selectionForLine(at: point), animate: false)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let textDrag else { super.mouseDragged(with: event); return }
        let end = convert(convert(event.locationInWindow, from: nil), to: textDrag.page)
        if let selection = textDrag.page.selection(from: textDrag.start, to: end) { setCurrentSelection(selection, animate: false) }
    }

    override func mouseUp(with event: NSEvent) {
        // PDFKit never saw the press: it would take this for a click and clear the selection.
        guard textDrag == nil else { textDrag = nil; return }
        super.mouseUp(with: event)
    }

    override func selectAll(_ sender: Any?) {
        guard let document, document.admitsEveryPage else { NSSound.beep(); return }
        super.selectAll(sender)
    }
}
