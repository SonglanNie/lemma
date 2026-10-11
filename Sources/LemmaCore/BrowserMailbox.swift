import Foundation

public enum BridgeError: LocalizedError {
    case invalidRequest, invalidImage, expired, messageTooLarge, invalidURL
    public var errorDescription: String? {
        switch self {
        case .invalidRequest: "This study question is unavailable. Prepare it again in Lemma."
        case .invalidImage: "The requested source image is unavailable."
        case .expired: "This question has expired. Prepare a new question in Lemma."
        case .messageTooLarge: "The browser message exceeds the supported size."
        case .invalidURL: "The response did not come from a ChatGPT conversation."
        }
    }
}

public struct BrowserMailbox: Sendable {
    public let root: URL
    public static let chunkSize = 96 * 1024
    public init(root: URL) { self.root = root.appendingPathComponent("Browser", isDirectory: true) }
    public func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    public func prepare(_ packet: BrowserPacket, imageData: [String: Data]) throws {
        let dir = directory(packet.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for image in packet.images {
            guard Self.isSafeImageName(image.name), let data = imageData[image.name], data.count == image.byteCount else {
                throw BridgeError.invalidImage
            }
            try data.write(to: dir.appendingPathComponent(image.name), options: .atomic)
        }
        try WorkspaceRepository.encoder.encode(packet).write(to: dir.appendingPathComponent("request.json"), options: .atomic)
    }

    /// The prepared packet. Its images and text can be fetched for an hour; a result can be saved for a day, since a
    /// reader may review a draft for a while and a thinking model may answer slowly.
    public func packet(_ id: UUID, now: Date = .now, maximumAge: TimeInterval = 3600) throws -> BrowserPacket {
        let url = directory(id).appendingPathComponent("request.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw BridgeError.invalidRequest }
        let packet = try WorkspaceRepository.decoder.decode(BrowserPacket.self, from: Data(contentsOf: url))
        guard packet.id == id else { throw BridgeError.invalidRequest }
        guard now.timeIntervalSince(packet.createdAt) < maximumAge else { throw BridgeError.expired }
        return packet
    }

    public func imageChunk(requestID: UUID, name: String, index: Int) throws -> (Data, Bool) {
        let packet = try packet(requestID)
        guard Self.isSafeImageName(name), packet.images.contains(where: { $0.name == name }), index >= 0 else {
            throw BridgeError.invalidImage
        }
        let data = try Data(contentsOf: directory(requestID).appendingPathComponent(name))
        let offset = index.multipliedReportingOverflow(by: Self.chunkSize)
        guard !offset.overflow, offset.partialValue < data.count else { throw BridgeError.invalidImage }
        let end = min(offset.partialValue + Self.chunkSize, data.count)
        return (data.subdata(in: offset.partialValue..<end), end == data.count)
    }

    public func saveResult(_ result: BrowserResult) throws {
        _ = try packet(result.requestID, maximumAge: 86_400)
        if let raw = result.conversationURL {
            guard let url = URL(string: raw), url.scheme == "https", url.host == "chatgpt.com" else {
                throw BridgeError.invalidURL
            }
        }
        guard ["prepared", "sent", "complete", "error"].contains(result.status) else { throw BridgeError.invalidRequest }
        try WorkspaceRepository.encoder.encode(result).write(to: directory(result.requestID).appendingPathComponent("result.json"), options: .atomic)
    }

    public func result(_ id: UUID) throws -> BrowserResult? {
        let url = directory(id).appendingPathComponent("result.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try WorkspaceRepository.decoder.decode(BrowserResult.self, from: Data(contentsOf: url))
    }

    public static func isSafeImageName(_ name: String) -> Bool {
        !name.isEmpty && name.count < 160 && name.hasSuffix(".png") &&
        name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") } &&
        !name.contains("..")
    }
}

public enum NativeMessage {
    public static func encode(_ value: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard data.count < 1024 * 1024 else { throw BridgeError.messageTooLarge }
        var count = UInt32(data.count).littleEndian
        var framed = withUnsafeBytes(of: &count) { Data($0) }
        framed.append(data)
        return framed
    }

    public static func read(from handle: FileHandle) throws -> [String: Any]? {
        guard let prefix = try readExactly(4, from: handle) else { return nil }
        let count = prefix.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        guard count > 0, count <= 1024 * 1024 else { throw BridgeError.messageTooLarge }
        guard let body = try readExactly(Int(count), from: handle),
              let message = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw BridgeError.invalidRequest
        }
        return message
    }

    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data? {
        var data = Data()
        while data.count < count {
            guard let fragment = try handle.read(upToCount: count - data.count), !fragment.isEmpty else {
                if data.isEmpty { return nil }
                throw BridgeError.invalidRequest
            }
            data.append(fragment)
        }
        return data
    }
}
