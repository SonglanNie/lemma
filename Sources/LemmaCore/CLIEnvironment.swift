import Foundation
import os

/// Where the reader's command-line tools live. An app opened from the Finder inherits launchd's minimal PATH
/// (`/usr/bin:/bin:/usr/sbin:/sbin`): no Homebrew, no `~/.local/bin`, no Node version manager. A CLI installed
/// with npm under nvm then fails with “env: node: No such file or directory” even when its path is chosen by hand.
/// Lemma asks the login shell for its PATH once per launch, adds the usual install folders, and puts the chosen
/// executable's own folder first, so a `#!/usr/bin/env node` script finds the Node it was installed with.
public enum CLIEnvironment {
    private static let loginPath = OSAllocatedUnfairLock<[String]?>(initialState: nil)
    private static let resolver = LoginShellResolver()

    /// The login shell's PATH once it has answered; empty before that. Never blocks, so views may call it.
    public static var cachedLoginShellPath: [String] { loginPath.withLock { $0 } ?? [] }

    /// Runs the login shell at most once per launch, off the calling thread, with a short timeout.
    public static func loginShellPath() async -> [String] {
        let value = await resolver.value()
        loginPath.withLock { $0 = value }
        return value
    }

    /// Folders to search, in order: the login shell's PATH, the inherited PATH, then the usual install folders.
    public static func searchPath(loginShell: [String] = cachedLoginShellPath,
                                  inherited: String? = ProcessInfo.processInfo.environment["PATH"],
                                  home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> [String] {
        unique(loginShell + (inherited ?? "").split(separator: ":").map(String.init) + commonDirectories(home: home))
    }

    /// Install folders a GUI app does not see: Homebrew, `~/.local/bin`, Volta, the newest nvm Node, fnm, asdf, mise.
    public static func commonDirectories(home: String) -> [String] {
        let fileManager = FileManager.default
        var candidates = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", home + "/.volta/bin"]
        let nvm = home + "/.nvm/versions/node"
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvm) {
            if let newest = versions.filter({ $0.hasPrefix("v") }).max(by: { versionLess($0, $1) }) { candidates.append("\(nvm)/\(newest)/bin") }
        }
        candidates += [home + "/.local/share/fnm/aliases/default/bin", home + "/Library/Application Support/fnm/aliases/default/bin",
                       home + "/.fnm/aliases/default/bin", home + "/.asdf/shims", home + "/.local/share/mise/shims",
                       home + "/.npm-global/bin", home + "/.bun/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        return candidates.filter { path in
            var directory: ObjCBool = false
            return fileManager.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
        }
    }

    /// `~` and `~/…` as the shell would expand them; other text is unchanged apart from surrounding spaces.
    public static func expandingTilde(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("~") ? (trimmed as NSString).expandingTildeInPath : trimmed
    }

    /// A typed executable: a path (with `~`), a folder containing `name`, or a bare command name looked up in `searchPath`.
    public static func resolve(_ typed: String, name: String? = nil, searchPath: [String]) -> URL? {
        let path = expandingTilde(typed)
        guard !path.isEmpty else { return nil }
        let fileManager = FileManager.default
        if !path.contains("/") {
            return searchPath.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent(path) }.first { fileManager.isExecutableFile(atPath: $0.path) }
        }
        var directory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &directory), directory.boolValue {
            guard let name else { return nil }
            let inside = URL(fileURLWithPath: path).appendingPathComponent(name)
            return fileManager.isExecutableFile(atPath: inside.path) ? inside : nil
        }
        return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    /// The first executable called `name` in `searchPath`.
    public static func find(_ name: String, searchPath: [String]) -> URL? {
        searchPath.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// The inherited environment with a complete PATH: the executable's own folder first (as given, not resolved, so a
    /// Homebrew or nvm symlink keeps its sibling `node`), then `searchPath`. Nothing else is added or removed here.
    public static func environment(for executable: URL?, base: [String: String] = ProcessInfo.processInfo.environment,
                                   searchPath: [String]) -> [String: String] {
        var result = base
        let own = executable.map { [$0.deletingLastPathComponent().path] } ?? []
        result["PATH"] = unique(own + searchPath + (base["PATH"] ?? "").split(separator: ":").map(String.init)).joined(separator: ":")
        return result
    }

    /// Asks `shell` for its interactive login PATH. The value is written to a file rather than read from a pipe:
    /// shell start-up files may print banners, and daemons they start can hold a pipe open forever.
    public static func queryLoginShell(shell: String = userShell(), timeout: TimeInterval = 4) -> [String] {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("lemma-path-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: output) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "printf '%s' \"$PATH\" > \"$1\"", "lemma-path", output.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return [] }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
        }
        guard let text = try? String(contentsOf: output, encoding: .utf8) else { return [] }
        return unique(text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":").map(String.init).filter { $0.hasPrefix("/") })
    }

    /// The account's login shell when it understands `-ilc` like zsh; otherwise zsh, macOS's default.
    public static func userShell() -> String {
        if let entry = getpwuid(getuid()), let raw = entry.pointee.pw_shell {
            let path = String(cString: raw)
            if ["zsh", "bash", "sh", "ksh", "dash"].contains((path as NSString).lastPathComponent), FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/bin/zsh"
    }

    static func unique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// `v20.10.1` after `v9.0.0`: numeric comparison of dotted components.
    static func versionLess(_ lhs: String, _ rhs: String) -> Bool {
        func parts(_ value: String) -> [Int] { value.drop { !$0.isNumber }.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let left = parts(lhs), right = parts(rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0, b = index < right.count ? right[index] : 0
            if a != b { return a < b }
        }
        return false
    }
}

/// One login-shell query per launch, however many callers ask at once.
private actor LoginShellResolver {
    private var task: Task<[String], Never>?
    func value() async -> [String] {
        if let task { return await task.value }
        let task = Task.detached(priority: .utility) { CLIEnvironment.queryLoginShell() }
        self.task = task
        return await task.value
    }
}
