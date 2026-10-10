import Foundation

/// Lemma's own Python for the Lab: a virtual environment in its support folder (`<support>/Lab/python`) with NumPy,
/// SciPy, Matplotlib, SymPy and pandas, made from a Python 3 already on the Mac. Recent python.org and Homebrew Pythons
/// refuse `pip install` outside an environment (“externally-managed-environment”), so this is the one way that works
/// everywhere. Nothing outside that folder changes, apart from pip's usual download cache.
public enum LabEnvironment {
    public static let packages = ["numpy", "scipy", "matplotlib", "sympy", "pandas"]
    /// python.org's page with the macOS installers, for a Mac without any Python 3.
    public static let downloadPage = URL(string: "https://www.python.org/downloads/macos/")!
    /// Written first and removed last: a folder that still has it is a setup stopped half way, which the Lab ignores.
    static let incompleteMarker = ".lemma-incomplete"

    public static func directory(support: URL) -> URL {
        support.appendingPathComponent("Lab", isDirectory: true).appendingPathComponent("python", isDirectory: true)
    }

    public static func interpreter(in directory: URL) -> URL {
        directory.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("python3")
    }

    public static func isComplete(at directory: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: interpreter(in: directory).path)
            && !FileManager.default.fileExists(atPath: directory.appendingPathComponent(incompleteMarker).path)
    }

    /// Pythons that can make the environment, the best first: released versions before previews; then python.org's,
    /// whose framework paths stay put across updates, before Homebrew's (an upgrade can remove the interpreter an
    /// environment points to), others, and the Command Line Tools' old one; the newest first within each.
    /// Lemma's own environment is never its own base.
    public static func bases(from interpreters: [LabInterpreter], excluding directory: URL) -> [LabInterpreter] {
        let own = interpreter(in: directory).standardizedFileURL.path
        return interpreters.enumerated()
            .filter { URL(fileURLWithPath: $0.element.path).standardizedFileURL.path != own && version($0.element.version).number.lexicographicallyPrecedes([3, 9]) == false }
            .sorted { lhs, rhs in
                let l = version(lhs.element.version), r = version(rhs.element.version)
                if l.preview != r.preview { return !l.preview }
                let lo = origin(lhs.element.path), ro = origin(rhs.element.path)
                if lo != ro { return lo < ro }
                if l.number != r.number { return r.number.lexicographicallyPrecedes(l.number) }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// 0 python.org, 1 Homebrew, 2 anything else (conda, pyenv, a venv), 3 Apple's developer tools.
    static func origin(_ path: String) -> Int {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved.hasPrefix("/Library/Frameworks/Python.framework/") { return 0 }
        if resolved.hasPrefix("/opt/homebrew/") || resolved.hasPrefix("/usr/local/Cellar/") || resolved.hasPrefix("/usr/local/opt/") { return 1 }
        if resolved.hasPrefix("/usr/bin/") || resolved.hasPrefix("/Library/Developer/") || resolved.hasPrefix("/Applications/Xcode") { return 3 }
        return 2
    }

    /// “3.14.0rc2” → ([3, 14, 0], preview).
    static func version(_ text: String) -> (number: [Int], preview: Bool) {
        let digits = text.prefix { $0.isNumber || $0 == "." }
        return (digits.split(separator: ".").compactMap { Int($0) }, digits.count < text.count)
    }
}

/// pip's install output as progress. pip first looks up each distribution (“Collecting numpy”, then a small
/// “….whl.metadata” download), then downloads the wheels in one go (“Downloading numpy-2.5.3-…whl (5.4 MB)”, or
/// “Using cached …” when they are in its cache), then installs them all (“Installing collected packages: …”).
/// Look-ups fill 20–40 %, wheels 40–75 %, installing shows 80 %.
struct PipProgress {
    private(set) var collected = 0
    private(set) var wheels = 0

    mutating func read(_ line: String) -> LabEnvironmentSetup.Progress? {
        let text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("Collecting ") {
            collected += 1
            let name = text.dropFirst("Collecting ".count).prefix { !" <>=!~;[(".contains($0) }
            return .init(step: .packages, detail: "Looking up \(name)", fraction: 0.2 + 0.2 * min(1, Double(collected) / 15))
        }
        let cached = text.hasPrefix("Using cached ")
        guard cached || text.hasPrefix("Downloading ") else {
            return text.hasPrefix("Installing collected packages") ? .init(step: .install, detail: "Installing the packages", fraction: 0.8) : nil
        }
        let rest = text.dropFirst(cached ? "Using cached ".count : "Downloading ".count)
        let file = String(rest.split(separator: " ").first ?? rest)
        guard file.hasSuffix(".whl") else { return nil }
        wheels += 1
        let parts = (file.split(separator: "/").last ?? Substring(file)).split(separator: "-")
        let name = parts.count >= 2 ? "\(parts[0]) \(parts[1])" : file
        let size = rest.range(of: "(").map { " " + rest[$0.lowerBound...] } ?? ""
        return .init(step: .packages, detail: cached ? "\(name), already downloaded" : "Downloading \(name)\(size)",
                     fraction: 0.4 + 0.35 * min(1, Double(wheels) / Double(max(collected, 1))))
    }
}

/// One run of Set Up Python for the Lab: venv, then pip, then a check that the packages import. Every step runs at
/// utility priority (`taskpolicy -c utility`) in its own process group, so Cancel stops pip and anything it started.
public final class LabEnvironmentSetup: @unchecked Sendable {
    public enum Step: String, Sendable { case environment, pip, packages, install, check }

    public struct Progress: Sendable, Equatable {
        public var step: Step
        public var detail: String
        public var fraction: Double
        public init(step: Step, detail: String, fraction: Double) { self.step = step; self.detail = detail; self.fraction = fraction }
    }

    public enum Outcome: Sendable, Equatable {
        case finished(LabInterpreter)
        case failed(String)
        case cancelled
    }

    public let base: String
    public let directory: URL
    public let packages: [String]
    public let upgradePip: Bool
    private let lock = NSLock()
    private var current: Process?
    private var cancelled = false
    private var lines: [String] = []

    public init(base: String, directory: URL, packages: [String] = LabEnvironment.packages, upgradePip: Bool = true) {
        self.base = base; self.directory = directory; self.packages = packages; self.upgradePip = upgradePip
    }

    /// The last lines venv and pip printed, for a failure's details.
    public var log: String { lock.withLock { lines.joined(separator: "\n") } }

    public var isCancelled: Bool { lock.withLock { cancelled } }

    private struct Stopped: Error {}
    private struct Failure: Error { let message: String }

    /// Makes the environment and returns how it ended. Blocks until then: call it off the main thread.
    /// A failed or cancelled setup removes its folder.
    public func run(progress: @escaping @Sendable (Progress) -> Void) -> Outcome {
        let manager = FileManager.default
        guard LabInterpreterFinder.isSafeToRun(base), manager.isExecutableFile(atPath: base) else {
            return .failed("This Python cannot be used to make the environment.")
        }
        do {
            progress(Progress(step: .environment, detail: "Creating the environment", fraction: 0.02))
            if manager.fileExists(atPath: directory.path) { try manager.removeItem(at: directory) }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent(LabEnvironment.incompleteMarker))
            // Without `site` (-S): the base's .pth files neither run nor reach into folders macOS protects. pip then
            // runs in the new environment, which does not read the base's site-packages.
            try step([base, "-I", "-S", "-m", "venv", directory.path], failure: "Python could not create the environment.") { _ in }
            let python = LabEnvironment.interpreter(in: directory).path
            let pip = [python, "-I", "-m", "pip", "--disable-pip-version-check", "--no-input", "--retries", "2", "--timeout", "20"]
            if upgradePip {
                progress(Progress(step: .pip, detail: "Updating pip", fraction: 0.1))
                try step(pip + ["install", "--upgrade", "pip"], failure: "pip could not be updated. Is the Mac online?") { _ in }
            }
            if !packages.isEmpty {
                progress(Progress(step: .packages, detail: "Looking up " + packages.joined(separator: ", "), fraction: 0.2))
                var reader = PipProgress()
                // Ready-made packages only: building one from source needs compilers and pegs the Mac for many minutes.
                try step(pip + ["install", "--only-binary=:all:", "--progress-bar", "off"] + packages,
                         failure: "pip could not install the packages.") { line in
                    if let update = reader.read(line) { progress(update) }
                }
            }
            progress(Progress(step: .check, detail: "Checking that the packages import", fraction: 0.95))
            guard let interpreter = LabInterpreterFinder.probe(python, timeout: 60) else {
                throw Failure(message: "The new environment's Python does not start.")
            }
            let missing = packages.filter { interpreter.packages[$0] == nil }
            guard missing.isEmpty else { throw Failure(message: "These packages did not install: \(missing.joined(separator: ", ")).") }
            try manager.removeItem(at: directory.appendingPathComponent(LabEnvironment.incompleteMarker))
            progress(Progress(step: .check, detail: "Done", fraction: 1))
            return .finished(interpreter)
        } catch {
            try? manager.removeItem(at: directory)
            if isCancelled { return .cancelled }
            if let failure = error as? Failure { return .failed(failure.message) }
            return .failed(error.localizedDescription)
        }
    }

    /// Stops the running step (SIGTERM to its process group, SIGKILL two seconds later if needed); `run` then returns.
    public func cancel() {
        let process = lock.withLock { cancelled = true; return current }
        guard let process, process.isRunning else { return }
        let pid = process.processIdentifier
        Self.signal(pid, SIGTERM)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { if process.isRunning { Self.signal(pid, SIGKILL) } }
    }

    /// Stops the running step before returning, for quitting: SIGTERM, then SIGKILL after `timeout`.
    public func cancelAndWait(timeout: TimeInterval = 0.5) {
        let process = lock.withLock { cancelled = true; return current }
        guard let process, process.isRunning else { return }
        let pid = process.processIdentifier
        Self.signal(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(timeout)
        while LabKernel.isProcessAlive(pid), Date() < deadline { usleep(10_000) }
        if LabKernel.isProcessAlive(pid) { Self.signal(pid, SIGKILL) }
    }

    /// The step's process group too, when it leads one (Foundation's Process makes it), so pip's helpers stop with it.
    private static func signal(_ pid: Int32, _ signal: Int32) {
        if getpgid(pid) == pid { killpg(pid, signal) } else { kill(pid, signal) }
    }

    private func step(_ arguments: [String], failure: String, onLine: (String) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/taskpolicy")
        process.arguments = ["-c", "utility"] + arguments
        var environment = ProcessInfo.processInfo.environment
        // Settings meant for another Python or environment would break this one.
        for key in ["PYTHONPATH", "PYTHONHOME", "PYTHONSTARTUP", "PYTHONUSERBASE", "VIRTUAL_ENV", "__PYVENV_LAUNCHER__",
                    "PIP_REQUIRE_VIRTUALENV", "PIP_USER", "PIP_TARGET", "PIP_PREFIX", "CONDA_PREFIX"] {
            environment.removeValue(forKey: key)
        }
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try lock.withLock {
            if cancelled { throw Stopped() }
            current = process
            try process.run()
        }
        defer { lock.withLock { current = nil } }
        let handle = pipe.fileHandleForReading
        var pending = Data()
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...newline)
                record(line)
                onLine(line)
            }
        }
        if !pending.isEmpty { record(String(decoding: pending, as: UTF8.self)) }
        while process.isRunning { usleep(20_000) }
        if isCancelled { throw Stopped() }
        guard process.terminationStatus == 0 else {
            // pip's own last error says best what went wrong (no network, no package for this Python…).
            let reason = lock.withLock { lines.last { $0.hasPrefix("ERROR:") } }
            throw Failure(message: failure + (reason.map { "\n\($0)" } ?? ""))
        }
    }

    private func record(_ line: String) {
        let line = line.replacingOccurrences(of: "\r", with: "")
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        lock.withLock {
            lines.append(line)
            if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        }
    }
}
