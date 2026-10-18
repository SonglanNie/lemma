import SwiftUI
import AppKit
import PDFKit
import LemmaCore

struct ReferencePeekRequest: Identifiable, Equatable {
    let id = UUID()
    let workspaceID: String
    let mention: PageMention
    /// The page where the reader clicked the mention.
    let pageIndex: Int
}

/// Presented from the PDF view so the clicked mention anchors the peek.
@MainActor
final class ReferencePeekPopover: NSObject, NSPopoverDelegate {
    let popover = NSPopover()
    /// The VS Code style's peek view, used instead of the popover.
    let panel = VSFloatingPanel()
    private weak var store: StudyStore?
    private let requestID: UUID

    var isShown: Bool { popover.isShown || panel.isShown }
    func close() {
        if popover.isShown { popover.close() }
        panel.close()
    }

    init(store: StudyStore, request: ReferencePeekRequest) {
        self.store = store; self.requestID = request.id
        super.init()
        popover.contentViewController = NSHostingController(rootView: ReferencePeekPane(store: store, request: request).tint(.lemmaOlive))
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        panel.onClose = { [weak self] in
            guard let self else { return }
            if self.store?.referencePeek?.id == self.requestID { self.store?.referencePeek = nil }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if store?.referencePeek?.id == requestID { store?.referencePeek = nil }
    }
}

@MainActor
extension RegionPDFView {
    func presentReferencePeek(_ request: ReferencePeekRequest, store: StudyStore) {
        guard window?.isVisible == true else { return }
        dismissReferencePeek()
        dismissDefinitionLookup()
        var anchor = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
        if let page = document?.page(at: request.pageIndex), let first = request.mention.rects.first {
            let rect = convert(first, from: page).intersection(bounds)
            if !rect.isNull, !rect.isEmpty { anchor = rect }
        }
        let presentation = ReferencePeekPopover(store: store, request: request)
        referencePopover = presentation
        if ThemeManager.shared.style == .vscode {
            // VS Code's peek view: under the line, across the editor, with a title bar and the peek frame.
            let line = CGRect(x: max(bounds.minX + 16, anchor.minX - 40), y: anchor.minY, width: 1, height: anchor.height)
            let width = min(680, max(420, bounds.width - 60))
            let key = request.mention.key
            let page = store.references?.knownTarget(key).map { store.pageText($0.pageIndex) } ?? ""
            let chrome = VSPeekChrome(icon: Self.peekIcon(key.kind), title: key.kind == .citation ? (key.name ?? key.title) : key.spokenTitle,
                                      description: page) {
                VSIconButton(icon: "close", help: "Close (Escape)") { presentation.close() }
            } content: {
                ReferencePeekPane(store: store, request: request, chromeless: true).padding(12)
            }
            presentation.panel.show(chrome, anchor: line, in: self, placement: .below, interactive: true, width: width)
            return
        }
        presentation.popover.show(relativeTo: anchor, of: self, preferredEdge: .minY)
    }

    /// The peek's title icon, as the Go to list shows each kind.
    static func peekIcon(_ kind: ReferenceKind) -> String {
        switch kind {
        case .citation: "book"
        case .equation: "symbol-numeric"
        case .figure: "file-media"
        case .table: "table"
        case .algorithm: "symbol-method"
        case .exercise: "tasklist"
        case .theorem: "verified"
        case .section, .chapter: "symbol-class"
        case .link: "link"
        }
    }

    func dismissReferencePeek() {
        referencePopover?.panel.onClose = nil
        referencePopover?.close()
        referencePopover = nil
    }
}

struct ReferencePeekPane: View {
    @Bindable var store: StudyStore
    let request: ReferencePeekRequest
    /// Inside VS Code's peek chrome, which shows the title and the close button.
    var chromeless = false
    @State private var target: ReferenceTarget?
    @State private var finished = false
    @State private var progress: Double?
    private var key: ReferenceKey { request.mention.key }
    private var peekWidth: CGFloat { 556 }

    /// Clicking the defining label itself has nothing to preview elsewhere.
    private var isDefinitionItself: Bool {
        guard let target, target.pageIndex == request.pageIndex else { return false }
        let anchor = target.anchor.rect.insetBy(dx: -1, dy: -1)
        return request.mention.rects.contains { $0.intersects(anchor) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !chromeless {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: key.kind.symbol).foregroundStyle(Color.lemmaOlive)
                Text(key.spokenTitle).font(.headline)
                if let target {
                    Text(store.printedLabel(for: target.pageIndex).map { "p. \($0) · PDF page \(target.pageIndex + 1)" } ?? "PDF page \(target.pageIndex + 1)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let count = store.analysis?.mentionCounts[key], count > 0, key.kind != .citation {
                        Text("· \(count) \(count == 1 ? "reference" : "references")").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { store.referencePeek = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).keyboardShortcut(.cancelAction).accessibilityLabel("Close reference preview")
            }
            }
            content
            if key.kind == .citation, let entry = store.analysis?.bibliographyEntry(key) {
                HStack(spacing: 14) {
                    Button("Copy Reference") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.text, forType: .string)
                        store.status = "Reference copied."
                    }
                    Button("Search Scholar ↗") {
                        var components = URLComponents(string: "https://scholar.google.com/scholar")!
                        components.queryItems = [URLQueryItem(name: "q", value: entry.searchQuery)]
                        if let url = components.url { NSWorkspace.shared.open(url) }
                    }.help("Look the work up on Google Scholar in your browser")
                    Spacer()
                    let citations = store.analysis?.citationCounts[entry.id] ?? 0
                    if citations > 0 { Text("Cited \(citations)× in this book").font(.caption).foregroundStyle(.secondary) }
                }.font(.callout).buttonStyle(.borderless)
                PaperLookupView(store: store, entry: entry)
            }
            HStack(spacing: 14) {
                Button(key.kind == .citation ? "Find Citations" : "Find All References") { store.referencePeek = nil; store.showReferences(to: key) }
                    .help("List the places in this book that cite \(key.title) · in the panel below")
                Button("Pin") { if let target { store.referencePeek = nil; store.pinReference(target) } }
                    .disabled(target == nil).help("Keep this passage in Context")
                if key.kind == .equation {
                    Button("LaTeX…") { if let target { store.referencePeek = nil; store.readFormula(target) } }.disabled(target == nil)
                        .help("Read this formula's LaTeX locally, with the original beside the transcription")
                }
                if [.equation, .algorithm, .figure, .table].contains(key.kind) {
                    Button("Lab") { if let target { store.referencePeek = nil; store.sendTargetToLab(target) } }
                        .disabled(target == nil).help("Try \(key.spokenTitle) in a Python notebook beside the page")
                }
                Spacer()
                Button("Open to the Side") { if let target { store.referencePeek = nil; store.openToSide(target) } }
                    .disabled(target == nil).help("Keep it in the side editor beside your page · ⌥-click a reference")
                Button("Go to") { if let target { store.referencePeek = nil; store.goToReference(target) } }
                    .keyboardShortcut(.defaultAction).disabled(target == nil || isDefinitionItself)
                    .help("Move the reader there. Back returns to this page · ⌥⌘←")
            }.font(.callout).buttonStyle(.borderless)
        }
        .padding(14).frame(width: peekWidth + 28)
        .task(id: request.id) { await resolve() }
    }

    @ViewBuilder private var content: some View {
        if !finished {
            VStack(alignment: .leading, spacing: 8) {
                if let progress { ProgressView(value: progress) } else { ProgressView().controlSize(.small) }
                Text(searchDescription).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        } else if let target, let document = store.document, store.workspace?.id == request.workspaceID {
            if isDefinitionItself {
                Text("This is where \(key.title) is defined. Find mentions lists the passages that refer to it.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            PeekPDFSurface(document: document, target: target)
                .frame(width: peekWidth, height: height(for: target))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                .accessibilityLabel("Live preview of \(key.spokenTitle) on PDF page \(target.pageIndex + 1)")
            Text(originDescription(target)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("No definition found for \(key.title)").font(.callout.weight(.medium))
                Text("Lemma looks for an equation label at the end of a line, a caption, a heading or a PDF link. Find mentions searches the text instead.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        }
    }

    private var searchDescription: String {
        if let range = store.references?.chapterRange(for: key) {
            return "Finding \(key.title) in PDF pages \(range.lowerBound + 1)–\(range.upperBound)…"
        }
        return "Finding \(key.title) near this page…"
    }

    private func originDescription(_ target: ReferenceTarget) -> String {
        switch target.origin {
        case .link: "From the PDF’s own link. Scroll the preview for more context."
        case .outline: "From the document outline. Scroll the preview for more context."
        case .text: target.key.kind == .citation ? "From the book’s list of references. Scroll the preview for neighbouring entries."
            : "Found from the label’s position in the text layer. Scroll the preview to check its context."
        }
    }

    private func height(for target: ReferenceTarget) -> CGFloat {
        let region = target.region.rect
        let scale = PeekPDFView.scale(for: region, width: peekWidth)
        return min(430, max(110, region.height * scale + 28))
    }

    private func resolve() async {
        guard let index = store.references, store.workspace?.id == request.workspaceID else { finished = true; return }
        target = await index.resolve(request.mention, from: request.pageIndex) { done, total in
            progress = total > 0 ? Double(done) / Double(total) : nil
        }
        finished = true
    }
}

/// A small live PDF view scrolled to the referenced region. It shares the reader's document.
struct PeekPDFSurface: NSViewRepresentable {
    let document: PDFDocument
    let target: ReferenceTarget
    @AppStorage(LemmaPreferences.pageGap) private var pageGap = LemmaPreferences.pageGapDefault

    func makeNSView(context: Context) -> PeekPDFView {
        let view = PeekPDFView()
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.setPageGap(pageGap, side: 6)
        view.backgroundColor = .windowBackgroundColor
        view.autoScales = false
        view.document = document
        view.target = target
        return view
    }

    func updateNSView(_ view: PeekPDFView, context: Context) {
        view.setPageGap(pageGap, side: 6)
        if view.document !== document { view.document = document }
        if view.target != target { view.target = target }
    }
}

final class PeekPDFView: PDFView {
    var target: ReferenceTarget? { didSet { applied = false; needsLayout = true } }
    private var applied = false

    static func scale(for region: CGRect, width: CGFloat) -> CGFloat {
        max(0.6, min(2.6, (width - 24) / max(region.width + 12, 40)))
    }

    override func layout() {
        super.layout()
        guard !applied, let target, bounds.width > 20, let page = document?.page(at: target.pageIndex) else { return }
        applied = true
        let region = target.region.rect
        scaleFactor = Self.scale(for: region, width: bounds.width)
        layoutDocumentView()
        let top = min(region.maxY + 8, page.bounds(for: .cropBox).maxY)
        go(to: PDFDestination(page: page, at: CGPoint(x: region.minX - 6, y: top)))
        // PDFView scrolls destinations vertically only; bring the region's columns into view as well.
        if let documentView {
            let visible = documentView.convert(convert(region.insetBy(dx: -6, dy: 0), from: page), from: self)
            documentView.scrollToVisible(CGRect(x: visible.minX, y: visible.midY, width: visible.width, height: 1))
        }
        if let label = page.selection(for: target.anchor.rect.insetBy(dx: -1, dy: -1)), !(label.string ?? "").isEmpty {
            label.color = NSColor.controlAccentColor.withAlphaComponent(0.35)
            highlightedSelections = [label]
        }
    }
}
