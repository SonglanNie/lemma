import XCTest
import AppKit
import PDFKit
import SwiftUI
import LemmaCore
@testable import Lemma

/// 1.0's workbench: the side editor group, derivations checked in the store, the Problems panel, line numbers
/// and Go to line, the page themes and downloads.
final class IDETests: XCTestCase {
    @MainActor
    func testSideEditorsAreTabsThatReuseAndRestore() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        store.openToSide(page: 1, title: "Page two")
        store.openToSide(page: 2, title: "Page three")
        XCTAssertEqual(store.sideEditors.count, 2, "Two places of the book beside the page, as tabs.")
        XCTAssertEqual(store.split?.title, "Page three", "The last one opened is in front.")
        store.openToSide(page: 1, title: "Page two")
        XCTAssertEqual(store.sideEditors.count, 2, "Opening the same place again brings its tab to the front.")
        XCTAssertEqual(store.split?.title, "Page two")

        let derivation = try XCTUnwrap(store.newDerivation(title: "Check", source: "(a+b)^2 = a^2 + 2ab + b^2"))
        XCTAssertEqual(store.openDerivationID, derivation)
        XCTAssertNil(store.split, "The derivation's tab is in front; the pages stay open behind it.")
        XCTAssertEqual(store.sideEditors.count, 3)
        store.openMap = MapRequest(scope: .chapter("1"))
        store.openMap = MapRequest(scope: .chapter("2"))
        XCTAssertEqual(store.sideEditors.filter { if case .map = $0 { true } else { false } }.count, 1, "One map at a time.")
        store.closeSideEditor("map")
        XCTAssertEqual(store.openDerivationID, derivation, "Closing a tab shows its neighbour.")
        for index in 0..<10 { store.openToSide(page: index % 4, title: "Tab \(index)") }
        XCTAssertLessThanOrEqual(store.sideEditors.count, 8, "At most eight side tabs.")
        store.closeBook()
        XCTAssertTrue(store.sideEditors.isEmpty)
    }

    @MainActor
    func testDerivationsAreCheckedAndTheirFailuresAreProblems() async throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        let id = try XCTUnwrap(store.newDerivation(title: "Square", source: "(a+b)^2 = a^2 + 2ab + b^2"))
        try await waitForReport(store, id)
        XCTAssertEqual(store.derivationReports[id]?.holds, 1)
        XCTAssertEqual(store.problemCounts.errors, 0)

        store.updateDerivation(id) { $0.source = "(a+b)^2 = a^2 + b^2\n= b^2 + a^2" }
        try await waitForReport(store, id) { $0.fails > 0 }
        XCTAssertEqual(store.problemCounts.errors, 1, "A failing step is an error in the Problems panel.")
        let problem = try XCTUnwrap(store.problemItems.first { $0.severity == .error })
        XCTAssertTrue(problem.location.contains("line 1"), problem.location)
        problem.open()
        XCTAssertEqual(store.derivationFocus?.line, 0, "Opening a problem moves the derivation's caret to its line.")

        // Saved with the book, exported as Markdown with each verdict.
        store.flush()
        let saved = try XCTUnwrap(try store.repository.load(id: store.workspace!.id))
        XCTAssertEqual(saved.derivations.first?.source, "(a+b)^2 = a^2 + b^2\n= b^2 + a^2")
        let markdown = store.derivationMarkdown(saved.derivations[0])
        XCTAssertTrue(markdown.contains("✗ $$(a+b)^2 = a^2 + b^2$$"), markdown)
        XCTAssertTrue(markdown.contains("✓ $$= b^2 + a^2$$"), markdown)

        store.deleteDerivation(id)
        XCTAssertNil(store.openDerivationID)
        XCTAssertEqual(store.problemCounts.errors, 0)
    }

    @MainActor
    func testAnAnswersStepsOpenAsADerivation() async throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        var note = StudyNote(anchor: SourceAnchor(pageIndex: 0, pageLabel: "1", region: PageRegion(x: 10, y: 10, width: 100, height: 20), quote: "", imageName: ""),
                             question: "Why?", body: "")
        note.explanation = SavedExplanation(body: "We expand:\n$$(a+b)^2 = a^2 + 2ab + b^2$$\nso $$(a-b)^2 = a^2 + b^2$$", conversationURL: nil, savedAt: .now)
        store.workspace?.notes.append(note)
        store.checkAnswerSteps(noteID: note.id)
        let id = try XCTUnwrap(store.openDerivationID)
        try await waitForReport(store, id) { $0.holds + $0.fails >= 2 }
        let report = try XCTUnwrap(store.derivationReports[id])
        XCTAssertEqual(report.holds, 1)
        XCTAssertEqual(report.fails, 1, "The answer's wrong step is caught.")
        XCTAssertTrue(store.derivation(id)?.title.hasPrefix("Check:") == true)
    }

    @MainActor
    func testLineNumbersAndGoToLine() async throws {
        let fixture = try WorkbenchFixture(hosted: true)
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        try await fixture.waitForAnalysis()
        try await fixture.settle()
        let lines = store.reader.readingLines(onPage: 1)
        XCTAssertGreaterThan(lines.count, 3)
        store.reader.goToLine(2, onPage: 1)
        XCTAssertEqual(store.reader.flash?.pageIndex, 1, "Go to line flashes the line.")
        store.reader.selectLine(2, onPage: 1)
        XCTAssertTrue(store.reader.hasSelection, "Clicking a line number selects its line.")
        XCTAssertEqual(store.reader.selection?.0, 1)
        let item = PaletteProvider(store: store).items(mode: .goTo, query: "2:3").first
        XCTAssertEqual(item?.title, "Go to line 3 of page 2")
        let index = store.reader.lineIndex(onPage: 1, y: lines[2].maxY - 1)
        XCTAssertEqual(index?.index, 2)
    }

    @MainActor
    func testNightAndSepiaRecolourPixels() {
        // White paper, black ink, an orange mark.
        var pixels: [UInt8] = [255, 255, 255, 255, 0, 0, 0, 255, 255, 165, 0, 255]
        pixels.withUnsafeMutableBufferPointer { ThemedPage.recolour($0.baseAddress!, width: 3, height: 1, theme: .night) }
        XCTAssertEqual(Array(pixels[0..<3]), [30, 30, 30], "Paper becomes the editor's dark grey.")
        XCTAssertEqual(Array(pixels[4..<7]), [222, 222, 222], "Ink becomes light.")
        XCTAssertGreaterThan(pixels[8], pixels[9], "An orange mark stays orange: red above green…")
        XCTAssertGreaterThan(pixels[9], pixels[10], "…above blue.")
        var paper: [UInt8] = [255, 255, 255, 255, 0, 0, 0, 255]
        paper.withUnsafeMutableBufferPointer { ThemedPage.recolour($0.baseAddress!, width: 2, height: 1, theme: .sepia) }
        // vImage rounds where the former per-pixel loop truncated: one level of 255 either way.
        for (value, expected) in zip(paper[0..<3], [246, 235, 212] as [UInt8]) {
            XCTAssertEqual(Double(value), Double(expected), accuracy: 1, "Sepia warms the paper.")
        }
        XCTAssertEqual(Array(paper[4..<7]), [0, 0, 0], "Ink stays black.")
        XCTAssertTrue(ThemedPageProvider.shared.classForPage() == ThemedPage.self)
    }

    @MainActor
    func testDownloadsKeepPDFsAndRefuseWebPages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pdf = root.appendingPathComponent("source.pdf"), html = root.appendingPathComponent("page.html")
        try Data("%PDF-1.7\n%…".utf8).write(to: pdf)
        try Data("<!doctype html><html>quota exceeded</html>".utf8).write(to: html)
        let downloads = PDFDownloads()
        let kept = try await downloads.download(id: "a", from: pdf, to: root.appendingPathComponent("Books/a.pdf"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
        do {
            _ = try await downloads.download(id: "b", from: html, to: root.appendingPathComponent("Books/b.pdf"))
            XCTFail("A web page is not saved as a book.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("web page"), error.localizedDescription)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Books/b.pdf").path))
        XCTAssertNil(downloads.progress["a"])
        XCTAssertEqual(StudyStore.fileName("Causal Inference: What If"), "Causal Inference – What If")
    }

    @MainActor
    private func waitForReport(_ store: StudyStore, _ id: UUID, until condition: (DerivationReport) -> Bool = { _ in true }) async throws {
        let deadline = Date.now.addingTimeInterval(10)
        while Date.now < deadline {
            if let report = store.derivationReports[id], store.derivationChecks[id] == nil, condition(report) { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("The derivation was not checked in time")
    }
}
