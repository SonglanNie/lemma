import XCTest
@testable import LemmaCore

/// 1.0's research tools in the core: reading scholarly services' answers, the catalog of free books, derivation
/// templates from the book's notation and from saved answers, and workspaces with derivations.
final class ResearchToolsTests: XCTestCase {
    func testCrossrefSemanticScholarAndArxivAnswersAreRead() throws {
        let crossref = """
        {"status":"ok","message":{"items":[{"DOI":"10.1111/j.1467-9868.2005.00503.x","title":["Regularization and Variable Selection Via the Elastic Net"],
        "author":[{"given":"Hui","family":"Zou"},{"given":"Trevor","family":"Hastie"}],"issued":{"date-parts":[[2005,4,1]]},
        "container-title":["Journal of the Royal Statistical Society Series B"],"is-referenced-by-count":17380,"score":92.1}]}}
        """
        let papers = PaperLookup.parseCrossref(Data(crossref.utf8))
        XCTAssertEqual(papers.count, 1)
        XCTAssertEqual(papers[0].authors, ["Zou", "Hastie"])
        XCTAssertEqual(papers[0].year, 2005)
        XCTAssertEqual(papers[0].pageURL?.absoluteString, "https://doi.org/10.1111/j.1467-9868.2005.00503.x")

        let s2 = """
        {"title":"Least angle regression","year":2004,"abstract":"The purpose of model selection algorithms…","citationCount":9000,
         "venue":"Annals of Statistics","externalIds":{"DOI":"10.1214/009053604000000067","ArXiv":"math/0406456"},"openAccessPdf":null,
         "authors":[{"name":"Bradley Efron"},{"name":"Trevor Hastie"}]}
        """
        let enriched = try XCTUnwrap(try PaperLookup.parseSemanticScholar(Data(s2.utf8)))
        XCTAssertEqual(enriched.arxivID, "math/0406456")
        XCTAssertEqual(enriched.pdfURL?.absoluteString, "https://arxiv.org/pdf/math/0406456", "An arXiv preprint is an open PDF.")
        XCTAssertEqual(enriched.authors, ["Efron", "Hastie"])

        let atom = """
        <?xml version="1.0" encoding="UTF-8"?><feed xmlns="http://www.w3.org/2005/Atom"><entry><id>http://arxiv.org/abs/1706.03762v7</id>
        <published>2017-06-12T17:57:34Z</published><title>Attention Is All
          You Need</title><summary>The dominant sequence transduction models…</summary>
        <author><name>Ashish Vaswani</name></author><author><name>Noam Shazeer</name></author></entry></feed>
        """
        let arxiv = PaperLookup.parseArxiv(Data(atom.utf8))
        XCTAssertEqual(arxiv.first?.arxivID, "1706.03762", "The version is dropped from the identifier.")
        XCTAssertEqual(arxiv.first?.title, "Attention Is All You Need", "Line breaks in titles are folded.")
        XCTAssertEqual(arxiv.first?.authors, ["Vaswani", "Shazeer"])
        XCTAssertEqual(arxiv.first?.pdfURL?.absoluteString, "https://arxiv.org/pdf/1706.03762")
    }

    func testReferencesMatchTheirWorks() {
        let entry = "Zou, H. and Hastie, T. (2005). Regularization and variable selection via the elastic net, Journal of the Royal Statistical Society Series B. 67(2): 301–320."
        XCTAssertEqual(PaperLookup.titleGuess(entry), "Regularization and variable selection via the elastic net, Journal of the Royal Statistical Society Series B")
        let right = PaperCandidate(id: "a", title: "Regularization and Variable Selection Via the Elastic Net", authors: ["Zou", "Hastie"], year: 2005)
        let wrong = PaperCandidate(id: "b", title: "Model-Free Variable Selection", authors: ["Li", "Cook"], year: 2005)
        XCTAssertGreaterThan(PaperLookup.confidence(right, entry: entry, authors: ["Zou", "Hastie"], year: 2005), 0.9)
        XCTAssertLessThan(PaperLookup.confidence(wrong, entry: entry, authors: ["Zou", "Hastie"], year: 2005), 0.6)
        XCTAssertEqual(PaperLookup.arxivID(in: "https://arxiv.org/abs/1706.03762v7"), "1706.03762")
        XCTAssertEqual(PaperLookup.arxivID(in: "arXiv:math/0406456"), "math/0406456")
        XCTAssertNil(PaperLookup.arxivID(in: "no identifier here"))
    }

    func testTheCatalogListsOfficialFreePDFs() {
        let books = BookCatalog.books
        XCTAssertGreaterThanOrEqual(books.count, 40)
        XCTAssertEqual(Set(books.map(\.id)).count, books.count, "Identifiers are unique.")
        // Only two authors serve their book over plain HTTP; the app allows exactly those hosts.
        XCTAssertEqual(Set(books.filter { $0.pdf.scheme == "http" }.compactMap { $0.pdf.host }), ["incompleteideas.net", "web4.cs.ucl.ac.uk"])
        XCTAssertTrue(books.allSatisfy { !$0.summary.isEmpty && !$0.authors.isEmpty && $0.year > 1950 })
        XCTAssertTrue(BookCatalog.search("elements statistical learning").contains { $0.id == "esl" })
        XCTAssertTrue(BookCatalog.search("Axler").count >= 2, "Search covers authors.")
        XCTAssertTrue(BookCatalog.search("zzzz nothing").isEmpty)
    }

    func testDeclarationsFromTheBooksNotation() {
        XCTAssertEqual(DerivationTemplate.declaration(symbol: "X", meaning: "the N × p input matrix"), "X \\in \\mathbb{R}^{N \\times p}")
        XCTAssertEqual(DerivationTemplate.declaration(symbol: "X", meaning: "N × (p + 1) matrix with each row an input vector"), "X \\in \\mathbb{R}^{N \\times (p+1)}")
        XCTAssertEqual(DerivationTemplate.declaration(symbol: "y", meaning: "the N-vector of outputs in the training set"), "y \\in \\mathbb{R}^{N}")
        XCTAssertEqual(DerivationTemplate.declaration(symbol: "β", meaning: "a vector of length p"), "\\beta \\in \\mathbb{R}^{p}")
        XCTAssertEqual(DerivationTemplate.declaration(symbol: "λ", meaning: "a positive constant"), "\\lambda > 0")
        XCTAssertNil(DerivationTemplate.declaration(symbol: "f", meaning: "the regression function"))
        XCTAssertEqual(DerivationTemplate.declaration(symbol: "X", meaning: "n×n symmetric matrix"), "X \\in \\mathbb{S}^{n}")
        XCTAssertEqual(DerivationTemplate.declaration(symbol: "h", meaning: "standard deviation of the Gaussian components"), "h > 0")
        // Measured on fourteen books: what must not become a declaration.
        XCTAssertNil(DerivationTemplate.declaration(symbol: "V", meaning: "n-dimensional vector space"))
        XCTAssertNil(DerivationTemplate.declaration(symbol: "V", meaning: "finite-dimensional vector spaces such that dim V > dim W"))
        XCTAssertNil(DerivationTemplate.declaration(symbol: "v", meaning: "zero mean unit variance Gaussian variable"))
        XCTAssertNil(DerivationTemplate.declaration(symbol: "X", meaning: "random variable with mean µ and variance σ2"))
        XCTAssertNil(DerivationTemplate.declaration(symbol: "Σ", meaning: "variance–covariance matrix of the latent variables"))
        // The declarations are read back by the checker.
        let report = DerivationChecker.check("X \\in \\mathbb{R}^{N \\times (p+1)}\n(X^TX)^T = X^TX")
        XCTAssertEqual(report.lines.map(\.status), [.declaration, .holds])
    }

    func testDisplayedStepsOfAnAnswer() {
        let answer = """
        Differentiate the criterion:

        $$\\frac{\\partial}{\\partial\\beta}(y - X\\beta)^T(y - X\\beta) = -2X^T(y - X\\beta)$$

        Setting it to zero,
        \\begin{aligned}
        X^Ty - X^TX\\beta &= 0 \\\\
        \\hat\\beta &= (X^TX)^{-1}X^Ty
        \\end{aligned}
        and the fitted values are $\\hat y = X\\hat\\beta$ (inline maths is left out).
        """
        XCTAssertEqual(DerivationTemplate.steps(fromAnswer: answer), [
            "\\frac{\\partial}{\\partial\\beta}(y - X\\beta)^T(y - X\\beta) = -2X^T(y - X\\beta)", "",
            "X^Ty - X^TX\\beta &= 0", "\\hat\\beta &= (X^TX)^{-1}X^Ty"
        ])
    }

    func testWorkspacesKeepDerivations() throws {
        var workspace = StudyWorkspace(id: "w", title: "Book", sourcePath: "/tmp/book.pdf", sourceBookmark: nil, fingerprint: "w")
        workspace.derivations = [Derivation(title: "Ridge", source: "(a+b)^2 = a^2 + 2ab + b^2", origin: LabSource(pageIndex: 3, label: "Equation (3.44)"))]
        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(StudyWorkspace.self, from: data)
        XCTAssertEqual(decoded.derivations.first?.title, "Ridge")
        XCTAssertEqual(decoded.derivations.first?.origin?.label, "Equation (3.44)")
        // A schema 9 workspace has no derivations.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["derivations"] = nil; object["schemaVersion"] = 9
        let older = try JSONDecoder().decode(StudyWorkspace.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(older.derivations.isEmpty)
    }
}
