import XCTest
import LemmaCore

final class ReviewTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    func testIntervalsGrowWithSuccessfulRecallAndShrinkAfterALapse() {
        var schedule = ReviewSchedule(dueAt: start)
        var now = start
        var intervals: [Double] = []
        for _ in 0..<4 {
            schedule = ReviewScheduler.next(schedule, grade: .good, now: now)
            intervals.append(schedule.interval)
            XCTAssertEqual(schedule.dueAt.timeIntervalSince(now), schedule.interval * day, accuracy: 0.001)
            now = schedule.dueAt
        }
        XCTAssertEqual(intervals, [1, 3, 8, 20], "Good recalls grow roughly by the ease factor.")
        XCTAssertEqual(schedule.repetitions, 4)

        let lapse = ReviewScheduler.next(schedule, grade: .again, now: now)
        XCTAssertEqual(lapse.dueAt.timeIntervalSince(now), ReviewScheduler.relearnDelay, accuracy: 0.001)
        XCTAssertEqual(lapse.lapses, 1)
        XCTAssertEqual(lapse.repetitions, 0)
        XCTAssertEqual(lapse.ease, 2.3, accuracy: 0.0001)
        XCTAssertEqual(ReviewScheduler.next(lapse, grade: .good, now: now).interval, 1, "Relearning starts again at one day.")

        let fresh = ReviewSchedule(dueAt: start)
        XCTAssertEqual(ReviewScheduler.next(fresh, grade: .hard, now: start).interval, 1)
        XCTAssertEqual(ReviewScheduler.next(fresh, grade: .easy, now: start).interval, 4)
        XCTAssertEqual(ReviewScheduler.next(fresh, grade: .easy, now: start).ease, 2.65, accuracy: 0.0001)
        var long = fresh; long.repetitions = 9; long.interval = 300; long.ease = 3
        XCTAssertEqual(ReviewScheduler.next(long, grade: .easy, now: start).interval, ReviewScheduler.maximumInterval)
        var floor = fresh
        for _ in 0..<10 { floor = ReviewScheduler.next(floor, grade: .again, now: start) }
        XCTAssertEqual(floor.ease, 1.3, accuracy: 0.0001, "Ease never falls below 1.3.")

        let delays = ReviewScheduler.delays(for: fresh, now: start)
        XCTAssertEqual(ReviewScheduler.describe(delays[.again]!), "10 min")
        XCTAssertEqual(ReviewScheduler.describe(delays[.good]!), "1 d")
        XCTAssertEqual(ReviewScheduler.describe(delays[.easy]!), "4 d")
        XCTAssertEqual(ReviewScheduler.describe(21 * day), "3 wk")
        XCTAssertEqual(ReviewScheduler.describe(120 * day), "4 mo")
    }

    func testGradingNotesAndUpgradingEarlierRevisitState() throws {
        let anchor = SourceAnchor(pageIndex: 4, pageLabel: "5", region: PageRegion(x: 100, y: 200, width: 300, height: 60), quote: "", imageName: "a.png")
        var note = StudyNote(anchor: anchor, question: "Why is RSS convex?")
        note.createdAt = start // ISO 8601 storage keeps whole seconds.
        XCTAssertFalse(note.isInReview)
        XCTAssertEqual(note.recallQuestion, "Why is RSS convex?")
        note.recallPrompt = "  What makes the Hessian positive semidefinite?  "
        XCTAssertEqual(note.recallQuestion, "What makes the Hessian positive semidefinite?")

        note.state = .revisit
        XCTAssertTrue(note.isInReview, "Notes marked Revisit by earlier versions stay in review.")
        XCTAssertTrue(note.isDue(at: start), "…and are due immediately.")
        note.grade(.good, now: start)
        XCTAssertEqual(note.state, .understood)
        XCTAssertEqual(note.reviewCount, 1)
        XCTAssertEqual(note.lastReviewedAt, start)
        XCTAssertFalse(note.isDue(at: start.addingTimeInterval(day / 2)))
        XCTAssertTrue(note.isDue(at: start.addingTimeInterval(day)))
        XCTAssertTrue(note.isInReview, "A good recall keeps the note in the deck for later.")
        note.grade(.again, now: start.addingTimeInterval(day))
        XCTAssertEqual(note.state, .revisit)

        note.masks = [PageRegion(x: 250, y: 205, width: 120, height: 40)]
        var workspace = StudyWorkspace(id: "w", title: "Book", sourcePath: "/b.pdf", sourceBookmark: nil, fingerprint: "w")
        workspace.notes = [note]
        let data = try WorkspaceRepository.encoder.encode(workspace)
        let decoded = try WorkspaceRepository.decoder.decode(StudyWorkspace.self, from: data)
        XCTAssertEqual(decoded.notes, [note])
        XCTAssertEqual(decoded.schemaVersion, 10)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var legacyNote = try XCTUnwrap((legacy["notes"] as? [[String: Any]])?.first)
        for key in ["review", "recallPrompt", "masks"] { legacyNote.removeValue(forKey: key) }
        legacy["notes"] = [legacyNote]; legacy["schemaVersion"] = 5
        let migrated = try WorkspaceRepository.decoder.decode(StudyWorkspace.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(migrated.notes[0].review)
        XCTAssertEqual(migrated.notes[0].recallPrompt, "")
        XCTAssertEqual(migrated.notes[0].masks, [])
        XCTAssertEqual(migrated.notes[0].reviewCount, note.reviewCount)

        let markdown = WorkspaceRepository(root: FileManager.default.temporaryDirectory).markdown(for: decoded)
        XCTAssertTrue(markdown.contains("Recall prompt: What makes the Hessian positive semidefinite?"))
        XCTAssertTrue(markdown.contains("Next review: "))
        XCTAssertTrue(markdown.contains("1 part of the source hidden during recall"))
    }
}
