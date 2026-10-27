import SwiftUI
import AppKit
import PDFKit
import LemmaCore

/// The secondary editor: the same book beside the reader, kept on a theorem, an equation or a page while the main
/// view follows the argument. Highlights and handwriting appear in both, since they belong to the document.
struct SecondaryEditor: View {
    @Bindable var store: StudyStore
    let state: SplitEditorState

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if ThemeManager.shared.style == .classic && state.bookID == nil {
            HStack(spacing: 8) {
                Image(systemName: state.target?.key.kind.symbol ?? "doc.text").font(.system(size: 11)).foregroundStyle(Color.lemmaOlive)
                Text(state.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(store.shortPageText(state.pageIndex)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button {
                    if let target = state.target { store.goToReference(target) } else { store.reader.goToPage(state.pageIndex + 1) }
                } label: { Image(systemName: "arrow.left.to.line") }
                    .help("Show this place in the main editor (Back returns)").accessibilityLabel("Show in main editor")
                Button { store.closeSideEditor(SideEditor.page(state).id) } label: { Image(systemName: "xmark") }
                    .help("Close the side editor · ⌘\\").accessibilityLabel("Close side editor")
            }
            .buttonStyle(.borderless).font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).frame(height: 28)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            } else {
            // The group's breadcrumbs, drawn as the first group's: book › page, with the group's one action at the end.
            HStack(spacing: 4) {
                FileIcon(kind: "file-pdf")
                Text(state.title).lineLimit(1).truncationMode(.tail).foregroundStyle(theme[.breadcrumbForeground])
                Codicon("chevron-right", size: 16).foregroundStyle(theme[.breadcrumbForeground].opacity(0.8))
                if let target = state.target, state.bookID == nil {
                    KindBadge(key: target.key, size: 13)
                }
                Text(state.bookID == nil ? store.shortPageText(state.pageIndex) : "PDF \(state.pageIndex + 1)")
                    .monospacedDigit().lineLimit(1).foregroundStyle(theme[.breadcrumbFocusForeground])
                Spacer(minLength: 4)
                if let bookID = state.bookID {
                    VSIconButton(icon: "go-to-file", help: "Open This Book in the Main Editor") { store.closeSideEditor(SideEditor.page(state).id); store.activateMainTab(bookID) }
                } else {
                    VSIconButton(icon: "arrow-left", help: "Show This Place in the Main Editor (⌥⌘← returns)") {
                        if let target = state.target { store.goToReference(target) } else { store.reader.goToPage(state.pageIndex + 1) }
                    }
                }
            }
            .font(.ui(13))
            .padding(.leading, 12).padding(.trailing, 6).frame(height: VSMetrics.breadcrumbHeight)
            .background(theme[.breadcrumbBackground])
            }
            if let document = store.sideDocument(for: state) {
                SecondaryPDFSurface(store: store, document: document, state: state, pageThemeRevision: store.pageThemeRevision)
            } else {
                VSWelcomeView(message: "This book's PDF could not be opened. Open it again from the library.") { EmptyView() }
            }
        }
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        .background(theme[.editorBackground])
    }
}

struct SecondaryPDFSurface: NSViewRepresentable {
    let store: StudyStore
    let document: PDFDocument
    let state: SplitEditorState
    /// The page theme's revision: pages drawn in another theme are drawn again.
    var pageThemeRevision = 0
    @AppStorage(LemmaPreferences.pageGap) private var pageGap = LemmaPreferences.pageGapDefault

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> SecondaryPDFView {
        let view = SecondaryPDFView()
        view.libraryDrop = PDFEditorDropHandler(store: store, toSide: true)
        view.registerForDraggedTypes(view.registeredDraggedTypes + [.string])
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.setPageGap(pageGap, side: 8)
        view.backgroundColor = Self.canvas
        view.autoScales = true
        view.document = document
        view.pageThemeRevision = pageThemeRevision
        view.show(state)
        floatBoxes(from: view)
        context.coordinator.observe(view)
        view.onLayout = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.observeScroll(in: view)
            coordinator?.scheduleReadingUpdate(view)
        }
        return view
    }

    func updateNSView(_ view: SecondaryPDFView, context: Context) {
        view.setPageGap(pageGap, side: 8)
        if view.document !== document { view.document = document; view.shownID = nil }
        let canvas = Self.canvas
        if view.backgroundColor != canvas { view.backgroundColor = canvas }
        if view.pageThemeRevision != pageThemeRevision {
            view.pageThemeRevision = pageThemeRevision
            view.redrawPages()
        }
        if view.shownID != state.id {
            // The place reached in the side tab being left is written before the view shows the next one.
            context.coordinator.flushPendingSave(view)
            view.show(state)
        }
        floatBoxes(from: view)
    }

    /// ⇧⌘-drag on the side page floats a box of it, of the book this side tab shows.
    private func floatBoxes(from view: SecondaryPDFView) {
        view.onFloatBox = { [weak store, weak view, state] pageIndex, region in
            guard let view else { return }
            store?.floatBox(from: state, page: pageIndex, region: region, drawnIn: view)
        }
    }

    /// The canvas around the pages, dark under night pages as in the main editor.
    private static var canvas: NSColor {
        PageThemeState.shared.theme.isDark ? NSColor(white: 0.085, alpha: 1) : ThemeSnapshot.shared.colors?.pageCanvas.nsColor ?? .windowBackgroundColor
    }

    static func dismantleNSView(_ view: SecondaryPDFView, coordinator: Coordinator) {
        coordinator.saveReading(view)
        coordinator.stop()
        view.onLayout = nil
    }

    @MainActor final class Coordinator {
        weak var store: StudyStore?
        private var observations: [NSObjectProtocol] = []
        private weak var clipView: NSClipView?
        private var scrollObservation: NSObjectProtocol?
        private var pendingSave: DispatchWorkItem?

        init(store: StudyStore) { self.store = store }

        func observe(_ view: SecondaryPDFView) {
            for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged, .PDFViewVisiblePagesChanged] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: view, queue: .main) { [weak self, weak view] _ in
                    MainActor.assumeIsolated { if let view { self?.scheduleReadingUpdate(view) } }
                })
            }
            observeScroll(in: view)
        }

        func observeScroll(in view: SecondaryPDFView) {
            guard let clip = view.documentView?.enclosingScrollView?.contentView, clip !== clipView else { return }
            if let scrollObservation { NotificationCenter.default.removeObserver(scrollObservation) }
            clipView = clip
            clip.postsBoundsChangedNotifications = true
            scrollObservation = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self, weak view] _ in
                MainActor.assumeIsolated { if let view { self?.scheduleReadingUpdate(view) } }
            }
        }

        /// The side editor's place is kept by its view while it scrolls and written to the store (which saves it) once the
        /// scrolling stops: written on every frame, it redrew every view that reads the side editors and rescheduled a save.
        func scheduleReadingUpdate(_ view: SecondaryPDFView) {
            pendingSave?.cancel()
            let work = DispatchWorkItem { [weak self, weak view] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pendingSave = nil
                    if let view { self.saveReading(view) }
                }
            }
            pendingSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        /// Writes a place still waiting for the scrolling to stop, now.
        func flushPendingSave(_ view: SecondaryPDFView) {
            guard let pendingSave else { return }
            pendingSave.cancel(); self.pendingSave = nil
            saveReading(view)
        }

        func saveReading(_ view: SecondaryPDFView) {
            guard view.isShowingPage, let id = view.shownID, let document = view.document,
                  let destination = view.currentDestination, let page = destination.page else { return }
            store?.updateSideReading(id: id, pageIndex: document.index(for: page), scale: Double(view.scaleFactor), point: destination.point)
        }

        func stop() {
            pendingSave?.cancel(); pendingSave = nil
            for observation in observations { NotificationCenter.default.removeObserver(observation) }
            if let scrollObservation { NotificationCenter.default.removeObserver(scrollObservation) }
            observations = []; scrollObservation = nil
        }
    }
}

@MainActor
extension StudyStore {
    func updateSideReading(id: UUID, pageIndex: Int, scale: Double, point: CGPoint) {
        guard let index = sideEditors.firstIndex(where: { if case let .page(state) = $0 { state.id == id } else { false } }),
              case var .page(state) = sideEditors[index] else { return }
        guard state.pageIndex != pageIndex || state.scale != scale || state.positionX != Double(point.x) || state.positionY != Double(point.y) else { return }
        state.pageIndex = pageIndex; state.scale = scale
        state.positionX = Double(point.x); state.positionY = Double(point.y)
        sideEditors[index] = .page(state)
        scheduleSave()
    }
}

final class SecondaryPDFView: PDFView {
    var libraryDrop: PDFEditorDropHandler?
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        libraryDrop?.update(sender, in: self) ?? super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        libraryDrop?.update(sender, in: self) ?? super.draggingUpdated(sender)
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        libraryDrop?.accepts(sender) == true || super.prepareForDragOperation(sender)
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        libraryDrop?.perform(sender, in: self) ?? super.performDragOperation(sender)
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        libraryDrop?.clear()
        super.draggingExited(sender)
    }
    var shownID: UUID?
    var pageThemeRevision = 0
    /// A box drawn with ⇧⌘, as in the main editor, floats above the page: (page index, region in page coordinates).
    /// ⌘-drag alone draws nothing here, since the side editor does not open boxes beside itself.
    var onFloatBox: ((Int, CGRect) -> Void)?
    /// Where a ⌘-drag began, in this view's coordinates.
    private var boxStart: CGPoint?
    /// The box being dragged, outlined as in the main editor.
    private(set) lazy var boxOutline: NSView = {
        let outline = NSView()
        outline.wantsLayer = true
        outline.layer?.borderWidth = 2
        outline.layer?.borderColor = NSColor.controlAccentColor.cgColor
        outline.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.13).cgColor
        return outline
    }()

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let target = super.hitTest(point) else { return nil }
        if !(target is NSScroller), PDFView.zoomsByScrolling(NSApp.currentEvent) { return self }
        // PDFKit's page views would otherwise take a ⌘-drag as a text selection.
        if onFloatBox != nil, !(target is NSScroller), let event = NSApp.currentEvent, event.type == .leftMouseDown,
           event.modifierFlags.contains(.command) { return self }
        return target
    }

    override func scrollWheel(with event: NSEvent) {
        if PDFView.zoomsByScrolling(event) { zoom(byScrolling: event) } else { super.scrollWheel(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        guard onFloatBox != nil, event.modifierFlags.contains(.command) else { super.mouseDown(with: event); return }
        boxStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = boxStart else { super.mouseDragged(with: event); return }
        let end = convert(event.locationInWindow, from: nil)
        guard boxOutline.superview != nil || hypot(end.x - start.x, end.y - start.y) > 3 else { return }
        if boxOutline.superview == nil { addSubview(boxOutline) }
        boxOutline.frame = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        NSCursor.crosshair.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = boxStart else { super.mouseUp(with: event); return }
        boxStart = nil
        let drawn = boxOutline.superview != nil
        boxOutline.removeFromSuperview()
        // ⇧ held at the release floats the box, as in the main editor.
        guard drawn, event.modifierFlags.contains(.shift),
              let box = boxRegion(from: start, to: convert(event.locationInWindow, from: nil)) else { return }
        onFloatBox?(box.pageIndex, box.region)
    }
    private var pending: SplitEditorState?
    var onLayout: (() -> Void)?
    private(set) var isShowingPage = false

    func show(_ state: SplitEditorState) {
        shownID = state.id
        isShowingPage = false
        pending = state
        needsLayout = true
    }

    override func layout() {
        super.layout()
        defer { onLayout?() }
        guard let state = pending, bounds.width > 40, let page = document?.page(at: state.pageIndex) else { return }
        pending = nil
        autoScales = false
        let region = state.region?.rect
        let text = Self.textBox(of: page)
        // A box opened to the side fills the view, up to 400 % for a few words. A page fits its text, not its paper: with
        // the blank margins a page is small in a side view beside the reader.
        let fitted = region.map { min((bounds.width - 24) / max($0.width, 1), (bounds.height - 24) / max($0.height, 1), 4) } ?? (bounds.width - 24) / max(text.width, 1)
        scaleFactor = max(minScaleFactor, min(maxScaleFactor, state.scale.map { CGFloat($0) } ?? fitted))
        layoutDocumentView()
        let left = text.minX - 12 / scaleFactor
        if let x = state.positionX, let y = state.positionY {
            go(to: PDFDestination(page: page, at: CGPoint(x: x, y: y)))
        } else if let region {
            // The box in the middle of the view, with the page around it still there to scroll to.
            let visible = CGSize(width: bounds.width / scaleFactor, height: bounds.height / scaleFactor)
            go(to: PDFDestination(page: page, at: CGPoint(x: region.midX - visible.width / 2, y: region.midY + visible.height / 2)))
        } else if let target = state.target {
            go(to: PDFDestination(page: page, at: CGPoint(x: left, y: min(target.region.rect.maxY + 40, page.bounds(for: .cropBox).maxY))))
        } else {
            go(to: PDFDestination(page: page, at: CGPoint(x: left, y: page.bounds(for: .cropBox).maxY)))
        }
        isShowingPage = true
    }

    /// The part of the page that holds its text, headers and page numbers included; the whole page when it has little
    /// or no text (a scan, a full-page figure).
    static func textBox(of page: PDFPage) -> CGRect {
        let paper = page.bounds(for: .cropBox)
        guard let text = page.selection(for: paper)?.bounds(for: page).intersection(paper),
              !text.isNull, text.width > paper.width * 0.4 else { return paper }
        return text
    }
}
