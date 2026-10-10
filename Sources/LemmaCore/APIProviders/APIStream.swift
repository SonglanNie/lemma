import Foundation

/// Why an API question did not produce an answer, in terms the reader can act on.
public enum APIFailure: Error, Equatable, Sendable {
    case missingKey
    case invalidKey(String)
    case quota(String)
    case rateLimited(retryAfter: Int?, String)
    case modelNotFound(String)
    case permission(String)
    case overloaded(String)
    case server(status: Int, String)
    case badRequest(String)
    /// The provider declined to answer: a safety refusal or a blocked prompt.
    case refused(String?)
    case offline(String)
    case timedOut
    /// The stream ended without the provider's closing event.
    case interrupted
    case stopped(String)
    case empty
    case cancelled

    /// A sentence for the Questions panel and the note's receipt. Provider messages are kept short and never echo a key.
    public func message(_ provider: QuestionProvider, model: String) -> String {
        let name = provider.label
        func detail(_ text: String) -> String {
            let cleaned = APIKeyFormat.redacted(text).trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "" : " (" + String(cleaned.prefix(400)) + ")"
        }
        switch self {
        case .missingKey: return "Add your \(provider.company) API key in Assistants › Connections first."
        case .invalidKey(let text): return "\(name) rejected the API key. Check or replace it in Assistants › Connections." + detail(text)
        case .quota(let text): return "Your \(provider.company) account has no credit or quota left for this key." + detail(text)
        case .rateLimited(let seconds, let text):
            let wait = seconds.map { "Try again in \($0) seconds." } ?? "Try again in a moment."
            return "\(name) rate limit reached. \(wait)" + detail(text)
        case .modelNotFound(let text):
            return "The model “\(model)” is not available to this API key. Choose another model in Assistants › Connections." + detail(text)
        case .permission(let text): return "\(name) refused access." + detail(text)
        case .overloaded(let text): return "\(name) is busy or temporarily unavailable. Try again shortly." + detail(text)
        case .server(let status, let text): return "\(name) had a server error (HTTP \(status)). Try again shortly." + detail(text)
        case .badRequest(let text): return "\(name) rejected the request." + detail(text)
        case .refused(let reason): return "\(name) declined to answer this question" + (reason.map { detail($0) } ?? "") + ". The source note is kept."
        case .offline(let text): return "Lemma could not reach \(provider.apiHost ?? name). Check the internet connection." + detail(text)
        case .timedOut: return "\(name) did not respond in time. Try again."
        case .interrupted: return "The connection to \(name) closed before the answer was complete. Try again."
        case .stopped(let text): return "\(name) stopped before answering." + detail(text)
        case .empty: return "\(name) returned no answer. Try again, or choose another model."
        case .cancelled: return "Question cancelled. Its source note is kept."
        }
    }

    /// Anthropic's fallback opt-in uses a beta header; an account where it is unavailable gets a plain request instead.
    public var rejectsServerFallbacks: Bool {
        if case .badRequest(let text) = self { return text.contains("anthropic-beta") || text.contains("fallbacks") }
        return false
    }

    /// Network failures in the reader's terms.
    public static func wrapping(_ error: Error) -> APIFailure {
        if let failure = error as? APIFailure { return failure }
        if error is CancellationError { return .cancelled }
        guard let url = error as? URLError else { return .stopped(error.localizedDescription) }
        switch url.code {
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .dataNotAllowed, .internationalRoamingOff, .callIsActive, .secureConnectionFailed:
            return .offline(url.localizedDescription)
        default: return .stopped(url.localizedDescription)
        }
    }

    /// An HTTP error response, read with each provider's error format.
    public static func http(_ provider: QuestionProvider, status: Int, body: Data, retryAfter: String? = nil) -> APIFailure {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        let text = (error?["message"] as? String) ?? String(decoding: body.prefix(400), as: UTF8.self)
        let wait = retryAfter.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        switch provider {
        case .anthropic: return anthropic(type: error?["type"] as? String, message: text, status: status, retryAfter: wait)
        case .openAI:
            return openAI(code: (error?["code"] as? String) ?? (error?["type"] as? String), message: text, status: status, retryAfter: wait)
        default:
            let reasons = (error?["details"] as? [[String: Any]] ?? []).compactMap { $0["reason"] as? String }
            return gemini(status: status, state: error?["status"] as? String, reasons: reasons, message: text, retryAfter: wait)
        }
    }

    static func anthropic(type: String?, message: String, status: Int?, retryAfter: Int?) -> APIFailure {
        let status = status ?? 0, type = type ?? ""
        if status == 401 || type == "authentication_error" { return .invalidKey(message) }
        if status == 402 || type == "billing_error" || message.localizedCaseInsensitiveContains("credit balance") { return .quota(message) }
        if status == 403 || type == "permission_error" { return .permission(message) }
        if status == 404 || type == "not_found_error" { return .modelNotFound(message) }
        if status == 429 || type == "rate_limit_error" { return .rateLimited(retryAfter: retryAfter, message) }
        if status == 529 || type == "overloaded_error" { return .overloaded(message) }
        if status >= 500 || type == "api_error" { return .server(status: max(status, 500), message) }
        return status == 0 ? .stopped(message) : .badRequest(message)
    }

    static func openAI(code: String?, message: String, status: Int?, retryAfter: Int?) -> APIFailure {
        let status = status ?? 0, code = code ?? ""
        let quotaCodes: Set<String> = ["insufficient_quota", "credit_balance_exhausted", "billing_hard_limit_reached",
                                       "organization_spend_limit_exceeded", "project_spend_limit_exceeded", "organization_usage_limit_exceeded"]
        if quotaCodes.contains(code) { return .quota(message) }
        if status == 401 || code == "invalid_api_key" { return .invalidKey(message) }
        if status == 403 { return .permission(message) }
        if status == 404 || code == "model_not_found" || (message.contains("model") && message.contains("does not exist")) { return .modelNotFound(message) }
        if status == 429 || code == "rate_limit_exceeded" || code == "slow_down" { return .rateLimited(retryAfter: retryAfter, message) }
        if status == 503 || code == "server_is_overloaded" { return .overloaded(message) }
        if code == "invalid_prompt" || code == "content_filter" { return .refused(message) }
        if status >= 500 || code == "server_error" { return .server(status: max(status, 500), message) }
        return status == 0 ? .stopped(message) : .badRequest(message)
    }

    static func gemini(status: Int?, state: String?, reasons: [String], message: String, retryAfter: Int?) -> APIFailure {
        let status = status ?? 0, state = state ?? ""
        if reasons.contains("API_KEY_INVALID") || reasons.contains("API_KEY_SERVICE_BLOCKED") || message.contains("API key not valid") || status == 401 {
            return .invalidKey(message)
        }
        if status == 404 || state == "NOT_FOUND" { return .modelNotFound(message) }
        if status == 429 || state == "RESOURCE_EXHAUSTED" { return .rateLimited(retryAfter: retryAfter, message) }
        if status == 403 || state == "PERMISSION_DENIED" || state == "FAILED_PRECONDITION" { return .permission(message) }
        if status == 503 || state == "UNAVAILABLE" || state == "DEADLINE_EXCEEDED" { return .overloaded(message) }
        if status >= 500 || state == "INTERNAL" { return .server(status: max(status, 500), message) }
        return status == 0 ? .stopped(message) : .badRequest(message)
    }
}

/// Reads one provider's stream into the public answer text. Reasoning and thinking parts are never kept.
public struct APIAnswerParser: Sendable {
    public enum Ending: Equatable, Sendable { case complete, truncated, refused(String?) }

    public let provider: QuestionProvider
    public private(set) var answer = ""
    /// The model that produced the answer, as the provider reports it.
    public private(set) var model: String?
    public private(set) var ending: Ending?
    public private(set) var failure: APIFailure?
    private var refusal = ""
    private var part: String?

    public init(provider: QuestionProvider) { self.provider = provider }

    public mutating func consume(_ event: ServerSentEvent) {
        guard failure == nil, let json = try? JSONSerialization.jsonObject(with: Data(event.data.utf8)) as? [String: Any] else { return }
        switch provider {
        case .anthropic: anthropic(json, event: event.event)
        case .openAI: openAI(json, event: event.event)
        case .gemini: gemini(json)
        default: break
        }
    }

    /// The text to save, once the stream has ended. A refusal discards any partial text, as the providers advise.
    public func result() throws -> (answer: String, model: String?, truncated: Bool) {
        if let failure { throw failure }
        switch ending {
        case .refused(let reason): throw APIFailure.refused(reason)
        case nil: throw answer.isEmpty ? APIFailure.empty : APIFailure.interrupted
        case .complete, .truncated: break
        }
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw APIFailure.empty }
        return (text, model, ending == .truncated)
    }

    private mutating func anthropic(_ json: [String: Any], event: String) {
        switch json["type"] as? String ?? event {
        case "message_start": model = (json["message"] as? [String: Any])?["model"] as? String ?? model
        case "content_block_start":
            let block = json["content_block"] as? [String: Any] ?? [:]
            // A server-side fallback continues the same answer on another model.
            if block["type"] as? String == "fallback", let to = (block["to"] as? [String: Any])?["model"] as? String { model = to }
            if block["type"] as? String == "text", let text = block["text"] as? String { answer += text }
        case "content_block_delta":
            if let delta = json["delta"] as? [String: Any], delta["type"] as? String == "text_delta", let text = delta["text"] as? String { answer += text }
        case "message_delta":
            let delta = json["delta"] as? [String: Any] ?? [:]
            if let stop = delta["stop_reason"] as? String {
                let details = (delta["stop_details"] ?? json["stop_details"]) as? [String: Any]
                switch stop {
                case "max_tokens": ending = .truncated
                case "refusal": ending = .refused((details?["explanation"] as? String) ?? (details?["category"] as? String))
                default: ending = .complete
                }
            }
        case "message_stop": if ending == nil { ending = .complete }
        case "error":
            let error = json["error"] as? [String: Any]
            failure = APIFailure.anthropic(type: error?["type"] as? String, message: error?["message"] as? String ?? "", status: nil, retryAfter: nil)
        default: break
        }
    }

    private mutating func openAI(_ json: [String: Any], event: String) {
        let response = json["response"] as? [String: Any]
        if let name = response?["model"] as? String { model = name }
        switch json["type"] as? String ?? event {
        case "response.output_text.delta":
            let key = "\(json["output_index"] ?? 0)/\(json["content_index"] ?? 0)"
            if let part, part != key, !answer.isEmpty { answer += "\n\n" }
            part = key
            answer += json["delta"] as? String ?? ""
        case "response.refusal.delta": refusal += json["delta"] as? String ?? ""
        case "response.refusal.done": refusal = json["refusal"] as? String ?? refusal
        case "response.completed": ending = answer.isEmpty && !refusal.isEmpty ? .refused(refusal) : .complete
        case "response.incomplete":
            let reason = (response?["incomplete_details"] as? [String: Any])?["reason"] as? String
            ending = reason == "content_filter" ? .refused("content filter") : .truncated
        case "response.failed":
            let error = response?["error"] as? [String: Any]
            failure = APIFailure.openAI(code: error?["code"] as? String, message: error?["message"] as? String ?? "", status: nil, retryAfter: nil)
        case "error":
            failure = APIFailure.openAI(code: json["code"] as? String, message: json["message"] as? String ?? "", status: nil, retryAfter: nil)
        default: break
        }
    }

    private mutating func gemini(_ json: [String: Any]) {
        if let error = json["error"] as? [String: Any] {
            let reasons = (error["details"] as? [[String: Any]] ?? []).compactMap { $0["reason"] as? String }
            failure = APIFailure.gemini(status: error["code"] as? Int, state: error["status"] as? String, reasons: reasons,
                                        message: error["message"] as? String ?? "", retryAfter: nil)
            return
        }
        if let version = json["modelVersion"] as? String { model = version }
        if let blocked = (json["promptFeedback"] as? [String: Any])?["blockReason"] as? String {
            ending = .refused("prompt blocked: " + blocked.lowercased().replacingOccurrences(of: "_", with: " "))
            return
        }
        guard let candidate = (json["candidates"] as? [[String: Any]])?.first else { return }
        for part in (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? [] where part["thought"] as? Bool != true {
            answer += part["text"] as? String ?? ""
        }
        guard let reason = candidate["finishReason"] as? String, reason != "FINISH_REASON_UNSPECIFIED" else { return }
        let readable = reason.lowercased().replacingOccurrences(of: "_", with: " ")
        switch reason {
        case "STOP": ending = .complete
        case "MAX_TOKENS": ending = .truncated
        case "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "LANGUAGE", "ESCALATION",
             "IMAGE_SAFETY", "IMAGE_PROHIBITED_CONTENT", "IMAGE_RECITATION", "IMAGE_OTHER":
            ending = .refused(readable)
        case "PUP_LIMITED_DISABLED": failure = .permission("account limited")
        default: failure = .stopped("finish reason: " + readable)
        }
    }
}

/// URLSession transport for the API providers: ephemeral (no cookies or cache on disk), with an idle timeout for
/// streams and an overall limit, and no waiting for connectivity, so an offline Mac is reported at once.
public struct APIClient: Sendable {
    public let session: URLSession

    public init(configuration: URLSessionConfiguration = APIClient.configuration()) { session = URLSession(configuration: configuration) }

    public static func configuration(idleTimeout: TimeInterval = 300, totalTimeout: TimeInterval = 1800) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = idleTimeout
        configuration.timeoutIntervalForResource = totalTimeout
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    /// The server-sent events of a streamed answer. An HTTP error status arrives as an `APIFailure`; cancelling the
    /// consuming task cancels the request.
    public func events(_ request: URLRequest, provider: QuestionProvider) -> AsyncThrowingStream<ServerSentEvent, Error> {
        let session = session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw APIFailure.stopped("not an HTTP response") }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count >= 65_536 { break }
                        }
                        throw APIFailure.http(provider, status: http.statusCode, body: body, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
                    }
                    var parser = ServerSentEventParser()
                    var line: [UInt8] = []
                    for try await byte in bytes {
                        line.append(byte)
                        guard byte == 10 else { continue }
                        for event in parser.feed(line) { continuation.yield(event) }
                        line.removeAll(keepingCapacity: true)
                    }
                    for event in parser.feed(line) { continuation.yield(event) }
                    for event in parser.finish() { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIFailure.wrapping(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Performs Check's request; succeeds when the provider accepts the key and knows the model.
    public func check(_ request: URLRequest, provider: QuestionProvider) async throws {
        do {
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIFailure.stopped("not an HTTP response") }
            guard (200..<300).contains(http.statusCode) else {
                throw APIFailure.http(provider, status: http.statusCode, body: body, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
            }
        } catch { throw APIFailure.wrapping(error) }
    }
}
