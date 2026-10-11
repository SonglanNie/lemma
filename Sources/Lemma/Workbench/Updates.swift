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
    private var controller: SPUStandardUpdaterController?
    /// What the last check found, for the QA hooks: "checking", "none", "found 3.1.1", "downloaded 3.1.1",
    /// "ready 3.1.1" (installs when Lemma quits) or "error …".
    private(set) var lastEvent = ""

    var isAvailable: Bool { controller != nil }

    func start() {
        guard controller == nil, Self.isEnabled else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        // Lemma 3.0 had its own daily check, off unless turned on: a reader who turned it on keeps it and is not asked again.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: UpdateChecker.automaticKey) { controller.updater.automaticallyChecksForUpdates = true }
        defaults.removeObject(forKey: UpdateChecker.automaticKey)
        controller.startUpdater()
        self.controller = controller
    }

    /// Sparkle runs in the packaged app only: not in tests, not in a build without a feed, not in QA copies unless
    /// `LEMMA_QA_UPDATES` is set.
    static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil, environment["XCTestConfigurationFilePath"] == nil else { return false }
        return environment["LEMMA_QA_DIR"] == nil || environment["LEMMA_QA_UPDATES"] != nil
    }

    /// False while a check or an installation is under way.
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? !UpdateChecker.shared.isChecking }

    /// Lemma › Check for Updates…: Sparkle's window, or, without Sparkle, a notification about the latest release.
    func checkForUpdates(store: StudyStore) {
        if let controller {
            controller.checkForUpdates(nil)
        } else {
            UpdateChecker.shared.store = store
            Task { await UpdateChecker.shared.check(userInitiated: true) }
        }
    }

    /// Checks quietly, as the daily check does (QA).
    func checkInBackground() {
        lastEvent = "checking"
        controller?.updater.checkForUpdatesInBackground()
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? UpdateChecker.shared.automatic }
        set { if let controller { controller.updater.automaticallyChecksForUpdates = newValue } else { UpdateChecker.shared.automatic = newValue } }
    }

    /// Sparkle downloads and installs on its own only while it also checks on its own: turning this on turns that on.
    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            guard let updater = controller?.updater else { return }
            if newValue, !updater.automaticallyChecksForUpdates { updater.automaticallyChecksForUpdates = true }
            updater.automaticallyDownloadsUpdates = newValue
        }
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
}
