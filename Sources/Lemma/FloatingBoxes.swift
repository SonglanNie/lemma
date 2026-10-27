import AppKit
import PDFKit
import LemmaCore
import Observation

/// A box of a page kept in a small window of its own above Lemma's windows: a figure, a table or a statement kept in
/// sight while reading another page or another book. Boxes outlive their book's tab and come back on relaunch.
struct FloatingBox: Codable, Equatable, Identifiable {
    var id = UUID()
    var bookID: String
    var pageIndex: Int
    var region: PageRegion
    /// What the box holds (“Figure 1.1”), after the book's title in its window's title bar.
    var title: String
    /// The window's content on the screen. Its proportions are the box's: resizing the window scales the box.
    var frame: CGRect
    /// How far the box is zoomed in beyond filling its window (pinch, ⌘+ and ⌘−); 1 fills it.
    var zoom: Double = 1
}

/// Every floating box, whichever window it was drawn in: they float above all of Lemma's windows, stay in place when a
/// window moves, and hide while another app is in front.
@MainActor @Observable
final class FloatingBoxes {
    @ObservationIgnored unowned let app: AppModel
    private(set) var boxes: [FloatingBox] = []
    /// Hide All: the boxes are kept, out of sight, until Show All or a new box.
    private(set) var hidden = false
    @ObservationIgnored private(set) var panels: [UUID: FloatingBoxPanel] = [:]

    init(app: AppModel) {
        self.app = app
        // A display unplugged or rearranged: each box stays on a screen, and no larger than it.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { for panel in self?.panels.values.map(\.self) ?? [] { panel.keepOnScreen() } }
        }
    }

    /// The boxes of the last session whose book and page are still there. Each box keeps its own copy of its page, so
    /// a book no window has open is read only to copy its pages.
    func restore(_ saved: [FloatingBox], hidden: Bool) {
        self.hidden = hidden
        var read: [String: PDFDocument?] = [:]
        for box in saved {
            if read[box.bookID] == nil { read[box.bookID] = source(for: box.bookID) }
            guard let document = read[box.bookID] ?? nil, !document.isLocked, box.pageIndex < document.pageCount,
                  let page = document.page(at: box.pageIndex), show(box, page: page) else { continue }
            boxes.append(box)
        }
    }

    /// A new box, shown with the others (a hidden set comes back with it).
    func add(_ box: FloatingBox, page: PDFPage) {
        guard show(box, page: page) else { return }
        boxes.append(box)
        if hidden { setHidden(false) } else { app.saveSession() }
    }

    func setHidden(_ hide: Bool) {
        hidden = hide
        for panel in panels.values {
            if hide { panel.orderOut(nil) } else {
                // A box out of sight missed any change of page theme.
                panel.boxView.redrawPages()
                panel.orderFront(nil)
            }
        }
        app.saveSession()
    }

    func closeAll() {
        for panel in Array(panels.values) { panel.close() }
    }

    /// The book a restored box is copied from: the document a window has open, or the book read from the library.
    private func source(for bookID: String) -> PDFDocument? {
        if let open = app.windows.lazy.compactMap({ $0.documents[bookID] ?? $0.sideDocuments[bookID] }).first { return open }
        return app.library.first { $0.id == bookID }.flatMap(app.libraryDocument)
    }

    /// Opens the box's window; false when its page cannot be copied.
    private func show(_ box: FloatingBox, page: PDFPage) -> Bool {
        guard let view = FloatingBoxView(box: box, page: page) else { return false }
        let book = app.library.first { $0.id == box.bookID }?.title
        let panel = FloatingBoxPanel(box: box, view: view, title: [book, box.title].compactMap(\.self).joined(separator: " · "))
        panel.onChange = { [weak self] box in self?.update(box) }
        panel.onClose = { [weak self] id in self?.remove(id) }
        panels[box.id] = panel
        panel.keepOnScreen()
        if !hidden { panel.orderFront(nil) }
        return true
    }

    private func update(_ box: FloatingBox) {
        guard let index = boxes.firstIndex(where: { $0.id == box.id }), boxes[index] != box else { return }
        boxes[index] = box
        app.saveSession()
    }

    private func remove(_ id: UUID) {
        // Quitting closes no box: the session keeps them.
        guard !app.quitting else { return }
        boxes.removeAll { $0.id == id }
        panels[id] = nil
        app.saveSession()
    }
}

/// A floating box's window: a utility panel whose content keeps the box's proportions, so resizing it scales the page.
final class FloatingBoxPanel: NSPanel, NSWindowDelegate {
    private(set) var box: FloatingBox
    let boxView: FloatingBoxView
    var onChange: ((FloatingBox) -> Void)?
    var onClose: ((UUID) -> Void)?

    init(box: FloatingBox, view: FloatingBoxView, title: String) {
        self.box = box
        boxView = view
        super.init(contentRect: box.frame, styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        self.title = title
        isFloatingPanel = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        // Above whichever Lemma window is in front, in its space or full screen.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let size = box.region.rect.size
        contentAspectRatio = size
        // Tiny boxes (a symbol, a short line) can still be grabbed: the shorter side is at least 40 pt.
        let least = 40 / max(min(size.width, size.height), 1)
        contentMinSize = NSSize(width: size.width * least, height: size.height * least)
        contentView = boxView
        delegate = self
        boxView.onZoom = { [weak self] zoom in
            guard let self else { return }
            self.box.zoom = zoom
            self.onChange?(self.box)
        }
    }

    /// ⌘+, ⌘− and ⌘0 zoom the box rather than the page in the window behind it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "=", "+": boxView.zoom(by: 1.25)
        case "-": boxView.zoom(by: 0.8)
        case "0": boxView.zoom(by: 0)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// Fits the box on the screen it is mostly on (or the main screen), shrunk if it is larger than that screen: saved
    /// with one arrangement of displays, it may be restored with another.
    func keepOnScreen() {
        let content = contentRect(forFrameRect: frame)
        func shared(_ screen: NSScreen) -> CGFloat { let overlap = screen.visibleFrame.intersection(content); return overlap.isNull ? 0 : overlap.width * overlap.height }
        let screen = NSScreen.screens.max { shared($0) < shared($1) }.flatMap { shared($0) > 0 ? $0 : nil } ?? NSScreen.main
        let fitted = Self.frame(over: content, on: screen)
        guard fitted != content else { return }
        setFrame(frameRect(forContentRect: fitted), display: true)
        rememberFrame()
    }

    func windowDidMove(_ notification: Notification) { rememberFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { rememberFrame() }
    func windowWillClose(_ notification: Notification) { onClose?(box.id) }

    private func rememberFrame() {
        box.frame = contentRect(forFrameRect: frame)
        onChange?(box)
    }

    /// Where a box drawn on the screen opens: its content over the box, no larger than the screen and on it.
    @MainActor static func frame(over box: CGRect, on screen: NSScreen?) -> CGRect {
        guard let visible = screen?.visibleFrame else { return box }
        let titleBar = NSPanel.frameRect(forContentRect: box, styleMask: [.titled, .utilityWindow]).height - box.height
        let shrink = min(1, visible.width / box.width, (visible.height - titleBar) / box.height)
        var content = CGRect(x: box.minX, y: box.minY, width: box.width * shrink, height: box.height * shrink)
        content.origin.x = min(max(content.minX, visible.minX), visible.maxX - content.width)
        content.origin.y = min(max(content.minY, visible.minY), visible.maxY - titleBar - content.height)
        return content
    }
}

/// The page in a floating box: filled by the box at any window size, sharp since the page stays a PDF. The view shows
/// its own copy of the page, cropped to the box, so nothing outside the box is there to scroll to: zoomed in (pinch,
/// ⌘+), it scrolls within the box.
final class FloatingBoxView: PDFView {
    private let page: PDFPage
    private let region: CGRect
    private(set) var zoom: CGFloat
    /// The point of the page kept in the middle of the view as the window is resized or the box zoomed.
    private var center: CGPoint
    private var fittedSize: CGSize = .zero
    var onZoom: ((Double) -> Void)?

    /// Nil when the page cannot be copied.
    init?(box: FloatingBox, page source: PDFPage) {
        // The copy keeps the page's coordinates and its theme; cropping it leaves the book's page as it was.
        guard let copy = source.copy() as? PDFPage else { return nil }
        copy.setBounds(box.region.rect, for: .cropBox)
        let document = PDFDocument()
        document.insert(copy, at: 0)
        page = copy
        region = copy.bounds(for: .cropBox)
        zoom = max(1, CGFloat(box.zoom))
        center = CGPoint(x: region.midX, y: region.midY)
        super.init(frame: .zero)
        displayMode = .singlePage
        displaysPageBreaks = false
        pageShadowsEnabled = false
        autoScales = false
        backgroundColor = PageThemeState.shared.theme.isDark ? NSColor(white: 0.085, alpha: 1) : .white
        self.document = document
        NotificationCenter.default.addObserver(self, selector: #selector(scrollZoomEnded), name: ScrollZoom.didEnd, object: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The scale at which the whole box fits the view; the window keeps the box's proportions, so it fills it.
    private var fitScale: CGFloat { min(bounds.width / max(region.width, 1), bounds.height / max(region.height, 1)) }

    override func layout() {
        super.layout()
        guard bounds.width > 1, bounds.size != fittedSize else { return }
        fittedSize = bounds.size
        apply()
    }

    /// Zooms by a factor, around the middle of the view; 0 returns to the box at its fitted size.
    func zoom(by factor: CGFloat) {
        rememberCenter()
        zoom = factor == 0 ? 1 : min(8, max(1, zoom * factor))
        if zoom == 1 { center = CGPoint(x: region.midX, y: region.midY) }
        apply()
        onZoom?(Double(zoom))
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        zoom = min(8, max(1, scaleFactor / fitScale))
        if zoom == 1 { center = CGPoint(x: region.midX, y: region.midY); apply() } else { rememberCenter() }
        if event.phase == .ended || event.phase == [] { onZoom?(Double(zoom)) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let target = super.hitTest(point) else { return nil }
        return !(target is NSScroller) && PDFView.zoomsByScrolling(NSApp.currentEvent) ? self : target
    }

    /// ⌘-scroll zooms around the pointer, within the same bounds as a pinch; the box keeps its zoom once the wheel stops.
    override func scrollWheel(with event: NSEvent) {
        guard PDFView.zoomsByScrolling(event) else { super.scrollWheel(with: event); rememberCenter(); return }
        guard event.momentumPhase == [] else { return }
        zoom(byScrolling: event)
        zoom = min(8, max(1, scaleFactor / fitScale))
        if zoom == 1 { center = CGPoint(x: region.midX, y: region.midY); apply() } else { rememberCenter() }
    }

    @objc private func scrollZoomEnded() { onZoom?(Double(zoom)) }

    private func rememberCenter() {
        center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: page)
    }

    private func apply() {
        // The bounds are widened before they are narrowed, so neither is ever set past the other.
        minScaleFactor = 0.01
        maxScaleFactor = fitScale * 8
        minScaleFactor = fitScale
        scaleFactor = fitScale * zoom
        layoutDocumentView()
        // Scroll bars only once there is more of the box than the window shows; the box's edges do not stretch past.
        if let scroll = documentView?.enclosingScrollView {
            scroll.hasVerticalScroller = zoom > 1; scroll.hasHorizontalScroller = zoom > 1
            scroll.verticalScrollElasticity = .none; scroll.horizontalScrollElasticity = .none
        }
        let visible = CGSize(width: bounds.width / scaleFactor, height: bounds.height / scaleFactor)
        go(to: PDFDestination(page: page, at: CGPoint(x: center.x - visible.width / 2, y: center.y + visible.height / 2)))
    }
}

@MainActor
extension StudyStore {
    /// A box of the page in front, floating over the place it was drawn, at the page's zoom.
    func floatBox(page pageIndex: Int, region: CGRect) {
        guard let book = workspace, let view = reader.view else { return }
        floatBox(bookID: book.id, page: pageIndex, region: region, title: boxTitle(page: pageIndex, region: region), drawnIn: view)
    }

    /// A box drawn with ⇧⌘ on a page of the side editor, floating over the place it was drawn, at the side page's zoom.
    func floatBox(from side: SplitEditorState, page pageIndex: Int, region: CGRect, drawnIn view: PDFView) {
        if let bookID = side.bookID, bookID != workspace?.id {
            // Another book: its statements are not analysed here, so the box is named after its page, as the side tab is.
            floatBox(bookID: bookID, page: pageIndex, region: region, title: "Region · PDF \(pageIndex + 1)", drawnIn: view)
        } else if let book = workspace {
            floatBox(bookID: book.id, page: pageIndex, region: region, title: boxTitle(page: pageIndex, region: region), drawnIn: view)
        }
    }

    private func floatBox(bookID: String, page pageIndex: Int, region: CGRect, title: String, drawnIn view: PDFView) {
        guard let window = view.window, let page = view.document?.page(at: pageIndex) else { return }
        let onScreen = window.convertToScreen(view.convert(view.convert(region, from: page), to: nil))
        let box = FloatingBox(bookID: bookID, pageIndex: pageIndex, region: PageRegion(region), title: title,
                              frame: FloatingBoxPanel.frame(over: onScreen, on: window.screen))
        app.floatingBoxes.add(box, page: page)
    }

    /// The float button's menu.
    var floatMenuItems: [VSMenuItem] {
        let floating = app.floatingBoxes
        return [
            .action("Draw a Box…", enabled: document != nil, shortcut: "⇧⌘-drag") { [self] in drawBox(.float) },
            .separator,
            .action(floating.hidden ? "Show All" : "Hide All", enabled: !floating.boxes.isEmpty) { floating.setHidden(!floating.hidden) },
            .action("Close All", enabled: !floating.boxes.isEmpty) { floating.closeAll() },
        ]
    }
}
