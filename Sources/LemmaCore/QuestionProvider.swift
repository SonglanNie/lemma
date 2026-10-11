import Foundation

public enum QuestionProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatGPTWeb, codex, claudeCode, openAI, anthropic, gemini

    /// How Lemma reaches the provider: its Web page inside Lemma, the reader's installed CLI, or an API with the reader's key.
    public enum Kind: Sendable { case web, cli, api }

    public var id: String { rawValue }
    public var kind: Kind {
        switch self {
        case .chatGPTWeb: .web
        case .codex, .claudeCode: .cli
        case .openAI, .anthropic, .gemini: .api
        }
    }
    public var label: String {
        switch self {
        case .chatGPTWeb: "ChatGPT Web"; case .codex: "Codex"; case .claudeCode: "Claude Code"
        case .openAI: "OpenAI API"; case .anthropic: "Anthropic API"; case .gemini: "Gemini API"
        }
    }
    /// The company whose servers receive the question, named in plain text.
    public var company: String {
        switch self {
        case .chatGPTWeb, .codex, .openAI: "OpenAI"
        case .claudeCode, .anthropic: "Anthropic"
        case .gemini: "Google"
        }
    }
    public var executableName: String? {
        switch self { case .codex: "codex"; case .claudeCode: "claude"; default: nil }
    }
}

/// Official CLI invocations. Questions and images are data, never shell command text.
///
/// The reader's CLI runs unmodified with whatever sign-in it is set up with: a subscription account, an API key,
/// an API key helper or a cloud provider. Lemma neither removes the CLI's own credentials from its environment
/// nor adds any, and it never forces a login method.
public enum QuestionCLI {
    /// The same instruction precedes the draft for every provider, CLI or API. The draft itself says what to base the
    /// answer on (the attached pages, and standard mathematics); this only sets the form.
    public static let studyInstruction = "You help a reader study a book: answer the study question that follows, about the attached pages. Return the explanation as Markdown, with mathematics in LaTeX between $…$ or $$…$$."
    static let cliInstruction = studyInstruction + " Do not run commands, browse files, use tools or delegate."

    /// The chosen executable (a path, `~/…`, a folder or a command name), else the first one found on the search path.
    public static func executable(_ provider: QuestionProvider, preferred: String? = nil, searchPath: [String] = CLIEnvironment.searchPath()) -> URL? {
        guard let name = provider.executableName else { return nil }
        if let preferred, !preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CLIEnvironment.resolve(preferred, name: name, searchPath: searchPath)
        }
        if let found = CLIEnvironment.find(name, searchPath: searchPath) { return found }
        if provider == .codex {
            let bundled = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
            if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        }
        return nil
    }

    /// The inherited environment, PATH completed for `executable`. Credentials and provider settings pass through
    /// untouched; only the markers of a parent Claude Code session are dropped, since they describe Lemma's own
    /// launch (a developer's terminal), not how the reader set up their CLI.
    public static func environment(for executable: URL?, base: [String: String] = ProcessInfo.processInfo.environment,
                                   searchPath: [String] = CLIEnvironment.searchPath()) -> [String: String] {
        var result = CLIEnvironment.environment(for: executable, base: base, searchPath: searchPath)
        for key in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"] { result.removeValue(forKey: key) }
        result["NO_COLOR"] = "1"
        return result
    }

    public static func arguments(provider: QuestionProvider, images: [URL], model: String = "") -> [String] {
        var args: [String]
        switch provider {
        case .codex:
            args = ["exec", "--ignore-user-config", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only",
                    "--json", "--color", "never", "-c", "approval_policy=\"never\"", "-c", "features.shell_tool=false"]
            for image in images { args += ["--image", image.path] }
        case .claudeCode:
            // Safe mode skips CLAUDE.md, hooks, plugins, skills and MCP servers but keeps authentication and settings,
            // so an API key helper or a cloud provider configured in settings keeps working.
            args = ["--safe-mode", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
                    "--tools", "", "--disable-slash-commands", "--permission-mode", "dontAsk", "--no-session-persistence",
                    "--print", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
        default: return []
        }
        if !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { args += ["--model", model.trimmingCharacters(in: .whitespacesAndNewlines)] }
        if provider == .codex { args.append("-") }
        return args
    }

    public static func input(provider: QuestionProvider, prompt: String, images: [Data]) throws -> Data {
        let instruction = cliInstruction + "\n\n" + prompt
        if provider == .codex { return Data(instruction.utf8) }
        var content: [[String: Any]] = [["type": "text", "text": instruction]]
        content += images.map { ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": $0.base64EncodedString()]] }
        var data = try JSONSerialization.data(withJSONObject: ["type": "user", "message": ["role": "user", "content": content]])
        data.append(10)
        return data
    }

    // MARK: Older CLI versions

    /// Hardening options an older CLI may not know yet. Each can be left out without changing what the question
    /// sends or allowing tools; options that keep tools off (`--tools ""`, `--sandbox read-only`) are never dropped.
    static let optionalFlags: [String: Int] = [
        "--safe-mode": 0, "--strict-mcp-config": 0, "--mcp-config": 1, "--disable-slash-commands": 0, "--permission-mode": 1,
        "--no-session-persistence": 0, "--include-partial-messages": 0,
        "--ignore-user-config": 0, "--ephemeral": 0, "--color": 1, "--skip-git-repo-check": 0
    ]

    /// The option an older CLI refused, from Commander (“unknown option '--x'”) or clap (“unexpected argument '--x' found”).
    public static func rejectedOption(in diagnostics: String) -> String? {
        for marker in ["unknown option", "Unknown option", "unexpected argument", "unrecognized option", "Found argument", "found argument"] {
            guard let range = diagnostics.range(of: marker) else { continue }
            let tail = diagnostics[range.upperBound...].prefix(120)
            if let flag = tail.range(of: "--[A-Za-z0-9][A-Za-z0-9-]*", options: .regularExpression) { return String(tail[flag]) }
        }
        return nil
    }

    /// `arguments` without `flag` (and its value), when the flag is one Lemma can do without.
    public static func dropping(_ flag: String, from arguments: [String]) -> [String]? {
        guard let values = optionalFlags[flag], let index = arguments.firstIndex(of: flag) else { return nil }
        var result = arguments
        result.removeSubrange(index...min(index + values, result.count - 1))
        if flag == "--strict-mcp-config", let config = result.firstIndex(of: "--mcp-config") { result.removeSubrange(config...min(config + 1, result.count - 1)) }
        if flag == "--mcp-config", let strict = result.firstIndex(of: "--strict-mcp-config") { result.remove(at: strict) }
        return result
    }

    // MARK: Sign-in status

    /// The command that reports the CLI's sign-in, as its current documentation describes it.
    public static func statusArguments(_ provider: QuestionProvider) -> [String] {
        provider == .codex ? ["login", "status"] : ["auth", "status", "--json"]
    }

    /// The sign-in commands Lemma offers. Each opens the provider's own page in the reader's browser.
    public static func signInMethods(_ provider: QuestionProvider) -> [CLISignInMethod] {
        switch provider {
        case .claudeCode: [.init(title: "Sign in with Claude account", arguments: ["auth", "login"], terminal: "claude auth login"),
                           .init(title: "Sign in with Claude Console", arguments: ["auth", "login", "--console"], terminal: "claude auth login --console")]
        case .codex: [.init(title: "Sign in with ChatGPT", arguments: ["login"], terminal: "codex login"),
                      .init(title: "Use a device code", arguments: ["login", "--device-auth"], terminal: "codex login --device-auth")]
        default: []
        }
    }

    /// Reads `auth status` / `login status`. Every account type counts: Lemma does not prefer one way of signing in.
    public static func signInState(_ provider: QuestionProvider, exitCode: Int32, output: String, errors: String) -> CLISignInState {
        let command = (provider.executableName ?? "") + " " + statusArguments(provider).joined(separator: " ")
        if provider == .claudeCode, let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"),
           let value = try? JSONSerialization.jsonObject(with: Data(output[start...end].utf8)) as? [String: Any], let loggedIn = value["loggedIn"] as? Bool {
            guard loggedIn else { return .signedOut }
            let method = (value["authMethod"] as? String) ?? ""
            let described: String = switch method {
            case "claude.ai": "Claude account" + ((value["subscriptionType"] as? String).map { " (\($0.capitalized))" } ?? "")
            case "api_key": "API key"
            case "api_key_helper": "API key helper"
            case "oauth_token": "OAuth token"
            case "third_party": "cloud provider" + ((value["apiProvider"] as? String).map { " (\($0))" } ?? "")
            case "", "none": "configured credentials"
            default: method
            }
            return .signedIn(described)
        }
        let text = (output + "\n" + errors).trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .codex, exitCode == 0, text.localizedCaseInsensitiveContains("logged in") {
            if text.localizedCaseInsensitiveContains("ChatGPT") { return .signedIn("ChatGPT account") }
            if text.localizedCaseInsensitiveContains("API key") { return .signedIn("API key") }
            if text.localizedCaseInsensitiveContains("access token") { return .signedIn("access token") }
            return .signedIn("configured credentials")
        }
        if exitCode == 1, text.localizedCaseInsensitiveContains("not logged in") || text.localizedCaseInsensitiveContains("not signed in") { return .signedOut }
        return .unknown(failureDescription(command: command, exitCode: exitCode, output: output, errors: errors))
    }

    /// “`claude auth status` exited with code 127: env: node: No such file or directory”, with a hint for a missing interpreter.
    public static func failureDescription(command: String, exitCode: Int32, output: String, errors: String) -> String {
        var detail = String((errors.isEmpty ? output : errors).trimmingCharacters(in: .whitespacesAndNewlines).suffix(600))
        if let last = detail.last, !".!?)".contains(last) { detail += "." }
        var text = exitCode < 0 ? "\(command) did not finish in time." : "\(command) exited with code \(exitCode)" + (detail.isEmpty ? "." : ":")
        if !detail.isEmpty { text += " " + detail }
        if exitCode == 126 || exitCode == 127 || detail.contains("No such file or directory") {
            text += " The CLI, or the interpreter it needs such as Node.js, was not found. Choose the executable below; Lemma adds its folder to PATH."
        }
        return text
    }
}

public struct CLISignInMethod: Hashable, Sendable {
    public let title: String
    public let arguments: [String]
    /// The same command for Terminal, when the reader prefers to sign in there.
    public let terminal: String
}

public enum CLISignInState: Equatable, Sendable {
    case signedIn(String), signedOut, unknown(String)
}

/// Parses only public answer text. Reasoning, tool output and account metadata stay out of notes.
public struct QuestionEventParser: Sendable {
    public private(set) var answer = ""
    public private(set) var model: String?
    public private(set) var completed = false
    public private(set) var error: String?
    public init() {}
    public mutating func consume(_ data: Data, provider: QuestionProvider) {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = value["type"] as? String else { return }
        if provider == .codex {
            if ["item.updated", "item.completed"].contains(type), let item = value["item"] as? [String: Any], item["type"] as? String == "agent_message", let text = item["text"] as? String { answer = text }
            if type == "turn.completed" { completed = true }
            if type == "error" { error = value["message"] as? String ?? "Codex could not answer the question." }
            if type == "turn.failed" { error = (value["error"] as? [String: Any])?["message"] as? String ?? "Codex could not answer the question." }
        } else if provider == .claudeCode {
            if type == "system", value["subtype"] as? String == "init" { model = value["model"] as? String }
            if type == "stream_event", let event = value["event"] as? [String: Any],
               let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta", let text = delta["text"] as? String { answer += text }
            if type == "assistant", let message = value["message"] as? [String: Any] {
                model = message["model"] as? String ?? model
                if let content = message["content"] as? [[String: Any]] {
                    let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    if !text.isEmpty { answer = text }
                }
            }
            if type == "result" {
                if value["is_error"] as? Bool == true {
                    error = value["result"] as? String ?? (value["errors"] as? [String])?.joined(separator: "\n") ?? "Claude Code could not answer the question."
                } else {
                    if let text = value["result"] as? String { answer = text }
                    completed = true
                }
            }
        }
    }
}
