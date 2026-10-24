import AppKit
import Sparkle

/// In-app updates, through Sparkle. **Lemma › Check for Updates…** looks at once and offers to install the new version
/// and relaunch; a check once a day runs only if the reader agreed (Sparkle asks at the second launch, and Settings ›
/// Updates changes it). Each release publishes, beside its disk image on GitHub, an appcast signed with the project's
/// EdDSA key, and an update installs only if its archive carries that key's signature.
///
/// Sparkle stays off in builds without a feed (`swift run`), in tests and in QA copies (unless `LEMMA_QA_UPDATES` is
/// set): `UpdateChecker` then only reports a newer release.
@MainActor
final class Updates: NSObject {
    static let shared = Updates()
    private var updater: SPUUpdater?
    private var userDriver: UserDriver?
    /// What the last check found, for the QA hooks: "checking", "none", "found 3.1.1", "downloaded 3.1.1",
    /// "ready 3.1.1" (installs when Lemma quits), "superseded 3.1.1" (set aside for a newer one) or "error …".
    private(set) var lastEvent = ""
    /// An update Sparkle resumed was set aside for a newer one: the check starts again, from the feed, once it ends.
    private var checksAgain = false
    private var supersededAt: Date?

    var isAvailable: Bool { updater != nil }

    func start() {
        guard updater == nil, Self.isEnabled else { return }
        let userDriver = UserDriver(hostBundle: .main, delegate: nil)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: userDriver, delegate: self)
        // Lemma 3.0 had its own daily check, off unless turned on: a reader who turned it on keeps it and is not asked again.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: UpdateChecker.automaticKey) { updater.automaticallyChecksForUpdates = true }
        defaults.removeObject(forKey: UpdateChecker.automaticKey)
        do {
            try updater.start()
        } catch {
            // Check for Updates… then asks GitHub for the latest release, as a build without Sparkle does.
            lastEvent = "error \(error.localizedDescription)"
            return
        }
        self.updater = updater
        self.userDriver = userDriver
    }

    /// Sparkle runs in the packaged app only: not in tests, not in a build without a feed, not in QA copies unless
    /// `LEMMA_QA_UPDATES` is set.
    static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil, environment["XCTestConfigurationFilePath"] == nil else { return false }
        return environment["LEMMA_QA_DIR"] == nil || environment["LEMMA_QA_UPDATES"] != nil
    }

    /// False while a check or an installation is under way.
    var canCheck: Bool { updater?.canCheckForUpdates ?? !UpdateChecker.shared.isChecking }

    /// Lemma › Check for Updates…: Sparkle's window, or, without Sparkle, a notification about the latest release.
    func checkForUpdates(store: StudyStore) {
        if let updater {
            updater.checkForUpdates()
        } else {
            UpdateChecker.shared.store = store
            Task { await UpdateChecker.shared.check(userInitiated: true) }
        }
    }

    /// Checks quietly, as the daily check does (QA).
    func checkInBackground() {
        lastEvent = "checking"
        updater?.checkForUpdatesInBackground()
    }

    var automaticallyChecks: Bool {
        get { updater?.automaticallyChecksForUpdates ?? UpdateChecker.shared.automatic }
        set { if let updater { updater.automaticallyChecksForUpdates = newValue } else { UpdateChecker.shared.automatic = newValue } }
    }

    /// Sparkle downloads and installs on its own only while it also checks on its own: turning this on turns that on.
    var automaticallyDownloads: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set {
            guard let updater else { return }
            if newValue, !updater.automaticallyChecksForUpdates { updater.automaticallyChecksForUpdates = true }
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    /// Whether the feed now lists a newer version than `item`, an update Sparkle offers again without reading the feed
    /// (downloaded earlier, or set to install when Lemma quits). At most once in half a minute, so that an installer slow
    /// to let go of the update cannot make the check go round.
    fileprivate func supersedes(_ item: SUAppcastItem) async -> Bool {
        if let supersededAt, Date.now.timeIntervalSince(supersededAt) < 30 { return false }
        guard let newest = await Self.newestVersionInFeed(), Self.isOlder(item.versionString, than: newest) else { return false }
        supersededAt = .now
        checksAgain = true
        lastEvent = "superseded \(item.displayVersionString)"
        return true
    }

    /// The newest version (build number) the feed lists, or nil when it cannot be read.
    private static func newestVersionInFeed() async -> String? {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String, let url = URL(string: feed) else { return nil }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return newestVersion(inAppcast: String(decoding: data, as: UTF8.self))
    }

    /// The highest `sparkle:version` among an appcast's items, compared as Sparkle compares them.
    nonisolated static func newestVersion(inAppcast appcast: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: #"<sparkle:version>\s*([^<\s]+)\s*</sparkle:version>|sparkle:version="([^"]+)""#)
        let versions = pattern.matches(in: appcast, range: NSRange(appcast.startIndex..., in: appcast)).compactMap { match in
            [1, 2].lazy.compactMap { Range(match.range(at: $0), in: appcast) }.first.map { String(appcast[$0]) }
        }
        return versions.max { isOlder($0, than: $1) }
    }

    nonisolated static func isOlder(_ version: String, than other: String) -> Bool {
        SUStandardVersionComparator.default.compareVersion(version, toVersion: other) == .orderedAscending
    }
}

extension Updates: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { lastEvent = "found \(item.displayVersionString)" }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { lastEvent = "none" }
    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) { lastEvent = "downloaded \(item.displayVersionString)" }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        lastEvent = "ready \(item.displayVersionString)"
        return false
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        lastEvent = (error as NSError).code == Int(SUError.noUpdateError.rawValue) ? "none" : "error \(error.localizedDescription)"
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard checksAgain else { return }
        checksAgain = false
        Task { [weak self] in
            // The installer that was waiting for Lemma to quit lets go of the update set aside first.
            try? await Task.sleep(for: .seconds(1))
            guard let updater = self?.updater else { return }
            if updateCheck == .updates { updater.checkForUpdates() } else { updater.checkForUpdatesInBackground() }
        }
    }
}

/// Sparkle's own windows, but for an update Sparkle offers again without reading the feed: one downloaded earlier, or set
/// to install when Lemma quits. When the feed has a newer version, that update is set aside and the check starts again
/// from the feed; a reader who had let an update wait while newer releases came out was offered the older one, and went
/// through each release in turn.
private final class UserDriver: SPUStandardUserDriver {
    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard state.stage != .notDownloaded else { return super.showUpdateFound(with: appcastItem, state: state, reply: reply) }
        Task {
            // Skipping cancels the waiting installation, or forgets the download; the version is newer than the one skipped.
            if await Updates.shared.supersedes(appcastItem) {
                reply(.skip)
            } else {
                super.showUpdateFound(with: appcastItem, state: state, reply: reply)
            }
        }
    }
}
