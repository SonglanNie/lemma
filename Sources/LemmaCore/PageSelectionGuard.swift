import Foundation
import PDFKit

/// Decides whether a page of a document may make text selections. A document's delegate takes this role, and
/// `SelectionGuardedPage` asks it.
public protocol PageSelectionPolicy: AnyObject {
    func admitsSelection(on page: PDFPage, in document: PDFDocument) -> Bool
    /// Called on an admitted page just before it makes a selection, which may end the process.
    func willSelect(on page: PDFPage, in document: PDFDocument)
}

extension PDFPage {
    /// False while the document's policy refuses selections on this page. Work derived from selections asks first, so that
    /// a refused page is tried again later rather than remembered as empty.
    public var admitsSelection: Bool {
        guard let document, let policy = document.delegate as? PageSelectionPolicy else { return true }
        return policy.admitsSelection(on: self, in: document)
    }
}

/// A page that gives no selection when its document's policy refuses it.
///
/// CoreGraphics traps on a few ordinary pages (seen on macOS 26.4, about one page in three hundred of the affected
/// books): selecting on them reaches a text range of negative length, and the process ends. The page's text and fonts
/// read normally, the trap needs no earlier call, and no property of the page predicts it. Every selection a page can
/// make is refused here, which callers already handle: `selection(for:)` and its relatives return nil on any page.
///
/// Subclasses must hold no state: PDFKit makes these pages without running Swift's property initialisers, so a stored
/// property reads as zeroed memory (an `Int?` reads as 0, on every page).
open class SelectionGuardedPage: PDFPage {
    private var maySelect: Bool {
        guard admitsSelection else { return false }
        if let document, let policy = document.delegate as? PageSelectionPolicy { policy.willSelect(on: self, in: document) }
        return true
    }

    open override func selection(for rect: CGRect) -> PDFSelection? {
        maySelect ? super.selection(for: rect) : nil
    }

    open override func selection(for range: NSRange) -> PDFSelection? {
        maySelect ? super.selection(for: range) : nil
    }

    open override func selection(from startPoint: CGPoint, to endPoint: CGPoint) -> PDFSelection? {
        maySelect ? super.selection(from: startPoint, to: endPoint) : nil
    }

    open override func selectionForWord(at point: CGPoint) -> PDFSelection? {
        maySelect ? super.selectionForWord(at: point) : nil
    }

    open override func selectionForLine(at point: CGPoint) -> PDFSelection? {
        maySelect ? super.selectionForLine(at: point) : nil
    }
}

/// The policy of a book being analysed. A trapping page can only be found by trapping, and a trap ends the process, so
/// `LemmaIndexer` analyses a book in a child process: it reads the markers this guard reports, and starts the analysis
/// again with the page that trapped in `blocked`. A blocked page keeps its text, so mentions on it are still found, and
/// loses what depends on its layout: the statements on it, usually all of them, are missing from the analysis.
///
/// Call `watch(_:)` before reading any page: PDFKit asks for the page class when it first makes a page.
public final class PageSelectionGuard: NSObject, PDFDocumentDelegate, PageSelectionPolicy {
    private let blocked: Set<Int>
    private let onSelecting: (Int) -> Void
    private var lastReported: Int?
    /// `PDFDocument.index(for:)` is asked once per page: an analysis makes many selections on each.
    private var indexes: [ObjectIdentifier: Int] = [:]

    /// - Parameters:
    ///   - blocked: page indexes that give no selections.
    ///   - onSelecting: called with a page's index before its first selection, and again whenever selections move to
    ///     another page, so the last call names the page in use when the process died.
    public init(blocked: Set<Int> = [], onSelecting: @escaping (Int) -> Void = { _ in }) {
        self.blocked = blocked
        self.onSelecting = onSelecting
    }

    /// `PDFDocument.delegate` is weak: the caller keeps the guard for as long as it reads the document.
    public func watch(_ document: PDFDocument) {
        document.delegate = self
    }

    public func classForPage() -> AnyClass { SelectionGuardedPage.self }

    public func admitsSelection(on page: PDFPage, in document: PDFDocument) -> Bool {
        !blocked.contains(index(of: page, in: document))
    }

    public func willSelect(on page: PDFPage, in document: PDFDocument) {
        let pageIndex = index(of: page, in: document)
        guard pageIndex != lastReported else { return }
        lastReported = pageIndex
        onSelecting(pageIndex)
    }

    private func index(of page: PDFPage, in document: PDFDocument) -> Int {
        let key = ObjectIdentifier(page)
        if let known = indexes[key] { return known }
        let pageIndex = document.index(for: page)
        indexes[key] = pageIndex
        return pageIndex
    }
}

/// Which pages of a book the reader may select on. A page that traps can only be found by trying it, and a trap in the
/// reader ends Lemma, so a page is refused until the analysis, which tries it in a process of its own, has read it.
///
/// The analysis selects again in later passes, so a page it has read can still prove bad: it is blocked as soon as that
/// happens. Until then a selection there is covered only by `PageInUseRecord`.
public struct PageSelectionClearance: Sendable, Equatable {
    public private(set) var blocked: Set<Int>
    /// Pages before this index have been read.
    private var pagesRead = 0
    private var allPagesRead = false

    public init(blocked: Set<Int> = []) { self.blocked = blocked }

    public func admits(_ pageIndex: Int) -> Bool {
        (allPagesRead || pageIndex < pagesRead) && !blocked.contains(pageIndex)
    }

    public var admitsEveryPage: Bool { allPagesRead && blocked.isEmpty }

    /// Some pages are refused only until the analysis reaches them.
    public var isWaitingForPages: Bool { !allPagesRead }

    /// The analysis has read this many pages. A run that starts over reports fewer: what it read before still stands.
    public mutating func read(pages count: Int) { pagesRead = max(pagesRead, count) }

    /// Every page is cleared: the book's analysis is known, or there will be none to wait for.
    public mutating func readAllPages() { allPagesRead = true }

    public mutating func block(_ pages: Set<Int>) { blocked.formUnion(pages) }
}

/// The paths the trap handler renames between: a signal handler can touch nothing that allocates or locks.
private nonisolated(unsafe) var pageInUseNotePath: UnsafeMutablePointer<CChar>?
private nonisolated(unsafe) var pageInUseTrapPath: UnsafeMutablePointer<CChar>?

/// A note, on disk, of the page selections last ran on. The analysis cannot find every bad page, because a page may trap
/// only for some selections, and without the note a book reopening on such a page would crash every time.
///
/// A trap leaves no time to work out what happened, so the note is written first, and the signal handler only renames it.
/// A note that was not renamed blames nothing: force quitting or losing power must not cost a healthy page its selections.
/// Swift's own runtime errors trap too, so one within `holdTime` of a selection does blame that page. A note lasts that long
/// after the page's last selection, and quitting removes it.
public final class PageInUseRecord: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var book: String
        public var pageIndex: Int
        public init(book: String, pageIndex: Int) { self.book = book; self.pageIndex = pageIndex }
    }

    private let url: URL
    private let holdTime: TimeInterval
    private let lock = NSLock()
    private var noted: Entry?
    private var lastUse = Date.distantPast
    private var removalScheduled = false
    private var held = false

    public init(url: URL, holdTime: TimeInterval = 2) { self.url = url; self.holdTime = holdTime }

    private static func trapURL(for url: URL) -> URL { url.appendingPathExtension("trapped") }

    /// From now on a trap (SIGTRAP on Apple silicon, SIGILL on Intel) marks the note. The handler then gives the signal back
    /// to the system and returns: the instruction runs again and the process ends as it would have, with its crash report.
    public func markNoteOnTrap() {
        pageInUseNotePath = strdup(url.path)
        pageInUseTrapPath = strdup(Self.trapURL(for: url).path)
        for number in [SIGTRAP, SIGILL] {
            signal(number) { number in
                if let note = pageInUseNotePath, let trap = pageInUseTrapPath { rename(note, trap) }
                signal(number, SIG_DFL)
            }
        }
    }

    /// Called before every selection, so only a change of page reaches the disk. Keeping the note is worth less than
    /// reading the page: a note that cannot be written leaves the page unprotected, as it was.
    public func note(_ entry: Entry) {
        lock.withLock {
            lastUse = .now
            guard entry != noted else { return }
            noted = entry
            try? JSONEncoder().encode(entry).write(to: url)
            scheduleRemoval(after: holdTime)
        }
    }

    /// Keeps the note for as long as `work` runs, however long since the last selection: PDFKit's mouse tracking selects
    /// without asking the page, for as long as the button is down.
    public func hold(during work: () -> Void) {
        lock.withLock { held = true }
        work()
        lock.withLock { held = false; lastUse = .now }
    }

    /// Lemma is quitting normally.
    public func remove() {
        lock.withLock { noted = nil; try? FileManager.default.removeItem(at: url) }
    }

    private func scheduleRemoval(after delay: TimeInterval) {
        guard !removalScheduled else { return }
        removalScheduled = true
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in self?.removeIfIdle() }
    }

    private func removeIfIdle() {
        lock.withLock {
            removalScheduled = false
            guard noted != nil else { return }
            let idle = held ? 0 : Date.now.timeIntervalSince(lastUse)
            if idle >= holdTime { noted = nil; try? FileManager.default.removeItem(at: url) }
            else { scheduleRemoval(after: holdTime - idle) }
        }
    }

    /// The page the last run of Lemma trapped on, if any. Removes what that run left.
    public static func take(at url: URL) -> Entry? {
        let trapURL = trapURL(for: url)
        defer { for leftover in [url, trapURL] { try? FileManager.default.removeItem(at: leftover) } }
        guard let data = try? Data(contentsOf: trapURL) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }
}

extension DocumentIndexRepository {
    /// Where `PageInUseRecord` keeps its note.
    public var pageInUseURL: URL { root.appendingPathComponent("selection-page-in-use.json") }

    private func blockedPagesURL(_ id: String) -> URL { directory(id).appendingPathComponent("selection-blocked-pages.json") }

    /// The pages of a book known to crash text selection, found by its analysis or by the reader crashing there. A file of
    /// its own, because the reader needs it before it may touch a page and the analysis takes time to read.
    public func selectionBlockedPages(_ id: String) -> Set<Int> {
        guard let data = try? Data(contentsOf: blockedPagesURL(id)), let pages = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
        return Set(pages)
    }

    public func addSelectionBlockedPages(_ pages: Set<Int>, id: String) throws {
        guard !pages.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory(id), withIntermediateDirectories: true)
        try JSONEncoder().encode(selectionBlockedPages(id).union(pages).sorted()).write(to: blockedPagesURL(id), options: .atomic)
    }
}

/// What the process supervising an analysis does when its child dies on a page.
public struct PageSelectionRecovery: Sendable, Equatable {
    /// Each blocked page costs a full run of the analysis, and a book with this many has a different problem.
    public static let pageLimit = 8

    public private(set) var blocked: Set<Int> = []

    public init() {}

    /// Blocks the page that was in use when the child died. False when another run cannot help: no page was in use, the
    /// page was already blocked, or the limit is reached. The crash then lies elsewhere than in a page's selections.
    public mutating func block(_ pageIndex: Int?) -> Bool {
        guard let pageIndex, !blocked.contains(pageIndex), blocked.count < Self.pageLimit else { return false }
        blocked.insert(pageIndex)
        return true
    }

    /// The child's report of the page it is selecting on, one line of its standard output.
    public static func marker(pageIndex: Int) -> String { "selecting \(pageIndex)" }

    public static func pageIndex(inMarker line: some StringProtocol) -> Int? { pageIndex(in: line, after: "selecting") }

    /// The supervisor's report that a page is blocked, one line of its standard output, so the reader hears at once.
    public static func blockedReport(pageIndex: Int) -> String { "blocked \(pageIndex)" }

    public static func pageIndex(inBlockedReport line: some StringProtocol) -> Int? { pageIndex(in: line, after: "blocked") }

    private static func pageIndex(in line: some StringProtocol, after word: String) -> Int? {
        let parts = line.split(separator: " ")
        guard parts.count == 2, parts[0] == word else { return nil }
        return Int(parts[1])
    }

    /// The blocked pages as one command-line argument, and back.
    public static func argument(for pages: Set<Int>) -> String { pages.sorted().map(String.init).joined(separator: ",") }

    public static func pages(inArgument argument: String) -> Set<Int>? {
        var pages: Set<Int> = []
        for part in argument.split(separator: ",") {
            guard let page = Int(part) else { return nil }
            pages.insert(page)
        }
        return pages
    }
}
