import Foundation

/// A model offered in the pick list. The model field stays editable: providers add and retire models often.
public struct APIModelChoice: Hashable, Sendable {
    public let id: String
    public let note: String
}

/// One attached image, in the order the draft numbers them.
public struct APIImage: Sendable {
    public var label: String
    public var png: Data
    public init(label: String, png: Data) { self.label = label; self.png = png }
}

extension QuestionProvider {
    /// The model used when the reader has not chosen one (current as of October 2026).
    public var defaultModel: String {
        switch self {
        case .openAI: "gpt-6.1-sol"
        case .anthropic: "claude-opus-5-5"
        case .gemini: "gemini-3.8-flash"
        default: ""
        }
    }

    public var suggestedModels: [APIModelChoice] {
        switch self {
        case .openAI: [.init(id: "gpt-6.1-sol", note: "Near GPT-6 Astra quality at a lower price"),
                       .init(id: "gpt-6-astra", note: "OpenAI's most capable model, highest price"),
                       .init(id: "gpt-6-luna", note: "Fastest and least expensive")]
        case .anthropic: [.init(id: "claude-opus-5-5", note: "Anthropic's default model"),
                          .init(id: "claude-sonnet-5-5", note: "Faster, lower price"),
                          .init(id: "claude-haiku-5-5", note: "Fastest and least expensive"),
                          .init(id: "claude-fable-5-1", note: "Most capable, highest price")]
        case .gemini: [.init(id: "gemini-3.8-flash", note: "Google's most capable stable Flash model"),
                       .init(id: "gemini-3.1-pro-preview", note: "Pro model, preview"),
                       .init(id: "gemini-3.5-flash-lite", note: "Fastest and least expensive")]
        default: []
        }
    }

    /// Where the reader creates a key, on the provider's own site.
    public var apiKeyPage: URL? {
        switch self {
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: URL(string: "https://platform.claude.com/settings/keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        default: nil
        }
    }

    /// The only host an API question is sent to.
    public var apiHost: String? {
        switch self {
        case .openAI: "api.openai.com"
        case .anthropic: "api.anthropic.com"
        case .gemini: "generativelanguage.googleapis.com"
        default: nil
        }
    }
}

/// HTTP requests for the API providers. Every request carries the reader's key in a header (never in the URL),
/// the same instruction and draft the CLIs receive, and each image after a short “Image n: label” line so the
/// numbering in the draft matches the attachments.
public enum APIRequestBuilder {
    public enum BuildError: LocalizedError, Equatable {
        case invalidModel(String)
        public var errorDescription: String? {
            if case .invalidModel(let model) = self { return "“\(model)” is not a valid model name. Choose a model in Assistants › Connections." }
            return nil
        }
    }

    /// Claude models whose declined requests Anthropic can retry on its recommended fallback model.
    static let anthropicFallbackModels: Set<String> = ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]
    static let anthropicFallbackBeta = "server-side-fallback-2026-07-01"

    /// Models that accept `output_config.effort`; older ones reject the field.
    static func anthropicAcceptsEffort(_ model: String) -> Bool {
        ["claude-opus-5", "claude-sonnet-5", "claude-haiku-5", "claude-fable-5", "claude-mythos-5",
         "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-4-6", "claude-opus-4-5"].contains { model.hasPrefix($0) }
    }

    /// A model identifier as it may appear in a URL path: letters, digits, `.`, `-`, `_`, and `:` for OpenAI's
    /// fine-tuned models (Gemini uses `:` before the method name, and its `models/` prefix is accepted).
    public static func validatedModel(_ model: String, provider: QuestionProvider) throws -> String {
        var value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { value = provider.defaultModel }
        if provider == .gemini, value.hasPrefix("models/") { value.removeFirst("models/".count) }
        let punctuation = provider == .openAI ? "._-:" : "._-"
        guard !value.isEmpty, value.count <= 200, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || punctuation.contains($0)) }) else {
            throw BuildError.invalidModel(model)
        }
        return value
    }

    /// A streamed answer. `serverFallbacks` opts eligible Claude models into Anthropic's server-side refusal fallback.
    public static func answer(_ provider: QuestionProvider, key: String, model rawModel: String, prompt: String, images: [APIImage],
                              serverFallbacks: Bool = true) throws -> URLRequest {
        let model = try validatedModel(rawModel, provider: provider)
        let labelled = images.enumerated().map { (index: $0.offset + 1, image: $0.element) }
        var request: URLRequest
        var body: [String: Any]
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            // Claude reads images best before the question.
            var content: [[String: Any]] = []
            for item in labelled {
                content.append(["type": "text", "text": "Image \(item.index): \(item.image.label)"])
                content.append(["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": item.image.png.base64EncodedString()]])
            }
            content.append(["type": "text", "text": prompt])
            body = ["model": model, "max_tokens": 64000, "stream": true, "system": QuestionCLI.studyInstruction,
                    "messages": [["role": "user", "content": content]]]
            if anthropicAcceptsEffort(model) { body["output_config"] = ["effort": "high"] }
            if serverFallbacks, anthropicFallbackModels.contains(model) {
                body["fallbacks"] = "default"
                request.setValue(anthropicFallbackBeta, forHTTPHeaderField: "anthropic-beta")
            }
        case .openAI:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            var content: [[String: Any]] = [["type": "input_text", "text": prompt]]
            for item in labelled {
                content.append(["type": "input_text", "text": "Image \(item.index): \(item.image.label)"])
                content.append(["type": "input_image", "image_url": "data:image/png;base64," + item.image.png.base64EncodedString(), "detail": "high"])
            }
            // `store: false`: the response is not kept on OpenAI's side for later retrieval.
            body = ["model": model, "stream": true, "store": false, "instructions": QuestionCLI.studyInstruction,
                    "input": [["role": "user", "content": content]]]
        case .gemini:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            var parts: [[String: Any]] = [["text": prompt]]
            for item in labelled {
                parts.append(["text": "Image \(item.index): \(item.image.label)"])
                parts.append(["inlineData": ["mimeType": "image/png", "data": item.image.png.base64EncodedString()]])
            }
            body = ["systemInstruction": ["parts": [["text": QuestionCLI.studyInstruction]]],
                    "contents": [["role": "user", "parts": parts]]]
        default:
            throw BuildError.invalidModel(rawModel)
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        return request
    }

    /// The minimal call behind Check: reads the model's description, which needs a valid key and an available model
    /// but generates nothing and costs nothing.
    public static func check(_ provider: QuestionProvider, key: String, model rawModel: String) throws -> URLRequest {
        let model = try validatedModel(rawModel, provider: provider)
        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models/\(model)")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAI:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models/\(model)")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .gemini:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model)")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        default:
            throw BuildError.invalidModel(rawModel)
        }
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
