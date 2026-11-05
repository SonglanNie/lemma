import Foundation
import PDFKit

/// Decides what a page of a document may do with its text. A document's delegate takes this role, and `TextGuardedPage` asks it.
public protocol PageTextPolicy: AnyObject {
    func admitsText(on page: PDFPage, in document: PDFDocument) -> Bool
    func admitsSelection(on page: PDFPage, in document: PDFDocument) -> Bool
    /// False while any page is refused text or selections: PDFKit's own selection and search, which ask no page, stay out.
    func admitsEveryPage(in document: PDFDocument) -> Bool
    /// Called on an admitted page just before it reads its text, which may never return.
    func willReadText(on page: PDFPage, in document: PDFDocument)
    /// Called on an admitted page just before it makes a selection, which may end the process.
    func willSelect(on page: PDFPage, in document: PDFDocument)
}

extension PDFPage {
    /// False while the document's policy refuses this page's text. Work derived from the text asks first, so that a refused
    /// page is tried again later rather than remembered as empty.
    public var admitsText: Bool {
        guard let document, let policy = document.delegate as? PageTextPolicy else { return true }
        return policy.admitsText(on: self, in: document)
    }

    /// False while the document's policy refuses selections on this page, which it does whenever it refuses the page's text.
    public var admitsSelection: Bool {
        guard let document, let policy = document.delegate as? PageTextPolicy else { return true }
        return policy.admitsSelection(on: self, in: document)
    }
}

extension PDFDocument {
    public var admitsEveryPage: Bool { (delegate as? PageTextPolicy)?.admitsEveryPage(in: self) ?? true }
}

/// A page that gives no text or selection when its document's policy refuses it.
///
/// Two macOS bugs make this necessary, on ordinary pages that no property predicts (both seen on macOS 26.4):
/// - CoreGraphics traps on about one page in three hundred of the affected books: selecting there reaches a text range of
///   negative length, and the process ends. The page's text and fonts read normally.
/// - On one page in 6,688 books, building the page's text layout takes about 1 GB a second and never returns. Every text call
///   and selection does so, and only drawing is safe.
///
/// Every call a page can receive is refused here, which callers already handle: `string` and `selection(for:)` return nil on
/// any page. Three CoreGraphics functions build a page's text, and on macOS 26.4 all PDFKit's calls to them are covered:
/// `CGPDFPageCopyString` by `string`, `CGPDFPageCopyPageLayout` by `buildPageLayout`, which is what a mouse move and a context
/// menu reach, from PDFKit's own threads too, and `CGPDFPageCopyRootTaggedNode` by `PageAccessibilityGuard`.
///
/// Subclasses must hold no state: PDFKit makes these pages without running Swift's property initialisers, so a stored
/// property reads as zeroed memory (an `Int?` reads as 0, on every page).
open class TextGuardedPage: PDFPage {
    private var mayReadText: Bool {
        guard admitsText else { return false }
        if let document, let policy = document.delegate as? PageTextPolicy { policy.willReadText(on: self, in: document) }
        return true
    }

    private var maySelect: Bool {
        guard admitsSelection else { return false }
        if let document, let policy = document.delegate as? PageTextPolicy { policy.willSelect(on: self, in: document) }
        return true
    }

    /// PDFKit's private method, which all its uses of a page's text layout go through. Nothing public reaches a mouse move or a
    /// right click, so this replaces it by name. Should macOS rename it, PDFKit stops calling this and those two paths lose
    /// their protection: `PageTextGuardTests` fails first. A page without a layout behaves as one without text.
    @objc(_buildPageLayout) dynamic func buildPageLayout() {
        guard mayReadText else { return }
        typealias Build = @convention(c) (AnyObject, Selector) -> Void
        let selector = #selector(buildPageLayout)
        guard let build = class_getMethodImplementation(PDFPage.self, selector) else { return }
        unsafeBitCast(build, to: Build.self)(self, selector)
    }

    open override var string: String? { mayReadText ? super.string : nil }

    open override var attributedString: NSAttributedString? { mayReadText ? super.attributedString : nil }

    open override var numberOfCharacters: Int { mayReadText ? super.numberOfCharacters : 0 }

    open override func characterBounds(at index: Int) -> CGRect { mayReadText ? super.characterBounds(at: index) : .zero }

    open override func characterIndex(at point: CGPoint) -> Int { mayReadText ? super.characterIndex(at: point) : -1 }

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

/// Keeps PDFKit's accessibility code off refused pages. It reads a page's tagged structure, which builds the page's text, for
/// anything that walks the accessibility tree and on some page changes with none, straight from `pageRef`: no method of the
/// page is involved, so the three private methods that do so are replaced here, once for the whole process. Each hands such
/// a page nothing, as for a page with no structure. `PageTextGuardTests` fails first if macOS renames one.
public enum PageAccessibilityGuard {
    static let rootNode = (type: "PDFAccessibilityNode", selector: NSSelectorFromString("createPDFAccessibilityRootNode:"))
    static let search = (type: "PDFAccessibilityNodePage", selector: NSSelectorFromString("resultNodeForSearchString:searchRange:searchOption:resultRange:"))
    static let imageNode = (type: "PDFAccessibilityNodeAnnotation", selector: NSSelectorFromString("_associatedImageNodeRef"))

    private static let installation: Void = {
        if let type = NSClassFromString(rootNode.type), let method = class_getClassMethod(type, rootNode.selector) {
            typealias Original = @convention(c) (AnyObject, Selector, AnyObject?) -> UnsafeRawPointer?
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self), selector = rootNode.selector
            let replacement: @convention(block) (AnyObject, AnyObject?) -> UnsafeRawPointer? = { node, page in
                refuses(page) ? nil : original(node, selector, page)
            }
            method_setImplementation(method, imp_implementationWithBlock(replacement))
        }
        if let type = NSClassFromString(search.type), let method = class_getInstanceMethod(type, search.selector) {
            typealias Original = @convention(c) (AnyObject, Selector, AnyObject?, NSRange, UInt, UnsafeMutablePointer<NSRange>?) -> UnsafeRawPointer?
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self), selector = search.selector
            let replacement: @convention(block) (AnyObject, AnyObject?, NSRange, UInt, UnsafeMutablePointer<NSRange>?) -> UnsafeRawPointer? = { node, text, range, option, result in
                refuses(page(of: node)) ? nil : original(node, selector, text, range, option, result)
            }
            method_setImplementation(method, imp_implementationWithBlock(replacement))
        }
        if let type = NSClassFromString(imageNode.type), let method = class_getInstanceMethod(type, imageNode.selector) {
            typealias Original = @convention(c) (AnyObject, Selector) -> UnsafeRawPointer?
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self), selector = imageNode.selector
            let replacement: @convention(block) (AnyObject) -> UnsafeRawPointer? = { node in
                refuses(page(of: node)) ? nil : original(node, selector)
            }
            method_setImplementation(method, imp_implementationWithBlock(replacement))
        }
    }()

    /// Call it before any document is shown.
    public static func install() { _ = installation }

    private static func refuses(_ page: AnyObject?) -> Bool { (page as? PDFPage)?.admitsText == false }

    private static func page(of node: AnyObject) -> AnyObject? {
        node.perform(NSSelectorFromString("page"))?.takeUnretainedValue()
    }
}

/// The policy of a book being read in a helper. A bad page can only be found by trying it. A trap ends the process, so
/// `LemmaIndexer` analyses a book in a child process: it reads the markers this guard reports, and starts the analysis again
/// with the page that trapped in `selectionBlocked`. A page whose text never returns is named by `pageInUse` when the helper
/// reaches its memory limit, and goes in `textBlocked`.
///
/// A page in `selectionBlocked` keeps its text, so mentions on it are still found, and loses what depends on its layout: the
/// statements on it, usually all of them, are missing from the analysis. A page in `textBlocked` loses everything but its image.
///
/// Call `watch(_:)` before reading any page: PDFKit asks for the page class when it first makes a page.
public final class PageTextGuard: NSObject, PDFDocumentDelegate, PageTextPolicy, @unchecked Sendable {
    private let selectionBlocked: Set<Int>
    public let textBlocked: Set<Int>
    private let onSelecting: (Int) -> Void
    private let lock = NSLock()
    private var inUse: Int?
    private var lastReported: Int?
    /// `PDFDocument.index(for:)` is asked once per page: an analysis makes many selections on each.
    private var indexes: [ObjectIdentifier: Int] = [:]

    /// - Parameters:
    ///   - selectionBlocked: page indexes that give no selections.
    ///   - textBlocked: page indexes that give neither text nor selections.
    ///   - onSelecting: called with a page's index before its first selection, and again whenever selections move to
    ///     another page, so the last call names the page in use when the process died.
    public init(selectionBlocked: Set<Int> = [], textBlocked: Set<Int> = [], onSelecting: @escaping (Int) -> Void = { _ in }) {
        self.selectionBlocked = selectionBlocked
        self.textBlocked = textBlocked
        self.onSelecting = onSelecting
    }

    /// `PDFDocument.delegate` is weak: the caller keeps the guard for as long as it reads the document. A guard may watch one
    /// document after another, but only one at a time: a page's identity outlives nothing it was read from.
    public func watch(_ document: PDFDocument) {
        lock.withLock { indexes = [:] }
        document.delegate = self
    }

    /// The page whose text or selections were asked for last. While a call on a page never returns, it names that page.
    public var pageInUse: Int? { lock.withLock { inUse } }

    public func classForPage() -> AnyClass { TextGuardedPage.self }

    public func admitsText(on page: PDFPage, in document: PDFDocument) -> Bool {
        !textBlocked.contains(index(of: page, in: document))
    }

    public func admitsSelection(on page: PDFPage, in document: PDFDocument) -> Bool {
        let pageIndex = index(of: page, in: document)
        return !textBlocked.contains(pageIndex) && !selectionBlocked.contains(pageIndex)
    }

    public func admitsEveryPage(in document: PDFDocument) -> Bool { textBlocked.isEmpty && selectionBlocked.isEmpty }

    public func willReadText(on page: PDFPage, in document: PDFDocument) {
        let pageIndex = index(of: page, in: document)
        lock.withLock { inUse = pageIndex }
    }

    public func willSelect(on page: PDFPage, in document: PDFDocument) {
        let pageIndex = index(of: page, in: document)
        let moved = lock.withLock { () -> Bool in
            inUse = pageIndex
            guard pageIndex != lastReported else { return false }
            lastReported = pageIndex
            return true
        }
        if moved { onSelecting(pageIndex) }
    }

    /// PDFKit is asked outside the lock: it may be waiting for a thread that is here.
    private func index(of page: PDFPage, in document: PDFDocument) -> Int {
        let key = ObjectIdentifier(page)
        if let known = lock.withLock({ indexes[key] }) { return known }
        let pageIndex = document.index(for: page)
        lock.withLock { indexes[key] = pageIndex }
        return pageIndex
    }
}

/// What a page copied out of its book may do: what its book allowed when it was copied. The copy keeps its class and lives in
/// a document of its own, whose delegate this is. Keep it for as long as the document: `PDFDocument.delegate` is weak.
public final class CopiedPagePolicy: NSObject, PDFDocumentDelegate, PageTextPolicy {
    private let text: Bool
    private let selections: Bool

    public init(copying page: PDFPage) {
        text = page.admitsText
        selections = page.admitsSelection
    }

    public func admitsText(on page: PDFPage, in document: PDFDocument) -> Bool { text }
    public func admitsSelection(on page: PDFPage, in document: PDFDocument) -> Bool { selections }
    public func admitsEveryPage(in document: PDFDocument) -> Bool { text && selections }
    public func willReadText(on page: PDFPage, in document: PDFDocument) {}
    public func willSelect(on page: PDFPage, in document: PDFDocument) {}
}

/// What the reader may do with each page of a book. A page that traps or whose text never returns can only be found by trying
/// it, and either one in the reader ends Lemma or takes the Mac's memory, so a page gives no text or selections until the
/// analysis, which tries it in a process of its own, has read it.
///
/// The analysis selects again in later passes, so a page it has read can still prove bad: it is blocked as soon as that
/// happens. Until then a selection there is covered only by `PageInUseRecord`.
public struct PageTextClearance: Sendable, Equatable {
    public private(set) var selectionBlocked: Set<Int>
    public private(set) var textBlocked: Set<Int>
    /// Pages before this index have been read.
    private var pagesRead = 0
    private var allPagesRead = false

    public init(selectionBlocked: Set<Int> = [], textBlocked: Set<Int> = []) {
        self.selectionBlocked = selectionBlocked
        self.textBlocked = textBlocked
    }

    public func admitsText(_ pageIndex: Int) -> Bool {
        (allPagesRead || pageIndex < pagesRead) && !textBlocked.contains(pageIndex)
    }

    public func admitsSelection(_ pageIndex: Int) -> Bool {
        admitsText(pageIndex) && !selectionBlocked.contains(pageIndex)
    }

    public var admitsEveryPage: Bool { allPagesRead && selectionBlocked.isEmpty && textBlocked.isEmpty }

    /// Some pages are refused only until the analysis reaches them.
    public var isWaitingForPages: Bool { !allPagesRead }

    /// The analysis has read this many pages. A run that starts over reports fewer: what it read before still stands.
    public mutating func read(pages count: Int) { pagesRead = max(pagesRead, count) }

    /// Every page is cleared: the book's analysis is known, or there will be none to wait for.
    public mutating func readAllPages() { allPagesRead = true }

    public mutating func blockSelection(_ pages: Set<Int>) { selectionBlocked.formUnion(pages) }

    public mutating func blockText(_ pages: Set<Int>) { textBlocked.formUnion(pages) }
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

    private func selectionBlockedURL(_ id: String) -> URL { directory(id).appendingPathComponent("selection-blocked-pages.json") }

    private func textBlockedURL(_ id: String) -> URL { directory(id).appendingPathComponent("text-blocked-pages.json") }

    private func pages(at url: URL) -> Set<Int> {
        guard let data = try? Data(contentsOf: url), let pages = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
        return Set(pages)
    }

    private func add(_ pages: Set<Int>, to url: URL, id: String) throws {
        guard !pages.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory(id), withIntermediateDirectories: true)
        try JSONEncoder().encode(self.pages(at: url).union(pages).sorted()).write(to: url, options: .atomic)
    }

    /// The pages of a book known to crash text selection, found by its analysis or by the reader crashing there. A file of
    /// its own, because the reader needs it before it may touch a page and the analysis takes time to read.
    public func selectionBlockedPages(_ id: String) -> Set<Int> { pages(at: selectionBlockedURL(id)) }

    public func addSelectionBlockedPages(_ pages: Set<Int>, id: String) throws { try add(pages, to: selectionBlockedURL(id), id: id) }

    /// The pages of a book whose text never returns, found by a helper reaching its memory limit there. Apart from
    /// `selectionBlockedPages`, because those pages keep their text.
    public func textBlockedPages(_ id: String) -> Set<Int> { pages(at: textBlockedURL(id)) }

    public func addTextBlockedPages(_ pages: Set<Int>, id: String) throws { try add(pages, to: textBlockedURL(id), id: id) }

    /// What is known of a book's pages before its analysis has said more.
    public func pageTextClearance(_ id: String) -> PageTextClearance {
        PageTextClearance(selectionBlocked: selectionBlockedPages(id), textBlocked: textBlockedPages(id))
    }
}

/// What the process supervising an analysis does when its child dies on a page.
public struct PageTextRecovery: Sendable, Equatable {
    /// Each blocked page costs a full run of the analysis, and a book with this many has a different problem.
    public static let pageLimit = 8

    public private(set) var selectionBlocked: Set<Int> = []

    public init() {}

    /// Blocks the page that was in use when the child died. False when another run cannot help: no page was in use, the
    /// page was already blocked, or the limit is reached. The crash then lies elsewhere than in a page's selections.
    public mutating func blockSelection(_ pageIndex: Int?) -> Bool {
        guard let pageIndex, !selectionBlocked.contains(pageIndex), selectionBlocked.count < Self.pageLimit else { return false }
        selectionBlocked.insert(pageIndex)
        return true
    }

    /// The page to block when a helper reaches its memory limit, with `pageInUse` the page it last asked for text and `known`
    /// the pages it was refusing. Nil when reading the book again cannot help: no page was in use, that page was refused
    /// already, or the limit is reached. The memory then went elsewhere than to a page's text.
    public static func textPage(toBlock pageInUse: Int?, known: Set<Int>) -> Int? {
        guard let pageInUse, !known.contains(pageInUse), known.count < pageLimit else { return nil }
        return pageInUse
    }

    /// The child's report of the page it is selecting on, one line of its standard output.
    public static func marker(pageIndex: Int) -> String { "selecting \(pageIndex)" }

    public static func pageIndex(inMarker line: some StringProtocol) -> Int? { pageIndex(in: line, after: "selecting") }

    /// The supervisor's report that a page is blocked, one line of its standard output, so the reader hears at once.
    public static func blockedReport(pageIndex: Int) -> String { "blocked \(pageIndex)" }

    public static func pageIndex(inBlockedReport line: some StringProtocol) -> Int? { pageIndex(in: line, after: "blocked") }

    /// A helper's report that a page's text is blocked, one line of its standard output.
    public static func textBlockedReport(pageIndex: Int) -> String { "text-blocked \(pageIndex)" }

    public static func pageIndex(inTextBlockedReport line: some StringProtocol) -> Int? { pageIndex(in: line, after: "text-blocked") }

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
