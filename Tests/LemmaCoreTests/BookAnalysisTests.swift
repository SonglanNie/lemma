import XCTest
import AppKit
import PDFKit
@testable import LemmaCore

final class BookAnalysisTests: XCTestCase {
    func testTextRepairJoinsLigaturesAccentsAndHyphenation() {
        XCTAssertEqual(TextRepair.repaired("B¨uhlmann and Hoﬀman, Aﬃne"), "Bühlmann and Hoffman, Affine")
        XCTAssertEqual(TextRepair.repaired("d´ej`a vu ¨"), "déj`a vu ¨", "A grave stays literal; a trailing spacing accent is kept.")
        XCTAssertEqual(TextRepair.folded("Bias–Variance  Trade-off"), "bias variance trade off")
        XCTAssertEqual(TextRepair.joinLines("Adaptive nearest neighbor meth-", "ods, 475–478"), "Adaptive nearest neighbor methods, 475–478")
        XCTAssertEqual(TextRepair.joinLines("Association rules, 492–495, 499–", "501"), "Association rules, 492–495, 499–501")
        XCTAssertEqual(TextRepair.joinLines("Akaike information criterion (AIC),", "230"), "Akaike information criterion (AIC), 230")
    }

    func testPageNumbersAreReadFromRunningHeads() {
        XCTAssertEqual(PageNumbering.candidateValue(inLine: "700 References")?.value, 700)
        XCTAssertEqual(PageNumbering.candidateValue(inLine: "2.3 Least Squares and Nearest Neighbors 13")?.value, 13)
        XCTAssertEqual(PageNumbering.candidateValue(inLine: "xiv Contents")?.style, .roman)
        XCTAssertEqual(PageNumbering.candidateValue(inLine: "xiv Contents")?.value, 14)
        XCTAssertNil(PageNumbering.candidateValue(inLine: "This is page"))
        XCTAssertNil(PageNumbering.candidateValue(inLine: "Overview of Supervised Learning"))

        // A book like ESL: roman front matter on physical pages 2–19, arabic from physical page 20 (printed 1),
        // chapter openings without running heads, and one stray number in a heading.
        var candidates: [PageNumbering.Candidate] = (1...18).map { .init(pageIndex: $0, value: $0 + 4, style: .roman) }
        candidates += (20..<300).filter { $0 % 25 != 0 }.map { .init(pageIndex: $0, value: $0 - 18, style: .arabic) }
        candidates.append(.init(pageIndex: 150, value: 3, style: .arabic))
        let numbering = try! XCTUnwrap(PageNumbering.infer(from: candidates, pageCount: 300))
        XCTAssertEqual(numbering.label(for: 30), "12")
        XCTAssertEqual(numbering.label(for: 19), "1", "The first chapter's opening page has no running head but continues the run.")
        XCTAssertEqual(numbering.label(for: 25), "7", "Pages without a running head take the surrounding offset.")
        XCTAssertEqual(numbering.label(for: 10), "xiv")
        XCTAssertEqual(numbering.label(for: 150), "132", "A stray number does not break the run.")
        XCTAssertEqual(numbering.pageIndex(forLabel: "124"), 142)
        XCTAssertEqual(numbering.pageIndex(forLabel: "xiv"), 10)
        XCTAssertNil(numbering.pageIndex(forLabel: "900"))
        XCTAssertTrue(numbering.differsFromPhysical)
        XCTAssertEqual(PageNumbering.roman(1994), "mcmxciv")
        XCTAssertNil(PageNumbering.romanValue("vix"), "Non-canonical spellings are words, not page numbers.")
    }

    func testBackOfBookIndexUsesIndentation() {
        // Two columns; subentries one step in, turned-over lines two steps in.
        func line(_ text: String, _ x: CGFloat, _ y: CGFloat, page: Int = 0) -> PageLine {
            PageLine(pageIndex: page, text: text, bounds: CGRect(x: x, y: y, width: CGFloat(text.count) * 5, height: 10))
        }
        let left: CGFloat = 134, right: CGFloat = 313
        let lines = [
            line("Index", left, 660).with(height: 19),
            line("Activation function, 392–395", left, 600),
            line("Adaptive nearest neighbor meth-", left, 588),
            line("ods, 475–478", left + 40, 576),
            line("AIC, see Akaike information cri-", left, 564),
            line("terion", left + 40, 552),
            line("Applications", left, 540),
            line("abstracts, 672", left + 20, 528),
            line("California housing, 371–372,", left + 20, 516),
            line("591", left + 40, 504),
            // The second column starts with more subentries of “Applications”.
            line("spam, 2, 300–304, 313", right + 20, 600),
            line("Bias, 16, 24, 37", right, 588),
            line("Bootstrap, 249, 261–264", right, 576),
            line("relationship to maximum like-", right + 20, 564),
            line("lihood method, 267", right + 40, 552),
            line("Bump hunting, see Patient rule", right, 540),
            line("induction method", right + 40, 528),
            line("738 Index", left, 700, page: 1).with(height: 9),
            line("Deviance, 124, 309", left, 600, page: 1)
        ]
        let entries = BookIndexParser.parse(lines, pageBounds: [0: CGRect(x: 72, y: 72, width: 450, height: 648), 1: CGRect(x: 72, y: 72, width: 450, height: 648)])
        let titles = entries.map(\.title)
        XCTAssertEqual(titles, ["Activation function", "Adaptive nearest neighbor methods", "AIC", "Applications", "Applications › abstracts",
                                "Applications › California housing", "Applications › spam", "Bias", "Bootstrap",
                                "Bootstrap › relationship to maximum likelihood method", "Bump hunting", "Deviance"])
        XCTAssertEqual(entries[1].locators, [PageSpan(first: "475", last: "478")])
        XCTAssertEqual(entries[2].see, ["Akaike information criterion"])
        XCTAssertEqual(entries[5].locators.map(\.text), ["371–372", "591"])
        XCTAssertEqual(entries[6].locators.map(\.text), ["2", "300–304", "313"])
        XCTAssertEqual(entries[10].see, ["Patient rule induction method"])
        XCTAssertEqual(entries.last?.pageIndex, 1, "The running head “738 Index” is not an entry; “Deviance, 124, 309” is.")
        XCTAssertTrue(BookIndexParser.isRunningHead("738 Index"))
        XCTAssertTrue(BookIndexParser.isRunningHead("Index 739"))
        XCTAssertFalse(BookIndexParser.isRunningHead("AdaBoost, 337"))
        XCTAssertFalse(BookIndexParser.isRunningHead("Association rules, 492–495, 499–"))

        XCTAssertEqual(BookIndexParser.parseEntry("Automatic selection of smoothing parameters , 156")?.term, "Automatic selection of smoothing parameters")
        XCTAssertEqual(BookIndexParser.parseEntry("Bayes, 21, see also Bayesian")?.see, ["Bayesian"])
        XCTAssertEqual(BookIndexParser.parseEntry("Bayes, 21, see also Bayesian")?.locators.map(\.text), ["21"])

        let found = BookIndexSearch.find("deviances", in: entries)
        XCTAssertEqual(found.first?.entry.term, "Deviance", "Plurals and case do not matter.")
        XCTAssertEqual(BookIndexSearch.find("maximum likelihood", in: entries).first?.entry.title, "Bootstrap › relationship to maximum likelihood method")
        XCTAssertTrue(BookIndexSearch.find("", in: entries).isEmpty)
    }

    func testBibliographyEntriesAndCitations() {
        func line(_ text: String, _ x: CGFloat, _ y: CGFloat) -> PageLine {
            PageLine(pageIndex: 3, text: text, bounds: CGRect(x: x, y: y, width: 320, height: 10))
        }
        let edge: CGFloat = 134
        let lines = [
            line("References", edge, 660).with(height: 19),
            line("Efron, B., Hastie, T., Johnstone, I. and Tibshirani, R. (2004). Least angle", edge, 600),
            line("regression (with discussion), Annals of Statistics 32(2): 407–499.", edge + 21, 588),
            line("Friedman, J. (1991). Multivariate adaptive regression splines (with dis-", edge, 569),
            line("cussion), Annals of Statistics 19(1): 1–141.", edge + 21, 557),
            line("Friedman, J. and Hall, P. (2007). On bagging and nonlinear estimation,", edge, 538),
            line("Journal of Statistical Planning and Inference 137: 669–683.", edge + 21, 526),
            line("Golub, G. and Van Loan, C. (1983). Matrix Computations, Johns Hopkins", edge, 507),
            line("Hastie, T. and Tibshirani, R. (1990). Generalized Additive Models, Chap-", edge, 488),
            line("man and Hall, London.", edge + 21, 476),
            line("Sch¨olkopf, B., Smola, A. and M¨uller, K.-R. (1999). Kernel principal component", edge, 457)
        ]
        let entries = BibliographyParser.parse(lines, pageBounds: [3: CGRect(x: 72, y: 72, width: 450, height: 648)])
        XCTAssertEqual(entries.map(\.shortTitle), ["Efron et al. (2004)", "Friedman (1991)", "Friedman and Hall (2007)", "Golub and Van Loan (1983)",
                                                   "Hastie and Tibshirani (1990)", "Schölkopf et al. (1999)"])
        XCTAssertEqual(entries[1].text, "Friedman, J. (1991). Multivariate adaptive regression splines (with discussion), Annals of Statistics 19(1): 1–141.")
        XCTAssertEqual(entries[0].pageIndex, 3)
        XCTAssertGreaterThan(entries[0].region.height, 20, "An entry's region covers its turned-over lines.")

        let text = """
        as in Hastie and Tibshirani (1990, Chapter 6). Least angle regression (Efron et al., 2004; Friedman, 1991)
        is related to MARS (Friedman 1991). Fried-
        man and Hall (2007) show this, see also Golub and Van Loan (1983) and made Knight (1999).
        """
        let mentions = CitationScanner.mentions(in: text)
        let resolved = mentions.map { mention in (mention.text, CitationScanner.match(mention, in: entries).map(\.shortTitle)) }
        XCTAssertEqual(resolved.map(\.0), ["Hastie and Tibshirani (1990, Chapter 6)", "Efron et al., 2004", "Friedman, 1991", "Friedman 1991",
                                           "Friedman and Hall (2007)", "Golub and Van Loan (1983)", "Knight (1999)"])
        XCTAssertEqual(resolved.map(\.1), [["Hastie and Tibshirani (1990)"], ["Efron et al. (2004)"], ["Friedman (1991)"], ["Friedman (1991)"],
                                           ["Friedman and Hall (2007)"], ["Golub and Van Loan (1983)"], []])
        let hyphenated = try! XCTUnwrap(mentions.first { $0.text.hasPrefix("Friedman and Hall") })
        XCTAssertEqual((text as NSString).substring(with: hyphenated.range), "Fried-\nman and Hall (2007)", "Ranges refer to the original text.")

        let numbered = BibliographyParser.parse([
            line("[1] A. Author and B. Writer. A first paper. Journal 1, 2001.", edge, 600),
            line("[2] C. Scholar. Another result. Proceedings, 2003.", edge, 580),
            line("[3] D. Researcher, E. Analyst and F. Theorist. A third. 1999.", edge, 560)
        ], pageBounds: [:])
        XCTAssertEqual(numbered.map(\.label), ["1", "2", "3"])
        XCTAssertEqual(numbered[0].authors, ["Author", "Writer"])
        XCTAssertEqual(numbered[2].year, "1999")
        let bracketed = CitationScanner.mentions(in: "as shown in [1, 3] and [2–3]", numeric: true)
        XCTAssertEqual(bracketed.compactMap(\.label), ["1", "3", "2", "3"])
        XCTAssertEqual(CitationScanner.match(bracketed[0], in: numbered).map(\.label), ["1"])
    }

    func testWholeBookAnalysisFindsNumberingObjectsIndexAndReferences() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("analysis-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try SyntheticBook.write(to: url)
        let outline = try XCTUnwrap(PDFDocument(url: url)).outlineItems()
        let analysis = try XCTUnwrap(BookAnalyzer.analyze(url: url, outline: outline))
        XCTAssertEqual(analysis.pageCount, 6)
        let numbering = try XCTUnwrap(analysis.numbering)
        XCTAssertEqual(numbering.label(for: 1), "1", "Printed page numbers come from the running heads, one less than the PDF's here.")
        XCTAssertEqual(numbering.label(for: 4), "4", "A page without a running head continues the run.")
        XCTAssertEqual(numbering.pageIndex(forLabel: "3"), 3)
        XCTAssertNil(numbering.label(for: 0), "The title page has no printed number.")

        let equation = ReferenceKey(kind: .equation, number: "1.1")
        XCTAssertEqual(analysis.definitionsByKey()[equation]?.pageIndex, 1)
        let mentions = analysis.mentions.filter { $0.key == equation }
        XCTAssertEqual(mentions.count, 1, "The defining label is not a mention.")
        XCTAssertEqual(mentions.first?.pageIndex, 2)
        XCTAssertTrue(mentions.first?.before.hasSuffix("model ") == true, "Mentions keep the words around them: \(mentions.first?.before ?? "")")

        XCTAssertEqual(analysis.indexPages, [5])
        XCTAssertEqual(analysis.index.map(\.title), ["Least squares", "Least squares › normal equations", "Ridge regression"])
        XCTAssertEqual(analysis.index.first?.locators.map(\.text), ["2–3"])
        XCTAssertEqual(analysis.bibliography.map(\.shortTitle), ["Hastie and Tibshirani (1990)", "Hoerl and Kennard (1970)"])
        XCTAssertEqual(analysis.citations.map(\.text), ["Hoerl and Kennard (1970)", "Hastie and Tibshirani, 1990"])
        XCTAssertEqual(analysis.citations.first?.entryIDs, [1])

        let term = try XCTUnwrap(analysis.terms.first { $0.term == "bias-variance tradeoff" }, "An italic term is read from the page's fonts: \(analysis.terms.map(\.term))")
        XCTAssertEqual(term.pageIndex, 3)
        XCTAssertTrue(term.definitional, "“is called the” marks a definition.")
        // Another document instance may order the page's text differently; the term is found again in it.
        let pageText = try XCTUnwrap(PDFDocument(url: url)?.page(at: 3)?.string) as NSString
        XCTAssertEqual(pageText.substring(with: try XCTUnwrap(term.locate(in: pageText as String))), "bias-variance tradeoff")
        var moved = term
        moved.location = 2
        XCTAssertEqual(pageText.substring(with: try XCTUnwrap(moved.locate(in: pageText as String))), "bias-variance tradeoff", "A stale range falls back to the nearest occurrence.")
        XCTAssertFalse(analysis.terms.contains { $0.surface.contains("compromise") }, "Upright words are not terms.")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = DocumentIndexRepository(root: root)
        try repository.save(analysis, id: "book")
        let reloaded = try XCTUnwrap(repository.bookAnalysis("book"))
        XCTAssertEqual(reloaded.index, analysis.index)
        XCTAssertEqual(reloaded.citations, analysis.citations)
        XCTAssertEqual(reloaded.numbering, analysis.numbering)
        XCTAssertEqual(reloaded.terms, analysis.terms)
    }
}

private extension PageLine {
    func with(height: CGFloat) -> PageLine { var line = self; line.bounds.size.height = height; return line }
}

extension PDFDocument {
    /// Outline entries in document order, as the app reads them.
    func outlineItems() -> [OutlineItem] {
        guard let root = outlineRoot else { return [] }
        var items: [OutlineItem] = []
        func walk(_ item: PDFOutline, level: Int) {
            for index in 0..<item.numberOfChildren {
                guard let child = item.child(at: index) else { continue }
                if let page = child.destination?.page { items.append(OutlineItem(title: child.label ?? "", pageIndex: self.index(for: page), level: level)) }
                walk(child, level: level + 1)
            }
        }
        walk(root, level: 0)
        return items
    }
}

/// A six-page book: running heads with printed numbers one less than the PDF's, an equation and its mention,
/// citations, a list of references and a two-level index.
enum SyntheticBook {
    static func write(to url: URL) throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 594, height: 792)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        let font = NSFont(name: "Times New Roman", size: 10) ?? .systemFont(ofSize: 10)
        let small = NSFont(name: "Times New Roman", size: 9) ?? .systemFont(ofSize: 9)
        func page(_ draw: () -> Void) {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSColor.white.setFill(); box.fill()
            draw()
            NSGraphicsContext.restoreGraphicsState(); context.endPDFPage()
        }
        func text(_ string: String, _ x: CGFloat, _ y: CGFloat, font: NSFont = font, right: Bool = false) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let width = (string as NSString).size(withAttributes: attributes).width
            (string as NSString).draw(at: CGPoint(x: right ? x - width : x, y: y), withAttributes: attributes)
        }
        func head(_ number: Int, _ title: String) {
            if number % 2 == 0 { text("\(number)    \(title)", 72, 740, font: small) } else { text("\(title)    \(number)", 522, 740, font: small, right: true) }
        }
        page { text("A Synthetic Book on Linear Models", 72, 600, font: .systemFont(ofSize: 20)) }
        page {
            head(1, "1. Least Squares")
            text("We fit a linear model by least squares. The residual sum of squares is minimised", 72, 680)
            text("over the coefficients, which leads to the normal equations", 72, 666)
            text("X^T (y - X b) = 0.", 250, 630)
            text("(1.1)", 522, 630, right: true)
            text("The solution is unique when the design has full column rank, as discussed below.", 72, 590)
        }
        page {
            head(2, "1.1 Regularisation")
            text("Returning to the model (1.1), ridge regression adds a penalty to the residual sum", 72, 680)
            text("of squares; it was introduced by Hoerl and Kennard (1970) for nonorthogonal problems", 72, 666)
            text("and appears in additive models as well (Hastie and Tibshirani, 1990) with smoothing.", 72, 652)
        }
        page {
            head(3, "1.1 Regularisation")
            text("The penalty shrinks the coefficients towards zero as it grows, trading variance for bias.", 72, 680)
            // A defined term in italic, as books introduce one.
            let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            let lead = "This compromise is called the "
            let leadWidth = (lead as NSString).size(withAttributes: [.font: font]).width
            text(lead, 72, 666)
            text("bias-variance tradeoff", 72 + leadWidth, 666, font: italic)
            let termWidth = ("bias-variance tradeoff" as NSString).size(withAttributes: [.font: italic]).width
            text(", and it recurs in every chapter.", 72 + leadWidth + termWidth, 666)
        }
        page {
            text("References", 72, 700, font: .systemFont(ofSize: 18))
            text("Hastie, T. and Tibshirani, R. (1990). Generalized Additive Models, Chapman", 72, 640)
            text("and Hall, London.", 93, 628)
            text("Hoerl, A. E. and Kennard, R. (1970). Ridge regression: biased estimation for", 72, 609)
            text("nonorthogonal problems, Technometrics 12: 55–67.", 93, 597)
        }
        page {
            head(5, "Index")
            text("Index", 72, 700, font: .systemFont(ofSize: 18))
            text("Least squares, 2–3", 72, 640)
            text("normal equations, 2", 92, 628)
            text("Ridge regression, 3, 4", 72, 616)
        }
        context.closePDF()
        guard let document = PDFDocument(data: data as Data) else { throw CocoaError(.fileWriteUnknown) }
        let root = PDFOutline()
        for (offset, entry) in [("1 Least Squares", 1), ("References", 4), ("Index", 5)].enumerated() {
            let item = PDFOutline()
            item.label = entry.0
            if let page = document.page(at: entry.1) { item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792)) }
            root.insertChild(item, at: offset)
        }
        document.outlineRoot = root
        guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
    }

    func testTermTableKeepsDefiningOccurrencesAndIndexedNouns() {
        func candidate(_ term: String, _ surface: String, definitional: Bool, before: String = "the ", after: String = " is used.") -> TermCandidate {
            TermCandidate(term: term, surface: surface, range: NSRange(location: 10, length: (surface as NSString).length), style: .italic,
                          contextBefore: before, contextAfter: after, definitional: definitional)
        }
        let candidates: [(pageIndex: Int, candidate: TermCandidate)] = [
            (30, candidate("cubic smoothing spline", "cubic smoothing spline", definitional: false, before: "the popular ")),
            (52, candidate("cubic smoothing spline", "cubic smoothing spline", definitional: true, before: "is called the ")),
            (60, candidate("deviance", "deviance", definitional: false, before: "we compute the ", after: " of the model.")),
            (61, candidate("twice", "twice", definitional: false, before: "it is counted ", after: " in total.")),
            (62, candidate("lasso", "lasso", definitional: false, before: "the ", after: " shrinks coefficients.")),
        ]
        let index = [BookIndexEntry(id: 0, term: "Deviance", locators: [PageSpan(first: "41"), PageSpan(first: "90", last: "92")], pageIndex: 700),
                     BookIndexEntry(id: 1, term: "Lasso", locators: [PageSpan(first: "68", last: "69")], pageIndex: 700),
                     BookIndexEntry(id: 2, term: "Smoothing splines", locators: [PageSpan(first: "151")], pageIndex: 700)]
        let table = BookTerms.table(candidates, index: index) { $0 - 19 }
        XCTAssertEqual(table.map(\.term), ["cubic smoothing spline", "deviance"])
        XCTAssertEqual(table[0].pageIndex, 52, "The occurrence with a definition cue is the definition.")
        XCTAssertTrue(table[0].definitional)
        XCTAssertEqual(table[0].occurrences, 2)
        XCTAssertTrue(table[1].inIndex, "A single word the index lists on that page is kept.")
        XCTAssertFalse(table.contains { $0.term == "lasso" }, "A single word whose index pages do not include it is dropped.")
        XCTAssertFalse(table.contains { $0.term == "twice" })

        XCTAssertEqual(BookTermSearch.find("spline", in: table).map(\.term), ["cubic smoothing spline"])
        XCTAssertEqual(BookTermSearch.find("Deviance", in: table).first?.term, "deviance")
        XCTAssertEqual(BookTermSearch.find("smoothing splines", in: table).map(\.term), ["cubic smoothing spline"], "Plurals meet singulars.")
        XCTAssertTrue(BookTermSearch.find("the deviance of the cubic model", in: table).isEmpty, "A lone word inside a longer query is not a match.")
        XCTAssertTrue(BookTermSearch.find("x", in: table).isEmpty)
    }
}
