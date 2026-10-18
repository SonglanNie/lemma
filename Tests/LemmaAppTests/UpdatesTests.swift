import XCTest
@testable import Lemma

final class UpdatesTests: XCTestCase {
    /// Sparkle runs only in the packaged app: never in tests (it would check GitHub and could replace the test host).
    @MainActor
    func testSparkleStaysOffInTestsAndTheMenuFallsBackToTheReleaseCheck() {
        XCTAssertFalse(Updates.isEnabled)
        Updates.shared.start()
        XCTAssertFalse(Updates.shared.isAvailable)
        XCTAssertTrue(Updates.shared.canCheck, "Without Sparkle, Check for Updates… asks GitHub for the latest release.")
        XCTAssertFalse(Updates.shared.automaticallyDownloads)
    }

    /// Settings › Updates: the daily check (without Sparkle, the release check's setting); downloading on its own is
    /// offered only where Sparkle runs.
    @MainActor
    func testSettingsOfferTheDailyCheck() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let previous = UserDefaults.standard.object(forKey: UpdateChecker.automaticKey)
        defer { UserDefaults.standard.set(previous, forKey: UpdateChecker.automaticKey) }
        let items = SettingsRegistry.items(store: fixture.store)
        let daily = try XCTUnwrap(items.first { $0.id == "update.automaticChecks" })
        XCTAssertEqual(daily.section, "Updates")
        daily.set("true")
        XCTAssertTrue(UpdateChecker.shared.automatic)
        daily.set("false")
        XCTAssertFalse(UpdateChecker.shared.automatic)
        XCTAssertNil(items.first { $0.id == "update.automaticDownloads" })
    }

    func testVersionsCompareNumerically() {
        XCTAssertTrue(UpdateChecker.isNewer("3.10.0", than: "3.9.2"))
        XCTAssertTrue(UpdateChecker.isNewer("3.1", than: "3.0.9"))
        XCTAssertFalse(UpdateChecker.isNewer("3.1.0", than: "3.1"))
        XCTAssertFalse(UpdateChecker.isNewer("3.0.0", than: "3.1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("4.0.0-beta.1", than: "3.9"))
        XCTAssertTrue(UpdateChecker.isNewer("3.2.1-fork.2", than: "3.2.1-fork.1"))
        XCTAssertTrue(UpdateChecker.isNewer("3.2.1-fork.1", than: "3.2.1"))
        XCTAssertTrue(UpdateChecker.isNewer("3.2.2", than: "3.2.1-fork.3"))
        XCTAssertFalse(UpdateChecker.isNewer("3.2.1-fork.1", than: "3.2.1-fork.1"))
    }
}
