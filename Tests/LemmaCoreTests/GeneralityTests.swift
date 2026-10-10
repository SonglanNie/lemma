import XCTest
import PDFKit
@testable import LemmaCore

/// The book analysis on documents typeset differently from ESL: LaTeX articles with undotted equation numbers and
/// numeric citations, a book with chapters, an index and author–year citations, and an amsart paper with equation
/// numbers on the left and alphabetic citation keys. The fixtures are compiled from the `.tex` files beside them.
final class GeneralityTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "pdf", subdirectory: "Fixtures"), "Missing fixture \(name).pdf")
    }

    private func analyze(_ name: String) throws -> BookAnalysis {
        let url = try fixture(name)
        let document = try XCTUnwrap(PDFDocument(url: url))
        return try XCTUnwrap(BookAnalyzer.analyze(document: document, outline: OutlineReader.items(in: document)))
    }

    func testArticleWithUndottedEquationsNumericCitationsAndProofs() throws {
        let analysis = try analyze("article-numeric")
        let keys = Set(analysis.definitions.map(\.key))
        for number in ["1", "2", "3"] { XCTAssertTrue(keys.contains(ReferenceKey(kind: .equation, number: number)), "Equation (\(number)) is defined") }
        XCTAssertEqual(analysis.plainEquationLabels(), ["1", "2", "3"])
        XCTAssertTrue(keys.contains(ReferenceKey(kind: .figure, number: "1")), "“Figure 1:” on the reference list's page is still a caption.")
        XCTAssertTrue(keys.contains(ReferenceKey(kind: .table, number: "1")))
        for (name, number) in [("Definition", "1"), ("Lemma", "1"), ("Theorem", "2"), ("Corollary", "3")] {
            XCTAssertTrue(keys.contains(ReferenceKey(kind: .theorem, number: number, name: name)), "\(name) \(number) is defined")
        }
        let equationOne = analysis.mentions.filter { $0.key == ReferenceKey(kind: .equation, number: "1") }
        XCTAssertGreaterThanOrEqual(equationOne.count, 2, "“(1)” in the text refers to equation (1) once the document is known to define it.")

        XCTAssertEqual(analysis.bibliography.map(\.label), ["1", "2", "3"])
        let pointer = try XCTUnwrap(analysis.citations.first { $0.text.contains("Theorem 2") }, "“[3, Theorem 2]” is a citation of [3].")
        XCTAssertEqual(pointer.entryIDs.map { analysis.bibliography[$0].label }, ["3"])

        let structure = analysis.structure
        XCTAssertEqual(structure.proofs.count, 2)
        XCTAssertEqual(Set(structure.proofs.compactMap(\.statement)), [ReferenceKey(kind: .theorem, number: "1", name: "Lemma"),
                                                                        ReferenceKey(kind: .theorem, number: "2", name: "Theorem")])
        XCTAssertTrue(structure.proofs.allSatisfy(\.endsWithMark), "amsthm's open box, drawn with rules, ends each proof.")
        let theorem = ReferenceKey(kind: .theorem, number: "2", name: "Theorem")
        XCTAssertEqual(structure.statement(theorem)?.title, "Shrinkage")
        let uses = Set(structure.uses(theorem).map(\.to))
        XCTAssertTrue(uses.contains(ReferenceKey(kind: .theorem, number: "1", name: "Lemma")), "The proof of Theorem 2 uses Lemma 1: \(uses)")
        XCTAssertFalse(uses.contains(ReferenceKey(kind: .figure, number: "1")), "The sentence after the proof's end mark is not part of the proof.")
        XCTAssertEqual(analysis.headings.map(\.title), ["1 Introduction", "2 Ridge regression"], "A PDF without an outline gets one from its bold numbered headings.")
    }

    func testBookWithChaptersIndexAuthorYearCitationsAndProofs() throws {
        let analysis = try analyze("book-chapters")
        XCTAssertEqual(analysis.numbering?.label(for: 4), "1", "Printed numbers come from the PDF's page labels.")
        let keys = Set(analysis.definitions.map(\.key))
        for number in ["1.1", "1.2", "1.3", "2.1"] { XCTAssertTrue(keys.contains(ReferenceKey(kind: .equation, number: number))) }
        XCTAssertTrue(keys.contains(ReferenceKey(kind: .theorem, number: "1.3", name: "Theorem")))
        XCTAssertTrue(keys.contains(ReferenceKey(kind: .exercise, number: "1.1")))
        XCTAssertEqual(analysis.index.count, 8)
        XCTAssertEqual(analysis.index.first { $0.term == "smoothing spline" }?.locators.map(\.text), ["3–4"])
        XCTAssertEqual(analysis.bibliography.count, 5)
        XCTAssertGreaterThanOrEqual(analysis.citations.count, 6)

        let structure = analysis.structure
        XCTAssertEqual(structure.proofs.count, 4)
        XCTAssertTrue(structure.proofs.allSatisfy { $0.statement != nil }, "Each proof follows the statement it proves.")
        let definition = ReferenceKey(kind: .theorem, number: "1.1", name: "Definition")
        let users = Set(structure.usedBy(definition).map(\.from))
        XCTAssertTrue(users.contains(ReferenceKey(kind: .theorem, number: "1.3", name: "Theorem")))
        XCTAssertTrue(users.contains(ReferenceKey(kind: .theorem, number: "2.1", name: "Theorem")), "Theorem 2.1's proof cites Definition 1.1 from another chapter.")
        let proposition = ReferenceKey(kind: .theorem, number: "1.4", name: "Proposition")
        XCTAssertFalse(structure.uses(proposition).contains { $0.to.kind == .figure }, "The proof ends at its box, before the text that cites Figure 1.1.")
    }

    func testLeftEquationLabelsAndAlphabeticCitationKeys() throws {
        let analysis = try analyze("leqno-alpha")
        let keys = Set(analysis.definitions.map(\.key))
        XCTAssertTrue(keys.contains(ReferenceKey(kind: .equation, number: "1")), "“(1)” at the left of a display is its label.")
        XCTAssertTrue(keys.contains(ReferenceKey(kind: .equation, number: "2")))
        XCTAssertEqual(analysis.bibliography.compactMap(\.label), ["CDS98", "CRT06", "CT05", "Don06"])
        let cited = Set(analysis.citations.flatMap { $0.entryIDs.compactMap { analysis.bibliography[$0].label } })
        XCTAssertEqual(cited, ["CDS98", "CRT06", "CT05", "Don06"])
        XCTAssertTrue(analysis.citations.contains { $0.text.contains("Theorem 1") }, "“[CRT06, Theorem 1]” is a citation with a pointer.")
        XCTAssertFalse(analysis.mentions.contains { $0.key == ReferenceKey(kind: .theorem, number: "1", name: "Theorem") && $0.pageIndex == 0 && $0.key.number == "1" && analysis.definitionsByKey()[$0.key] != nil },
                       "Theorem 1 of the cited work is not this paper's statement.")
        XCTAssertEqual(analysis.structure.proofs.count, 2)
        XCTAssertTrue(analysis.structure.proofs.allSatisfy { $0.endsWithMark && $0.statement != nil })
        XCTAssertTrue(analysis.structure.uses(ReferenceKey(kind: .theorem, number: "2.1", name: "Theorem")).contains { $0.to == ReferenceKey(kind: .theorem, number: "2.2", name: "Lemma") })
    }

    func testExerciseSectionsSmallCapitalHeadsAndSolutionMarks() throws {
        let analysis = try analyze("exercises-smallcaps")
        let keys = Set(analysis.definitions.map(\.key))
        XCTAssertTrue(keys.contains(ReferenceKey(kind: .theorem, number: "1.1", name: "Definition")),
                      "“definition 1.1 (Weak learnability)” in small capitals, set apart from the text above, is a statement head.")
        XCTAssertTrue(keys.contains(ReferenceKey(kind: .theorem, number: "1.2", name: "Lemma")))
        let exercises = Set(analysis.definitions.filter { $0.key.kind == .exercise }.map(\.key.number))
        XCTAssertEqual(exercises, ["1.3.4", "1.3.5", "1.3.6", "1.3.7", "2.1"],
                       "Numbered items of the Exercises section from 1.3.4 on, and “◁ Exercise 2.1.”; not “1.2 for the margin.” or the contents.")
        let mentions = analysis.mentions.filter { $0.key.kind == .exercise }
        XCTAssertGreaterThanOrEqual(mentions.count, 4)
        XCTAssertTrue(mentions.allSatisfy { keys.contains($0.key) }, "Every mention of an exercise finds it: \(mentions.map(\.key.number))")
        // “Exercises 64” in a contents line or a running head names no exercise; “Hypothesis 2.1” is singular.
        XCTAssertTrue(PageReferenceAnalyzer.isPluralHead("Exercises 64"))
        XCTAssertTrue(PageReferenceAnalyzer.isPluralHead("Figures 2.1"))
        XCTAssertFalse(PageReferenceAnalyzer.isPluralHead("Hypothesis 2.1"))
        XCTAssertFalse(PageReferenceAnalyzer.isPluralHead("Exercise 2.1"))
    }

    func testScannerReadsLowerCaseHeadsJoinedWordsAndUndottedEquations() {
        func keys(_ text: String, plain: Set<String> = []) -> [String] { ReferenceScanner.mentions(in: text, plainEquations: plain).map(\.key.spokenTitle) }
        XCTAssertEqual(keys("as in figure 3.7 and section 2.3, see example 3.12"), ["Figure 3.7", "Section 2.3", "Example 3.12"])
        XCTAssertEqual(keys("separately, Figure3.15illustrates the difficulty"), ["Figure 3.15"], "Some PDFs drop the spaces around numbers.")
        XCTAssertEqual(keys("from (1) and (12) we get (3)", plain: ["1", "12"]), ["Equation (1)", "Equation (12)"])
        XCTAssertEqual(keys("from (1) and (12)"), [], "Undotted numbers stay ambiguous unless the document defines such equations.")
        XCTAssertEqual(keys("Corollary1.3.4 and lemma 16.2"), ["Corollary 1.3.4", "Lemma 16.2"])
        XCTAssertEqual(keys("appendix equation (A.1) holds"), ["Equation (A.1)"])
    }

    func testSectionNumbersRejectTableValues() {
        for value in ["0.50", "25.03", "6.66", "62.1", "4.82"] { XCTAssertFalse(ReferenceScanner.isSectionNumber(value), value) }
        for value in ["0.1", "3.4.1", "2.3", "14.10", "11.21"] { XCTAssertTrue(ReferenceScanner.isSectionNumber(value), value) }
    }

    func testKeyResolverFollowsSharedCountersOnly() {
        func target(_ key: ReferenceKey) -> ReferenceTarget {
            ReferenceTarget(key: key, pageIndex: 0, anchor: PageRegion(x: 0, y: 0, width: 1, height: 1), region: PageRegion(x: 0, y: 0, width: 1, height: 1), origin: .text)
        }
        let shared = KeyResolver(definitions: [target(ReferenceKey(kind: .theorem, number: "3.59", name: "Result")),
                                               target(ReferenceKey(kind: .theorem, number: "3.60", name: "Definition"))], itemsByNumber: true)
        XCTAssertEqual(shared.resolve(ReferenceKey(kind: .theorem, number: "3.59", name: "Theorem"))?.name, "Result")
        XCTAssertEqual(shared.resolve(ReferenceKey(kind: .equation, number: "3.60"))?.name, "Definition", "“(3.60)” cites item 3.60 when every item shares one sequence.")
        let separate = KeyResolver(definitions: [target(ReferenceKey(kind: .theorem, number: "1", name: "Lemma")),
                                                 target(ReferenceKey(kind: .theorem, number: "1", name: "Definition")),
                                                 target(ReferenceKey(kind: .theorem, number: "2", name: "Theorem"))])
        XCTAssertNil(separate.resolve(ReferenceKey(kind: .theorem, number: "2", name: "Lemma")), "Separate counters: Lemma 2 is not Theorem 2.")
        XCTAssertNil(separate.resolve(ReferenceKey(kind: .equation, number: "2")))
    }

    func testColumnEdgesThatCrossDoNotTrap() {
        // The most common left edge lies right of the most common right edge (ragged, indented lines): a valid range comes back.
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        var fragments: [LayoutFragment] = []
        for row in 0..<6 { fragments.append(LayoutFragment(text: "indented line of text \(row)", bounds: CGRect(x: 300, y: 700 - CGFloat(row) * 12, width: 200, height: 10))) }
        for row in 0..<6 { fragments.append(LayoutFragment(text: "short line \(row)", bounds: CGRect(x: 100, y: 600 - CGFloat(row) * 12, width: 150, height: 10))) }
        let column = ReferenceLayout.column(containing: 392, near: 622, fragments: fragments, page: page)
        XCTAssertLessThanOrEqual(column.lowerBound, column.upperBound)
    }

    func testJustifiedEdgesCountTogetherAcrossFractionsOfAPoint() {
        // MacKay: the text column's lines end at 395.9–396.6, three margin notes at 547.9.
        let edge = ReferenceLayout.edge([395.9, 396.1, 396.4, 396.6, 547.9, 547.9, 547.9], fallback: 0)
        XCTAssertEqual(edge, 396.25, accuracy: 0.5)
    }

    func testCitationScannerReadsAlphabeticKeysAndPointers() {
        let mentions = CitationScanner.mentions(in: "basis pursuit [CDS98, CT05] and [CRT06, Theorem 1], not [Fig. 2]", labels: ["CDS98", "CT05", "CRT06"])
        XCTAssertEqual(mentions.compactMap(\.label), ["CDS98", "CT05", "CRT06"])
        let numbered = CitationScanner.mentions(in: "see [72, Theorem 1.4] and [3]", numeric: true)
        XCTAssertEqual(numbered.compactMap(\.label), ["72", "3"])
        XCTAssertEqual(BibliographyParser.numericLabel("[ABB+99] E. Anderson, Z. Bai"), "ABB+99")
        XCTAssertEqual(BibliographyParser.authorsAndYear("[CRT06] E. J. Candès, J. Romberg and T. Tao, Stable signal recovery, 2006.").0.first, "Candès")
    }

    func testOutlineRepairNeverRemovesSpaces() {
        XCTAssertEqual(OutlineTitle.repaired("About this book", pageText: "Aboutthisbook\nThis book is about"), "About this book")
        XCTAssertEqual(OutlineTitle.repaired("3.4.1Ridge Regression", pageText: "3.4.1 Ridge Regression\nRidge"), "3.4.1 Ridge Regression")
    }

    func testStatementBodiesAreNotTerms() {
        let text = "Theorem 4.1. Assume that the function f has bounded gradients. A training set is called balanced if"
        let ns = text as NSString
        let body = EmphasisRun(text: "Assume that the function", range: ns.range(of: "Assume that the function"), style: .italic)
        let term = EmphasisRun(text: "balanced", range: ns.range(of: "balanced"), style: .italic)
        let candidates = TermCandidates.candidates(runs: [body, term], pageText: text)
        XCTAssertEqual(candidates.map(\.term), ["balanced"])
    }

    func testRunningHeadsAreReadFromTheTopRowWhateverItsMargin() {
        let box = CGRect(x: 0, y: 0, width: 612, height: 792)
        // Lebl's heads are 16.5 pt tall; Durrett's sit 60 pt below the top edge.
        let lines = [LayoutFragment(text: "2.3. LIMIT SUPERIOR", bounds: CGRect(x: 72, y: 726, width: 400, height: 16.5)),
                     LayoutFragment(text: "81", bounds: CGRect(x: 528, y: 726, width: 12, height: 16.5)),
                     LayoutFragment(text: "Exercise 2.3.5: a) Let x", bounds: CGRect(x: 72, y: 695, width: 300, height: 11)),
                     LayoutFragment(text: "body text continues here with words", bounds: CGRect(x: 72, y: 600, width: 400, height: 11))]
        let candidates = BookAnalyzer.runningHeadCandidates(lines, pageIndex: 80, box: box)
        XCTAssertEqual(candidates.map(\.0.value), [81])
    }
}

final class AnkiExportTests: XCTestCase {
    func testReviewCardsBecomeATabSeparatedAnkiFileWithImagesInline() {
        var workspace = StudyWorkspace(id: "w", title: "Notes on Linear Smoothers", sourcePath: "/b.pdf", sourceBookmark: nil, fingerprint: "w")
        let anchor = SourceAnchor(pageIndex: 4, pageLabel: "1", region: PageRegion(x: 0, y: 0, width: 10, height: 10), quote: "The hat matrix\tH is idempotent.", imageName: "a.png")
        var card = StudyNote(anchor: anchor, question: "Lemma 1.2", kind: .theorem)
        card.recallPrompt = "State Lemma 1.2 and its hypotheses."
        card.body = "H = X(XᵀX)⁻¹Xᵀ\nso H² = H."
        card.review = ReviewSchedule(dueAt: .now)
        let other = StudyNote(anchor: anchor, question: "Not in review")
        workspace.notes = [card, other]
        let cards = AnkiExport.cards(for: workspace) { _ in Data([0x89, 0x50]) }
        XCTAssertEqual(cards.count, 1, "Only notes in the review deck become cards.")
        XCTAssertTrue(cards[0].front.hasPrefix("<div>State Lemma 1.2 and its hypotheses.</div>"))
        XCTAssertTrue(cards[0].front.contains("data:image/png;base64,iVA="), "The source crop travels inside the card.")
        XCTAssertTrue(cards[0].back.contains("H = X(XᵀX)⁻¹Xᵀ<br>so H² = H."))
        let text = AnkiExport.text(cards, deck: "Lemma::Notes")
        let lines = text.split(separator: "\n")
        XCTAssertEqual(Array(lines.prefix(4)), ["#separator:tab", "#html:true", "#tags column:3", "#deck:Lemma::Notes"])
        XCTAssertEqual(lines[4].split(separator: "\t", omittingEmptySubsequences: false).count, 3, "Front, back and tags; tabs inside fields are removed.")
        XCTAssertTrue(lines[4].hasSuffix("\tlemma theorem"))
    }
}

final class NotationTests: XCTestCase {
    private func meanings(_ text: String) -> [String: String] {
        Dictionary(Notation.definitions(in: text, pageIndex: 0).map { ($0.symbol, $0.meaning) }, uniquingKeysWith: { first, _ in first })
    }

    func testSentencesThatDefineSymbols() {
        XCTAssertEqual(meanings("Here λ ≥ 0 is a complexity parameter that controls the amount of shrinkage.")["λ"],
                       "complexity parameter that controls the amount of shrinkage")
        XCTAssertEqual(meanings("Let X denote the N × p input matrix.")["X"], "N × p input matrix")
        XCTAssertEqual(meanings("We use R to denote the set of real numbers, R+ to denote the set of nonnegative real numbers.")["R"],
                       "set of real numbers", "The meaning stops at the next symbol's definition.")
        XCTAssertEqual(meanings("Let C ⊆ Rn be a convex set, with x1, . . . , xk ∈ C.")["C"], "convex set", "…and at a clause that moves on.")
        XCTAssertEqual(meanings("(where n is its dimension), and therefore the generic results apply.")["n"], "its dimension")
        XCTAssertNil(meanings("We write x ⪰K y for y ⪯K x.")["x"], "The notation defined there is a relation, not x.")
    }

    func testSymbolsUsedSurviveACombiningMarkAfterALineBreak() {
        // Mathematics for Machine Learning sets ∉ as a line break followed by U+0338: one composed sequence for
        // NSString, two characters for Swift. Scanning such a page stopped the app before 3.0.
        let index = NotationIndex(Notation.definitions(in: "Let X denote the input matrix.", pageIndex: 0))
        let text = "where X is given and y\n\u{0338}∈ S, so X has rank p."
        let found = index.symbols(usedIn: text, pageIndex: 1)
        XCTAssertEqual(found.map(\.symbol), ["X"])
    }

    func testTheMeaningInForceIsTheLatestBeforeThePlace() {
        let index = NotationIndex(Notation.definitions(in: "Let X denote the input matrix.", pageIndex: 2)
                                  + Notation.definitions(in: "Now X is a random vector.", pageIndex: 9))
        XCTAssertEqual(index.definition(of: "X", at: TextPoint(pageIndex: 5, location: 0))?.definition.meaning, "input matrix")
        XCTAssertEqual(index.definition(of: "X", at: TextPoint(pageIndex: 12, location: 0))?.definition.meaning, "random vector")
        XCTAssertEqual(index.definition(of: "X", at: TextPoint(pageIndex: 0, location: 0))?.later, true, "Before page 3 it is only defined later.")
    }
}
