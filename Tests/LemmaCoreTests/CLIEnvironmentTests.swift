import XCTest
@testable import LemmaCore

final class CLIEnvironmentTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("lemma-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return home
    }

    private func script(_ url: URL, _ body: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func testLoginShellPathIsReadFromAFileAndATimeoutIsHarmless() throws {
        let home = try temporaryHome()
        // A stand-in shell: arguments are -ilc, the command, $0, then the output file. It prints a banner too.
        let shell = home.appendingPathComponent("fake-zsh")
        try script(shell, "echo 'Welcome back'\nprintf '%s' '/opt/tools/bin:/usr/bin:relative/dir:/opt/tools/bin' > \"$4\"")
        XCTAssertEqual(CLIEnvironment.queryLoginShell(shell: shell.path, timeout: 5), ["/opt/tools/bin", "/usr/bin"])
        let slow = home.appendingPathComponent("slow-zsh")
        try script(slow, "sleep 30")
        let started = Date()
        XCTAssertEqual(CLIEnvironment.queryLoginShell(shell: slow.path, timeout: 0.5), [])
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "A shell that hangs is stopped after the timeout.")
    }

    func testCommonFoldersIncludeTheNewestNvmNodeAndVolta() throws {
        let home = try temporaryHome()
        for version in ["v9.11.2", "v20.10.1", "v18.19.0"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".nvm/versions/node/\(version)/bin"), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".volta/bin"), withIntermediateDirectories: true)
        let folders = CLIEnvironment.commonDirectories(home: home.path)
        XCTAssertTrue(folders.contains(home.path + "/.nvm/versions/node/v20.10.1/bin"))
        XCTAssertFalse(folders.contains(home.path + "/.nvm/versions/node/v18.19.0/bin"))
        XCTAssertTrue(folders.contains(home.path + "/.volta/bin"))
        XCTAssertFalse(folders.contains(home.path + "/.asdf/shims"), "Folders that do not exist are left out.")
        let search = CLIEnvironment.searchPath(loginShell: ["/login/bin"], inherited: "/usr/bin:/bin", home: home.path)
        XCTAssertEqual(search.first, "/login/bin")
        XCTAssertEqual(search.filter { $0 == "/usr/bin" }.count, 1, "Each folder appears once.")
    }

    func testTypedPathsExpandTildeAcceptFoldersAndCommandNames() throws {
        let home = try temporaryHome()
        let tool = home.appendingPathComponent("bin/claude")
        try script(tool, "exit 0")
        XCTAssertEqual(CLIEnvironment.expandingTilde("  ~/bin/claude "), (NSHomeDirectory() as NSString).appendingPathComponent("bin/claude"))
        XCTAssertEqual(CLIEnvironment.resolve(tool.path, searchPath: [])?.path, tool.path)
        XCTAssertEqual(CLIEnvironment.resolve(tool.deletingLastPathComponent().path, name: "claude", searchPath: [])?.path, tool.path)
        XCTAssertEqual(CLIEnvironment.resolve("claude", searchPath: ["/nonexistent", tool.deletingLastPathComponent().path])?.path, tool.path)
        XCTAssertNil(CLIEnvironment.resolve(home.appendingPathComponent("missing").path, searchPath: []))
        XCTAssertEqual(QuestionCLI.executable(.claudeCode, preferred: tool.path, searchPath: [])?.path, tool.path)
        XCTAssertEqual(QuestionCLI.executable(.claudeCode, searchPath: [tool.deletingLastPathComponent().path])?.path, tool.path)
    }

    /// The case behind “env: node: No such file or directory”: a `#!/usr/bin/env node` CLI next to its own Node,
    /// in a folder a Finder-launched app does not have on PATH.
    func testTheExecutablesFolderComesFirstSoEnvFindsItsInterpreter() async throws {
        let home = try temporaryHome()
        let bin = home.appendingPathComponent(".nvm/versions/node/v22.1.0/bin")
        try script(bin.appendingPathComponent("node"), "echo \"node-ran $@\"")
        let cli = bin.appendingPathComponent("codex")
        try Data("#!/usr/bin/env node\n".utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let launchd = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home.path]
        let bare = try await QuestionProcess.capture(executable: cli, arguments: ["--version"], directory: home, environment: launchd)
        XCTAssertEqual(bare.code, 127, "Without its folder on PATH, env cannot find node.")
        let environment = QuestionCLI.environment(for: cli, base: launchd, searchPath: [])
        XCTAssertTrue(environment["PATH"]!.hasPrefix(bin.path + ":"))
        let fixed = try await QuestionProcess.capture(executable: cli, arguments: ["--version"], directory: home, environment: environment)
        XCTAssertEqual(fixed.code, 0); XCTAssertTrue(fixed.output.contains("node-ran"))
    }
}

final class QuestionProcessTests: XCTestCase {
    /// A sign-in prints its page address and then waits; the address must reach Lemma while the CLI is still running.
    func testOutputArrivesWhileTheCLIIsStillRunning() async throws {
        let process = QuestionProcess()
        let stream = try process.start(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'visit https://example.com/authorize\\n'; sleep 20"],
                                       directory: FileManager.default.temporaryDirectory, environment: ["PATH": "/usr/bin:/bin"])
        let started = Date()
        var first: String?
        for await event in stream {
            if case .output(let data) = event { first = String(decoding: data, as: UTF8.self); break }
        }
        process.cancel()
        XCTAssertEqual(first, "visit https://example.com/authorize\n")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    /// Without F_SETNOSIGPIPE, writing a large question to a CLI that has already exited would kill the test runner.
    func testACLIThatExitsWithoutReadingItsInputCannotKillLemma() async throws {
        let process = QuestionProcess()
        let stream = try process.start(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo 'error: unknown option' >&2; exit 3"],
                                       directory: FileManager.default.temporaryDirectory, environment: ["PATH": "/usr/bin:/bin"],
                                       input: Data(repeating: 65, count: 4 * 1024 * 1024))
        var exit: Int32?, diagnostics = ""
        for await event in stream {
            switch event {
            case .exited(let code): exit = code
            case .diagnostic(let data): diagnostics += String(decoding: data, as: UTF8.self)
            default: break
            }
        }
        XCTAssertEqual(exit, 3); XCTAssertTrue(diagnostics.contains("unknown option"))
    }
}
