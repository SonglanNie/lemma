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
        let width = page.displayedSize.width
        scaleFactor = max(minScaleFactor, min(maxScaleFactor, state.scale.map { CGFloat($0) } ?? (bounds.width - 24) / max(width, 1)))
        layoutDocumentView()
        if let x = state.positionX, let y = state.positionY {
            go(to: PDFDestination(page: page, at: CGPoint(x: x, y: y)))
        } else if let target = state.target {
            let region = target.region.rect
            go(to: PDFDestination(page: page, at: CGPoint(x: region.minX, y: min(region.maxY + 40, page.bounds(for: .cropBox).maxY))))
        } else {
            go(to: page)
        }
        isShowingPage = true
    }
}
