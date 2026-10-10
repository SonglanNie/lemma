import Foundation
import Security
import os

/// The reader's API keys for the OpenAI, Anthropic and Gemini providers. A key lives only in the macOS Keychain,
/// one generic password per provider; it is never written to UserDefaults, study files, question packets or logs.
public protocol APIKeyStore: Sendable {
    func key(for provider: QuestionProvider) throws -> String?
    /// Whether a key is saved, without reading it (no Keychain prompt).
    func hasKey(for provider: QuestionProvider) -> Bool
    func save(_ key: String, for provider: QuestionProvider) throws
    func remove(for provider: QuestionProvider) throws
}

public enum APIKeyError: LocalizedError, Equatable {
    case empty, malformed, keychain(OSStatus)
    public var errorDescription: String? {
        switch self {
        case .empty: "Paste an API key first."
        case .malformed: "That does not look like an API key: it contains spaces or is too long."
        case .keychain(let status):
            "The Keychain refused the request: " + ((SecCopyErrorMessageString(status, nil) as String?) ?? "error \(status)") + "."
        }
    }
}

/// Generic passwords in the login keychain: service “Lemma Assistant Keys”, account = provider identifier.
public struct KeychainAPIKeyStore: APIKeyStore {
    public static let defaultService = "Lemma Assistant Keys"
    public let service: String
    public init(service: String = KeychainAPIKeyStore.defaultService) { self.service = service }

    public func query(_ provider: QuestionProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: provider.rawValue]
    }

    public func key(for provider: QuestionProvider) throws -> String? {
        var query = query(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw APIKeyError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }

    public func hasKey(for provider: QuestionProvider) -> Bool {
        var query = query(provider)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    public func save(_ key: String, for provider: QuestionProvider) throws {
        let data = Data(try APIKeyFormat.cleaned(key).utf8)
        let update = SecItemUpdate(query(provider) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw APIKeyError.keychain(update) }
        var item = query(provider)
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "\(service) (\(provider.company))"
        item[kSecAttrDescription as String] = "API key"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw APIKeyError.keychain(status) }
    }

    public func remove(for provider: QuestionProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIKeyError.keychain(status) }
    }
}

/// Keys held in memory only: tests, and QA copies of Lemma, which must not touch the reader's Keychain.
public final class MemoryAPIKeyStore: APIKeyStore {
    private let keys = OSAllocatedUnfairLock<[QuestionProvider: String]>(initialState: [:])
    public init(_ initial: [QuestionProvider: String] = [:]) { keys.withLock { $0 = initial } }
    public func key(for provider: QuestionProvider) throws -> String? { keys.withLock { $0[provider] } }
    public func hasKey(for provider: QuestionProvider) -> Bool { keys.withLock { $0[provider] != nil } }
    public func save(_ key: String, for provider: QuestionProvider) throws {
        let cleaned = try APIKeyFormat.cleaned(key)
        keys.withLock { $0[provider] = cleaned }
    }
    public func remove(for provider: QuestionProvider) throws { _ = keys.withLock { $0.removeValue(forKey: provider) } }
}

public enum APIKeyFormat {
    /// Trims what copying from a web page adds. Formats differ by provider and change over time, so beyond
    /// “one token without spaces” the provider itself is the judge (Check).
    public static func cleaned(_ key: String) throws -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
        guard !trimmed.isEmpty else { throw APIKeyError.empty }
        guard trimmed.count <= 1024, !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw APIKeyError.malformed }
        return trimmed
    }

    /// Removes anything shaped like an API key from text Lemma shows or saves, such as a provider's error message.
    public static func redacted(_ text: String, key: String? = nil) -> String {
        var result = text
        if let key, key.count >= 8 { result = result.replacingOccurrences(of: key, with: "[key hidden]") }
        for pattern in ["sk-[A-Za-z0-9_\\-*.]{8,}", "AIza[0-9A-Za-z_\\-]{16,}", "(?i)bearer\\s+[A-Za-z0-9_\\-.~+/]{8,}=*"] {
            result = result.replacingOccurrences(of: pattern, with: "[key hidden]", options: .regularExpression)
        }
        return result
    }
}
