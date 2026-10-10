import XCTest
import AppKit
import LemmaCore
@testable import Lemma

/// Lemma costs nothing at rest: timers run only while there is something to count or to wait for.
final class IdleTests: XCTestCase {
    @MainActor
    func testReadingTimerRunsOnlyWhileLemmaIsInFront() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        let tracker = try XCTUnwrap(store.tracker)
        var front = false
        tracker.isReaderInFront = { front }
        store.open(fixture.book)
        XCTAssertFalse(tracker.isTiming, "In the background nothing is counted, so no timer runs")
        front = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(tracker.isTiming, "Back in front with a book open, reading time is counted again")
        front = false
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        XCTAssertFalse(tracker.isTiming)
        front = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        XCTAssertFalse(tracker.isTiming, "A sleeping screen is not being read")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertTrue(tracker.isTiming)
        front = false
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
    }

    @MainActor
    func testAnswersAreAwaitedOnlyWhileAQuestionIsOut() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        store.reader.selection = (0, CGRect(x: 20, y: 20, width: 60, height: 60), "source")
        store.addNote()
        XCTAssertFalse(store.hasPendingQuestion, "Nothing to wait for: no polling")
        let id = try XCTUnwrap(store.selectedNoteID)
        store.updateNote(id: id) { $0.pendingRequestID = UUID() }
        XCTAssertTrue(store.hasPendingQuestion)
        store.open(fixture.paper)
        store.flush()
        XCTAssertTrue(store.hasPendingQuestion, "A question asked in another book is still awaited")
    }
}
