import XCTest
import LemmaCore

final class BrowserTests: XCTestCase {
    func testMailboxTransfersOnlyPreparedImagesAndLinksResult() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let mailbox = BrowserMailbox(root: root)
        let bytes = Data((0..<(BrowserMailbox.chunkSize * 2 + 7)).map { UInt8($0 % 251) })
        let packet = BrowserPacket(noteID: UUID(), mode: .askAndSave, prompt: "What about β̂?", images: [BrowserImage(name: "source.png", label: "Source A", byteCount: bytes.count)])
        try mailbox.prepare(packet, imageData: ["source.png": bytes])
        var received = Data()
        for index in 0..<3 {
            let (chunk, done) = try mailbox.imageChunk(requestID: packet.id, name: "source.png", index: index)
            received.append(chunk)
            XCTAssertEqual(done, index == 2)
        }
        XCTAssertEqual(received, bytes)
        XCTAssertThrowsError(try mailbox.imageChunk(requestID: packet.id, name: "../request.json", index: 0))
        XCTAssertThrowsError(try mailbox.imageChunk(requestID: packet.id, name: "unselected.png", index: 0))
        XCTAssertThrowsError(try mailbox.packet(packet.id, now: .now.addingTimeInterval(3601)))
        XCTAssertThrowsError(try mailbox.saveResult(BrowserResult(requestID: packet.id, status: "complete", answer: "a", conversationURL: "https://example.com/c/1")))
        try mailbox.saveResult(BrowserResult(requestID: packet.id, status: "complete", answer: "$X^\\top X$", conversationURL: "https://chatgpt.com/c/test"))
        XCTAssertEqual(try mailbox.result(packet.id)?.answer, "$X^\\top X$")
        XCTAssertEqual(try mailbox.packet(packet.id).noteID, packet.noteID)
    }

    func testNativeFramePreservesUnicodeAndRejectsTruncation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let encoded = try NativeMessage.encode(["prompt": "β̂ and café", "callID": 3])
        try encoded.write(to: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        XCTAssertEqual(try NativeMessage.read(from: handle)?["prompt"] as? String, "β̂ and café")
        XCTAssertNil(try NativeMessage.read(from: handle))
        try encoded.dropLast().write(to: url)
        try handle.seek(toOffset: 0)
        XCTAssertThrowsError(try NativeMessage.read(from: handle))
    }
}
