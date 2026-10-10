import SwiftUI
import AppKit
import PDFKit
import LemmaCore

/// A narrow map of the whole book beside the page, like an editor's overview ruler: chapters, the visible pages,
/// notes, highlights, bookmarks and search matches. Click or drag to move through the book.
///
/// The book's marks are computed once per change of what they show and drawn in one canvas; the visible pages and the
/// hover label are separate views, so scrolling and moving the pointer redraw only themselves.
struct OverviewRuler: View {
    @Bindable var store: StudyStore
    @State private var marks = OverviewMarks()

    var body: some View {
        let _ = QAPerf.tick("OverviewRuler")
        GeometryReader { geometry in
            let height = geometry.size.height, count = max(store.reader.pageCount, 1)
            let snapshot = marks.update(store: store)
            ZStack(alignment: .topLeading) {
                OverviewVisiblePages(reader: store.reader, count: count)
                OverviewMarksCanvas(snapshot: snapshot, revision: marks.revision, count: count).equatable()
                OverviewRulerPointer(store: store, marks: marks, height: height, count: count)
            }
        }
        .frame(width: 14)
        .background(Color.lemmaChrome.opacity(0.6))
        .overlay(alignment: .leading) { Divider() }
        .accessibilityElement()
        .accessibilityLabel("Book overview")
        .accessibilityValue("Page \(store.reader.pageNumber) of \(store.reader.pageCount)")
        .accessibilityAdjustableAction { direction in
            store.reader.goToPage(store.reader.pageNumber + (direction == .increment ? 10 : -10))
        }
        .help("Overview of the book: pages you have read (left edge), chapters, statements (right edge, by kind), folded proofs, notes, highlights and matches. Click to go there.")
    }

    static func y(_ pageIndex: Int, count: Int, height: CGFloat) -> CGFloat { (CGFloat(pageIndex) + 0.5) / CGFloat(count) * height }

    static func pageIndex(at y: CGFloat, height: CGFloat, count: Int) -> Int { min(count - 1, max(0, Int(y / max(height, 1) * CGFloat(count)))) }

    static func draw(_ marks: OverviewMarks.Snapshot, in context: inout GraphicsContext, size: CGSize, count: Int) {
        QAPerf.tick("OverviewRuler.draw")
        let width = size.width, height = size.height
        // Chapters: hairlines at their first page.
        for page in marks.chapters {
            let lineY = (CGFloat(page) / CGFloat(count) * height).rounded()
            context.fill(Path(CGRect(x: 2, y: lineY, width: width - 4, height: 0.5)), with: .color(.secondary.opacity(0.35)))
        }
        // Pages read: a band on the left edge, darker with more time spent.
        let pageHeight = max(1, height / CGFloat(count))
        for (page, strength) in marks.read where page < count {
            context.fill(Path(CGRect(x: 0, y: CGFloat(page) / CGFloat(count) * height, width: 2.5, height: pageHeight)),
                         with: .color(Color.lemmaOlive.opacity(0.25 + 0.65 * strength)))
        }
        for (page, color) in marks.highlights {
            context.fill(Path(CGRect(x: 2, y: y(page, count: count, height: height) - 1, width: 4, height: 2)), with: .color(color))
        }
        for page in marks.bookmarks {
            context.fill(Path(CGRect(x: width - 5, y: y(page, count: count, height: height) - 2, width: 3, height: 4)), with: .color(.blue.opacity(0.8)))
        }
        for page in marks.matches {
            context.fill(Path(CGRect(x: 2, y: y(page, count: count, height: height) - 0.75, width: width - 4, height: 1.5)), with: .color(.orange.opacity(0.85)))
        }
        // Statements, coloured by kind (green once understood), and folded proofs: the book's structure at a glance.
        for (page, color) in marks.statements {
            context.fill(Path(CGRect(x: width - 4.5, y: y(page, count: count, height: height) - 0.75, width: 3.5, height: 1.5)), with: .color(color))
        }
        for (start, end) in marks.folded {
            let top = CGFloat(start) / CGFloat(count) * height, bottom = CGFloat(end + 1) / CGFloat(count) * height
            context.fill(Path(CGRect(x: width - 2, y: top, width: 1.5, height: max(2, bottom - top))), with: .color(Color.lemmaOlive.opacity(0.8)))
        }
        for (page, color) in marks.notes {
            let center = y(page, count: count, height: height)
            context.fill(Path(ellipseIn: CGRect(x: width / 2 - 2.5, y: center - 2.5, width: 5, height: 5)), with: .color(color))
        }
        if let split = marks.split {
            let center = y(split, count: count, height: height)
            context.stroke(Path(CGRect(x: 1.5, y: center - 3, width: width - 3, height: 6)), with: .color(.lemmaOlive), lineWidth: 1)
        }
    }
}

/// The book's marks in one canvas, drawn again only when they change (not when the parent is re-evaluated for a page turn).
private struct OverviewMarksCanvas: View, Equatable {
    let snapshot: OverviewMarks.Snapshot
    let revision: Int
    let count: Int

    nonisolated static func == (a: Self, b: Self) -> Bool { a.revision == b.revision && a.count == b.count }

    var body: some View {
        Canvas { context, size in OverviewRuler.draw(snapshot, in: &context, size: size, count: count) }
    }
}

/// The pages on screen, redrawn when they change (the book's marks are not).
private struct OverviewVisiblePages: View {
    let reader: ReaderController
    let count: Int

    var body: some View {
        Canvas { context, size in
            guard let range = reader.visiblePageRange else { return }
            let top = CGFloat(range.lowerBound) / CGFloat(count) * size.height, bottom = CGFloat(range.upperBound + 1) / CGFloat(count) * size.height
            context.fill(Path(roundedRect: CGRect(x: 1, y: top, width: size.width - 2, height: max(4, bottom - top)), cornerRadius: 2), with: .color(.primary.opacity(0.13)))
        }
    }
}

/// Clicks, drags and the label under the pointer. The pointer's position is this view's own state, so moving it
/// redraws only the label.
private struct OverviewRulerPointer: View {
    let store: StudyStore
    let marks: OverviewMarks
    let height: CGFloat
    let count: Int
    @State private var hover: CGFloat?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in go(to: value.location.y) })
            .onContinuousHover { phase in
                switch phase {
                case let .active(location): hover = location.y
                case .ended: hover = nil
                }
            }
            .overlay(alignment: .topTrailing) {
                if let hover {
                    let page = OverviewRuler.pageIndex(at: hover, height: height, count: count)
                    Text(label(for: page)).font(.system(size: 11)).lineLimit(1).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
                        .fixedSize()
                        .offset(x: -18, y: min(max(0, hover - 10), max(0, height - 22)))
                        .allowsHitTesting(false)
                }
            }
    }

    private func go(to y: CGFloat) {
        let index = OverviewRuler.pageIndex(at: y, height: height, count: count)
        if index != store.reader.pageNumber - 1 { store.reader.goToPage(index + 1) }
    }

    private func label(for pageIndex: Int) -> String {
        let section = marks.section(at: pageIndex)
        let seconds = store.workspace?.readingLog.seconds(onPage: pageIndex) ?? 0
        let read = seconds >= 4 ? "read \(ReadingLog.describe(seconds))" : nil
        return [store.shortPageText(pageIndex), section, read].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The overview's marks, computed again only when what they show changes: the reading log, highlights, bookmarks,
/// statements, folds, notes, matches or the outline. Search matches are placed once each, as a search's results arrive.
@MainActor
final class OverviewMarks {
    struct Snapshot {
        var chapters: [Int] = []
        var read: [(page: Int, strength: Double)] = []
        var highlights: [(page: Int, color: Color)] = []
        var bookmarks: [Int] = []
        var matches: [Int] = []
        var statements: [(page: Int, color: Color)] = []
        var folded: [(start: Int, end: Int)] = []
        var notes: [(page: Int, color: Color)] = []
        var split: Int?
    }

    private(set) var snapshot = Snapshot()
    /// Changes with the snapshot, so the canvas redraws only then.
    private(set) var revision = 0
    /// The outline flattened once, for the hover label.
    private var sections: [OutlineEntry] = []
    private var outline: [OutlineEntry] = []
    private var log: (count: Int, last: Date?) = (-1, nil)
    private var highlights: [StudyHighlight] = []
    private var bookmarks: [ReadingBookmark] = []
    private var notes: [StudyNote] = []
    private var understood: [ReferenceKey] = []
    private var folded: [String] = []
    private var analyzedAt: Date?
    private var matches: [PDFSelection] = []
    private weak var document: PDFDocument?
    private var computed = false

    func section(at pageIndex: Int) -> String? { sections.last { ($0.pageIndex ?? .max) <= pageIndex }?.title }

    func update(store: StudyStore) -> Snapshot {
        let workspace = store.workspace
        var changed = !computed
        if !store.outline.sharesStorage(with: outline) {
            outline = store.outline; sections = outline.flatMap(\.flattened); changed = true
            snapshot.chapters = outline.compactMap { $0.pageIndex.flatMap { $0 > 0 ? $0 : nil } }
        }
        let logKey = (workspace?.readingLog.pageSeconds.count ?? 0, workspace?.readingLog.lastReadAt)
        if logKey.0 != log.count || logKey.1 != log.last {
            log = (logKey.0, logKey.1)
            snapshot.read = (workspace?.readingLog.pageSeconds ?? [:]).compactMap { key, seconds in
                guard seconds >= 4, let page = Int(key) else { return nil }
                return (page, min(1, log10(1 + seconds / ReadingLog.readThreshold) / log10(16)))
            }
            changed = true
        }
        let highlights = workspace?.highlights ?? []
        if !highlights.sharesStorage(with: self.highlights) {
            self.highlights = highlights
            snapshot.highlights = highlights.map { ($0.pageIndex, Color(nsColor: $0.color.nativeColor.withAlphaComponent(0.9))) }
            changed = true
        }
        let bookmarks = workspace?.bookmarks ?? []
        if !bookmarks.sharesStorage(with: self.bookmarks) { self.bookmarks = bookmarks; snapshot.bookmarks = bookmarks.map(\.pageIndex); changed = true }
        let notes = workspace?.notes ?? []
        if !notes.sharesStorage(with: self.notes) {
            self.notes = notes
            snapshot.notes = notes.map { note in
                (note.anchor.pageIndex, note.isDue() ? Color.lemmaOlive : (note.state == .understood ? Color.green.opacity(0.8) : Color.lemmaOlive.opacity(0.75)))
            }
            changed = true
        }
        let understood = workspace?.understood ?? [], folded = workspace?.foldedProofs ?? []
        let analyzedAt = store.analysis?.analysis?.analyzedAt
        if !understood.sharesStorage(with: self.understood) || !folded.sharesStorage(with: self.folded) || analyzedAt != self.analyzedAt {
            self.understood = understood; self.folded = folded; self.analyzedAt = analyzedAt
            if let structure = store.analysis?.analysis?.structure {
                let understoodKeys = Set(understood), foldedIDs = Set(folded)
                snapshot.statements = structure.statements.map { statement in
                    (statement.start.pageIndex, understoodKeys.contains(statement.key) ? Color.green.opacity(0.9) : KindBadge.color(for: statement.key).opacity(0.75))
                }
                snapshot.folded = structure.proofs.filter { foldedIDs.contains($0.stableID) }.map { ($0.start.pageIndex, $0.end.pageIndex) }
            } else { snapshot.statements = []; snapshot.folded = [] }
            changed = true
        }
        // Results grow in batches while a search runs: the matches already placed are kept.
        let results = store.reader.searchResults.prefix(2000)
        if store.document !== document { document = store.document; matches = []; snapshot.matches = []; changed = true }
        let extends = results.count >= matches.count && (matches.isEmpty || (results[results.startIndex] === matches[0]
            && results[results.startIndex + matches.count - 1] === matches[matches.count - 1]))
        if !extends { matches = []; snapshot.matches = []; changed = true }
        if results.count > matches.count, let document {
            for match in results.dropFirst(matches.count) { if let page = match.pages.first { snapshot.matches.append(document.index(for: page)) } }
            matches = Array(results); changed = true
        }
        let split = store.split?.pageIndex
        if split != snapshot.split { snapshot.split = split; changed = true }
        computed = true
        if changed { revision &+= 1; QAPerf.tick("OverviewRuler.marks") }
        return snapshot
    }
}
