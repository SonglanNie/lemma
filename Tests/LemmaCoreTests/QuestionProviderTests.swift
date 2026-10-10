import XCTest
@testable import LemmaCore

final class QuestionProviderTests: XCTestCase {
    func testCLIInvocationsAttachImagesWithoutShellInterpolation() throws {
        let prompt = "Why $X^\\top X$? `do not run` $(touch ignored)\nSecond line."
        let images = [URL(fileURLWithPath: "/tmp/source with spaces.png")]
        let codex = QuestionCLI.arguments(provider: .codex, images: images)
        XCTAssertTrue(codex.contains("read-only")); XCTAssertTrue(codex.contains("--ignore-user-config"))
        XCTAssertTrue(codex.contains(images[0].path)); XCTAssertEqual(codex.last, "-")
        XCTAssertFalse(codex.contains(prompt))
        XCTAssertFalse(codex.joined(separator: " ").contains("forced_login_method"), "Codex keeps whichever sign-in the reader set up.")
        XCTAssertTrue(String(decoding: try QuestionCLI.input(provider: .codex, prompt: prompt, images: []), as: UTF8.self).hasSuffix(prompt))
        let claude = QuestionCLI.arguments(provider: .claudeCode, images: images)
        XCTAssertFalse(claude.contains("--bare"), "Bare mode skips the CLI's own sign-in.")
        XCTAssertFalse(claude.contains("--setting-sources"), "Settings may hold the reader's API key helper or cloud provider.")
        XCTAssertTrue(claude.contains("--safe-mode")); XCTAssertTrue(claude.contains("--tools"))
        XCTAssertEqual(claude[try XCTUnwrap(claude.firstIndex(of: "--tools")) + 1], "")
        let data = Data([1, 2, 3, 4])
        let message = try XCTUnwrap(JSONSerialization.jsonObject(with: QuestionCLI.input(provider: .claudeCode, prompt: prompt, images: [data])) as? [String: Any])
        let content = try XCTUnwrap((message["message"] as? [String: Any])?["content"] as? [[String: Any]])
        XCTAssertTrue((content[0]["text"] as? String)?.hasSuffix(prompt) == true)
        XCTAssertEqual((content[1]["source"] as? [String: String])?["data"], data.base64EncodedString())
    }

    /// Anthropic's terms for products that run Claude Code: no built-in sign-in method may be removed or restricted.
    func testTheCLIKeepsTheReadersCredentialsAndProviderSettings() {
        let executable = URL(fileURLWithPath: "/opt/tools/bin/claude")
        let inherited = ["OPENAI_API_KEY": "kept", "ANTHROPIC_API_KEY": "kept", "CLAUDE_CODE_USE_BEDROCK": "1", "AWS_PROFILE": "work",
                         "CLAUDE_CODE_OAUTH_TOKEN": "kept", "HOME": "/unchanged", "PATH": "/usr/bin:/bin", "CLAUDECODE": "1"]
        let env = QuestionCLI.environment(for: executable, base: inherited, searchPath: ["/opt/homebrew/bin"])
        for key in ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "CLAUDE_CODE_USE_BEDROCK", "AWS_PROFILE", "CLAUDE_CODE_OAUTH_TOKEN", "HOME"] {
            XCTAssertEqual(env[key], inherited[key], key)
        }
        XCTAssertNil(env["CLAUDECODE"], "Only the marker of a parent Claude Code session is dropped.")
        XCTAssertNil(env["BROWSER"])
        XCTAssertEqual(env["PATH"], "/opt/tools/bin:/opt/homebrew/bin:/usr/bin:/bin")
    }

    func testSignInStatusAcceptsEveryAccountTypeAndExplainsFailures() {
        func claude(_ json: String, code: Int32 = 0) -> CLISignInState { QuestionCLI.signInState(.claudeCode, exitCode: code, output: json, errors: "") }
        XCTAssertEqual(claude(#"{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"max"}"#), .signedIn("Claude account (Max)"))
        XCTAssertEqual(claude(#"{"loggedIn":true,"authMethod":"api_key"}"#), .signedIn("API key"))
        XCTAssertEqual(claude(#"{"loggedIn":true,"authMethod":"third_party","apiProvider":"bedrock"}"#), .signedIn("cloud provider (bedrock)"))
        XCTAssertEqual(claude(#"{"loggedIn":false,"authMethod":"none"}"#, code: 1), .signedOut)
        XCTAssertEqual(QuestionCLI.signInState(.codex, exitCode: 0, output: "Logged in using ChatGPT\n", errors: ""), .signedIn("ChatGPT account"))
        XCTAssertEqual(QuestionCLI.signInState(.codex, exitCode: 0, output: "Logged in using an API key - sk-proj-***ABCD\n", errors: ""), .signedIn("API key"))
        XCTAssertEqual(QuestionCLI.signInState(.codex, exitCode: 1, output: "Not logged in\n", errors: ""), .signedOut)
        guard case .unknown(let missingNode) = QuestionCLI.signInState(.codex, exitCode: 127, output: "", errors: "env: node: No such file or directory\n") else {
            return XCTFail("A CLI that cannot start is not reported as signed out.")
        }
        XCTAssertTrue(missingNode.contains("exited with code 127")); XCTAssertTrue(missingNode.contains("env: node: No such file or directory"))
        XCTAssertTrue(missingNode.contains("Node.js"))
        guard case .unknown(let old) = QuestionCLI.signInState(.claudeCode, exitCode: 1, output: "", errors: "error: unknown command 'auth'") else { return XCTFail() }
        XCTAssertTrue(old.contains("unknown command 'auth'"))
    }

    func testOlderCLIsAreAskedAgainWithoutTheOptionTheyRefuse() {
        XCTAssertEqual(QuestionCLI.rejectedOption(in: "error: unknown option '--safe-mode'\n(Did you mean --safe?)"), "--safe-mode")
        XCTAssertEqual(QuestionCLI.rejectedOption(in: "error: unexpected argument '--ignore-user-config' found\n\nUsage: codex exec"), "--ignore-user-config")
        XCTAssertNil(QuestionCLI.rejectedOption(in: "Error: Invalid API key"))
        let claude = QuestionCLI.arguments(provider: .claudeCode, images: [])
        let withoutSafeMode = try? XCTUnwrap(QuestionCLI.dropping("--safe-mode", from: claude))
        XCTAssertEqual(withoutSafeMode?.contains("--safe-mode"), false)
        let withoutMCP = QuestionCLI.dropping("--strict-mcp-config", from: claude)
        XCTAssertEqual(withoutMCP?.contains("--mcp-config"), false); XCTAssertEqual(withoutMCP?.contains("{\"mcpServers\":{}}"), false)
        XCTAssertNil(QuestionCLI.dropping("--tools", from: claude), "Options that keep tools off are never dropped.")
        XCTAssertNil(QuestionCLI.dropping("--sandbox", from: QuestionCLI.arguments(provider: .codex, images: [])))
    }

    func testParsesCompletedAnswersAndKeepsReasoningAndErrorsOut() {
        var codex = QuestionEventParser()
        codex.consume(Data(#"{"type":"item.completed","item":{"type":"reasoning","text":"Private reasoning"}}"#.utf8), provider: .codex)
        XCTAssertEqual(codex.answer, "")
        codex.consume(Data(#"{"type":"item.completed","item":{"type":"agent_message","text":"Use $X^\\top X$."}}"#.utf8), provider: .codex)
        XCTAssertFalse(codex.completed)
        codex.consume(Data(#"{"type":"turn.completed","usage":{}}"#.utf8), provider: .codex)
        XCTAssertTrue(codex.completed); XCTAssertEqual(codex.answer, "Use $X^\\top X$.")
        var claude = QuestionEventParser()
        claude.consume(Data(#"{"type":"stream_event","event":{"delta":{"type":"thinking_delta","thinking":"private"}}}"#.utf8), provider: .claudeCode)
        XCTAssertEqual(claude.answer, "")
        claude.consume(Data(#"{"type":"stream_event","event":{"delta":{"type":"text_delta","text":"A partial reply."}}}"#.utf8), provider: .claudeCode)
        XCTAssertFalse(claude.completed)
        claude.consume(Data(#"{"type":"result","is_error":true,"result":"Usage limit reached"}"#.utf8), provider: .claudeCode)
        XCTAssertFalse(claude.completed); XCTAssertEqual(claude.error, "Usage limit reached")
    }

    func testLegacyQuestionAndExplanationDecodeWithoutProviderMetadata() throws {
        let explanation = try JSONDecoder().decode(SavedExplanation.self, from: Data(#"{"body":"Kept","savedAt":0}"#.utf8))
        XCTAssertEqual(explanation.body, "Kept"); XCTAssertNil(explanation.provider)
        let packet = BrowserPacket(noteID: UUID(), mode: .draft, prompt: "Kept", images: [])
        let restored = try JSONDecoder().decode(BrowserPacket.self, from: JSONEncoder().encode(packet))
        XCTAssertNil(restored.provider); XCTAssertNil(restored.workspaceID)
    }

    /// Lemma 2.x reads `provider` with three cases only. An API answer must not make a book unreadable after a downgrade.
    func testAPIProvenanceStaysReadableByOlderVersions() throws {
        struct Legacy: Decodable {
            enum Provider: String, Decodable { case chatGPTWeb, codex, claudeCode }
            var body: String; var provider: Provider?; var model: String?; var savedAt: Date
        }
        let saved = SavedExplanation(body: "Full rank.", savedAt: Date(timeIntervalSinceReferenceDate: 7), provider: .anthropic, model: "claude-opus-5-5")
        let data = try WorkspaceRepository.encoder.encode(saved)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["service"] as? String, "anthropic"); XCTAssertNil(json["provider"])
        let legacy = try WorkspaceRepository.decoder.decode(Legacy.self, from: data)
        XCTAssertEqual(legacy.body, "Full rank."); XCTAssertNil(legacy.provider); XCTAssertEqual(legacy.model, "claude-opus-5-5")
        XCTAssertEqual(try WorkspaceRepository.decoder.decode(SavedExplanation.self, from: data), saved)
        // CLI and Web provenance keep the original key.
        let codex = try XCTUnwrap(JSONSerialization.jsonObject(with: WorkspaceRepository.encoder.encode(SavedExplanation(body: "b", provider: .codex))) as? [String: Any])
        XCTAssertEqual(codex["provider"] as? String, "codex"); XCTAssertNil(codex["service"])
        // A provider from a later version reads as unknown instead of failing the whole book.
        let future = try JSONDecoder().decode(SavedExplanation.self, from: Data(#"{"body":"b","savedAt":0,"service":"someday"}"#.utf8))
        XCTAssertNil(future.provider)
    }
}
