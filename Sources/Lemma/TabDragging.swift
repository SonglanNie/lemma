import SwiftUI
import AppKit

/// Drags a book's tab: within its tab bar to reorder it, onto another window's tab bar or editor to move the book there,
/// or out of every window to open the book in a window of its own, where the tab was dropped.
///
/// SwiftUI's `draggable` does not say where a drag ended when nothing took it, so the drag is AppKit's: a mouse-down on
/// a tab, then a drag past a few points, starts it from the tab's anchor view. Its payload is the tab's
/// `lemma-tab:` string, which the tab bars and editors accept. Other apps are offered nothing, so a tab dropped on
/// Finder makes no text clipping.
@MainActor
final class TabDragging: NSObject, NSDraggingSource {
    static let shared = TabDragging()
    private var monitor: Any?
    private var pressed: (anchor: TabDragAnchorView, location: NSPoint)?
    /// The tab being dragged, and where the pointer is from its window's top left corner were the tab the first one.
    private var dragged: (store: StudyStore, bookID: String, offset: NSPoint)?
    private let anchors = NSHashTable<TabDragAnchorView>.weakObjects()

    func register(_ anchor: TabDragAnchorView) {
        anchors.add(anchor)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
            TabDragging.shared.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            pressed = event.modifierFlags.contains(.control) ? nil : anchor(at: event).map { ($0, event.locationInWindow) }
        case .leftMouseDragged:
            guard let (anchor, start) = pressed else { break }
            let moved = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
            guard moved > 4 else { return nil }
            pressed = nil
            if begin(from: anchor, event: event) { return nil }
        case .leftMouseUp:
            pressed = nil
        default: break
        }
        return event
    }

    /// The tab under the pointer, among the tabs of the window it went down in.
    private func anchor(at event: NSEvent) -> TabDragAnchorView? {
        guard let window = event.window else { return nil }
        return anchors.allObjects.first { anchor in
            anchor.window === window && anchor.convert(anchor.bounds, to: nil).contains(event.locationInWindow)
        }
    }

    private func begin(from anchor: TabDragAnchorView, event: NSEvent) -> Bool {
        guard let store = anchor.store, let bookID = anchor.bookID else { return false }
        let item = NSPasteboardItem()
        item.setString("lemma-tab:\(bookID)", forType: .string)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        let frame = anchor.bounds
        dragItem.setDraggingFrame(frame, contents: snapshot(of: anchor) ?? NSImage(size: frame.size))
        // A window opened at the drop has the book's tab, its first, under the pointer, as the tab was held.
        guard let window = anchor.window else { return false }
        let tab = anchor.convert(anchor.bounds, to: nil)
        let firstTab = anchors.allObjects.filter { $0.window === window }.map { $0.convert($0.bounds, to: nil).minX }.min() ?? tab.minX
        let pointer = event.locationInWindow
        dragged = (store, bookID, NSPoint(x: firstTab + pointer.x - tab.minX, y: window.frame.height - pointer.y))
        let session = anchor.beginDraggingSession(with: [dragItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
        return true
    }

    /// The tab as drawn in its window.
    private func snapshot(of anchor: TabDragAnchorView) -> NSImage? {
        guard let content = anchor.window?.contentView else { return nil }
        let rect = content.convert(anchor.bounds, from: anchor)
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        content.cacheDisplay(in: rect, to: bitmap)
        let image = NSImage(size: rect.size)
        image.addRepresentation(bitmap)
        return image
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy, .generic] : []
    }

    /// Nothing took the tab: dropped outside every window, it opens its book in a new window there. Dropped on a window
    /// where nothing takes it (a side bar, the status bar), it stays where it was.
    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated {
            defer { dragged = nil }
            guard operation.isEmpty, let (store, bookID, offset) = dragged else { return }
            guard !NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(screenPoint) }) else { return }
            store.app.moveBookToNewWindow(bookID, topLeft: NSPoint(x: screenPoint.x - offset.x, y: screenPoint.y + offset.y))
        }
    }
}

/// Marks a book's tab for `TabDragging`: a view behind the tab that takes no clicks.
final class TabDragAnchorView: NSView {
    weak var store: StudyStore?
    var bookID: String?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { MainActor.assumeIsolated { TabDragging.shared.register(self) } }
    }
}

struct TabDragAnchor: NSViewRepresentable {
    let store: StudyStore
    let bookID: String
    func makeNSView(context: Context) -> TabDragAnchorView {
        let view = TabDragAnchorView()
        view.store = store; view.bookID = bookID
        return view
    }
    func updateNSView(_ view: TabDragAnchorView, context: Context) { view.store = store; view.bookID = bookID }
}

extension View {
    /// Lets the reader drag this book tab to reorder it, into another window, or out into a window of its own.
    func bookTabDrag(_ store: StudyStore, bookID: String) -> some View {
        background(TabDragAnchor(store: store, bookID: bookID))
            .dropDestination(for: String.self) { values, _ in store.dropBookTab(values, onto: bookID) }
    }
}
