import XCTest
import LemmaCore

final class QuestionComposerTests: XCTestCase {
    private func note(_ title: String, kind: NoteKind, page: Int, names: String = "", notation: String = "", scope: String = "", body: String = "") -> StudyNote {
        var note = StudyNote(anchor: SourceAnchor(pageIndex: page, pageLabel: "\(page + 1)", region: PageRegion(x: 0, y: 0, width: 10, height: 10), quote: "", imageName: "\(UUID()).png"),
                             question: title, body: body, kind: kind)
        note.lookupTerms = names; note.notation = notation; note.scope = scope
        return note
    }

    func testCompositionNamesEveryIncludedItemAndNumbersImagesInOrder() {
        var question = note("Why is RSS convex?", kind: .question, page: 30)
        question.body = "Its Hessian looks positive semidefinite."
        var composition = QuestionComposition(bookTitle: "ESL", section: "2.3.1 Linear Models and Least Squares", note: question,
                                              sourceText: "RSS(β) = Σ (yi − xiT β)2. (2.3)", style: .hint)
        composition.cited = [.init(title: "Equation (2.6)", pageIndex: 30, pageLabel: "12")]
        var glossaryNote = note("Design matrix", kind: .notation, page: 30, names: "X\ndesign matrix", notation: "N × p", scope: "Chapter 2", body: "Private reasoning stays local.")
        glossaryNote.explanation = SavedExplanation(body: "A saved answer stays local.")
        composition.glossary = [.init(note: glossaryNote)]
        composition.linked = [.init(title: "Definition: Normal equations", pageIndex: 30, pageLabel: "12", note: "Used to find the minimum.")]
        composition.pins = [.init(title: "Hessian identity", pageIndex: 40, pageLabel: "21")]
        let prompt = composition.prompt
        for expected in ["I am studying ESL, in the section “2.3.1 Linear Models and Least Squares”.", "shown in attached image 1",
                         "Text layer of Source A", "RSS(β) = Σ", "Question:\nWhy is RSS convex?", "My reasoning so far:\nIts Hessian",
                         "- Image 2: Equation (2.6), PDF page 31, label 12.", "Design matrix (written X)", ": N × p. Scope: Chapter 2. Defined near PDF page 31.",
                         "- Image 3: Definition: Normal equations, PDF page 31 · Used to find the minimum.", "Reference 1 (image 4): Hessian identity, PDF page 41, label 21.",
                         QuestionStyle.hint.instruction] {
            XCTAssertTrue(prompt.contains(expected), expected)
        }
        XCTAssertFalse(prompt.contains("Private reasoning stays local."), "Glossary context shares names, notation and scope only.")
        XCTAssertFalse(prompt.contains("A saved answer stays local."))
        XCTAssertEqual(composition.imageLabels, ["Source A", "Cited: Equation (2.6)", "Linked: Definition: Normal equations", "Reference 1: Hessian identity"])

        let bare = QuestionComposition(bookTitle: "ESL", note: question, style: .explanation)
        XCTAssertFalse(bare.prompt.contains("Text layer"))
        XCTAssertFalse(bare.prompt.contains("section"))
        XCTAssertEqual(bare.imageLabels, ["Source A"])
        XCTAssertEqual(QuestionStyle.nextStep.defaultQuestion, "What is the next step here?")
    }

    func testGlossaryMatchingUsesWholeTermsAndSymbolCase() {
        let design = note("Design matrix", kind: .notation, page: 10, names: "X\ndesign matrix")
        let lowerX = note("Input vector", kind: .notation, page: 12, names: "x")
        let ridge = note("Ridge penalty", kind: .definition, page: 50, names: "λ")
        let theorem = note("Gauss–Markov theorem", kind: .theorem, page: 30)
        let question = note("Design matrix", kind: .question, page: 11)
        let notes = [design, lowerX, ridge, theorem, question]
        let found = GlossaryMatcher.entries(mentionedIn: "where X is an N × p matrix and the Design   Matrix has full rank", from: notes, near: 20)
        XCTAssertEqual(found.map(\.id), [design.id], "Single symbols keep case; questions are not glossary entries.")
        XCTAssertEqual(GlossaryMatcher.entries(mentionedIn: "Each x is an input; λ ≥ 0.", from: notes, near: 20).map(\.id), [lowerX.id, ridge.id],
                       "Entries before the passage come first, then later ones.")
        XCTAssertTrue(GlossaryMatcher.entries(mentionedIn: "Matrices and XX are different words", from: notes, near: 20).isEmpty)
        XCTAssertEqual(GlossaryMatcher.entries(mentionedIn: "By the Gauss–Markov theorem", from: notes, near: 20).map(\.id), [theorem.id])
        XCTAssertTrue(GlossaryMatcher.entries(mentionedIn: "X and x", from: notes, near: 20, excluding: design.id).allSatisfy { $0.id != design.id })
        XCTAssertEqual(GlossaryMatcher.entries(mentionedIn: "X and x and λ", from: notes, near: 20, limit: 2).count, 2)
    }
}
