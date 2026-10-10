import Foundation

/// Messages from a running Lab kernel, in the order the kernel wrote them.
public enum LabKernelEvent: Sendable, Equatable {
    case ready(python: String, executable: String, packages: [String: String])
    case stream(requestID: UUID?, name: String, text: String)
    case image(requestID: UUID?, png: Data)
    case result(requestID: UUID?, text: String)
    case error(requestID: UUID?, name: String, value: String, traceback: String)
    case done(requestID: UUID?, status: String, count: Int, duration: Double)
    case completions(requestID: UUID?, text: String, matches: [String])
    /// Output written below Python (C extensions, subprocesses), which bypasses the cell's streams.
    case log(String)
    case exited(Int32)
}

/// One Python process running a notebook's cells (`LabKernelScript`). Requests are queued by the kernel and run
/// in order; `interrupt()` sends SIGINT, which raises KeyboardInterrupt in the running cell.
/// The process can be clamped to utility QoS with fewer math threads (“gentle”), to keep the Mac cool.
///
/// A kernel never outlives Lemma: `shutdown()` escalates from closing its input to SIGKILL on its own, `shutdownAll`
/// stops every kernel of the app before returning (for quitting, when no queue runs afterwards), a kernel nobody holds
/// any more is stopped as it goes, and the script itself exits when Lemma's process does, even in the middle of a cell.
public final class LabKernel: @unchecked Sendable {
    public struct Configuration: Sendable, Equatable {
        public var interpreter: URL
        public var workingDirectory: URL
        public var scriptURL: URL
        public var gentle: Bool
        public init(interpreter: URL, workingDirectory: URL, scriptURL: URL, gentle: Bool) {
            self.interpreter = interpreter; self.workingDirectory = workingDirectory; self.scriptURL = scriptURL; self.gentle = gentle
        }
    }

    public let configuration: Configuration
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var handler: (@Sendable ([LabKernelEvent]) -> Void)?
    private var started = false
    private var stopping = false
    /// Cells sent and not yet done, so stopping interrupts only a kernel that is running one.
    private var inFlight = 0
    /// Events waiting for the next delivery; with an interval, streams are merged and delivered at most that often.
    private var pending: [LabKernelEvent] = []
    private var interval: TimeInterval = 0
    private var deliveryScheduled = false
    private var outputClosed = false
    private var exitStatus: Int32?
    private var finished = false
    /// Deliveries run here, in order, one batch at a time.
    private let delivery = DispatchQueue(label: "com.lemma.lab.kernel", qos: .userInitiated)

    public init(configuration: Configuration) { self.configuration = configuration }

    deinit {
        // A kernel nobody holds any more (its notebook was closed or restarted while it started) must not keep running.
        if process.isRunning, !stopping { Self.escalate(process, input: input.fileHandleForWriting, interrupt: inFlight > 0) }
    }

    public var isRunning: Bool { lock.withLock { started } && process.isRunning }
    public var processIdentifier: Int32 { process.processIdentifier }

    /// Launches the interpreter. Each event arrives on its own, on a background queue, as soon as it is read.
    public func start(handler: @escaping @Sendable (LabKernelEvent) -> Void) throws {
        try start(every: 0) { events in events.forEach(handler) }
    }

    /// Launches the interpreter. Events arrive in batches on a background queue: output is gathered for `interval`
    /// (consecutive chunks of one stream merged into one event), so a chatty cell costs its reader at most one batch
    /// per interval; ready, done, completions and exit are delivered at once, after everything before them.
    public func start(every interval: TimeInterval, handler: @escaping @Sendable ([LabKernelEvent]) -> Void) throws {
        guard LabInterpreterFinder.isSafeToRun(configuration.interpreter.path) else { throw CocoaError(.executableNotLoadable) }
        try FileManager.default.createDirectory(at: configuration.workingDirectory, withIntermediateDirectories: true)
        var environment = ProcessInfo.processInfo.environment
        environment["MPLBACKEND"] = "Agg"
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PYTHONIOENCODING"] = "utf-8"
        // The script watches this process and exits with it.
        environment["LEMMA_PARENT_PID"] = String(getpid())
        environment.removeValue(forKey: "PYTHONSTARTUP")
        if configuration.gentle {
            for key in ["VECLIB_MAXIMUM_THREADS", "OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"] { environment[key] = "2" }
            // taskpolicy replaces itself with Python (same process), so signals and the exit status are Python's.
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/taskpolicy")
            process.arguments = ["-c", "utility", configuration.interpreter.path, "-u", configuration.scriptURL.path]
        } else {
            process.executableURL = configuration.interpreter
            process.arguments = ["-u", configuration.scriptURL.path]
        }
        process.environment = environment
        process.currentDirectoryURL = configuration.workingDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        // Writing to a kernel that has just died fails with EPIPE instead of raising SIGPIPE, which would end Lemma.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        lock.withLock { self.handler = handler; self.interval = interval }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // End of file: the handler must go, or it is called again and again.
            guard !data.isEmpty else { handle.readabilityHandler = nil; self?.outputDidClose(); return }
            self?.consume(data)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.enqueue([.log(String(decoding: data, as: UTF8.self))])
        }
        process.terminationHandler = { [weak self] process in
            let pid = process.processIdentifier, status = process.terminationStatus
            // Whatever the cells started dies with the kernel (Process makes the kernel lead its own process group).
            if let entry = LabKernel.registry.remove(pid), entry.leadsGroup { killpg(pid, SIGTERM) }
            self?.processDidExit(status)
        }
        try process.run()
        let pid = process.processIdentifier
        Self.registry.add(pid, process: process, input: input.fileHandleForWriting, leadsGroup: getpgid(pid) == pid)
        lock.withLock { started = true }
    }

    public func execute(id: UUID, code: String) {
        lock.withLock { inFlight += 1 }
        send(["type": "execute", "id": id.uuidString, "code": code])
    }

    /// Asks for names completing `text` (“np.lin”) in the kernel's namespace. Answered between cells only.
    public func complete(id: UUID, text: String) {
        send(["type": "complete", "id": id.uuidString, "text": text])
    }

    /// Raises KeyboardInterrupt in the running cell; an idle kernel ignores it.
    public func interrupt() {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGINT)
    }

    /// Stops the kernel without waiting: its input closes (an idle kernel exits at once), SIGINT ends a running cell,
    /// then SIGTERM after half a second and SIGKILL after one and a half, for the kernel and whatever its cells started.
    public func shutdown() {
        let busy: Bool? = lock.withLock {
            guard started, !stopping else { return nil }
            stopping = true
            return inFlight > 0
        }
        guard let busy, process.isRunning else { return }
        Self.escalate(process, input: input.fileHandleForWriting, interrupt: busy)
    }

    /// Stops at once with SIGTERM, for tests.
    public func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }

    /// Stops every kernel this app started before returning, for quitting: after the app returns from its last
    /// callback no queue runs, so a deferred signal would never be sent and a busy kernel would be orphaned.
    /// Each kernel's input closes and a running cell is interrupted; whatever is still running after a third of
    /// `timeout` gets SIGTERM, after two thirds SIGKILL. Never takes longer than `timeout`.
    public static func shutdownAll(timeout: TimeInterval = 1) {
        let entries = registry.all().filter { isProcessAlive($0.pid) }
        guard !entries.isEmpty else { return }
        func alive(_ entry: Registry.Entry) -> Bool { entry.process.isRunning && isProcessAlive(entry.pid) }
        let start = Date()
        func waitUntil(_ fraction: Double) -> [Registry.Entry] {
            var left = entries.filter(alive)
            while !left.isEmpty, Date().timeIntervalSince(start) < timeout * fraction {
                usleep(10_000)
                left = left.filter(alive)
            }
            return left
        }
        for entry in entries {
            try? entry.input.close()
            kill(entry.pid, SIGINT)
        }
        for entry in waitUntil(0.35) { signal(entry, SIGTERM) }
        for entry in waitUntil(0.7) { signal(entry, SIGKILL) }
        _ = waitUntil(1)
        // Children of kernels that exited on their own would be left to launchd otherwise.
        for entry in entries where entry.leadsGroup { killpg(entry.pid, SIGKILL) }
    }

    /// The kernel processes of this app that are still running, for diagnostics and tests.
    public static var runningProcessIdentifiers: [Int32] { registry.all().map(\.pid).filter(isProcessAlive) }

    /// True while the process exists and has not exited (a zombie waiting to be reaped counts as exited).
    public static func isProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return false }
        return info.kp_proc.p_stat != SZOMB
    }

    private static func escalate(_ process: Process, input: FileHandle, interrupt: Bool) {
        try? input.close()
        let pid = process.processIdentifier
        if interrupt { kill(pid, SIGINT) }
        let queue = DispatchQueue.global(qos: .utility)
        // The closures hold the Process, so it is still there to ask; the registry knows whether it leads a group.
        queue.asyncAfter(deadline: .now() + 0.5) { if process.isRunning, let entry = registry.entry(pid) { signal(entry, SIGTERM) } }
        queue.asyncAfter(deadline: .now() + 1.5) { if process.isRunning, let entry = registry.entry(pid) { signal(entry, SIGKILL) } }
    }

    private static func signal(_ entry: Registry.Entry, _ signal: Int32) {
        if entry.leadsGroup { killpg(entry.pid, signal) } else { kill(entry.pid, signal) }
    }

    private func send(_ message: [String: String]) {
        guard process.isRunning, let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        do { try input.fileHandleForWriting.write(contentsOf: data + Data([0x0A])) } catch {}
    }

    // MARK: Delivery

    private enum Delivery { case now, later, none }

    private func enqueue(_ events: [LabKernelEvent]) {
        guard !events.isEmpty else { return }
        let (action, wait): (Delivery, TimeInterval) = lock.withLock {
            for event in events {
                if interval > 0 { Self.coalesce(event, into: &pending) } else { pending.append(event) }
            }
            if interval <= 0 || events.contains(where: \.isPrompt) { deliveryScheduled = true; return (.now, 0) }
            if deliveryScheduled { return (.none, 0) }
            deliveryScheduled = true
            return (.later, interval)
        }
        switch action {
        case .now: delivery.async { [weak self] in self?.deliver() }
        case .later: delivery.asyncAfter(deadline: .now() + wait) { [weak self] in self?.deliver() }
        case .none: break
        }
    }

    private func deliver() {
        let (batch, handler) = lock.withLock {
            let batch = pending
            pending = []; deliveryScheduled = false
            return (batch, self.handler)
        }
        guard !batch.isEmpty else { return }
        handler?(batch)
    }

    /// Merges a stream chunk into the previous one of the same request and stream.
    static func coalesce(_ event: LabKernelEvent, into events: inout [LabKernelEvent]) {
        switch (events.last, event) {
        case let (.stream(id, name, first)?, .stream(nextID, nextName, next)) where id == nextID && name == nextName:
            events[events.count - 1] = .stream(requestID: id, name: name, text: first + next)
        case let (.log(first)?, .log(next)):
            // Native code can write faster than anyone reads; a cell's output keeps far less than this anyway.
            guard first.utf8.count < 262_144 else { return }
            events[events.count - 1] = .log(first + next)
        default:
            events.append(event)
        }
    }

    private func consume(_ data: Data) {
        var lines: [Data] = []
        lock.withLock {
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
            }
        }
        let events = lines.compactMap { Self.event(from: Data($0)) }
        let done = events.filter { if case .done = $0 { true } else { false } }.count
        if done > 0 { lock.withLock { inFlight = max(0, inFlight - done) } }
        enqueue(events)
    }

    /// The exit event comes after the last output: once the process has exited and its output pipe is closed,
    /// or a second after the exit if a forked child still holds the pipe.
    private func processDidExit(_ status: Int32) {
        let closed = lock.withLock { exitStatus = status; return outputClosed }
        if closed { finish() } else { delivery.asyncAfter(deadline: .now() + 1) { [weak self] in self?.finish() } }
    }

    private func outputDidClose() {
        let exited = lock.withLock { outputClosed = true; return exitStatus != nil }
        if exited { finish() }
    }

    private func finish() {
        let status: Int32? = lock.withLock {
            guard !finished, let exitStatus else { return nil }
            finished = true
            return exitStatus
        }
        guard let status else { return }
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        enqueue([.exited(status)])
    }

    /// Decodes one protocol line.
    public static func event(from line: Data) -> LabKernelEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = object["type"] as? String else { return nil }
        let id = (object["id"] as? String).flatMap(UUID.init(uuidString:))
        switch type {
        case "ready":
            return .ready(python: object["python"] as? String ?? "", executable: object["executable"] as? String ?? "",
                          packages: (object["packages"] as? [String: String]) ?? [:])
        case "stream":
            return .stream(requestID: id, name: object["name"] as? String ?? "stdout", text: object["text"] as? String ?? "")
        case "image":
            guard let encoded = object["data"] as? String, let png = Data(base64Encoded: encoded) else { return nil }
            return .image(requestID: id, png: png)
        case "result":
            return .result(requestID: id, text: object["text"] as? String ?? "")
        case "error":
            return .error(requestID: id, name: object["ename"] as? String ?? "Error", value: object["evalue"] as? String ?? "",
                          traceback: object["traceback"] as? String ?? "")
        case "done":
            return .done(requestID: id, status: object["status"] as? String ?? "ok", count: object["count"] as? Int ?? 0,
                         duration: object["duration"] as? Double ?? 0)
        case "completions":
            return .completions(requestID: id, text: object["text"] as? String ?? "", matches: object["matches"] as? [String] ?? [])
        default:
            return nil
        }
    }

    /// Writes the kernel script where the interpreter can run it, replacing an older version.
    public static func installScript(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("lemma_kernel_v\(LabKernelScript.version).py")
        let data = Data(LabKernelScript.source.utf8)
        if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
        return url
    }

    // MARK: Every kernel of the app

    static let registry = Registry()

    /// The kernel processes this app started that have not exited, held here so quitting can reach every one of them.
    final class Registry: @unchecked Sendable {
        struct Entry { let pid: Int32; let process: Process; let input: FileHandle; let leadsGroup: Bool }
        private let lock = NSLock()
        private var entries: [Int32: Entry] = [:]
        func add(_ pid: Int32, process: Process, input: FileHandle, leadsGroup: Bool) {
            lock.withLock { entries[pid] = Entry(pid: pid, process: process, input: input, leadsGroup: leadsGroup) }
        }
        func remove(_ pid: Int32) -> Entry? { lock.withLock { entries.removeValue(forKey: pid) } }
        func entry(_ pid: Int32) -> Entry? { lock.withLock { entries[pid].flatMap { $0.process.isRunning ? $0 : nil } } }
        /// Only processes Foundation has not reaped: a reaped process's pid may already belong to another program.
        func all() -> [Entry] {
            lock.withLock {
                entries = entries.filter { $0.value.process.isRunning }
                return Array(entries.values)
            }
        }
    }
}

extension LabKernelEvent {
    /// Events a reader waits for: delivered at once rather than with the next batch of output.
    var isPrompt: Bool {
        switch self {
        case .ready, .done, .completions, .exited: true
        case .stream, .image, .result, .error, .log: false
        }
    }
}

// MARK: - Finding Python

/// A Python interpreter on this Mac and the scientific packages it can import.
public struct LabInterpreter: Codable, Equatable, Sendable, Identifiable {
    public var path: String
    public var version: String
    public var packages: [String: String]
    public var id: String { path }
    public init(path: String, version: String, packages: [String: String]) { self.path = path; self.version = version; self.packages = packages }

    /// NumPy and Matplotlib are what most book experiments need.
    public var isScientific: Bool { packages["numpy"] != nil && packages["matplotlib"] != nil }
    public var summary: String {
        let names = ["numpy", "scipy", "matplotlib", "pandas", "sklearn"].filter { packages[$0] != nil }
        return "Python \(version)" + (names.isEmpty ? " · no scientific packages" : " · " + names.joined(separator: ", "))
    }
}

public enum LabInterpreterFinder {
    /// Common places for python3 on a Mac, most likely to carry scientific packages first; Lemma's own environment
    /// (`managed`, made by Set Up Python for the Lab) comes before all of them once it is complete.
    public static func candidatePaths(home: URL = FileManager.default.homeDirectoryForCurrentUser, managed: URL? = nil) -> [String] {
        let h = home.path
        var paths = [
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/opt/homebrew/bin/python3",
            "\(h)/miniforge3/bin/python3", "\(h)/miniconda3/bin/python3", "\(h)/anaconda3/bin/python3",
            "/opt/homebrew/Caskroom/miniforge/base/bin/python3", "/opt/homebrew/Caskroom/miniconda/base/bin/python3",
            "/opt/anaconda3/bin/python3", "/opt/miniconda3/bin/python3",
            "\(h)/.pyenv/shims/python3", "\(h)/.local/bin/python3",
            "/usr/bin/python3"
        ]
        if let managed { paths.insert(managed.path, at: 0) }
        for version in ["3.14", "3.13", "3.12", "3.11", "3.10"] {
            paths.append("/Library/Frameworks/Python.framework/Versions/\(version)/bin/python3")
            paths.append("/opt/homebrew/opt/python@\(version)/bin/python3")
        }
        var seen = Set<String>()
        // Real paths only: a symlink to the same interpreter counts once. A venv's python3 is a symlink to its base
        // interpreter but a different environment, so it is kept by the path of its own directory.
        return paths.filter { isSafeToRun($0) && FileManager.default.isExecutableFile(atPath: $0) && seen.insert(identity($0)).inserted }
    }

    /// Without the Command Line Tools, /usr/bin/python3 (like every developer tool in /usr/bin) is a stub that opens
    /// Apple's “install the developer tools” dialog. Lemma never runs it then, under any name that leads to it.
    public static func isSafeToRun(_ path: String) -> Bool { isSafeToRun(path, developerToolsInstalled: developerToolsInstalled) }

    static func isSafeToRun(_ path: String, developerToolsInstalled: Bool) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard resolved.hasPrefix("/usr/bin/") || path.hasPrefix("/usr/bin/") else { return true }
        return developerToolsInstalled
    }

    static var developerToolsInstalled: Bool {
        ["/Library/Developer/CommandLineTools/usr/bin/python3", "/Applications/Xcode.app/Contents/Developer/usr/bin/python3"]
            .contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func identity(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        // venv: <env>/bin/python3 beside <env>/pyvenv.cfg
        let config = url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("pyvenv.cfg")
        if FileManager.default.fileExists(atPath: config.path) { return url.standardizedFileURL.path }
        return url.resolvingSymlinksInPath().path
    }

    /// Run with `-I -S`: without `site`, no .pth file runs. A .pth can run any code, and one that reaches into a protected
    /// folder (an editable install under ~/Documents) makes macOS hold the probe until the reader answers a privacy prompt
    /// on Lemma's behalf, at launch, for a mere look. The environment's own site-packages are added instead, found the way
    /// `site` finds them (a venv's from its pyvenv.cfg, which Pythons before 3.14 only read in `site`).
    static let probeScript = """
    import importlib.util, json, os, sys, sysconfig
    def site_packages():
        exe_dir = os.path.dirname(os.path.abspath(sys.executable))
        prefix = os.path.dirname(exe_dir)
        config = next((c for c in (os.path.join(exe_dir, "pyvenv.cfg"), os.path.join(prefix, "pyvenv.cfg")) if os.path.isfile(c)), None)
        if config is None:
            paths = sysconfig.get_paths()
            return [paths["purelib"], paths["platlib"]]
        scheme = "venv" if "venv" in sysconfig.get_scheme_names() else "posix_prefix"
        paths = sysconfig.get_paths(scheme=scheme, vars={"base": prefix, "platbase": prefix})
        found = [paths["purelib"], paths["platlib"]]
        with open(config, encoding="utf-8") as f:
            settings = dict((k.strip().lower(), v.strip().lower()) for k, _, v in (line.partition("=") for line in f) if _)
        if settings.get("include-system-site-packages") == "true":
            base = sysconfig.get_paths(vars={"base": sys.base_prefix, "platbase": sys.base_exec_prefix})
            found += [base["purelib"], base["platlib"]]
        return found
    for path in site_packages():
        if path and path not in sys.path and os.path.isdir(path):
            sys.path.append(path)
    try:
        from importlib import metadata
    except ImportError:
        metadata = None
    found = {}
    for module, dist in (("numpy","numpy"),("scipy","scipy"),("matplotlib","matplotlib"),("pandas","pandas"),("sklearn","scikit-learn"),("sympy","sympy"),("statsmodels","statsmodels")):
        if importlib.util.find_spec(module) is None: continue
        try: found[module] = metadata.version(dist) if metadata else ""
        except Exception: found[module] = ""
    print(json.dumps({"version": sys.version.split()[0], "packages": found}))
    """

    /// Runs the interpreter briefly to read its version and packages. Returns nil when it cannot run.
    public static func probe(_ path: String, timeout: TimeInterval = 10) -> LabInterpreter? {
        guard isSafeToRun(path), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-I", "-S", "-c", probeScript]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        // SIGKILL: a probe has nothing to save, and SIGTERM cannot end one that macOS holds in a privacy check.
        if process.isRunning { kill(process.processIdentifier, SIGKILL); return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? String else { return nil }
        return LabInterpreter(path: path, version: version, packages: object["packages"] as? [String: String] ?? [:])
    }

    /// Every working interpreter, the most useful first: NumPy and Matplotlib, then NumPy, then the newest Python.
    /// `managed` is Lemma's own environment; it is skipped while incomplete (a setup was stopped half way).
    public static func discover(preferred: String? = nil, managed: URL? = nil) -> [LabInterpreter] {
        let environment = managed.flatMap { LabEnvironment.isComplete(at: $0) ? LabEnvironment.interpreter(in: $0) : nil }
        var paths = candidatePaths(managed: environment)
        if let preferred, isSafeToRun(preferred), FileManager.default.isExecutableFile(atPath: preferred) {
            paths.removeAll { $0 == preferred }; paths.insert(preferred, at: 0)
        }
        let found = paths.compactMap { probe($0) }
        return found.enumerated().sorted { lhs, rhs in
            if lhs.element.path == preferred { return true }
            if rhs.element.path == preferred { return false }
            let l = rank(lhs.element), r = rank(rhs.element)
            return l == r ? lhs.offset < rhs.offset : l > r
        }.map(\.element)
    }

    static func rank(_ interpreter: LabInterpreter) -> Int {
        (interpreter.isScientific ? 4 : 0) + (interpreter.packages["numpy"] != nil ? 2 : 0) + (interpreter.packages["scipy"] != nil ? 1 : 0)
    }
}
