import Foundation
import LemmaCore

let root: URL
if let override = ProcessInfo.processInfo.environment["LEMMA_SUPPORT_DIR"] {
    root = URL(fileURLWithPath: override, isDirectory: true)
} else {
    root = WorkspaceRepository.defaultRoot
}
let mailbox = BrowserMailbox(root: root)

func respond(to message: [String: Any]) throws -> [String: Any] {
    guard let operation = message["operation"] as? String else { throw BridgeError.invalidRequest }
    if operation == "ping" { return ["ok": true, "version": 1] }
    if operation == "arxiv" {
        guard let id = message["arxivID"] as? String, ArxivIdentifier.parse(id) == id, let link = ArxivIdentifier.link(id) else { throw BridgeError.invalidRequest }
        let bundle = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard bundle.pathExtension == "app" else { throw BridgeError.invalidRequest }
        let launch = Process(); launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launch.arguments = ["-a", bundle.path, link.absoluteString]
        launch.standardOutput = FileHandle.standardError; launch.standardError = FileHandle.standardError
        try launch.run(); launch.waitUntilExit()
        guard launch.terminationStatus == 0 else { throw BridgeError.invalidRequest }
        return ["ok": true, "arxivID": id]
    }
    guard let rawID = message["requestID"] as? String, let id = UUID(uuidString: rawID) else {
        throw BridgeError.invalidRequest
    }
    switch operation {
    case "packet":
        let packet = try mailbox.packet(id)
        let data = try WorkspaceRepository.encoder.encode(packet)
        return ["ok": true, "packet": try JSONSerialization.jsonObject(with: data)]
    case "image":
        guard let name = message["name"] as? String, let index = message["index"] as? Int else {
            throw BridgeError.invalidImage
        }
        let (data, done) = try mailbox.imageChunk(requestID: id, name: name, index: index)
        return ["ok": true, "data": data.base64EncodedString(), "done": done]
    case "result":
        guard let status = message["status"] as? String else { throw BridgeError.invalidRequest }
        let result = BrowserResult(requestID: id, status: status, answer: message["answer"] as? String,
                                   conversationURL: message["conversationURL"] as? String,
                                   message: message["message"] as? String)
        try mailbox.saveResult(result)
        return ["ok": true]
    default:
        throw BridgeError.invalidRequest
    }
}

do {
    while let message = try NativeMessage.read(from: .standardInput) {
        var response: [String: Any]
        do { response = try respond(to: message) }
        catch { response = ["ok": false, "error": error.localizedDescription] }
        response["callID"] = message["callID"]
        try FileHandle.standardOutput.write(contentsOf: NativeMessage.encode(response))
    }
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Lemma browser host: \(error.localizedDescription)\n".utf8))
    exit(1)
}
