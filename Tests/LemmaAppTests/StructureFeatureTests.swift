import XCTest
import AppKit
import PDFKit
import SwiftUI
import LemmaCore
@testable import Lemma

/// Results, folded proofs, understanding, the hierarchy, the dependency map, the reading ruler and lemma:// links,
/// on a LaTeX book (Tests/LemmaCoreTests/Fixtures/book-chapters.tex) rather than on ESL.
final class StructureFeatureTests: XCTestCase {
    @MainActor
    private func openFixture(hosted: Bool = true) async throws -> (WorkbenchFixture, URL) {
        let fixture = try WorkbenchFixture(hosted: hosted)
        let source = try XCTUnwrap(Bundle.module.url(forResource: "book-chapters", withExtension: "pdf", subdirectory: "Fixtures"))
        let copy = fixture.root.appendingPathComponent("Notes_on_Linear_Smoothers.pdf")
        try FileManager.default.copyItem(at: source, to: copy)
        fixture.store.open(copy)
        try await fixture.waitForAnalysis()
        try await fixture.settle()
        return (fixture, copy)
    }

    private let theorem = ReferenceKey(kind: .theorem, number: "1.3", name: "Theorem")
    private let lemma = ReferenceKey(kind: .theorem, number: "1.2", name: "Lemma")
    private let definition = ReferenceKey(kind: .theorem, number: "1.1", name: "Definition")

    @MainActor
    func testStatementInViewReturnsAfterMinimapDragging() async throws {
        let (fixture, _) = try await openFixture()
        defer { fixture.close() }
        let store = fixture.store
        let target = try XCTUnwrap(store.analysis?.target(for: definition))
        let focusY = target.anchor.rect.maxY + 1
        store.reader.beginScrubbing()
        store.reader.focusPageIndex = target.pageIndex; store.reader.focusY = focusY
        XCTAssertNil(store.readingStatement(), "Transient pages must not build the sticky statement's PDF text map.")
        store.reader.endScrubbing()
        // Keep the same focus that was inspected during the drag: a deferred result must not cache a missing statement.
        store.reader.focusPageIndex = target.pageIndex; store.reader.focusY = focusY
        XCTAssertEqual(store.readingStatement()?.statement.key, definition)
    }

    @MainActor
    func testProofsFoldUnderstandingPersistsAndTheHierarchyFollowsReferences() async throws {
        let (fixture, _) = try await openFixture()
        defer { fixture.close() }
        let store = fixture.store
        let structure = try XCTUnwrap(store.analysis?.analysis?.structure)
        XCTAssertEqual(structure.statements.count, 5)
        XCTAssertEqual(store.proofs.count, 4)

        store.toggleAllProofs()
        XCTAssertTrue(store.allProofsFolded)
        try await fixture.settle()
        XCTAssertEqual(store.reader.foldedProofs.count, 4, "The page folds what the workspace folds.")
        let proof = try XCTUnwrap(structure.proof(of: theorem))
        store.toggleProof(proof.stableID)
        XCTAssertFalse(store.isFolded(proof))
        store.toggleUnderstood(lemma)
        store.flush()
        let saved = try XCTUnwrap(store.repository.load(id: try XCTUnwrap(store.workspace?.id)))
        XCTAssertEqual(saved.foldedProofs.count, 3)
        XCTAssertEqual(saved.understood, [lemma])
        XCTAssertEqual(saved.schemaVersion, 10)

        let uses = Set(try XCTUnwrap(store.analysis).uses(theorem).map(\.to))
        XCTAssertTrue(uses.isSuperset(of: [definition, lemma]), "Theorem 1.3's proof cites Definition 1.1 and Lemma 1.2: \(uses)")
        store.showHierarchy(theorem)
        XCTAssertEqual(store.panelTab, .hierarchy)
        XCTAssertTrue(store.showPanel)
        XCTAssertEqual(store.hierarchyKey, theorem)
        XCTAssertTrue(try XCTUnwrap(store.analysis).usedBy(definition).contains { $0.from == theorem })
    }

    @MainActor
    func testTheMapPutsPrerequisitesAboveWhatUsesThem() async throws {
        let (fixture, _) = try await openFixture(hosted: false)
        defer { fixture.close() }
        let store = fixture.store
        let chapter = MapGraph.build(request: MapRequest(scope: .chapter("1")), store: store)
        let positions = Dictionary(chapter.nodes.map { ($0.key, $0.center) }, uniquingKeysWith: { first, _ in first })
        let lemmaY = try XCTUnwrap(positions[lemma]?.y), theoremY = try XCTUnwrap(positions[theorem]?.y)
        XCTAssertLessThan(lemmaY, theoremY, "Lemma 1.2 sits above Theorem 1.3, which rests on it.")
        XCTAssertTrue(chapter.edges.contains { $0.from == theorem && $0.to == lemma })
        let frames = chapter.nodes.map { CGRect(x: $0.center.x - 88, y: $0.center.y - 21, width: 176, height: 42) }
        for (i, a) in frames.enumerated() { for b in frames[(i + 1)...] { XCTAssertFalse(a.intersects(b), "Nodes do not overlap.") } }

        let prerequisites = MapGraph.build(request: MapRequest(scope: .prerequisites(ReferenceKey(kind: .theorem, number: "2.1", name: "Theorem"))), store: store)
        XCTAssertTrue(Set(prerequisites.nodes.map(\.key)).isSuperset(of: [definition, lemma]), "Theorem 2.1 rests on Definition 1.1 and Lemma 1.2, across chapters.")
    }

    @MainActor
    func testRulerStepsLineByLineAcrossPages() async throws {
        let (fixture, _) = try await openFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.reader.goToPage(5)
        try await fixture.settle()
        store.reader.rulerMode = true
        let start = try XCTUnwrap(store.reader.rulerLine)
        store.reader.moveRuler(by: 1)
        let next = try XCTUnwrap(store.reader.rulerLine)
        XCTAssertEqual(next.pageIndex, start.pageIndex)
        XCTAssertEqual(next.index, start.index + 1)
        XCTAssertGreaterThan(start.rect.minY, next.rect.minY, "The next line is lower on the page.")
        store.reader.moveRuler(by: next.count - next.index)
        XCTAssertEqual(store.reader.rulerLine?.pageIndex, next.pageIndex + 1, "Past the last line the ruler moves to the next page.")
        XCTAssertEqual(store.reader.rulerLine?.index, 0)
        store.reader.rulerMode = false
        XCTAssertNil(store.reader.rulerLine)
    }

    @MainActor
    func testFoldedProofsShowAFoldBarOnThePage() async throws {
        let (fixture, _) = try await openFixture()
        defer { fixture.close() }
        let store = fixture.store
        let proof = try XCTUnwrap(store.analysis?.analysis?.structure.proof(of: lemma))
        store.toggleProof(proof.stableID)
        store.reader.goToPage(proof.start.pageIndex + 1)
        try await fixture.settle(400)
        let view = try XCTUnwrap(store.reader.view)
        func bars(in view: NSView) -> [ProofFoldBar] { view.subviews.flatMap { ($0 as? ProofFoldBar).map { [$0] } ?? bars(in: $0) } }
        XCTAssertFalse(bars(in: view).isEmpty, "A folded proof is covered by its fold bar.")
        func controls(in view: NSView) -> [GutterFoldControl] { view.subviews.flatMap { ($0 as? GutterFoldControl).map { [$0] } ?? controls(in: $0) } }
        XCTAssertFalse(controls(in: view).isEmpty, "Proofs on the page have fold controls in the gutter.")
    }

    @MainActor
    func testQuestionMarksQueuePassagesForLater() async throws {
        let (fixture, _) = try await openFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.reader.goToPage(6)
        try await fixture.settle()
        store.reader.rulerMode = true
        store.reader.moveRuler(by: 2)
        let line = try XCTUnwrap(store.reader.rulerLine)
        store.markUnclear()
        XCTAssertEqual(store.openMarks.count, 1)
        let mark = try XCTUnwrap(store.openMarks.first)
        XCTAssertTrue(mark.isQuickMark)
        XCTAssertEqual(mark.anchor.pageIndex, line.pageIndex)
        XCTAssertTrue(mark.title.hasPrefix("? "), mark.title)
        XCTAssertFalse(store.reader.hasSelection, "Marking does not leave a selection behind; reading continues.")
        store.reader.rulerMode = false
        store.reader.goToPage(1)
        try await fixture.settle()
        store.resumeAtFirstMark()
        try await fixture.settle()
        XCTAssertEqual(store.reader.pageNumber - 1, line.pageIndex, "Resume goes back to the earliest open mark.")
        store.updateNote(id: mark.id) { $0.question = "Why is the trace equal to the rank?" }
        XCTAssertTrue(store.openMarks.isEmpty, "A mark with a written question is an ordinary question note.")
    }

    @MainActor
    func testLemmaLinksOpenAStatement() async throws {
        let (fixture, _) = try await openFixture()
        defer { fixture.close() }
        let store = fixture.store
        let id = try XCTUnwrap(store.workspace?.id)
        store.reader.goToPage(1)
        try await fixture.settle()
        store.copyLink(to: theorem)
        let link = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertTrue(link.hasPrefix("lemma://open?book=\(id)&ref=Theorem"), link)
        store.openLink(try XCTUnwrap(URL(string: link)))
        try await Task.sleep(for: .milliseconds(400))
        try await fixture.settle()
        let target = try XCTUnwrap(store.analysis?.target(for: theorem))
        XCTAssertEqual(store.reader.pageNumber - 1, target.pageIndex, "The link goes to Theorem 1.3's page.")
    }
}
