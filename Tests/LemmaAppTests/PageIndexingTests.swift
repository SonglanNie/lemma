import XCTest
import AppKit
import PDFKit
import LemmaCore
@testable import Lemma

/// Page indexing runs in the bundled helper without any outside tool: it reports its pages, waits while the Mac
/// should not work hard (the process is stopped, then continued), and Stop ends it keeping the pages done.
final class PageIndexingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PageIndexing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        PowerConditions.simulated = nil
        try? FileManager.default.removeItem(at: root)
    }

    /// The helper built beside the tests (`swift build` builds it with them).
    private func helper() throws -> URL {
        let url = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("LemmaIndexer")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw XCTSkip("LemmaIndexer is not built beside the tests.") }
        return url
    }

    private func book(pages: Int) throws -> (url: URL, id: String) {
        let bytes = NSMutableData(); var box = CGRect(x: 0, y: 0, width: 600, height: 400)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: bytes)), mediaBox: &box, nil))
        for page in 0..<pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            ("Page \(page + 1): a design matrix has one row per observation." as NSString)
                .draw(at: CGPoint(x: 25, y: 270), withAttributes: [.font: NSFont.systemFont(ofSize: 20)])
            NSGraphicsContext.restoreGraphicsState(); context.endPDFPage()
        }
        context.closePDF()
        let url = root.appendingPathComponent("book.pdf")
        try (bytes as Data).write(to: url)
        return (url, try WorkspaceRepository.fingerprint(of: url))
    }

    @MainActor private func processState(_ id: String) -> String {
        guard let pid = PageIndexer.shared.processIdentifier(id, root: root.appendingPathComponent("support")) else { return "" }
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps"); task.arguments = ["-o", "stat=", "-p", "\(pid)"]
        task.standardOutput = pipe
        try? task.run(); task.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    func testIndexingWaitsWhileTheMacShouldRestThenFinishes() async throws {
        let helper = try helper()
        let (url, id) = try book(pages: 4)
        let support = root.appendingPathComponent("support"), repository = DocumentIndexRepository(root: support)
        PowerConditions.simulated = .some(.battery)
        var reported: [(Int, Int)] = []
        var outcome: PageIndexOutcome?
        try PageIndexer.shared.start(id: id, source: url.path, root: support, jobName: "test", helper: helper,
                                     onProgress: { reported.append(($0, $1)) }, onExit: { outcome = $0 })
        XCTAssertTrue(PageIndexer.shared.isRunning(id, root: support))
        XCTAssertEqual(PageIndexer.shared.pause, .battery, "The window says why indexing waits")
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertTrue(processState(id).hasPrefix("T"), "On battery the helper is stopped, not ended (state \(processState(id)))")
        XCTAssertNil(outcome)
        XCTAssertNotEqual(try repository.progress(id)?.status, .complete)

        PowerConditions.simulated = .some(nil)
        PageIndexer.shared.conditionsChanged()
        XCTAssertNil(PageIndexer.shared.pause)
        let deadline = Date().addingTimeInterval(60)
        while outcome == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(outcome, .finished)
        XCTAssertFalse(PageIndexer.shared.isRunning(id, root: support))
        XCTAssertEqual(try repository.progress(id)?.status, .complete)
        XCTAssertEqual(repository.pageCount(id), 4)
        XCTAssertEqual(try repository.pages(id).count, 4)
    }

    @MainActor
    func testStopEndsAWaitingHelperAndKeepsTheIndexReadable() async throws {
        let helper = try helper()
        let (url, id) = try book(pages: 3)
        let support = root.appendingPathComponent("support")
        PowerConditions.simulated = .some(.heat)
        var outcome: PageIndexOutcome?
        try PageIndexer.shared.start(id: id, source: url.path, root: support, jobName: "stop", helper: helper,
                                     onProgress: { _, _ in }, onExit: { outcome = $0 })
        XCTAssertEqual(PageIndexer.shared.pause, .heat)
        try await Task.sleep(for: .milliseconds(800))
        PageIndexer.shared.stop(id, root: support)
        let deadline = Date().addingTimeInterval(20)
        while outcome == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(outcome, .stopped, "A stopped (waiting) helper still ends when asked")
        XCTAssertFalse(PageIndexer.shared.isRunning(id, root: support))
        XCTAssertNil(PageIndexer.shared.pause, "Nothing waits once no job runs")
    }
}
