import XCTest
@testable import LemmaCore

/// Answers every request from a script, records what was sent, and never touches the network.
final class APIStubProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var headers: [String: String] = ["Content-Type": "text/event-stream"]
        var chunks: [Data] = []
        var error: URLError?
        /// Sends the headers, then nothing more until cancelled.
        var hang = false
    }
    nonisolated(unsafe) static var reply = Reply()
    nonisolated(unsafe) static var sent: [(request: URLRequest, body: Data)] = []
    nonisolated(unsafe) static var stopped = false

    static func configuration() -> URLSessionConfiguration {
        let configuration = APIClient.configuration(idleTimeout: 5, totalTimeout: 10)
        configuration.protocolClasses = [APIStubProtocol.self]
        return configuration
    }

    static func reset(_ reply: Reply) { self.reply = reply; sent = []; stopped = false }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession hands the body to protocols as a stream.
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(buffer, count: count) }
        }
        Self.sent.append((request, body))
        let reply = Self.reply
        if let error = reply.error { client?.urlProtocol(self, didFailWithError: error); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if reply.hang { return }
        for chunk in reply.chunks { client?.urlProtocol(self, didLoad: chunk) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { Self.stopped = true }
}

func sse(_ events: [(name: String?, json: String)]) -> Data {
    Data(events.map { ($0.name.map { "event: \($0)\n" } ?? "") + "data: \($0.json)\n\n" }.joined().utf8)
}

final class APIProviderTests: XCTestCase {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4, 5])
    var images: [APIImage] { [APIImage(label: "Source A", png: png), APIImage(label: "Cited: Equation (2.3)", png: Data([9, 8, 7]))] }

    /// Streams `chunks` through APIClient into a parser, as Lemma's runtime does.
    func stream(_ provider: QuestionProvider, _ chunks: [Data], status: Int = 200, headers: [String: String]? = nil) async throws -> APIAnswerParser {
        var reply = APIStubProtocol.Reply(status: status, chunks: chunks)
        if let headers { reply.headers = headers }
        APIStubProtocol.reset(reply)
        let client = APIClient(configuration: APIStubProtocol.configuration())
        let request = try APIRequestBuilder.answer(provider, key: "test-key-0123456789", model: "", prompt: "Why?", images: images)
        var parser = APIAnswerParser(provider: provider)
        for try await event in client.events(request, provider: provider) { parser.consume(event) }
        return parser
    }

    func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func failure(_ provider: QuestionProvider, status: Int, json: String, retryAfter: String? = nil) async -> APIFailure? {
        var headers = ["Content-Type": "application/json"]
        if let retryAfter { headers["Retry-After"] = retryAfter }
        do { _ = try await stream(provider, [Data(json.utf8)], status: status, headers: headers); return nil }
        catch { return error as? APIFailure }
    }

    // MARK: Server-sent events

    func testEventParserJoinsSplitChunksCRLFAndMultilineData() {
        var parser = ServerSentEventParser()
        var events: [ServerSentEvent] = []
        let text = ": keep-alive\r\nevent: message_start\r\ndata: {\"a\":\r\n\r\nevent: delta\ndata: line one\ndata: line two\n\ndata: tail"
        for chunk in Array(text.utf8).chunked(into: 5) { events += parser.feed(chunk) }
        events += parser.finish()
        XCTAssertEqual(events, [ServerSentEvent(event: "message_start", data: "{\"a\":"), ServerSentEvent(event: "delta", data: "line one\nline two"),
                                ServerSentEvent(event: "message", data: "tail")])
    }

    // MARK: Anthropic

    func testAnthropicRequestCarriesKeyHeadersImagesAndTheDraft() throws {
        let request = try APIRequestBuilder.answer(.anthropic, key: "sk-ant-test", model: "", prompt: "Question:\nWhy full rank?", images: images)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let json = try body(request)
        XCTAssertEqual(json["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["max_tokens"] as? Int, 64000)
        XCTAssertEqual(json["fallbacks"] as? String, "default")
        XCTAssertEqual((json["output_config"] as? [String: String])?["effort"], "high")
        XCTAssertEqual(json["system"] as? String, QuestionCLI.studyInstruction)
        let content = try XCTUnwrap(((json["messages"] as? [[String: Any]])?.first)?["content"] as? [[String: Any]])
        XCTAssertEqual(content.compactMap { $0["type"] as? String }, ["text", "image", "text", "image", "text"])
        XCTAssertEqual(content[0]["text"] as? String, "Image 1: Source A")
        let source = try XCTUnwrap(content[1]["source"] as? [String: String])
        XCTAssertEqual(source["type"], "base64"); XCTAssertEqual(source["media_type"], "image/png"); XCTAssertEqual(source["data"], png.base64EncodedString())
        XCTAssertEqual(content.last?["text"] as? String, "Question:\nWhy full rank?")
        // Models without the fallback or effort options get a plain request.
        let haiku = try body(APIRequestBuilder.answer(.anthropic, key: "k", model: "claude-haiku-4-5", prompt: "p", images: []))
        XCTAssertNil(haiku["fallbacks"]); XCTAssertNil(haiku["output_config"])
        let plain = try APIRequestBuilder.answer(.anthropic, key: "k", model: "claude-opus-5-5", prompt: "p", images: [], serverFallbacks: false)
        XCTAssertNil(plain.value(forHTTPHeaderField: "anthropic-beta")); XCTAssertNil(try body(plain)["fallbacks"])
    }

    func testAnthropicStreamKeepsTextFollowsAFallbackAndSkipsThinking() async throws {
        let parser = try await stream(.anthropic, [sse([
            ("message_start", #"{"type":"message_start","message":{"id":"msg_1","model":"claude-opus-5-5"}}"#),
            ("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#),
            ("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"private"}}"#),
            ("ping", #"{"type":"ping"}"#),
            ("content_block_start", #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#),
            ("content_block_delta", #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Full rank gives "}}"#),
            ("content_block_start", #"{"type":"content_block_start","index":2,"content_block":{"type":"fallback","from":{"model":"claude-opus-5-5"},"to":{"model":"claude-opus-4-8"}}}"#),
            ("content_block_delta", #"{"type":"content_block_delta","index":3,"delta":{"type":"text_delta","text":"uniqueness: $X^\\top X$."}}"#),
            ("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}"#),
            ("message_stop", #"{"type":"message_stop"}"#)])])
        let result = try parser.result()
        XCTAssertEqual(result.answer, "Full rank gives uniqueness: $X^\\top X$.")
        XCTAssertEqual(result.model, "claude-opus-4-8", "The model that finished the answer is recorded.")
        XCTAssertFalse(result.truncated)
        XCTAssertFalse(result.answer.contains("private"))
    }

    func testAnthropicRefusalsErrorsAndTruncation() async throws {
        let refused = try await stream(.anthropic, [sse([
            ("message_start", #"{"type":"message_start","message":{"model":"claude-opus-5-5"}}"#),
            ("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Partial"}}"#),
            ("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"}}}"#),
            ("message_stop", #"{"type":"message_stop"}"#)])])
        XCTAssertThrowsError(try refused.result()) { XCTAssertEqual($0 as? APIFailure, .refused("cyber"), "Partial text of a refusal is not saved.") }
        let overloaded = try await stream(.anthropic, [sse([("error", #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)])])
        XCTAssertThrowsError(try overloaded.result()) { XCTAssertEqual($0 as? APIFailure, .overloaded("Overloaded")) }
        let long = try await stream(.anthropic, [sse([
            ("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Long"}}"#),
            ("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#), ("message_stop", #"{"type":"message_stop"}"#)])])
        XCTAssertEqual(try long.result().truncated, true)
        let cut = try await stream(.anthropic, [sse([("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Half"}}"#)])])
        XCTAssertThrowsError(try cut.result()) { XCTAssertEqual($0 as? APIFailure, .interrupted) }

        let invalid = await failure(.anthropic, status: 401, json: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
        XCTAssertEqual(invalid, .invalidKey("invalid x-api-key"))
        let limited = await failure(.anthropic, status: 429, json: #"{"type":"error","error":{"type":"rate_limit_error","message":"Number of requests has exceeded your rate limit"}}"#, retryAfter: "20")
        XCTAssertEqual(limited, .rateLimited(retryAfter: 20, "Number of requests has exceeded your rate limit"))
        let credit = await failure(.anthropic, status: 400, json: #"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API."}}"#)
        XCTAssertEqual(credit, .quota("Your credit balance is too low to access the Anthropic API."))
        let missing = await failure(.anthropic, status: 404, json: #"{"type":"error","error":{"type":"not_found_error","message":"model: claude-nope"}}"#)
        XCTAssertEqual(missing, .modelNotFound("model: claude-nope"))
        do { let mapped = await failure(.anthropic, status: 529, json: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#); XCTAssertEqual(mapped, .overloaded("Overloaded")) }
        let beta = await failure(.anthropic, status: 400, json: #"{"type":"error","error":{"type":"invalid_request_error","message":"Unexpected value(s) `server-side-fallback-2026-07-01` for the `anthropic-beta` header."}}"#)
        XCTAssertEqual(beta?.rejectsServerFallbacks, true, "An account without the fallback beta is asked again without it.")
        XCTAssertTrue(APIFailure.invalidKey("x").message(.anthropic, model: "claude-opus-5-5").contains("Anthropic API rejected the API key"))
    }

    // MARK: OpenAI

    func testOpenAIRequestUsesBearerResponsesAPIAndDataURLs() throws {
        let request = try APIRequestBuilder.answer(.openAI, key: "sk-proj-test", model: " gpt-6-luna ", prompt: "Why?", images: images)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-proj-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try body(request)
        XCTAssertEqual(json["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["store"] as? Bool, false, "Responses are not kept on OpenAI's side.")
        XCTAssertEqual(json["instructions"] as? String, QuestionCLI.studyInstruction)
        let content = try XCTUnwrap(((json["input"] as? [[String: Any]])?.first)?["content"] as? [[String: Any]])
        XCTAssertEqual(content.compactMap { $0["type"] as? String }, ["input_text", "input_text", "input_image", "input_text", "input_image"])
        XCTAssertEqual(content[0]["text"] as? String, "Why?")
        XCTAssertEqual(content[2]["image_url"] as? String, "data:image/png;base64," + png.base64EncodedString())
        XCTAssertEqual(content[2]["detail"] as? String, "high")
        XCTAssertEqual(try body(APIRequestBuilder.answer(.openAI, key: "k", model: "", prompt: "p", images: []))["model"] as? String, "gpt-6.1-sol")
    }

    func testOpenAIStreamTextModelTruncationRefusalAndFailure() async throws {
        let parser = try await stream(.openAI, [sse([
            ("response.created", #"{"type":"response.created","response":{"id":"resp_1","status":"in_progress","model":"gpt-6.1-sol"}}"#),
            ("response.reasoning_summary_text.delta", #"{"type":"response.reasoning_summary_text.delta","delta":"thinking"}"#),
            ("response.output_text.delta", #"{"type":"response.output_text.delta","output_index":1,"content_index":0,"delta":"Use "}"#),
            ("response.output_text.delta", #"{"type":"response.output_text.delta","output_index":1,"content_index":0,"delta":"$X^\\top X$."}"#),
            ("response.completed", #"{"type":"response.completed","response":{"status":"completed","model":"gpt-6.1-sol-2026-08-01"}}"#)])])
        let result = try parser.result()
        XCTAssertEqual(result.answer, "Use $X^\\top X$."); XCTAssertEqual(result.model, "gpt-6.1-sol-2026-08-01")
        let cut = try await stream(.openAI, [sse([
            ("response.output_text.delta", #"{"type":"response.output_text.delta","output_index":0,"content_index":0,"delta":"Long"}"#),
            ("response.incomplete", #"{"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}}}"#)])])
        XCTAssertEqual(try cut.result().truncated, true)
        let refused = try await stream(.openAI, [sse([
            ("response.refusal.delta", #"{"type":"response.refusal.delta","delta":"I can't help with that."}"#),
            ("response.completed", #"{"type":"response.completed","response":{"status":"completed"}}"#)])])
        XCTAssertThrowsError(try refused.result()) { XCTAssertEqual($0 as? APIFailure, .refused("I can't help with that.")) }
        let failed = try await stream(.openAI, [sse([("response.failed", #"{"type":"response.failed","response":{"status":"failed","error":{"code":"server_error","message":"The server had an error"}}}"#)])])
        XCTAssertThrowsError(try failed.result()) { XCTAssertEqual($0 as? APIFailure, .server(status: 500, "The server had an error")) }
        let quota = try await stream(.openAI, [sse([("error", #"{"type":"error","code":"insufficient_quota","message":"You exceeded your current quota","param":null}"#)])])
        XCTAssertThrowsError(try quota.result()) { XCTAssertEqual($0 as? APIFailure, .quota("You exceeded your current quota")) }
    }

    func testOpenAIHTTPErrorsMapToKeyQuotaRateAndModel() async {
        let key = await failure(.openAI, status: 401, json: #"{"error":{"message":"Incorrect API key provided: sk-proj-****abcd.","type":"invalid_request_error","param":null,"code":"invalid_api_key"}}"#)
        XCTAssertEqual(key, .invalidKey("Incorrect API key provided: sk-proj-****abcd."))
        XCTAssertFalse(key!.message(.openAI, model: "gpt-6.1-sol").contains("sk-proj"), "Key fragments never reach the panel or the receipt.")
        do { let mapped = await failure(.openAI, status: 429, json: #"{"error":{"message":"You exceeded your current quota","type":"insufficient_quota","code":"insufficient_quota"}}"#); XCTAssertEqual(mapped, .quota("You exceeded your current quota")) }
        do { let mapped = await failure(.openAI, status: 429, json: #"{"error":{"message":"Rate limit reached","type":"requests","code":"rate_limit_exceeded"}}"#, retryAfter: "7"); XCTAssertEqual(mapped, .rateLimited(retryAfter: 7, "Rate limit reached")) }
        do { let mapped = await failure(.openAI, status: 404, json: #"{"error":{"message":"The model `gpt-9` does not exist or you do not have access to it.","code":"model_not_found"}}"#); XCTAssertEqual(mapped, .modelNotFound("The model `gpt-9` does not exist or you do not have access to it.")) }
        do { let mapped = await failure(.openAI, status: 403, json: #"{"error":{"message":"Country, region, or territory not supported","code":"unsupported_country_region_territory"}}"#); XCTAssertEqual(mapped, .permission("Country, region, or territory not supported")) }
        do { let mapped = await failure(.openAI, status: 503, json: #"{"error":{"message":"Slow down","code":"server_is_overloaded"}}"#); XCTAssertEqual(mapped, .overloaded("Slow down")) }
    }

    // MARK: Gemini

    func testGeminiRequestKeepsTheKeyInAHeaderAndSendsInlineImages() throws {
        let request = try APIRequestBuilder.answer(.gemini, key: "AIzaTestKey", model: "models/gemini-3.5-flash-lite", prompt: "Why?", images: images)
        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:streamGenerateContent?alt=sse")
        XCTAssertFalse(request.url!.absoluteString.contains("AIza"), "The key never travels in the URL.")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "AIzaTestKey")
        let json = try body(request)
        XCTAssertEqual(((json["systemInstruction"] as? [String: Any])?["parts"] as? [[String: String]])?.first?["text"], QuestionCLI.studyInstruction)
        let parts = try XCTUnwrap(((json["contents"] as? [[String: Any]])?.first)?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 5)
        XCTAssertEqual(parts[0]["text"] as? String, "Why?")
        XCTAssertEqual(parts[1]["text"] as? String, "Image 1: Source A")
        XCTAssertEqual(parts[2]["inlineData"] as? [String: String], ["mimeType": "image/png", "data": png.base64EncodedString()])
        XCTAssertThrowsError(try APIRequestBuilder.answer(.gemini, key: "k", model: "gemini:evil/../x", prompt: "p", images: []))
        XCTAssertTrue(try APIRequestBuilder.answer(.gemini, key: "k", model: "", prompt: "p", images: []).url!.path.hasSuffix("/gemini-3.8-flash:streamGenerateContent"))
    }

    func testGeminiStreamSkipsThoughtsAndReportsBlocksAndLimits() async throws {
        let parser = try await stream(.gemini, [sse([
            (nil, #"{"candidates":[{"content":{"parts":[{"text":"weighing the options","thought":true}],"role":"model"},"index":0}],"modelVersion":"gemini-3.8-flash"}"#),
            (nil, #"{"candidates":[{"content":{"parts":[{"text":"Full rank "}],"role":"model"},"index":0}],"modelVersion":"gemini-3.8-flash"}"#),
            (nil, #"{"candidates":[{"content":{"parts":[{"text":"gives uniqueness."}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"totalTokenCount":9},"modelVersion":"gemini-3.8-flash"}"#)])])
        let result = try parser.result()
        XCTAssertEqual(result.answer, "Full rank gives uniqueness."); XCTAssertEqual(result.model, "gemini-3.8-flash")
        let blocked = try await stream(.gemini, [sse([(nil, #"{"promptFeedback":{"blockReason":"PROHIBITED_CONTENT"},"modelVersion":"gemini-3.8-flash"}"#)])])
        XCTAssertThrowsError(try blocked.result()) { XCTAssertEqual($0 as? APIFailure, .refused("prompt blocked: prohibited content")) }
        let safety = try await stream(.gemini, [sse([(nil, #"{"candidates":[{"content":{"parts":[{"text":"Par"}]},"finishReason":"SAFETY"}]}"#)])])
        XCTAssertThrowsError(try safety.result()) { XCTAssertEqual($0 as? APIFailure, .refused("safety")) }
        let long = try await stream(.gemini, [sse([(nil, #"{"candidates":[{"content":{"parts":[{"text":"Long"}]},"finishReason":"MAX_TOKENS"}]}"#)])])
        XCTAssertEqual(try long.result().truncated, true)
        let midStream = try await stream(.gemini, [sse([(nil, #"{"error":{"code":503,"message":"The model is overloaded.","status":"UNAVAILABLE"}}"#)])])
        XCTAssertThrowsError(try midStream.result()) { XCTAssertEqual($0 as? APIFailure, .overloaded("The model is overloaded.")) }
    }

    func testGeminiHTTPErrorsMapToKeyModelRateAndAccess() async {
        let invalid = #"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID","domain":"googleapis.com"}]}}"#
        do { let mapped = await failure(.gemini, status: 400, json: invalid); XCTAssertEqual(mapped, .invalidKey("API key not valid. Please pass a valid API key.")) }
        do { let mapped = await failure(.gemini, status: 404, json: #"{"error":{"code":404,"message":"models/gemini-9 is not found for API version v1beta","status":"NOT_FOUND"}}"#); XCTAssertEqual(mapped, .modelNotFound("models/gemini-9 is not found for API version v1beta")) }
        do { let mapped = await failure(.gemini, status: 429, json: #"{"error":{"code":429,"message":"You exceeded your current quota","status":"RESOURCE_EXHAUSTED"}}"#); XCTAssertEqual(mapped, .rateLimited(retryAfter: nil, "You exceeded your current quota")) }
        do { let mapped = await failure(.gemini, status: 400, json: #"{"error":{"code":400,"message":"User location is not supported for the API use.","status":"FAILED_PRECONDITION"}}"#); XCTAssertEqual(mapped, .permission("User location is not supported for the API use.")) }
        do { let mapped = await failure(.gemini, status: 503, json: #"{"error":{"code":503,"message":"The model is overloaded.","status":"UNAVAILABLE"}}"#); XCTAssertEqual(mapped, .overloaded("The model is overloaded.")) }
    }

    // MARK: Transport

    func testOfflineAndTimeoutsAreReportedAndCancellationStopsTheRequest() async throws {
        APIStubProtocol.reset(.init(error: URLError(.notConnectedToInternet)))
        let client = APIClient(configuration: APIStubProtocol.configuration())
        let request = try APIRequestBuilder.answer(.anthropic, key: "k", model: "", prompt: "p", images: [])
        do { for try await _ in client.events(request, provider: .anthropic) {}; XCTFail("Offline must fail") }
        catch { guard case .offline = error as? APIFailure else { return XCTFail("\(error)") } }
        XCTAssertTrue(APIFailure.offline("x").message(.anthropic, model: "m").contains("api.anthropic.com"))
        APIStubProtocol.reset(.init(error: URLError(.timedOut)))
        do { for try await _ in client.events(request, provider: .anthropic) {}; XCTFail("A timeout must fail") }
        catch { XCTAssertEqual(error as? APIFailure, .timedOut) }

        APIStubProtocol.reset(.init(hang: true))
        let reading = Task { for try await _ in client.events(request, provider: .anthropic) {} }
        try await Task.sleep(for: .milliseconds(200))
        reading.cancel()
        let started = Date()
        _ = await reading.result
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "Cancel ends the question at once.")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(APIStubProtocol.stopped, "Cancelling the reader cancels the HTTP request.")
    }

    func testCheckReadsTheModelWithTheKeyAndMapsRejections() async throws {
        let client = APIClient(configuration: APIStubProtocol.configuration())
        for provider in [QuestionProvider.openAI, .anthropic, .gemini] {
            APIStubProtocol.reset(.init(status: 200, headers: ["Content-Type": "application/json"], chunks: [Data("{}".utf8)]))
            try await client.check(APIRequestBuilder.check(provider, key: "secret-key", model: ""), provider: provider)
            let sent = try XCTUnwrap(APIStubProtocol.sent.first?.request)
            XCTAssertEqual(sent.httpMethod, "GET")
            XCTAssertTrue(sent.url!.absoluteString.hasSuffix("/models/" + provider.defaultModel), sent.url!.absoluteString)
            XCTAssertFalse(sent.url!.absoluteString.contains("secret-key"))
            XCTAssertEqual(sent.allHTTPHeaderFields?.values.contains { $0.contains("secret-key") }, true)
        }
        APIStubProtocol.reset(.init(status: 401, headers: ["Content-Type": "application/json"], chunks: [Data(#"{"error":{"message":"bad key","code":"invalid_api_key"}}"#.utf8)]))
        do { try await client.check(APIRequestBuilder.check(.openAI, key: "k", model: ""), provider: .openAI); XCTFail() }
        catch { XCTAssertEqual(error as? APIFailure, .invalidKey("bad key")) }
    }

    // MARK: Keys

    func testKeysAreTrimmedKeptOutOfMessagesAndAddressedPerProvider() throws {
        let store = MemoryAPIKeyStore()
        XCTAssertFalse(store.hasKey(for: .openAI))
        try store.save("  sk-proj-abc123def456\n", for: .openAI)
        XCTAssertEqual(try store.key(for: .openAI), "sk-proj-abc123def456")
        XCTAssertNil(try store.key(for: .anthropic))
        XCTAssertThrowsError(try store.save("   ", for: .gemini)) { XCTAssertEqual($0 as? APIKeyError, .empty) }
        XCTAssertThrowsError(try store.save("two words", for: .gemini)) { XCTAssertEqual($0 as? APIKeyError, .malformed) }
        try store.remove(for: .openAI)
        XCTAssertFalse(store.hasKey(for: .openAI))
        let keychain = KeychainAPIKeyStore().query(.gemini)
        XCTAssertEqual(keychain[kSecAttrService as String] as? String, "Lemma Assistant Keys")
        XCTAssertEqual(keychain[kSecAttrAccount as String] as? String, "gemini")
        XCTAssertEqual(APIKeyFormat.redacted("Bad key sk-ant-api03-AbCdEf123456 and AIzaSyA1234567890abcdefghij, Bearer abcdefghijkl"),
                       "Bad key [key hidden] and [key hidden], [key hidden]")
        XCTAssertEqual(APIKeyFormat.redacted("custom secret-value-123 leaked", key: "secret-value-123"), "custom [key hidden] leaked")
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] { stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) } }
}
