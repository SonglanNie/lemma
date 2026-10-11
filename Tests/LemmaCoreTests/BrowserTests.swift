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

    /// Images and the draft can be fetched for an hour; an answer can still be saved for a day, since a reader may review
    /// a draft for a while and a thinking model may answer slowly.
    func testAnAnswerArrivingAfterAnHourIsStillSaved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let mailbox = BrowserMailbox(root: root)
        var packet = BrowserPacket(noteID: UUID(), mode: .draft, prompt: "Explain this step.", images: [BrowserImage(name: "source-1.png", label: "Source A", byteCount: 3)])
        packet.createdAt = .now.addingTimeInterval(-2 * 3600)
        try mailbox.prepare(packet, imageData: ["source-1.png": Data([1, 2, 3])])
        XCTAssertThrowsError(try mailbox.imageChunk(requestID: packet.id, name: "source-1.png", index: 0), "Transfers stop after an hour.")
        try mailbox.saveResult(BrowserResult(requestID: packet.id, status: "complete", answer: "Late but complete.", conversationURL: "https://chatgpt.com/c/late"))
        XCTAssertEqual(try mailbox.result(packet.id)?.answer, "Late but complete.")
        XCTAssertEqual(try mailbox.packet(packet.id, maximumAge: .infinity).prompt, "Explain this step.")
        var stale = BrowserPacket(noteID: UUID(), mode: .askAndSave, prompt: "Old", images: [])
        stale.createdAt = .now.addingTimeInterval(-2 * 86_400)
        try mailbox.prepare(stale, imageData: [:])
        XCTAssertThrowsError(try mailbox.saveResult(BrowserResult(requestID: stale.id, status: "complete", answer: "Too late")))
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
