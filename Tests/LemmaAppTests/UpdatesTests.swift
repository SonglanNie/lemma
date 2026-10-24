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

    /// An update Sparkle resumes without reading the feed (downloaded earlier, or set to install when Lemma quits) is set
    /// aside when the feed lists a newer version: 3.4.0's appcast lists 3.4.0 and 3.3.1.
    func testTheFeedsNewestVersionSupersedesAResumedUpdate() {
        let appcast = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
        <item><title>3.3.1</title><sparkle:version>44</sparkle:version><sparkle:shortVersionString>3.3.1</sparkle:shortVersionString></item>
        <item><title>3.4.0</title><sparkle:version>45</sparkle:version><sparkle:shortVersionString>3.4.0</sparkle:shortVersionString></item>
        <item><title>3.0.0</title><enclosure url="https://example.com/Lemma.dmg" sparkle:version="37"/></item>
        </channel></rss>
        """
        XCTAssertEqual(Updates.newestVersion(inAppcast: appcast), "45")
        XCTAssertNil(Updates.newestVersion(inAppcast: "<rss><channel></channel></rss>"))
        XCTAssertTrue(Updates.isOlder("44", than: "45"))
        XCTAssertFalse(Updates.isOlder("45", than: "45"))
        XCTAssertTrue(Updates.isOlder("9", than: "10"), "Build numbers compare as numbers, as Sparkle compares them.")
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
