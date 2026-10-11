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
        for expected in ["I am studying ESL, in the section “2.3.1 Linear Models and Least Squares”.", "Source A: PDF page 31, the passage I am asking about, attached as image 1.",
                         "Text of Source A, extracted from the PDF", "<source_text>\nRSS(β) = Σ", "Question:\nWhy is RSS convex?\n", "My reasoning so far:\nIts Hessian",
                         "- Image 2: Equation (2.6), PDF page 31 (printed page 12).", "Design matrix (written X)", ": N × p. Scope: Chapter 2. Defined near PDF page 31.",
                         "- Image 3: Definition: Normal equations, PDF page 31 (printed page 12) · Used to find the minimum.",
                         "- Image 4: Reference 1, Hessian identity, PDF page 41 (printed page 21).",
                         QuestionStyle.hint.instruction, QuestionComposition.answerRules] {
            XCTAssertTrue(prompt.contains(expected), expected)
        }
        XCTAssertFalse(prompt.contains("Private reasoning stays local."), "Glossary context shares names, notation and scope only.")
        XCTAssertFalse(prompt.contains("A saved answer stays local."))
        XCTAssertEqual(composition.imageLabels, ["Source A", "Cited: Equation (2.6)", "Linked: Definition: Normal equations", "Reference 1: Hessian identity"])
        // The book and its pages come first, the question and the kind of help last.
        let order = ["I am studying", "Image 2:", "Image 4:", "<source_text>", "My glossary entries", "My reasoning so far", "Question:", QuestionStyle.hint.instruction]
        let positions = order.map { prompt.range(of: $0)?.lowerBound }
        XCTAssertFalse(positions.contains(nil))
        XCTAssertEqual(positions.compactMap { $0 }, positions.compactMap { $0 }.sorted(), "Context before the question; the question before the instruction.")

        let bare = QuestionComposition(bookTitle: "ESL", note: question, style: .explanation)
        XCTAssertFalse(bare.prompt.contains("Text of Source A"))
        XCTAssertFalse(bare.prompt.contains("section"))
        XCTAssertFalse(bare.prompt.contains("printed page"), "A page label equal to the PDF's number says nothing more.")
        XCTAssertEqual(bare.imageLabels, ["Source A"])
        XCTAssertEqual(QuestionStyle.nextStep.defaultQuestion, "What is the next step here?")
    }

    /// The printed page is named only when the book prints a number other than the PDF's own; the authors follow the
    /// title; ChatGPT's page can still recognise the draft as Lemma's.
    func testPrintedPagesAuthorsAndTheMarksLemmaRecognises() {
        var question = note("Explain this step.", kind: .question, page: 156)
        question.anchor.pageLabel = "157"
        var composition = QuestionComposition(bookTitle: "ISLP (An Introduction to Statistical Learning)", section: "4.4.1 Linear Discriminant Analysis for p = 1",
                                              note: question, sourceText: "Taking the log of (4.17)", style: .explanation)
        XCTAssertTrue(composition.prompt.contains("Source A: PDF page 157, the passage"), "The PDF's own label is not a printed page.")
        composition.printedPage = "148"
        composition.bookAuthors = "Gareth James, Daniela Witten, Trevor Hastie, Robert Tibshirani, Jonathan Taylor"
        composition.cited = [.init(title: "Equation (4.17)", pageIndex: 155, pageLabel: "147")]
        let prompt = composition.prompt
        XCTAssertTrue(prompt.hasPrefix("I am studying ISLP (An Introduction to Statistical Learning) by Gareth James, Daniela Witten, Trevor Hastie, Robert Tibshirani, Jonathan Taylor, in the section “4.4.1 Linear Discriminant Analysis for p = 1”."))
        XCTAssertTrue(prompt.contains("Source A: PDF page 157 (printed page 148), the passage I am asking about, attached as image 1."))
        XCTAssertTrue(prompt.contains("- Image 2: Equation (4.17), PDF page 156 (printed page 147)."))
        XCTAssertTrue(prompt.contains("filling in any step the book leaves out"), "Explain asks for the steps the book skips.")
        XCTAssertTrue(prompt.hasSuffix(QuestionComposition.answerRules))
        // dom.js recognises Lemma's own unsent drafts by these two marks.
        XCTAssertTrue(prompt.hasPrefix("I am studying "))
        XCTAssertNotNil(prompt.range(of: #"Source A: PDF page \d+"#, options: .regularExpression))
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
