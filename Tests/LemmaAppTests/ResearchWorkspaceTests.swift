import XCTest
import AppKit
import PDFKit
import LemmaCore
@testable import Lemma

final class ResearchWorkspaceTests: XCTestCase {
    @MainActor
    func testCorrectedFormulaBecomesADurableDerivationWithItsOriginalSource() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        let pdf = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LemmaCoreTests/Fixtures/formula-layout.pdf")
        store.open(pdf)
        let target = try XCTUnwrap(BookAnalyzer.analyze(document: try XCTUnwrap(store.document), outline: [])?.definitions.first { $0.key.kind == .equation })
        store.readFormula(target)
        let request = try XCTUnwrap(store.formulaRequest)
        XCTAssertNotNil(NSImage(data: request.image))
        XCTAssertTrue(request.reading?.latex.contains(#"\hat{\beta}"#) == true)
        let corrected = #"\hat{\beta}=(X^T X+\lambda I)^{-1}X^T y"#
        store.deriveFormula(request, latex: corrected)
        XCTAssertNil(store.formulaRequest)
        let id = try XCTUnwrap(store.openDerivationID)
        let saved = try XCTUnwrap(store.derivation(id))
        XCTAssertTrue(saved.source.hasSuffix(corrected))
        XCTAssertEqual(saved.origin?.region, request.region)
        XCTAssertEqual(saved.origin?.pageIndex, request.pageIndex)
        store.flush()
        let restarted = StudyStore(root: store.repository.root)
        restarted.restore()
        XCTAssertEqual(restarted.openDerivationID, id)
        XCTAssertEqual(restarted.derivation(id)?.source, saved.source)
    }

    @MainActor
    func testSwitchingBooksAndRestartingRestoreSideEditorsAndTheSelectedNote() async throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        let bookID = try XCTUnwrap(store.workspace?.id)
        let note = StudyNote(anchor: SourceAnchor(pageIndex: 1, pageLabel: "1", region: PageRegion(x: 70, y: 640, width: 200, height: 40), quote: "Model", imageName: ""), question: "Why?")
        store.workspace?.notes.append(note); store.selectedNoteID = note.id
        store.studySection = .glossary
        store.openToSide(page: 2, title: "Prerequisite")
        let pageID = try XCTUnwrap(store.activeSideEditorID)
        let derivationID = try XCTUnwrap(store.newDerivation(title: "Work", source: "(x+1)^2 = x^2 + 2x + 1"))
        store.activateSideEditor(pageID)
        store.workbenchLayout.sidebarWidth = 232; store.workbenchLayout.sidebarPosition = .right
        store.navigatorSection = .lab; store.showPanel = true; store.panelTab = .problems
        store.flush()
        store.open(fixture.paper)
        XCTAssertTrue(store.sideEditors.isEmpty)
        store.openToSide(page: 1, title: "Paper reference")
        store.activateTab(bookID)
        XCTAssertEqual(store.sideEditors.count, 2)
        XCTAssertEqual(store.activeSideEditorID, pageID, "Switching books must not discard the editor group.")
        XCTAssertEqual(store.selectedNoteID, note.id)
        XCTAssertEqual(store.studySection, .glossary)
        store.flush()
        let reopened = StudyStore(root: store.repository.root)
        reopened.restore()
        XCTAssertEqual(reopened.workspace?.id, bookID)
        XCTAssertEqual(reopened.sideEditors.count, 2)
        XCTAssertEqual(reopened.activeSideEditorID, pageID, "Persisted editor IDs must be stable.")
        XCTAssertEqual(reopened.selectedNoteID, note.id)
        XCTAssertEqual(reopened.workbenchLayout.sidebarWidth, 232)
        XCTAssertEqual(reopened.workbenchLayout.sidebarPosition, .right)
        XCTAssertEqual(reopened.panelTab, .problems)
        XCTAssertTrue(reopened.showPanel)
        XCTAssertTrue(reopened.sideEditors.contains(.derivation(derivationID)))
        XCTAssertTrue(reopened.lab.sessions.isEmpty, "Restoring a notebook must never execute code.")
        reopened.flush()
    }

    @MainActor
    func testCollectingAcrossBooksKeepsOriginalCropsAndTheProjectBesideTheSource() async throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        let projectID = try XCTUnwrap(store.newProject(title: "Normal equations", question: "What changes with regularization?"))
        let rect = CGRect(x: 72, y: 630, width: 370, height: 80)
        store.reader.selection = (1, rect, "The normal equations"); store.reader.hasSelection = true
        store.collectSelection(projectID: projectID)
        let first = try XCTUnwrap(store.project(projectID)?.passages.first)
        let image = try Data(contentsOf: store.projectRepository.imageURL(projectID, name: first.anchor.imageName))
        XCTAssertNotNil(NSImage(data: image))
        XCTAssertEqual(first.anchor.pageIndex, 1)
        store.open(fixture.paper)
        XCTAssertEqual(store.activeSideEditor, .project(projectID), "The synthesis stays beside a second book.")
        store.reader.selection = (0, CGRect(x: 72, y: 650, width: 330, height: 35), "Sparse estimates")
        store.collectSelection(projectID: projectID)
        XCTAssertEqual(store.project(projectID)?.passages.map(\.number), [1, 2])
        XCTAssertEqual(store.project(projectID)?.bookIDs.count, 2)
        store.appendProjectCitation(first, projectID: projectID)
        XCTAssertTrue(store.project(projectID)?.synthesis.contains(first.citation) == true)
        store.openProjectPassage(first, projectID: projectID)
        XCTAssertEqual(store.workspace?.id, first.bookID)
        XCTAssertEqual(store.activeSideEditor, .project(projectID))
        XCTAssertEqual(try Data(contentsOf: store.projectRepository.imageURL(projectID, name: first.anchor.imageName)), image)
        store.flush()
        XCTAssertEqual(try store.projectRepository.load().first?.passages.count, 2)
    }

    @MainActor
    func testProjectScopeExcludesOtherBooksAndArchiveCanBeRestored() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        let bookID = try XCTUnwrap(store.workspace?.id)
        let projectID = try XCTUnwrap(store.newProject(title: "A question"))
        store.open(fixture.paper)
        XCTAssertEqual(store.booksForSearch(.project).map(\.id), [bookID])
        XCTAssertEqual(store.booksForSearch(.library).count, 2)
        store.searchProject(projectID)
        XCTAssertEqual(store.noteSearchScope, .project)
        XCTAssertEqual(store.pageSearchScope, .project)
        store.archiveProject(projectID, archived: true)
        XCTAssertTrue(store.activeProjects.isEmpty)
        XCTAssertNil(store.selectedProjectID)
        XCTAssertEqual(store.project(projectID)?.bookIDs, [bookID])
        store.archiveProject(projectID, archived: false)
        XCTAssertEqual(store.currentProject?.id, projectID)
        XCTAssertEqual(store.activeSideEditor, .project(projectID))
    }

    @MainActor
    func testProjectsWorkWithoutABookAndTabOrderSurvivesRestart() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        let projectID = try XCTUnwrap(store.newProject(title: "An independent question"))
        store.updateProject(projectID) { $0.synthesis = "Start with the assumptions." }
        store.flush()
        let emptyRestart = StudyStore(root: store.repository.root)
        emptyRestart.restore()
        XCTAssertNil(emptyRestart.document)
        XCTAssertEqual(emptyRestart.activeSideEditor, .project(projectID))
        XCTAssertEqual(emptyRestart.currentProject?.synthesis, "Start with the assumptions.")
        store.open(fixture.book)
        store.open(fixture.paper)
        let first = store.tabs[0].id, second = store.tabs[1].id
        // A drag to the right: the first tab dropped on the second takes its place.
        store.moveTab(first, onto: second)
        store.flush()
        let restart = StudyStore(root: store.repository.root)
        restart.restore()
        XCTAssertEqual(restart.tabs.map(\.id), [second, first])
        XCTAssertEqual(restart.workspace?.id, second)
        store.closeOtherTabs(keeping: first)
        XCTAssertEqual(store.tabs.map(\.id), [first])
        restart.flush()
    }

    @MainActor
    func testMalformedProjectManifestIsNotOverwrittenByAnEmptyLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = Data("interrupted or future project data".utf8)
        let manifest = folder.appendingPathComponent("projects.json")
        try original.write(to: manifest)
        let store = StudyStore(root: root)
        XCTAssertNotNil(store.error)
        XCTAssertNil(store.newProject())
        store.flush()
        XCTAssertEqual(try Data(contentsOf: manifest), original)
    }
}
