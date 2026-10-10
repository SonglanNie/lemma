import Foundation

/// One server-sent event. All three providers stream answers this way: `event:` names it (Gemini leaves it out)
/// and `data:` carries one JSON object.
public struct ServerSentEvent: Equatable, Sendable {
    public var event: String
    public var data: String
    public init(event: String = "message", data: String) { self.event = event; self.data = data }
}

/// An incremental parser for `text/event-stream` (WHATWG): bytes may arrive split anywhere, lines end with LF or
/// CRLF, `:` lines are comments, consecutive `data:` lines join with newlines, and a blank line ends an event.
public struct ServerSentEventParser: Sendable {
    private var buffer: [UInt8] = []
    private var name = ""
    private var data: [String] = []

    public init() {}

    public mutating func feed<Bytes: Sequence>(_ bytes: Bytes) -> [ServerSentEvent] where Bytes.Element == UInt8 {
        buffer.append(contentsOf: bytes)
        var events: [ServerSentEvent] = []
        var start = 0
        while let newline = buffer[start...].firstIndex(of: 10) {
            var end = newline
            if end > start, buffer[end - 1] == 13 { end -= 1 }
            if let event = line(String(decoding: buffer[start..<end], as: UTF8.self)) { events.append(event) }
            start = newline + 1
        }
        buffer.removeFirst(start)
        return events
    }

    /// The end of the stream: a last line without a newline, then any event not yet closed by a blank line.
    public mutating func finish() -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []
        if !buffer.isEmpty {
            if buffer.last == 13 { buffer.removeLast() }
            if let event = line(String(decoding: buffer, as: UTF8.self)) { events.append(event) }
            buffer.removeAll()
        }
        if let event = dispatch() { events.append(event) }
        return events
    }

    private mutating func line(_ line: String) -> ServerSentEvent? {
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }
        var field = Substring(line), value = Substring("")
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
        }
        switch field {
        case "event": name = String(value)
        case "data": data.append(String(value))
        default: break
        }
        return nil
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer { name = ""; data = [] }
        guard !data.isEmpty else { return nil }
        return ServerSentEvent(event: name.isEmpty ? "message" : name, data: data.joined(separator: "\n"))
    }
}
