import XCTest
import AppKit
import PDFKit
import SwiftUI
import LemmaCore
@testable import Lemma

final class ReadingRestorationTests: XCTestCase {
    @MainActor
    func testRestartRestoresTheDestinationAfterTheWorkbenchHasLaidOut() async throws {
        let fixture = try WorkbenchFixture(hosted: true)
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        try await fixture.settle(500)
        let view = try XCTUnwrap(store.reader.view)
        let page = try XCTUnwrap(store.document?.page(at: 2))
        view.autoScales = false
        view.scaleFactor = 1.9
        view.go(to: PDFDestination(page: page, at: CGPoint(x: 72, y: 470)))
        try await fixture.settle()
        store.flush()
        let saved = try XCTUnwrap(store.workspace?.reading)
        XCTAssertEqual(saved.pageIndex, 2)

        let restarted = StudyStore(app: AppModel(root: store.repository.root))
        restarted.app.restore()
        fixture.window.contentView = NSHostingView(rootView: ReaderWindow(store: restarted))
        try await fixture.settle(500)
        restarted.flush()
        let restored = try XCTUnwrap(restarted.workspace?.reading)
        XCTAssertEqual(restored.pageIndex, saved.pageIndex)
        XCTAssertEqual(restored.scale, saved.scale, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(restored.positionX), try XCTUnwrap(saved.positionX), accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(restored.positionY), try XCTUnwrap(saved.positionY), accuracy: 1,
                       "PDFKit must restore the destination in the final display mode and pane size.")
    }

    @MainActor
    func testALayoutChosenFromThePagesContextMenuStaysAndComesBack() async throws {
        let fixture = try WorkbenchFixture(hosted: true)
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        try await fixture.settle(500)
        let view = try XCTUnwrap(store.reader.view)
        XCTAssertEqual(view.displayMode, .singlePageContinuous)
        for (offset, layout) in [ReadingLayout.twoPages, .singlePage, .twoPagesContinuous].enumerated() {
            // PDFKit's context menu (Two Pages, Single Page, Two Pages Continuous) sets the display mode itself; moving to
            // another page then updates the reader, which used to put Continuous back.
            view.displayMode = layout.displayMode
            view.go(to: try XCTUnwrap(store.document?.page(at: offset + 1)))
            try await fixture.settle()
            XCTAssertEqual(view.displayMode, layout.displayMode, "\(layout.label) stays after the reader updates.")
            XCTAssertEqual(store.workspace?.reading.layout, layout, "The book keeps \(layout.label).")
        }
        store.flush()

        let restarted = StudyStore(app: AppModel(root: store.repository.root))
        restarted.app.restore()
        fixture.window.contentView = NSHostingView(rootView: ReaderWindow(store: restarted))
        try await fixture.settle(500)
        XCTAssertEqual(restarted.workspace?.reading.layout, .twoPagesContinuous)
        XCTAssertEqual(restarted.reader.view?.displayMode, .twoUpContinuous, "The book opens again in the layout chosen.")
    }
}
