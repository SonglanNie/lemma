import Foundation

/// Review cards as a text file Anki imports (File → Import): tab-separated front, back and tags, with the source crop
/// embedded in the front as an image, so the deck needs no separate media folder.
public enum AnkiExport {
    public struct Card: Equatable, Sendable {
        public var front: String
        public var back: String
        public var tags: [String]
        public init(front: String, back: String, tags: [String]) { self.front = front; self.back = back; self.tags = tags }
    }

    /// One card per note in the review deck: the recall prompt (or the note's title) and the source image on the front;
    /// the reader's answer, reasoning and saved explanation on the back, with the page.
    public static func cards(for workspace: StudyWorkspace, image: (StudyNote) -> Data?) -> [Card] {
        workspace.notes.filter(\.isInReview).map { note in
            let prompt = note.recallPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            var front = "<div>\(html(prompt.isEmpty ? note.title : prompt))</div>"
            if let data = image(note) {
                front += "<div><img src=\"data:image/png;base64,\(data.base64EncodedString())\" style=\"max-width:100%\"></div>"
            }
            var back: [String] = []
            for part in [note.reviewAnswer, note.body, note.explanation?.body ?? ""] where !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                back.append("<div>\(html(part))</div>")
            }
            if !note.anchor.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                back.append("<div style=\"color:#666\"><i>\(html(String(note.anchor.quote.prefix(600))))</i></div>")
            }
            back.append("<div style=\"color:#888;font-size:85%\">\(html(workspace.title)) · page \(html(note.anchor.pageLabel))</div>")
            return Card(front: front, back: back.joined(), tags: ["lemma", note.kind.rawValue])
        }
    }

    /// The file's text, with the header lines Anki 2.1.55+ reads (separator, HTML, tags column, deck).
    public static func text(_ cards: [Card], deck: String) -> String {
        var lines = ["#separator:tab", "#html:true", "#tags column:3", "#deck:\(deck.replacingOccurrences(of: "\t", with: " "))"]
        for card in cards {
            lines.append([field(card.front), field(card.back), card.tags.joined(separator: " ")].joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func field(_ text: String) -> String { text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: "<br>") }

    static func html(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
