import Foundation
import PDFKit
import LemmaCore

@main
struct LemmaIndexer {
    @MainActor
    static func main() async {
        let args = CommandLine.arguments
        func argument(_ key: String) -> String? {
            guard let index = args.firstIndex(of: key), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        exitWithParent()
        limitMemory()
        // Reading a book's structure runs here rather than in the app, so a malformed PDF cannot take the reader down.
        if let source = argument("--analyze") {
            guard let id = argument("--workspace"), let root = argument("--root") else {
                FileHandle.standardError.write(Data("Expected --analyze PDF --workspace fingerprint --root support\n".utf8))
                exit(2)
            }
            superviseAnalysis(source: source, id: id, root: root)
        }
        if let source = argument("--analyze-pages") {
            guard let id = argument("--workspace"), let root = argument("--root"),
                  let blocked = PageTextRecovery.pages(inArgument: argument("--blocked-pages") ?? "") else {
                FileHandle.standardError.write(Data("Expected --analyze-pages PDF --workspace fingerprint --root support --blocked-pages 1,2\n".utf8))
                exit(2)
            }
            analyze(source: URL(fileURLWithPath: source), id: id, root: URL(fileURLWithPath: root), blocked: blocked)
            return
        }
        // Library-wide search reads page texts here too: PDFKit's text extraction can take hundreds of megabytes for
        // a long book, which this process gives back when it exits.
        if let source = argument("--pagetext") {
            guard let output = argument("--output"), let id = argument("--workspace"), let root = argument("--root") else {
                FileHandle.standardError.write(Data("Expected --pagetext PDF --output file --workspace fingerprint --root support\n".utf8))
                exit(2)
            }
            let textGuard = guardText(id: id, repository: DocumentIndexRepository(root: URL(fileURLWithPath: root)))
            defer { withExtendedLifetime(textGuard) {} }
            guard let pages = PageTextFile.extract(source: URL(fileURLWithPath: source), textGuard: textGuard) else {
                FileHandle.standardError.write(Data("Could not open the PDF.\n".utf8))
                exit(1)
            }
            do { try PageTextFile.write(pages, to: URL(fileURLWithPath: output)) } catch {
                FileHandle.standardError.write(Data("Could not save the page texts: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }
        // Page indexing: one book, page by page, reporting “progress <done> <total>” lines on standard output.
        // (`--guard` is accepted too: Lemma 2 passed the run's name that way.)
        guard let source = argument("--source"), let id = argument("--workspace"),
              let root = argument("--root"), let name = argument("--job") ?? argument("--guard") else {
            FileHandle.standardError.write(Data("Expected --source PDF --workspace fingerprint --root support --job name\n".utf8))
            exit(2)
        }
        let output = FileHandle.standardOutput
        let repository = DocumentIndexRepository(root: URL(fileURLWithPath: root))
        let textGuard = guardText(id: id, repository: repository)
        defer { withExtendedLifetime(textGuard) {} }
        do {
            try await DocumentIndexer.index(source: URL(fileURLWithPath: source), id: id, repository: repository, jobName: name, textGuard: textGuard) { done, total in
                output.write(Data("progress \(done) \(total)\n".utf8))
            }
            output.write(Data("done\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("Indexing failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    /// The helper works for the Lemma that started it: when that process ends (it quit, or crashed), so does the
    /// helper, rather than reading a book for nobody. Lemma starts it directly or through `taskpolicy`, which keeps
    /// the same process, so Lemma is the parent.
    static func exitWithParent() {
        let parent = getppid()
        guard parent > 1 else { exit(3) }
        let source = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .global(qos: .utility))
        source.setEventHandler { exit(3) }
        source.resume()
        parentWatch = source
        // The parent may have ended before the watch began.
        if getppid() != parent { exit(3) }
    }
    nonisolated(unsafe) static var parentWatch: DispatchSourceProcess?

    /// The most memory a helper may use. The heaviest of 6,688 books took 1.3 GB.
    static let memoryLimit: UInt64 = 6 << 30

    /// On a few pages PDFKit's text extraction never returns, and takes memory until the whole Mac slows down. No check can
    /// foresee such a page and nothing can interrupt the call, so the helper stops itself. Reaching the limit in a call on a
    /// page's text blames that page: see `continueWithoutPage`.
    static func limitMemory() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        // A runaway takes more than a gigabyte a second, and a helper at utility priority has its timers put off unless told not to.
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(250), leeway: .milliseconds(50))
        timer.setEventHandler {
            var usage = rusage_info_current()
            let status = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0) }
            }
            guard status == 0, usage.ri_phys_footprint > memoryLimit else { return }
            continueWithoutPage()
            FileHandle.standardError.write(Data("Reading this PDF's text took too much memory, so it was stopped.\n".utf8))
            _exit(4)
        }
        timer.resume()
        memoryWatch = timer
    }
    nonisolated(unsafe) static var memoryWatch: DispatchSourceTimer?

    /// The guard reading a book in this process, and where its blocked pages are kept.
    nonisolated(unsafe) static var textReading: (textGuard: PageTextGuard, id: String, repository: DocumentIndexRepository)?

    /// The guard for reading a book's text here: it refuses the pages known to be bad, and names the page in use if the helper
    /// reaches its memory limit. Called before any page is read.
    static func guardText(id: String, repository: DocumentIndexRepository, selectionBlocked: Set<Int> = [],
                          onSelecting: @escaping (Int) -> Void = { _ in }) -> PageTextGuard {
        let textGuard = PageTextGuard(selectionBlocked: selectionBlocked, textBlocked: repository.textBlockedPages(id), onSelecting: onSelecting)
        textReading = (textGuard, id, repository)
        return textGuard
    }

    /// Records the page in use as one whose text never returns, and starts this helper over: the call can't be interrupted, and
    /// only a new process image gives the memory back. It keeps its process, so whoever started it, pauses it or reads its
    /// output sees no difference. Its next run refuses the page. Returns only when that can't help.
    static func continueWithoutPage() {
        guard let reading = textReading, let executable = Bundle.main.executablePath,
              let page = PageTextRecovery.textPage(toBlock: reading.textGuard.pageInUse, known: reading.textGuard.textBlocked),
              (try? reading.repository.addTextBlockedPages([page], id: reading.id)) != nil else { return }
        FileHandle.standardOutput.write(Data((PageTextRecovery.textBlockedReport(pageIndex: page) + "\n").utf8))
        FileHandle.standardError.write(Data("The text of page index \(page) never finished reading; going on without it.\n".utf8))
        execv(executable, CommandLine.unsafeArgv)
    }

    /// Analyses a book in a child process, relaying its progress. CoreGraphics traps on a few ordinary pages, which no
    /// check can foresee (`PageTextGuard`): when the child traps, it runs again without selections on that page, so
    /// the book loses that page's statements rather than its whole analysis. Each run starts over.
    static func superviseAnalysis(source: String, id: String, root: String) -> Never {
        func fail(_ message: String) -> Never {
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
        guard let executable = Bundle.main.executableURL else { fail("The analysis could not start.") }
        let repository = DocumentIndexRepository(root: URL(fileURLWithPath: root))
        var recovery = PageTextRecovery()
        while true {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--analyze-pages", source, "--workspace", id, "--root", root,
                                 "--blocked-pages", PageTextRecovery.argument(for: recovery.selectionBlocked)]
            process.qualityOfService = .utility
            let output = Pipe()
            process.standardOutput = output
            do { try process.run() } catch { fail(error.localizedDescription) }
            let selecting = relayProgress(from: output.fileHandleForReading)
            process.waitUntilExit()
            guard process.terminationReason == .uncaughtSignal else {
                // Kept only now: Swift's own runtime errors trap too, and a run that gives up has shown nothing about its pages.
                if process.terminationStatus == 0 {
                    do { try repository.addSelectionBlockedPages(recovery.selectionBlocked, id: id) } catch { fail(error.localizedDescription) }
                }
                exit(process.terminationStatus)
            }
            // A trap arrives as SIGTRAP on Apple silicon and as SIGILL on Intel.
            guard [SIGTRAP, SIGILL].contains(process.terminationStatus), recovery.blockSelection(selecting), let selecting else {
                fail("The book's structure could not be read: the analysis stopped on this PDF. Reading, notes and search still work.")
            }
            FileHandle.standardOutput.write(Data((PageTextRecovery.blockedReport(pageIndex: selecting) + "\n").utf8))
            FileHandle.standardError.write(Data("Reading page index \(selecting) stopped the analysis; running it again without that page's layout.\n".utf8))
        }
    }

    /// Passes the child's output on until it ends, keeping back the page markers. Returns the last page marked.
    static func relayProgress(from pipe: FileHandle) -> Int? {
        var selecting: Int?
        var pending = Data()
        while true {
            let data = pipe.availableData
            guard !data.isEmpty else { return selecting }
            pending.append(data)
            while let end = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: pending[pending.startIndex..<end], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...end)
                if let page = PageTextRecovery.pageIndex(inMarker: line) { selecting = page }
                else { FileHandle.standardOutput.write(Data((line + "\n").utf8)) }
            }
        }
    }

    /// Writes `Indexes/<id>/analysis.json`, and reports “progress <done> <total>” and page marker lines on standard output.
    static func analyze(source: URL, id: String, root: URL, blocked: Set<Int>) {
        guard let document = PDFDocument(url: source) else {
            FileHandle.standardError.write(Data("Could not open the PDF.\n".utf8))
            exit(1)
        }
        let output = FileHandle.standardOutput
        let repository = DocumentIndexRepository(root: root)
        let textGuard = guardText(id: id, repository: repository, selectionBlocked: blocked) { page in
            output.write(Data((PageTextRecovery.marker(pageIndex: page) + "\n").utf8))
        }
        textGuard.watch(document)
        defer { withExtendedLifetime(textGuard) {} }
        let analysis = BookAnalyzer.analyze(document: document, outline: OutlineReader.items(in: document), progress: { done, total in
            output.write(Data("progress \(done) \(total)\n".utf8))
        })
        guard let analysis else {
            FileHandle.standardError.write(Data("The analysis did not finish.\n".utf8))
            exit(1)
        }
        do {
            try repository.save(analysis, id: id)
            output.write(Data("done\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("Could not save the analysis: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
