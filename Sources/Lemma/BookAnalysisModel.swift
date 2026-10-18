import AppKit
import PDFKit
import LemmaCore
import Observation
import os

/// The whole-book analysis of one open document: loaded from its cache, or computed once in the background
/// with progress shown in the status bar, like an IDE indexing a project.
@MainActor @Observable
final class BookAnalysisModel {
    let workspaceID: String
    private(set) var analysis: BookAnalysis?
    /// Pages read so far while analysing; nil when idle.
    private(set) var progress: (done: Int, total: Int)?
    private(set) var failed = false
    /// Why the last analysis failed, for the status bar.
    private(set) var failure: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cancellation: CancellationFlag?
    @ObservationIgnored private let repository: DocumentIndexRepository
    @ObservationIgnored private(set) var definitionsByKey: [ReferenceKey: ReferenceTarget] = [:]
    @ObservationIgnored private(set) var definitionCounts: [ReferenceKind: Int] = [:]
    @ObservationIgnored private(set) var mentionCounts: [ReferenceKey: Int] = [:]
    @ObservationIgnored private(set) var definitionsByPage: [Int: [ReferenceTarget]] = [:]
    @ObservationIgnored private(set) var citationsByPage: [Int: [CitationRecord]] = [:]
    @ObservationIgnored private(set) var citationCounts: [Int: Int] = [:]
    /// Undotted equation labels the book defines, so “(12)” is a reference in papers that number equations that way.
    @ObservationIgnored private(set) var plainEquations: Set<String> = []
    /// Maps a mention to the item the book defines under that number.
    @ObservationIgnored private(set) var resolver = KeyResolver(definitions: [])
    /// Proofs by the pages they cover, for folding them on the page.
    @ObservationIgnored private(set) var proofsByPage: [Int: [ProofBlock]] = [:]
    @ObservationIgnored private(set) var statementsByKey: [ReferenceKey: StatementInfo] = [:]
    @ObservationIgnored private(set) var usesByKey: [ReferenceKey: [DependencyEdge]] = [:]
    @ObservationIgnored private(set) var usedByKey: [ReferenceKey: [DependencyEdge]] = [:]
    /// What the book's symbols stand for, by position.
    @ObservationIgnored private(set) var notation = NotationIndex([])
    /// Called on the main actor when an analysis is ready: read from its cache, or freshly made.
    @ObservationIgnored var onReady: (() -> Void)?
    /// The saved analysis is being read (megabytes for a long book) off the main thread.
    private(set) var isLoadingCache = false
    @ObservationIgnored private var cacheTask: Task<Void, Never>?
    /// A `start` asked for while the cache was being read: it runs only if no saved analysis turns up.
    @ObservationIgnored private var pendingStart: (url: URL, outline: [OutlineItem], force: Bool)?
    /// The helper process reading this book, so closing the book or quitting stops it at once.
    @ObservationIgnored private var helper: HelperHandle?

    /// Reads the saved analysis in the background: decoding it and building its indexes takes tens of milliseconds for
    /// a long book, which the window's first frame and switching tabs should not wait for. Until it arrives the book reads
    /// as not analysed yet; its decorations appear with `onReady`.
    init(workspaceID: String, repository: DocumentIndexRepository) {
        self.workspaceID = workspaceID; self.repository = repository
        isLoadingCache = true
        let id = workspaceID
        cacheTask = Task { [weak self] in
            let prepared = await Task.detached(priority: .userInitiated) { repository.bookAnalysis(id).map(Prepared.init) }.value
            guard let self, !Task.isCancelled else { return }
            self.isLoadingCache = false; self.cacheTask = nil
            if let prepared, self.analysis == nil { self.apply(prepared); self.onReady?() }
            if let request = self.pendingStart {
                self.pendingStart = nil
                self.start(url: request.url, outline: request.outline, force: request.force)
            }
        }
    }

    var isAnalyzing: Bool { progress != nil }
    var numbering: PageNumbering? { analysis?.numbering }

    /// The packaged helper that reads books in its own process; nil when running from tests or `swift run`.
    nonisolated static var helperURL: URL? {
        Bundle.main.bundleURL.pathExtension == "app" ? PageIndexer.helperURL : nil
    }

    /// Starts reading the book unless a current analysis exists. The packaged app reads it in a helper process, so a
    /// malformed PDF can stop the analysis but never the reader; elsewhere it runs on a background thread.
    func start(url: URL, outline: [OutlineItem], force: Bool = false) {
        if isLoadingCache, !force { pendingStart = (url, outline, force); return }
        guard task == nil, force || analysis == nil else { return }
        failed = false; failure = nil
        progress = (0, 0)
        let id = workspaceID, repository = repository, flag = CancellationFlag()
        cancellation = flag
        if let helperURL = Self.helperURL {
            let handle = HelperHandle()
            helper = handle
            task = Task { [weak self] in
                let reporter = ProgressRelay { done, total in self?.progress = (done, total) }
                let outcome = await Self.runHelper(helperURL, source: url, id: id, root: repository.root, flag: flag, reporter: reporter, handle: handle)
                guard let self, !flag.isCancelled else { return }
                switch outcome {
                case .finished:
                    // Read back and indexed off the main thread, like a cached analysis.
                    let prepared = await Task.detached(priority: .userInitiated) { repository.bookAnalysis(id).map(Prepared.init) }.value
                    guard !flag.isCancelled else { return }
                    self.task = nil; self.progress = nil; self.cancellation = nil; self.helper = nil
                    guard let prepared else { self.failed = true; self.failure = "The analysis could not be read back."; return }
                    self.apply(prepared)
                    self.onReady?()
                case let .failed(message):
                    self.task = nil; self.progress = nil; self.cancellation = nil; self.helper = nil
                    self.failed = true; self.failure = message
                }
            }
            return
        }
        task = Task { [weak self] in
            let reporter = ProgressRelay { done, total in self?.progress = (done, total) }
            let prepared = await Task.detached(priority: .utility) { () -> Prepared? in
                guard let result = BookAnalyzer.analyze(url: url, outline: outline, progress: { done, total in reporter.report(done, total) },
                                                        isCancelled: { flag.isCancelled }) else { return nil }
                try? repository.save(result, id: id)
                return Prepared(result)
            }.value
            guard let self, !flag.isCancelled else { return }
            self.task = nil; self.progress = nil; self.cancellation = nil
            guard let prepared else { self.failed = true; return }
            self.apply(prepared)
            self.onReady?()
        }
    }

    /// Leaves the book unanalysed, saying why in the status bar and the Results view.
    func skip(_ reason: String) {
        cacheTask?.cancel(); cacheTask = nil; isLoadingCache = false; pendingStart = nil
        failed = true; failure = reason
    }

    enum HelperOutcome: Sendable { case finished, failed(String) }

    /// Runs `LemmaIndexer --analyze` at utility priority, relaying its progress lines; cancelling terminates it. Its error
    /// output is read as it comes (keeping the end), so a helper that logs a lot never blocks on a full pipe.
    nonisolated static func runHelper(_ helper: URL, source: URL, id: String, root: URL, flag: CancellationFlag,
                                      reporter: ProgressRelay, handle: HelperHandle = HelperHandle()) async -> HelperOutcome {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = helper
            process.arguments = ["--analyze", source.path, "--workspace", id, "--root", root.path]
            process.qualityOfService = .utility
            let output = Pipe(), errors = Pipe()
            process.standardOutput = output; process.standardError = errors
            let buffer = LineBuffer()
            let errorTail = OutputTail(limit: 64 * 1024)
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for line in buffer.append(data) {
                    let parts = line.split(separator: " ")
                    if parts.count == 3, parts[0] == "progress", let done = Int(parts[1]), let total = Int(parts[2]) { reporter.report(done, total) }
                }
                if flag.isCancelled, process.isRunning { process.terminate() }
            }
            errors.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { errorTail.append(data) }
            }
            process.terminationHandler = { process in
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                errorTail.append(errors.fileHandleForReading.readDataToEndOfFile())
                handle.finished()
                let message = errorTail.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationReason == .exit, process.terminationStatus == 0 { continuation.resume(returning: .finished) }
                else if process.terminationReason == .uncaughtSignal {
                    continuation.resume(returning: .failed("The book's structure could not be read: the analysis stopped on this PDF. Reading, notes and search still work."))
                } else {
                    continuation.resume(returning: .failed(message.isEmpty ? "The analysis did not finish." : message))
                }
            }
            do {
                try process.run()
                handle.started(process)
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: .failed(error.localizedDescription))
            }
        }
    }

    func cancel() {
        cacheTask?.cancel(); cacheTask = nil; isLoadingCache = false; pendingStart = nil
        cancellation?.cancel(); cancellation = nil; task?.cancel(); task = nil; progress = nil
        // The helper would otherwise read on until its next progress line, and could still save an analysis.
        helper?.terminate(); helper = nil
    }

    /// Stops every analysis helper still running: Lemma is quitting.
    nonisolated static func terminateHelpers() { HelperHandle.terminateAll() }

    /// Everything derived from an analysis, computed off the main thread before it is shown.
    struct Prepared: Sendable {
        let analysis: BookAnalysis
        let definitionsByKey: [ReferenceKey: ReferenceTarget]
        let definitionCounts: [ReferenceKind: Int]
        let mentionCounts: [ReferenceKey: Int]
        let definitionsByPage: [Int: [ReferenceTarget]]
        let citationsByPage: [Int: [CitationRecord]]
        let citationCounts: [Int: Int]
        let plainEquations: Set<String>
        let resolver: KeyResolver
        let proofsByPage: [Int: [ProofBlock]]
        let statementsByKey: [ReferenceKey: StatementInfo]
        let usesByKey: [ReferenceKey: [DependencyEdge]]
        let usedByKey: [ReferenceKey: [DependencyEdge]]
        let notation: NotationIndex

        init(_ analysis: BookAnalysis) {
            self.analysis = analysis
            definitionsByKey = analysis.definitionsByKey()
            definitionCounts = definitionsByKey.keys.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
            mentionCounts = analysis.mentionCounts()
            definitionsByPage = Dictionary(grouping: analysis.definitions, by: \.pageIndex)
            citationsByPage = Dictionary(grouping: analysis.citations, by: \.pageIndex)
            citationCounts = analysis.citations.reduce(into: [:]) { counts, record in for id in record.entryIDs { counts[id, default: 0] += 1 } }
            plainEquations = analysis.plainEquationLabels()
            resolver = KeyResolver(definitions: analysis.definitions, itemsByNumber: analysis.itemsByNumber)
            var proofs: [Int: [ProofBlock]] = [:]
            for proof in analysis.structure.proofs {
                for page in Set(proof.regions.map(\.pageIndex)) { proofs[page, default: []].append(proof) }
            }
            proofsByPage = proofs
            statementsByKey = Dictionary(analysis.structure.statements.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            usesByKey = Dictionary(grouping: analysis.structure.edges, by: \.from)
            usedByKey = Dictionary(grouping: analysis.structure.edges, by: \.to)
            notation = NotationIndex(analysis.symbols)
        }
    }

    private func apply(_ prepared: Prepared) {
        analysis = prepared.analysis
        definitionsByKey = prepared.definitionsByKey
        definitionCounts = prepared.definitionCounts
        mentionCounts = prepared.mentionCounts
        definitionsByPage = prepared.definitionsByPage
        citationsByPage = prepared.citationsByPage
        citationCounts = prepared.citationCounts
        plainEquations = prepared.plainEquations
        resolver = prepared.resolver
        proofsByPage = prepared.proofsByPage
        statementsByKey = prepared.statementsByKey
        usesByKey = prepared.usesByKey
        usedByKey = prepared.usedByKey
        notation = prepared.notation
    }

    var structure: DocumentStructure { analysis?.structure ?? DocumentStructure() }

    /// What `key` mentions, merged across its statement and proof, most mentioned first.
    func uses(_ key: ReferenceKey) -> [DependencyEdge] { Self.merged(usesByKey[key] ?? [], by: \.to) }
    /// The statements and sections that mention `key`, most mentions first.
    func usedBy(_ key: ReferenceKey) -> [DependencyEdge] { Self.merged(usedByKey[key] ?? [], by: \.from) }

    private static func merged(_ edges: [DependencyEdge], by side: KeyPath<DependencyEdge, ReferenceKey>) -> [DependencyEdge] {
        var byKey: [ReferenceKey: DependencyEdge] = [:]
        for edge in edges {
            if var existing = byKey[edge[keyPath: side]] {
                existing.count += edge.count; existing.inProof = existing.inProof || edge.inProof
                byKey[edge[keyPath: side]] = existing
            } else { byKey[edge[keyPath: side]] = edge }
        }
        return byKey.values.sorted { $0.count == $1.count ? $0[keyPath: side].title < $1[keyPath: side].title : $0.count > $1.count }
    }

    /// The printed label of a physical page, when the book prints numbers different from the PDF's.
    func printedLabel(for pageIndex: Int) -> String? {
        guard let numbering, numbering.differsFromPhysical else { return nil }
        return numbering.label(for: pageIndex)
    }

    func references(to key: ReferenceKey) -> [MentionRecord] {
        analysis?.mentions.filter { $0.key == key } ?? []
    }

    /// The key a citation shows: the first entry it names, with its short title.
    func citationKey(for record: CitationRecord) -> ReferenceKey? {
        guard let id = record.entryIDs.first, let entry = analysis?.bibliography.first(where: { $0.id == id }) else { return nil }
        return ReferenceKey(kind: .citation, number: String(id), name: entry.shortTitle)
    }

    func bibliographyEntry(_ key: ReferenceKey) -> BibliographyEntry? {
        guard key.kind == .citation, let id = Int(key.number) else { return nil }
        return analysis?.bibliography.first { $0.id == id }
    }

    /// Where a citation leads: the entry in the reference list, shown like any other definition.
    func target(for key: ReferenceKey) -> ReferenceTarget? {
        if let entry = bibliographyEntry(key) {
            let first = CGRect(x: entry.region.x, y: entry.region.y + entry.region.height - 13, width: entry.region.width, height: 13)
            return ReferenceTarget(key: key, pageIndex: entry.pageIndex, anchor: PageRegion(first), region: entry.region, origin: .text)
        }
        return definitionsByKey[key]
    }
}

/// Lets a background analysis notice that the reader closed its book.
final class CancellationFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)
    var isCancelled: Bool { state.withLock { $0 } }
    func cancel() { state.withLock { $0 = true } }
}

/// The last part of a helper's error output (analysis, page indexing), read as it arrives so the helper never waits
/// on a full pipe, and kept for the message shown when it fails.
final class OutputTail: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Data())
    private let limit: Int
    init(limit: Int) { self.limit = limit }
    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock { kept in
            kept.append(data)
            if kept.count > limit { kept.removeFirst(kept.count - limit) }
        }
    }
    var text: String { String(decoding: lock.withLock { $0 }, as: UTF8.self) }
}

/// A running analysis helper, so closing its book or quitting Lemma terminates it.
final class HelperHandle: @unchecked Sendable {
    private struct State { var process: Process?; var done = false }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private static let running = OSAllocatedUnfairLock(initialState: [ObjectIdentifier: HelperHandle]())

    func started(_ process: Process) {
        let terminateNow = state.withLock { state -> Bool in
            if state.done { return true }
            state.process = process
            return false
        }
        if terminateNow { if process.isRunning { process.terminate() }; return }
        Self.running.withLock { $0[ObjectIdentifier(self)] = self }
    }

    func finished() {
        state.withLock { $0.process = nil; $0.done = true }
        Self.running.withLock { $0[ObjectIdentifier(self)] = nil }
    }

    func terminate() {
        let process = state.withLock { state -> Process? in
            state.done = true
            defer { state.process = nil }
            return state.process
        }
        if let process, process.isRunning { process.terminate() }
        Self.running.withLock { $0[ObjectIdentifier(self)] = nil }
    }

    static func terminateAll() {
        for handle in running.withLock({ Array($0.values) }) { handle.terminate() }
    }
}

/// Splits a helper's output into lines as it arrives.
final class LineBuffer: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Data())
    func append(_ data: Data) -> [String] {
        lock.withLock { pending in
            pending.append(data)
            var lines: [String] = []
            while let newline = pending.firstIndex(of: 0x0A) {
                lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...newline)
            }
            return lines
        }
    }
}

/// Forwards progress from the background analysis to the main actor, at most once per call site's cadence.
final class ProgressRelay: @unchecked Sendable {
    private let update: @MainActor (Int, Int) -> Void
    init(_ update: @escaping @MainActor (Int, Int) -> Void) { self.update = update }
    func report(_ done: Int, _ total: Int) {
        let update = update
        Task { @MainActor in update(done, total) }
    }
}
