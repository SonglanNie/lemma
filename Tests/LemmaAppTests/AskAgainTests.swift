import XCTest
import AppKit
import PDFKit
import LemmaCore
@testable import Lemma

/// The Questions panel's recovery: a failed or cancelled question is asked again as a new request with the same draft
/// and images, and its answer reaches the same note.
final class AskAgainTests: XCTestCase {
    @MainActor
    func testAFailedQuestionIsAskedAgainWithTheSameDraftAndImages() async throws {
        let (store, root) = try fixture()
        // A stand-in Claude Code that fails the first question (as an overloaded service would) and answers the next.
        store.questions.executableOverrides[.claudeCode] = try standIn(root, script: """
        if [ ! -f "\(root.path)/failed-once" ]; then
          touch "\(root.path)/failed-once"
          printf '%s\\n' '{"type":"result","is_error":true,"result":"Overloaded. Try again later."}'
          exit 1
        fi
        cat > received-input
        printf '%s\\n' '{"type":"result","is_error":false,"result":"Full rank gives uniqueness."}'
        """)
        let note = try XCTUnwrap(store.currentNote), bookID = try XCTUnwrap(store.workspace?.id)
        let image = try Data(contentsOf: store.repository.assetURL(workspaceID: bookID, name: note.anchor.imageName))
        store.askWeb(mode: .askAndSave, content: QuestionContent(prompt: "I am studying a book.\nSource A: PDF page 1.\n\nQuestion:\nWhy full rank?\n\nExplain it.", images: [("Source A", image)]),
                     noteID: note.id, provider: .claudeCode)
        try await wait { store.questions.jobs.first?.finished == true }
        let failed = try XCTUnwrap(store.questions.jobs.first)
        XCTAssertTrue(failed.failed); XCTAssertTrue(failed.message.contains("Overloaded"), failed.message)
        XCTAssertEqual(failed.title, "Why full rank?", "The list names the note's question.")
        XCTAssertNil(store.currentNote?.pendingRequestID, "A failed question leaves its note free to ask again.")

        store.questions.retry(failed)
        XCTAssertEqual(store.questions.jobs.count, 2)
        let again = try XCTUnwrap(store.questions.jobs.first)
        XCTAssertNotEqual(again.id, failed.id, "A new request, never the failed one resent.")
        XCTAssertEqual(again.packet.prompt, failed.packet.prompt)
        XCTAssertEqual(again.packet.images.map(\.label), failed.packet.images.map(\.label))
        XCTAssertEqual(again.packet.noteID, note.id)
        XCTAssertEqual(store.currentNote?.pendingRequestID, again.id)
        XCTAssertEqual(try Data(contentsOf: store.mailbox.directory(again.id).appendingPathComponent("source-1.png")), image)
        try await wait { again.finished }
        XCTAssertFalse(again.failed, again.message)
        let saved = try XCTUnwrap(store.repository.load(id: bookID)?.notes.first { $0.id == note.id })
        XCTAssertEqual(saved.explanation?.body, "Full rank gives uniqueness.")
        XCTAssertNil(saved.pendingRequestID)
        store.questions.shutdown()
    }

    @MainActor
    func testACancelledQuestionSaysSoAndCanBeAskedAgain() async throws {
        let (store, root) = try fixture()
        store.questions.executableOverrides[.claudeCode] = try standIn(root, script: """
        cat > received-input
        sleep 5
        printf '%s\\n' '{"type":"result","is_error":false,"result":"Too late."}'
        """)
        let note = try XCTUnwrap(store.currentNote)
        store.askWeb(mode: .askAndSave, content: QuestionContent(prompt: "Question:\nWhy?", images: []), noteID: note.id, provider: .claudeCode)
        let job = try XCTUnwrap(store.questions.jobs.first)
        store.cancelQuestion(noteID: note.id)
        XCTAssertTrue(job.finished); XCTAssertTrue(job.failed)
        XCTAssertEqual(job.failureReason, "cancelled")
        XCTAssertEqual(QuestionJobStatusIcon.state(job), "cancelled")
        XCTAssertNil(store.currentNote?.pendingRequestID)
        store.questions.retry(job)
        XCTAssertEqual(store.questions.jobs.count, 2)
        XCTAssertEqual(store.currentNote?.pendingRequestID, store.questions.jobs.first?.id)
        store.questions.shutdown()
    }

    /// macOS's smart quotes turned the draft's `"""` into `“”"` as Lemma typed it into ChatGPT, so the question no longer
    /// matched (October 2026). Lemma turns WebKit's text substitutions off before its first web view exists.
    @MainActor
    func testWebKitTextSubstitutionsAreOffForTheChatGPTPage() {
        ChatGPTSession.disableTextSubstitutions()
        for key in ["WebAutomaticQuoteSubstitutionEnabled", "WebAutomaticDashSubstitutionEnabled", "WebAutomaticTextReplacementEnabled", "WebAutomaticSpellingCorrectionEnabled"] {
            XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Bool, false, key)
        }
    }

    @MainActor
    func testTheQuestionListNamesTheDraftsQuestion() {
        XCTAssertEqual(QuestionJob.question(in: "I am studying ESL.\n\nQuestion:\nWhy is RSS convex?\nAnd unique?\n\nExplain it step by step."), "Why is RSS convex?\nAnd unique?")
        XCTAssertEqual(QuestionJob.question(in: "No heading here"), "No heading here")
    }

    @MainActor
    private func fixture() throws -> (StudyStore, URL) {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        addTeardownBlock { UserDefaults.standard.set(previous, forKey: "lastWorkspaceID"); try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("fixture.pdf")
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 300, height: 400), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("X transpose X" as NSString).draw(at: CGPoint(x: 30, y: 50), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black])
            return true
        }
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0); XCTAssertTrue(document.write(to: source))
        let store = StudyStore(root: root.appendingPathComponent("support")); store.open(source)
        store.questions.loginShellPath = { [] }
        store.questions.keys = MemoryAPIKeyStore()
        store.reader.selection = (0, CGRect(x: 20, y: 35, width: 240, height: 60), "X transpose X"); store.addNote()
        store.updateNote { $0.question = "Why full rank?" }
        return (store, root)
    }

    /// A stand-in Claude Code: signed in, then `script` answers the question.
    private func standIn(_ root: URL, script: String) throws -> URL {
        let file = root.appendingPathComponent("claude")
        try """
        #!/bin/sh
        if [ "$1" = auth ]; then
          printf '%s\\n' '{"loggedIn":true,"authMethod":"claude.ai"}'
          exit 0
        fi
        \(script)
        """.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    @MainActor private func wait(seconds: TimeInterval = 15, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(predicate())
    }
}
