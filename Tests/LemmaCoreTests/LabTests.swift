import XCTest
@testable import LemmaCore

/// The Lab: notebook model, templates, export, the Python tokenizer, the kernel protocol and a real kernel run.
final class LabTests: XCTestCase {
    func testTokenizerColoursPythonLikeAnEditor() {
        let code = """
        @njit
        def ridge(X, y, lam=1e-3):
            # closed form: (X^T X + λI)^{-1} X^T y
            s = f"λ = {lam}"  # not a #comment inside
            return np.linalg.solve(X.T @ X + lam * np.eye(3), X.T @ y), None
        x = r'\\d+' + '''triple
        quoted'''
        """
        let tokens = PythonSyntax.tokens(in: code)
        let text = code as NSString
        func kind(of word: String) -> PythonSyntax.Kind? {
            tokens.first { text.substring(with: $0.range) == word }?.kind
        }
        XCTAssertEqual(kind(of: "@njit"), .decorator)
        XCTAssertEqual(kind(of: "def"), .keyword)
        XCTAssertEqual(kind(of: "ridge"), .definition, "The name after def is a definition.")
        XCTAssertEqual(kind(of: "1e-3"), .number, "Exponents with a sign stay one number.")
        XCTAssertEqual(kind(of: "# closed form: (X^T X + λI)^{-1} X^T y"), .comment)
        XCTAssertEqual(kind(of: "f\"λ = {lam}\""), .string, "String prefixes belong to the string.")
        XCTAssertEqual(kind(of: "# not a #comment inside"), .comment)
        XCTAssertEqual(kind(of: "return"), .keyword)
        XCTAssertEqual(kind(of: "None"), .constant)
        XCTAssertEqual(kind(of: "np"), .builtin)
        XCTAssertNil(tokens.first { text.substring(with: $0.range) == "linalg" }, "Attributes after a dot are plain names.")
        XCTAssertEqual(kind(of: "r'\\d+'"), .string)
        XCTAssertEqual(kind(of: "'''triple\nquoted'''"), .string, "Triple-quoted strings span lines.")
        XCTAssertEqual(PythonSyntax.tokens(in: "s = 'unterminated\nx = 1").last?.kind, .number, "An unterminated string ends at the line.")
        XCTAssertEqual(PythonSyntax.tokens(in: "np").map(\.kind), [.builtin], "A name at the very start is read without looking before it.")
        for text in ["", "n", "@", "'", "1e", "def", "#"] { _ = PythonSyntax.tokens(in: text) }
    }

    func testIndentationAndCommentToggling() {
        XCTAssertEqual(PythonSyntax.indentation(after: "    for i in range(3):"), "        ")
        XCTAssertEqual(PythonSyntax.indentation(after: "    x = 1  # note:"), "    ", "A colon in a comment does not indent.")
        XCTAssertEqual(PythonSyntax.toggleComment(["x = 1", "    y = 2"]), ["# x = 1", "#     y = 2"])
        XCTAssertEqual(PythonSyntax.toggleComment(["# x = 1", "#     y = 2"]), ["x = 1", "    y = 2"])
        XCTAssertEqual(PythonSyntax.toggleComment(["    a", "", "    b"]), ["    # a", "", "    # b"], "Blank lines stay blank; indentation is kept.")
    }

    func testConsoleInputCompleteness() {
        XCTAssertTrue(PythonSyntax.isComplete("1 + 2"))
        XCTAssertFalse(PythonSyntax.isComplete("f(1,"))
        XCTAssertFalse(PythonSyntax.isComplete("for i in range(3):"))
        XCTAssertFalse(PythonSyntax.isComplete("for i in range(3):\n    print(i)"), "A block waits for an empty line.")
        XCTAssertTrue(PythonSyntax.isComplete("for i in range(3):\n    print(i)\n"))
        XCTAssertFalse(PythonSyntax.isComplete("x = \"\"\"abc"))
        XCTAssertTrue(PythonSyntax.isComplete("x = \"\"\"abc\"\"\""))
        XCTAssertFalse(PythonSyntax.isComplete("x = 1 + \\"))
        XCTAssertTrue(PythonSyntax.isComplete("d = {'a': 1}"))
        XCTAssertTrue(PythonSyntax.isComplete("s = 'a:'  # ends with a colon only in a string"))
        XCTAssertFalse(PythonSyntax.isComplete("   "))
    }

    func testCodeBlocksFromAnAnswer() {
        let answer = """
        Here is the idea.

        ```python
        import numpy as np
        print(np.arange(3))
        ```

        In R:
        ```r
        x <- 1:3
        ```

        ```
        beta = np.linalg.solve(A, b)
        ```

        ```json
        {"a": 1}
        ```
        """
        let blocks = LabTemplate.codeBlocks(in: answer)
        XCTAssertEqual(blocks, ["import numpy as np\nprint(np.arange(3))", "beta = np.linalg.solve(A, b)"])
    }

    func testTemplatesQuoteTheSourceOnlyWhenAsked() {
        let source = LabSource(pageIndex: 82, region: PageRegion(x: 1, y: 2, width: 3, height: 4), label: "Equation (3.44)", quote: "β = (XᵀX + λI)⁻¹Xᵀy,\n(3.44)")
        let quoted = LabTemplate.cells(for: source, sectionTitle: "3.4.1 Ridge Regression", bookTitle: "ESL")
        XCTAssertEqual(quoted.map(\.kind), [.text, .code])
        XCTAssertTrue(quoted[0].source.contains("> β = (XᵀX + λI)⁻¹Xᵀy,"))
        XCTAssertTrue(quoted[0].source.contains("*ESL · 3.4.1 Ridge Regression*"))
        XCTAssertTrue(quoted[1].source.contains("# Equation (3.44) · try it"))
        let plain = LabTemplate.cells(for: source, bookTitle: "ESL", quoteSource: false)
        XCTAssertEqual(plain.map(\.kind), [.code], "The source card shows a passage with a region.")
        XCTAssertEqual(LabTemplate.cells(for: nil, bookTitle: "ESL").map(\.kind), [.code])
    }

    func testStreamOutputCoalescesAndIsCapped() {
        var outputs: [LabOutput] = []
        LabOutput.append("a", stream: .stdout, to: &outputs)
        LabOutput.append("b\n", stream: .stdout, to: &outputs)
        LabOutput.append("warn\n", stream: .stderr, to: &outputs)
        LabOutput.append("c", stream: .stdout, to: &outputs)
        XCTAssertEqual(outputs.map(\.kind), [.stdout, .stderr, .stdout])
        XCTAssertEqual(outputs[0].text, "ab\n")
        var long: [LabOutput] = []
        for _ in 0..<2000 { LabOutput.append(String(repeating: "x", count: 100) + "\n", stream: .stdout, to: &long) }
        XCTAssertEqual(long.count, 1)
        XCTAssertLessThan(long[0].text.count, LabOutput.textLimit + 100)
        XCTAssertTrue(long[0].text.hasSuffix("output truncated by Lemma"))
    }

    func testNotebookExportsAsJupyterAndPython() throws {
        var notebook = LabNotebook(title: "Ridge path", source: LabSource(pageIndex: 82, label: "Equation (3.44)", quote: "ridge"))
        var code = LabCell(kind: .code, source: "x = 1\nx + 41")
        code.executionCount = 3
        code.outputs = [LabOutput(kind: .stdout, text: "hello\n"), LabOutput(kind: .result, text: "42"),
                        LabOutput(kind: .image, imageName: "figure.png"), LabOutput(kind: .error, text: "ValueError: bad", detail: "Traceback\nValueError: bad")]
        notebook.cells = [LabCell(kind: .text, source: "# Title\nSome *text*."), code]
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let data = try LabExport.ipynb(notebook, python: "3.13.7") { $0 == "figure.png" ? png : nil }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["nbformat"] as? Int, 4)
        let cells = try XCTUnwrap(json["cells"] as? [[String: Any]])
        XCTAssertEqual(cells.map { $0["cell_type"] as? String }, ["markdown", "markdown", "code"])
        XCTAssertEqual(cells[1]["source"] as? [String], ["# Title\n", "Some *text*."])
        let outputs = try XCTUnwrap(cells[2]["outputs"] as? [[String: Any]])
        XCTAssertEqual(outputs.map { $0["output_type"] as? String }, ["stream", "execute_result", "display_data", "error"])
        XCTAssertEqual((outputs[2]["data"] as? [String: Any])?["image/png"] as? String, png.base64EncodedString())
        XCTAssertEqual(outputs[3]["ename"] as? String, "ValueError")
        XCTAssertEqual(cells[2]["execution_count"] as? Int, 3)
        let script = LabExport.python(notebook, bookTitle: "ESL")
        XCTAssertTrue(script.contains("# Ridge path\n# From Lemma, ESL · Equation (3.44), PDF page 83"))
        XCTAssertTrue(script.contains("# %%\nx = 1\nx + 41"))
        XCTAssertTrue(script.contains("# # Title\n# Some *text*."))
        XCTAssertEqual(LabExport.fileName(for: LabNotebook(title: "a/b: c?"), extension: "ipynb"), "a-b- c-.ipynb")
    }

    func testWorkspaceKeepsNotebooksAndReadsSchemaSevenFiles() throws {
        var workspace = StudyWorkspace(id: "w", title: "Book", sourcePath: "/b.pdf", sourceBookmark: nil, fingerprint: "w")
        var notebook = LabNotebook(title: "Lab", cells: [LabCell(source: "print(1)")])
        notebook.createdAt = Date(timeIntervalSince1970: 1_790_000_000); notebook.updatedAt = notebook.createdAt
        workspace.labs = [notebook]
        workspace.readingLog.record(30, onPage: 4, at: Date(timeIntervalSince1970: 1_790_000_000))
        let data = try WorkspaceRepository.encoder.encode(workspace)
        let decoded = try WorkspaceRepository.decoder.decode(StudyWorkspace.self, from: data)
        XCTAssertEqual(decoded.labs, workspace.labs)
        XCTAssertEqual(decoded.readingLog, workspace.readingLog)
        XCTAssertEqual(decoded.schemaVersion, 10)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "labs"); legacy.removeValue(forKey: "readingLog"); legacy["schemaVersion"] = 7
        let migrated = try WorkspaceRepository.decoder.decode(StudyWorkspace.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(migrated.labs.isEmpty)
        XCTAssertEqual(migrated.readingLog, ReadingLog())
    }

    func testKernelProtocolLinesDecode() {
        let id = UUID()
        func event(_ object: [String: Any]) -> LabKernelEvent? {
            LabKernel.event(from: try! JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertEqual(event(["type": "stream", "id": id.uuidString, "name": "stderr", "text": "w"]), .stream(requestID: id, name: "stderr", text: "w"))
        XCTAssertEqual(event(["type": "result", "id": id.uuidString, "text": "42"]), .result(requestID: id, text: "42"))
        XCTAssertEqual(event(["type": "done", "id": id.uuidString, "status": "error", "count": 2, "duration": 0.5]),
                       .done(requestID: id, status: "error", count: 2, duration: 0.5))
        XCTAssertEqual(event(["type": "image", "data": Data([1, 2]).base64EncodedString()]), .image(requestID: nil, png: Data([1, 2])))
        XCTAssertNil(event(["type": "unknown"]))
        XCTAssertNil(LabKernel.event(from: Data("not json".utf8)))
    }

    /// Runs cells in a real interpreter when one is installed: output, the last value, errors, persistence and an interrupt.
    func testKernelRunsCellsInPython() throws {
        guard let interpreter = LabInterpreterFinder.discover().first else { throw XCTSkip("No Python 3 on this Mac") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = try LabKernel.installScript(in: directory)
        XCTAssertEqual(try LabKernel.installScript(in: directory), script, "Installing again keeps the same file.")
        let kernel = LabKernel(configuration: .init(interpreter: URL(fileURLWithPath: interpreter.path), workingDirectory: directory.appendingPathComponent("work"),
                                                    scriptURL: script, gentle: true))
        let collector = EventCollector()
        try kernel.start { collector.append($0) }
        defer { kernel.terminate() }
        XCTAssertTrue(collector.wait(timeout: 20) { $0.contains { if case .ready = $0 { true } else { false } } }, "The kernel reports ready.")

        let first = UUID(), second = UUID(), third = UUID(), fourth = UUID()
        kernel.execute(id: first, code: "x = 40\nprint('hello', x)\nx + 2")
        kernel.execute(id: second, code: "def f():\n    raise ValueError('bad input')\nf()")
        kernel.execute(id: third, code: "import os\nprint(os.getcwd().endswith('work'), x)")
        XCTAssertTrue(collector.wait(timeout: 20) { $0.filter { if case .done = $0 { true } else { false } }.count >= 3 })
        let events = collector.events
        XCTAssertTrue(events.contains(.stream(requestID: first, name: "stdout", text: "hello 40\n")) || events.contains { if case let .stream(id, _, text) = $0 { id == first && text.contains("hello") } else { false } })
        XCTAssertTrue(events.contains(.result(requestID: first, text: "42")), "The last expression's value is returned.")
        XCTAssertTrue(events.contains { if case let .error(id, name, value, traceback) = $0 { id == second && name == "ValueError" && value == "bad input" && traceback.contains("line 2, in f") && !traceback.contains("lemma_kernel") } else { false } },
                      "Errors carry the cell's traceback without the kernel's own frames.")
        XCTAssertTrue(events.contains { if case let .stream(id, _, text) = $0 { id == third && text.contains("True 40") } else { false } },
                      "Variables persist between cells; the kernel runs in the notebook's folder.")

        let completion = UUID()
        kernel.execute(id: UUID(), code: "import math\nbeta_hat = 1")
        kernel.complete(id: completion, text: "math.sq")
        XCTAssertTrue(collector.wait(timeout: 10) { $0.contains { if case let .completions(id, _, matches) = $0 { id == completion && matches.contains("math.sqrt(") } else { false } } },
                      "Completion reads the kernel's namespace, between cells.")
        let local = UUID()
        kernel.complete(id: local, text: "beta_")
        XCTAssertTrue(collector.wait(timeout: 10) { $0.contains { if case let .completions(id, _, matches) = $0 { id == local && matches == ["beta_hat"] } else { false } } })
        XCTAssertEqual(PythonSyntax.staticCompletions("whi"), ["while"])
        XCTAssertEqual(PythonSyntax.staticCompletions("imp"), ["import", "import matplotlib.pyplot as plt", "import numpy as np", "import pandas as pd"])

        kernel.execute(id: fourth, code: "import time\nfor _ in range(100):\n    time.sleep(0.1)")
        Thread.sleep(forTimeInterval: 0.6)
        kernel.interrupt()
        XCTAssertTrue(collector.wait(timeout: 10) { $0.contains { if case let .done(id, status, _, _) = $0 { id == fourth && status == "interrupted" } else { false } } },
                      "An interrupt stops the running cell and the kernel stays alive.")
        kernel.shutdown()
        XCTAssertTrue(collector.wait(timeout: 10) { $0.contains { if case .exited = $0 { true } else { false } } })
    }

    func testInterpreterRankingPrefersScientificPythons() {
        let plain = LabInterpreter(path: "/usr/bin/python3", version: "3.9.6", packages: [:])
        let numeric = LabInterpreter(path: "/a", version: "3.12", packages: ["numpy": "2"])
        let scientific = LabInterpreter(path: "/b", version: "3.13", packages: ["numpy": "2", "matplotlib": "3.10", "scipy": "1"])
        XCTAssertGreaterThan(LabInterpreterFinder.rank(scientific), LabInterpreterFinder.rank(numeric))
        XCTAssertGreaterThan(LabInterpreterFinder.rank(numeric), LabInterpreterFinder.rank(plain))
        XCTAssertTrue(scientific.isScientific)
        XCTAssertEqual(scientific.summary, "Python 3.13 · numpy, scipy, matplotlib")
    }
}

/// 3.0: kernels never outlive Lemma, output is capped and batched, the stub python3 is never run, and Lemma can make
/// its own Python environment. Python runs are kept tiny.
final class LabLifetimeTests: XCTestCase {
    private static let python: String? = LabInterpreterFinder.discover().first?.path

    private func python() throws -> String {
        guard let python = Self.python else { throw XCTSkip("No Python 3 on this Mac") }
        return python
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lab-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func startKernel(in directory: URL, collector: EventCollector) throws -> LabKernel {
        let script = try LabKernel.installScript(in: directory)
        let kernel = LabKernel(configuration: .init(interpreter: URL(fileURLWithPath: try python()), workingDirectory: directory.appendingPathComponent("work"),
                                                    scriptURL: script, gentle: true))
        try kernel.start { collector.append($0) }
        XCTAssertTrue(collector.wait(timeout: 20) { $0.contains { if case .ready = $0 { true } else { false } } }, "The kernel reports ready.")
        return kernel
    }

    private func isDone(_ id: UUID) -> ([LabKernelEvent]) -> Bool {
        { events in events.contains { if case let .done(request, _, _, _) = $0 { request == id } else { false } } }
    }

    func testShutdownAllStopsEveryKernelWithinASecond() throws {
        let directory = temporaryDirectory()
        let busy = try startKernel(in: directory.appendingPathComponent("busy"), collector: EventCollector())
        let stubborn = try startKernel(in: directory.appendingPathComponent("stubborn"), collector: EventCollector())
        defer { busy.terminate(); stubborn.terminate() }
        busy.execute(id: UUID(), code: "while True:\n    pass")
        // Ignores SIGINT and SIGTERM: only SIGKILL stops it.
        stubborn.execute(id: UUID(), code: "import signal, time\nsignal.signal(signal.SIGINT, signal.SIG_IGN)\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nwhile True:\n    time.sleep(0.05)")
        Thread.sleep(forTimeInterval: 0.5)
        let pids = [busy.processIdentifier, stubborn.processIdentifier]
        XCTAssertTrue(pids.allSatisfy(LabKernel.isProcessAlive))
        XCTAssertTrue(Set(LabKernel.runningProcessIdentifiers).isSuperset(of: pids))
        let started = Date()
        LabKernel.shutdownAll(timeout: 1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.3, "Quitting waits a second at most.")
        XCTAssertFalse(pids.contains(where: LabKernel.isProcessAlive), "Both kernels have stopped when shutdownAll returns.")
    }

    func testAKernelNobodyHoldsIsStopped() throws {
        let directory = temporaryDirectory()
        var kernel: LabKernel? = try startKernel(in: directory, collector: EventCollector())
        kernel?.execute(id: UUID(), code: "import time\nwhile True:\n    time.sleep(0.05)")
        Thread.sleep(forTimeInterval: 0.3)
        let pid = try XCTUnwrap(kernel?.processIdentifier)
        kernel = nil
        let deadline = Date().addingTimeInterval(4)
        while LabKernel.isProcessAlive(pid), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertFalse(LabKernel.isProcessAlive(pid), "Releasing a running kernel stops its process.")
    }

    func testKernelEndsWhenLemmaDoes() throws {
        let python = try python()
        let directory = temporaryDirectory()
        let script = try LabKernel.installScript(in: directory)
        // A stand-in for Lemma: starts the kernel leading its own process group (as Foundation's Process does), gives it
        // a long cell that starts a process of its own, prints both pids and exits without stopping anything.
        let parent = directory.appendingPathComponent("parent.py")
        try #"""
        import json, os, subprocess, sys
        kernel = subprocess.Popen([sys.executable, "-u", sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True, start_new_session=True)
        kernel.stdout.readline()
        cell = "import subprocess, time\nchild = subprocess.Popen(['/bin/sleep', '30'])\nprint(child.pid, flush=True)\ntime.sleep(30)"
        kernel.stdin.write(json.dumps({"type": "execute", "id": "x", "code": cell}) + "\n")
        kernel.stdin.flush()
        child = json.loads(kernel.stdout.readline())["text"].strip()
        print(kernel.pid, child, flush=True)
        os._exit(0)
        """#.write(to: parent, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-I", parent.path, script.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let pids = text.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
        XCTAssertEqual(pids.count, 2, text)
        defer { for pid in pids where LabKernel.isProcessAlive(pid) { kill(pid, SIGKILL) } }
        let deadline = Date().addingTimeInterval(5)
        while pids.contains(where: LabKernel.isProcessAlive), Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertFalse(pids.contains(where: LabKernel.isProcessAlive), "The kernel, busy in a cell, and the process its cell started end with their parent.")
    }

    func testCellOutputIsCappedInTheKernel() throws {
        let collector = EventCollector()
        let kernel = try startKernel(in: temporaryDirectory(), collector: collector)
        defer { kernel.terminate() }
        let id = UUID()
        kernel.execute(id: id, code: "print('a' * 30000)\nprint('b' * 30000)\nprint('end')")
        XCTAssertTrue(collector.wait(timeout: 20, until: isDone(id)))
        let text = collector.events.compactMap { event -> String? in
            if case let .stream(request, _, text) = event, request == id { text } else { nil }
        }.joined()
        XCTAssertLessThan(text.count, 41_000, "A cell sends its first and last 20,000 characters, not all 60,000.")
        XCTAssertTrue(text.hasPrefix(String(repeating: "a", count: 1000)))
        XCTAssertTrue(text.contains("output truncated by Lemma"))
        XCTAssertTrue(text.contains("20,006 characters not shown"), "Head, tail and the count add up to the 60,006 characters printed.")
        XCTAssertTrue(text.hasSuffix("bbb\nend\n"), "The last lines arrive when the cell ends.")
    }

    func testPrintsShowSoonEvenWhenTheCellGoesQuiet() throws {
        let collector = EventCollector()
        let kernel = try startKernel(in: temporaryDirectory(), collector: collector)
        defer { kernel.terminate() }
        let id = UUID()
        kernel.execute(id: id, code: "import time\nprint('start')\ntime.sleep(1.5)")
        XCTAssertTrue(collector.wait(timeout: 1) { $0.contains(.stream(requestID: id, name: "stdout", text: "start\n")) },
                      "Buffered output is sent within a fraction of a second, not when the cell ends.")
        XCTAssertFalse(isDone(id)(collector.events))
        XCTAssertTrue(collector.wait(timeout: 10, until: isDone(id)))
    }

    func testBatchedDeliveryMergesChattyOutput() throws {
        let directory = temporaryDirectory()
        let script = try LabKernel.installScript(in: directory)
        let kernel = LabKernel(configuration: .init(interpreter: URL(fileURLWithPath: try python()), workingDirectory: directory.appendingPathComponent("work"),
                                                    scriptURL: script, gentle: true))
        let batches = BatchCollector()
        try kernel.start(every: 0.1) { batches.append($0) }
        defer { kernel.terminate() }
        XCTAssertTrue(batches.wait(timeout: 20) { $0.contains { if case .ready = $0 { true } else { false } } })
        let id = UUID()
        kernel.execute(id: id, code: "for i in range(3000):\n    print(i, flush=True)")
        XCTAssertTrue(batches.wait(timeout: 20, until: isDone(id)))
        let streams = batches.events.compactMap { event -> String? in if case let .stream(request, _, text) = event, request == id { text } else { nil } }
        XCTAssertEqual(streams.joined(), (0..<3000).map { "\($0)\n" }.joined(), "Nothing is lost or reordered.")
        XCTAssertLessThan(streams.count, 30, "3,000 flushed prints arrive as a few merged chunks, not 3,000 events.")
        XCTAssertLessThan(batches.count, 30)
        let last = try XCTUnwrap(batches.events.last)
        XCTAssertTrue(isDone(id)([last]), "Done comes after the cell's output.")
    }

    func testTheDeveloperToolsStubIsNeverRun() throws {
        XCTAssertFalse(LabInterpreterFinder.isSafeToRun("/usr/bin/python3", developerToolsInstalled: false))
        XCTAssertTrue(LabInterpreterFinder.isSafeToRun("/usr/bin/python3", developerToolsInstalled: true))
        XCTAssertTrue(LabInterpreterFinder.isSafeToRun("/opt/homebrew/bin/python3", developerToolsInstalled: false))
        let link = temporaryDirectory().appendingPathComponent("python3")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/usr/bin/python3"))
        XCTAssertFalse(LabInterpreterFinder.isSafeToRun(link.path, developerToolsInstalled: false), "A link to the stub is the stub.")
        if !LabInterpreterFinder.developerToolsInstalled {
            XCTAssertFalse(LabInterpreterFinder.candidatePaths().contains("/usr/bin/python3"))
            XCTAssertNil(LabInterpreterFinder.probe("/usr/bin/python3"))
        }
    }

    func testEnvironmentIsMadeFromAReleasedPythonNewestFirst() {
        let directory = LabEnvironment.directory(support: URL(fileURLWithPath: "/tmp/support"))
        XCTAssertEqual(directory.path, "/tmp/support/Lab/python")
        let own = LabEnvironment.interpreter(in: directory).path
        let found = [LabInterpreter(path: "/a", version: "3.9.6", packages: [:]), LabInterpreter(path: "/b", version: "3.15.0b1", packages: [:]),
                     LabInterpreter(path: "/c", version: "3.13.7", packages: [:]), LabInterpreter(path: "/d", version: "3.8.10", packages: [:]),
                     LabInterpreter(path: own, version: "3.13.7", packages: ["numpy": "2"]), LabInterpreter(path: "/e", version: "3.12.4", packages: [:])]
        XCTAssertEqual(LabEnvironment.bases(from: found, excluding: directory).map(\.path), ["/c", "/e", "/a", "/b"],
                       "Released versions newest first, then previews; never Python 3.8 or the environment itself.")
        let homebrew = LabInterpreter(path: "/opt/homebrew/opt/python@3.14/bin/python3", version: "3.14.6", packages: [:])
        let python = LabInterpreter(path: "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3", version: "3.13.7", packages: [:])
        let tools = LabInterpreter(path: "/Library/Developer/CommandLineTools/usr/bin/python3", version: "3.9.6", packages: [:])
        XCTAssertEqual(LabEnvironment.bases(from: [tools, homebrew, python], excluding: directory).map(\.path), [python.path, homebrew.path, tools.path],
                       "python.org's stays put across updates; Homebrew's next; the developer tools' last.")
    }

    func testEnvironmentSetupMakesAVenvAndACancelledOneLeavesNothing() throws {
        let python = try python()
        let directory = LabEnvironment.directory(support: temporaryDirectory())
        // No packages and no pip update: nothing is downloaded.
        let setup = LabEnvironmentSetup(base: python, directory: directory, packages: [], upgradePip: false)
        let steps = BatchCollector()
        let outcome = setup.run { _ in steps.append([]) }
        guard case let .finished(interpreter) = outcome else { return XCTFail("\(outcome)\n\(setup.log)") }
        XCTAssertEqual(interpreter.path, LabEnvironment.interpreter(in: directory).path)
        XCTAssertTrue(LabEnvironment.isComplete(at: directory))
        XCTAssertEqual(LabInterpreterFinder.candidatePaths(managed: URL(fileURLWithPath: interpreter.path)).first, interpreter.path,
                       "Lemma's environment is looked at first.")
        XCTAssertGreaterThan(steps.count, 1, "Progress is reported.")
        XCTAssertTrue(interpreter.packages.isEmpty, "A venv reports its own packages, never its base's: \(interpreter.packages)")
        // Discovery never runs a .pth file (one could run anything, or reach into a folder macOS protects).
        let lib = directory.appendingPathComponent("lib")
        let version = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: lib.path).first { $0.hasPrefix("python") })
        let marker = directory.appendingPathComponent("pth-ran")
        try "import os; open(\(String(reflecting: marker.path)), 'w').close()\n"
            .write(to: lib.appendingPathComponent("\(version)/site-packages/lemma_probe_check.pth"), atomically: true, encoding: .utf8)
        XCTAssertNotNil(LabInterpreterFinder.probe(interpreter.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "Probing did not run the environment's .pth files.")

        let again = LabEnvironmentSetup(base: python, directory: directory, packages: [], upgradePip: false)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { again.cancel() }
        XCTAssertEqual(again.run { _ in }, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "A cancelled setup removes its unfinished environment.")
        XCTAssertFalse(LabEnvironment.isComplete(at: directory))
    }

    /// The real thing, opt-in (it downloads about 60 MB from PyPI): LEMMA_LAB_SETUP_E2E=1.
    /// LEMMA_LAB_SETUP_DIR keeps the environment for a look afterwards.
    func testSettingUpPythonForTheLabEndToEnd() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEMMA_LAB_SETUP_E2E"] == "1" else { throw XCTSkip("Set LEMMA_LAB_SETUP_E2E=1 to download and install the packages") }
        let interpreters = LabInterpreterFinder.discover()
        let support = environment["LEMMA_LAB_SETUP_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? temporaryDirectory()
        let directory = LabEnvironment.directory(support: support)
        let base = try XCTUnwrap(LabEnvironment.bases(from: interpreters, excluding: directory).first)
        let progress = BatchCollector()
        let details = DetailLog()
        let started = Date()
        let setup = LabEnvironmentSetup(base: base.path, directory: directory)
        let outcome = setup.run { step in progress.append([]); details.add("\(step.step.rawValue) \(Int(step.fraction * 100))% \(step.detail)") }
        print("Made from \(base.path) (\(base.version)) in \(Int(Date().timeIntervalSince(started))) s, \(progress.count) progress updates:")
        print(details.lines.joined(separator: "\n"))
        guard case let .finished(interpreter) = outcome else { return XCTFail("\(outcome)\n\(setup.log)") }
        for package in LabEnvironment.packages { XCTAssertNotNil(interpreter.packages[package], package) }
        XCTAssertTrue(interpreter.isScientific)
        XCTAssertTrue(LabEnvironment.isComplete(at: directory))
        XCTAssertEqual(LabInterpreterFinder.discover(managed: directory).first?.path, interpreter.path, "The Lab picks Lemma's environment.")
    }

    func testPipOutputBecomesProgress() {
        var reader = PipProgress()
        let lines = ["Collecting numpy", "  Downloading numpy-2.5.3-cp313-cp313-macosx_14_0_arm64.whl.metadata (6.6 kB)",
                     "Collecting python-dateutil>=2.7 (from matplotlib)", "  Using cached python_dateutil-2.9.0.post0-py2.py3-none-any.whl.metadata (8.4 kB)",
                     "Downloading numpy-2.5.3-cp313-cp313-macosx_14_0_arm64.whl (5.4 MB)",
                     "Using cached python_dateutil-2.9.0.post0-py2.py3-none-any.whl (229 kB)",
                     "Installing collected packages: python-dateutil, numpy", "Successfully installed numpy-2.5.3 python-dateutil-2.9.0.post0"]
        let updates = lines.map { reader.read($0) }
        XCTAssertEqual(updates.map { $0?.detail }, ["Looking up numpy", nil, "Looking up python-dateutil", nil, "Downloading numpy 2.5.3 (5.4 MB)",
                                                    "python_dateutil 2.9.0.post0, already downloaded", "Installing the packages", nil])
        let fractions = updates.compactMap { $0?.fraction }
        XCTAssertEqual(fractions, fractions.sorted(), "Progress only moves forward.")
        XCTAssertEqual(fractions[3], 0.75, accuracy: 0.001, "Every wheel there: the downloads are done.")
        XCTAssertEqual(updates.last??.step, nil)
        XCTAssertEqual(updates[6]?.step, .install)
    }

    func testFiguresAndScriptsAreNamedAfterTheirNotebook() throws {
        var notebook = LabNotebook(title: "Ridge: path")
        notebook.cells = [LabCell(kind: .text, source: "Notes"), LabCell(kind: .code, outputs: [LabOutput(kind: .image, imageName: "a.png")]),
                          LabCell(kind: .code, outputs: [LabOutput(kind: .stdout, text: "x"), LabOutput(kind: .image, imageName: "b.png"),
                                                         LabOutput(kind: .image, imageName: "c.png")])]
        XCTAssertEqual(LabExport.figureFileName(for: notebook, imageName: "a.png"), "Ridge- path, cell 2.png")
        XCTAssertEqual(LabExport.figureFileName(for: notebook, imageName: "c.png"), "Ridge- path, cell 3, figure 2.png")
        XCTAssertEqual(LabExport.figureFileName(for: notebook, imageName: "gone.png"), "Ridge- path.png")
        let url = temporaryDirectory().appendingPathComponent("Ridge.ipynb")
        let script = LabExport.scriptURL(beside: url)
        XCTAssertEqual(script.lastPathComponent, "Ridge.py")
        try "# mine\n".write(to: script, atomically: true, encoding: .utf8)
        try LabExport.write(notebook, to: url, bookTitle: "ESL", python: nil, script: false) { _ in nil }
        XCTAssertEqual(try String(contentsOf: script, encoding: .utf8), "# mine\n", "Without the script option an existing .py is left alone.")
        try LabExport.write(notebook, to: url, bookTitle: "ESL", python: nil, script: true) { _ in nil }
        XCTAssertTrue(try String(contentsOf: script, encoding: .utf8).hasPrefix("# Ridge: path"), "Replacing it writes the notebook's code.")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: url)), "The notebook replaced the earlier export.")
    }
}

/// Thread-safe list of progress lines.
final class DetailLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var lines: [String] { lock.withLock { stored } }
    func add(_ line: String) { lock.withLock { stored.append(line) } }
}

/// Thread-safe list of event batches.
final class BatchCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [[LabKernelEvent]] = []
    var events: [LabKernelEvent] { lock.withLock { stored.flatMap { $0 } } }
    var count: Int { lock.withLock { stored.count } }
    func append(_ batch: [LabKernelEvent]) { lock.withLock { stored.append(batch) } }
    func wait(timeout: TimeInterval, until condition: ([LabKernelEvent]) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition(events) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return condition(events)
    }
}

/// Thread-safe event list for kernel callbacks.
final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [LabKernelEvent] = []
    var events: [LabKernelEvent] { lock.withLock { stored } }
    func append(_ event: LabKernelEvent) { lock.withLock { stored.append(event) } }
    func wait(timeout: TimeInterval, until condition: ([LabKernelEvent]) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition(events) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return condition(events)
    }
}
