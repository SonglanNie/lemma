import AppKit
import IOKit.ps
import LemmaCore
import Observation
import os

/// Why page indexing waits.
enum IndexingPause: Equatable, Sendable {
    case battery, lowPower, heat
    var label: String {
        switch self {
        case .battery: "Paused on battery · resumes when the Mac is plugged in"
        case .lowPower: "Paused in Low Power Mode"
        case .heat: "Paused while the Mac is hot · resumes when it cools"
        }
    }
}

/// How a run of the indexing helper ended.
enum PageIndexOutcome: Equatable, Sendable { case finished, stopped, failed(String) }

/// Page indexing (text extraction, OCR of scanned pages and sentence embeddings: a long job) runs in the bundled
/// `LemmaIndexer`, one process per book, clamped to utility priority. It waits (the process is stopped, not ended)
/// while the Mac runs on battery, in Low Power Mode or hot, and goes on by itself afterwards. Quitting Lemma ends it;
/// completed pages are kept and Resume continues from there. Progress comes from the helper's output: nothing polls.
@MainActor @Observable
final class PageIndexer {
    static let shared = PageIndexer()

    /// Why the running jobs wait; nil while they run, or when none runs.
    private(set) var pause: IndexingPause?
    @ObservationIgnored private var jobs: [String: Job] = [:]
    @ObservationIgnored private var power: PowerConditions?
    @ObservationIgnored private var quitObserver: NSObjectProtocol?

    @MainActor private final class Job {
        let process: Process
        let onProgress: @MainActor (Int, Int) -> Void
        let onExit: @MainActor (PageIndexOutcome) -> Void
        let errors = OutputTail(limit: 4096)
        /// SIGSTOP is in force.
        var stopped = false
        /// Stop was asked for (or Lemma is quitting).
        var ending = false
        var latest: (done: Int, total: Int)?
        var deliveryScheduled = false
        init(process: Process, onProgress: @escaping @MainActor (Int, Int) -> Void, onExit: @escaping @MainActor (PageIndexOutcome) -> Void) {
            self.process = process; self.onProgress = onProgress; self.onExit = onExit
        }
    }

    /// The helper. The app bundle keeps it in a background-only bundle of its own, Contents/Helpers/LemmaIndexer.app:
    /// PDFKit registers the helper with the window server, and from Contents/MacOS it would register as Lemma and get
    /// a Dock icon of its own. A development build has it beside Lemma's executable.
    nonisolated static var helperURL: URL? {
        let bundle = Bundle.main.bundleURL
        let url = bundle.pathExtension == "app"
            ? bundle.appendingPathComponent("Contents/Helpers/LemmaIndexer.app/Contents/MacOS/LemmaIndexer")
            : Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("LemmaIndexer")
        guard let url, FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }

    private static func key(_ id: String, root: URL) -> String { root.standardizedFileURL.path + "|" + id }

    func isRunning(_ id: String, root: URL) -> Bool { jobs[Self.key(id, root: root)] != nil }

    /// The helper's process while it runs, for tests and diagnostics.
    func processIdentifier(_ id: String, root: URL) -> Int32? { jobs[Self.key(id, root: root)]?.process.processIdentifier }

    /// Starts indexing a book in the helper. `onProgress` hears of completed pages at most once a second.
    func start(id: String, source: String, root: URL, jobName: String, helper: URL,
               onProgress: @escaping @MainActor (Int, Int) -> Void, onExit: @escaping @MainActor (PageIndexOutcome) -> Void) throws {
        let key = Self.key(id, root: root)
        guard jobs[key] == nil else { return }
        let process = Process()
        let arguments = ["--source", source, "--workspace", id, "--root", root.path, "--job", jobName]
        // As the Lab's gentle mode does: `taskpolicy -c utility` clamps every thread of the helper (Vision's and
        // NaturalLanguage's too) to utility QoS. It becomes the helper (same process), so stopping and ending work alike.
        let taskpolicy = "/usr/sbin/taskpolicy"
        if FileManager.default.isExecutableFile(atPath: taskpolicy) {
            process.executableURL = URL(fileURLWithPath: taskpolicy)
            process.arguments = ["-c", "utility", helper.path] + arguments
        } else {
            process.executableURL = helper
            process.arguments = arguments
        }
        process.qualityOfService = .utility
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        let job = Job(process: process, onProgress: onProgress, onExit: onExit)
        let lines = LineBuffer(), tail = job.errors
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in lines.append(data) {
                let parts = line.split(separator: " ")
                guard parts.count == 3, parts[0] == "progress", let done = Int(parts[1]), let total = Int(parts[2]) else { continue }
                Task { @MainActor in PageIndexer.shared.advance(key, done: done, total: total) }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { tail.append(data) }
        }
        process.terminationHandler = { process in
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            let status = process.terminationStatus, signalled = process.terminationReason == .uncaughtSignal
            Task { @MainActor in PageIndexer.shared.ended(key, status: status, signalled: signalled) }
        }
        try process.run()
        jobs[key] = job
        watchConditions()
    }

    /// Ends a book's indexing; the pages done so far are kept.
    func stop(_ id: String, root: URL) {
        guard let job = jobs[Self.key(id, root: root)] else { return }
        end(job)
    }

    /// Lemma is quitting: no helper outlives it (the next Resume continues from the pages kept).
    func endAll() { for job in jobs.values { end(job) } }

    private func end(_ job: Job) {
        job.ending = true
        guard job.process.isRunning else { return }
        let pid = job.process.processIdentifier
        kill(pid, SIGTERM)
        // A stopped process acts on the signal once it continues.
        if job.stopped { kill(pid, SIGCONT); job.stopped = false }
    }

    private func advance(_ key: String, done: Int, total: Int) {
        guard let job = jobs[key] else { return }
        job.latest = (done, total)
        guard !job.deliveryScheduled else { return }
        job.deliveryScheduled = true
        // Pages of text are indexed many times a second: the window hears of them at most once a second.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard let job = PageIndexer.shared.jobs[key] else { return }
            job.deliveryScheduled = false
            if let latest = job.latest { job.onProgress(latest.done, latest.total) }
        }
    }

    private func ended(_ key: String, status: Int32, signalled: Bool) {
        guard let job = jobs.removeValue(forKey: key) else { return }
        let outcome: PageIndexOutcome
        if job.ending { outcome = .stopped }
        else if !signalled && status == 0 { outcome = .finished }
        else if signalled { outcome = .failed("The indexing worker stopped on this PDF. Completed pages are kept; resume to try again.") }
        else {
            let message = job.errors.text.trimmingCharacters(in: .whitespacesAndNewlines)
            outcome = .failed(message.isEmpty ? "Indexing did not finish. Completed pages are kept; resume to try again." : message)
        }
        job.onExit(outcome)
        watchConditions()
    }

    /// Battery, Low Power Mode and heat are watched only while a job runs.
    private func watchConditions() {
        guard !jobs.isEmpty else {
            power?.stop(); power = nil
            if pause != nil { pause = nil }
            return
        }
        if power == nil {
            let conditions = PowerConditions { PageIndexer.shared.conditionsChanged() }
            conditions.start()
            power = conditions
        }
        if quitObserver == nil {
            quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PageIndexer.shared.endAll() }
            }
        }
        conditionsChanged()
    }

    /// Stops or continues the running jobs as the Mac's conditions now require.
    func conditionsChanged() {
        let reason = jobs.isEmpty ? nil : PowerConditions.reason
        if pause != reason { pause = reason }
        for job in jobs.values where !job.ending && job.process.isRunning {
            let pid = job.process.processIdentifier
            if reason != nil, !job.stopped { kill(pid, SIGSTOP); job.stopped = true }
            else if reason == nil, job.stopped { kill(pid, SIGCONT); job.stopped = false }
        }
    }
}

/// Whether long background work should wait: on battery, in Low Power Mode, or while the Mac is hot. Changes are
/// announced (power source, thermal state, Low Power Mode) rather than polled, and only while `start` is in force.
@MainActor
final class PowerConditions {
    private let changed: @MainActor () -> Void
    private var source: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []

    init(changed: @escaping @MainActor () -> Void) { self.changed = changed }

    fileprivate func notify() { changed() }

    /// Replaces the Mac's conditions in tests (`.some(nil)`: nothing to wait for).
    nonisolated(unsafe) static var simulated: IndexingPause?? = nil

    /// Why long work should wait now, if it should.
    static var reason: IndexingPause? {
        if let simulated { return simulated }
        let info = ProcessInfo.processInfo
        if info.thermalState == .serious || info.thermalState == .critical { return .heat }
        if info.isLowPowerModeEnabled { return .lowPower }
        if onBattery { return .battery }
        return nil
    }

    /// The Mac draws on its battery (IOKit's providing power source; “Battery Power” is `kIOPMBatteryPowerKey`).
    static var onBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return false }
        return (type as String) == "Battery Power"
    }

    func start() {
        guard observers.isEmpty else { return }
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed() }
            })
        }
        // Plugging in and unplugging are announced on the main run loop.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(powerSourceChanged, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            self.source = source
        }
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes); CFRunLoopSourceInvalidate(source) }
        source = nil
    }
}

/// IOKit's power source callback, outside any actor (closures formed in main-actor code check their executor).
private let powerSourceChanged: IOPowerSourceCallbackType = { context in
    guard let address = context.map({ UInt(bitPattern: $0) }) else { return }
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
        Unmanaged<PowerConditions>.fromOpaque(pointer).takeUnretainedValue().notify()
    }
}
