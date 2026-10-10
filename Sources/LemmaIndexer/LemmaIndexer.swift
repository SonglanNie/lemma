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
        // Reading a book's structure runs here rather than in the app, so a malformed PDF cannot take the reader down.
        if let source = argument("--analyze") {
            guard let id = argument("--workspace"), let root = argument("--root") else {
                FileHandle.standardError.write(Data("Expected --analyze PDF --workspace fingerprint --root support\n".utf8))
                exit(2)
            }
            analyze(source: URL(fileURLWithPath: source), id: id, root: URL(fileURLWithPath: root))
            return
        }
        // Library-wide search reads page texts here too: PDFKit's text extraction can take hundreds of megabytes for
        // a long book, which this process gives back when it exits.
        if let source = argument("--pagetext") {
            guard let output = argument("--output") else {
                FileHandle.standardError.write(Data("Expected --pagetext PDF --output file\n".utf8))
                exit(2)
            }
            guard let pages = PageTextFile.extract(source: URL(fileURLWithPath: source)) else {
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
        do {
            try await DocumentIndexer.index(source: URL(fileURLWithPath: source), id: id,
                repository: DocumentIndexRepository(root: URL(fileURLWithPath: root)), jobName: name) { done, total in
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

    /// Writes `Indexes/<id>/analysis.json` and reports “progress <done> <total>” lines on standard output.
    static func analyze(source: URL, id: String, root: URL) {
        guard let document = PDFDocument(url: source) else {
            FileHandle.standardError.write(Data("Could not open the PDF.\n".utf8))
            exit(1)
        }
        let output = FileHandle.standardOutput
        let analysis = BookAnalyzer.analyze(document: document, outline: OutlineReader.items(in: document), progress: { done, total in
            output.write(Data("progress \(done) \(total)\n".utf8))
        })
        guard let analysis else {
            FileHandle.standardError.write(Data("The analysis did not finish.\n".utf8))
            exit(1)
        }
        do {
            try DocumentIndexRepository(root: root).save(analysis, id: id)
            output.write(Data("done\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("Could not save the analysis: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
