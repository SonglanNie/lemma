import XCTest
@testable import LemmaCore

/// Derivations checked by random draws: the parser, typing of vectors and matrices, identities, inequalities,
/// calculus, conditions and the named slips.
final class DerivationTests: XCTestCase {
    private func statuses(_ source: String) -> [DerivationLineReport.Status] {
        DerivationChecker.check(source).lines.filter { $0.status != .blank }.map(\.status)
    }

    private func line(_ source: String, _ index: Int) -> DerivationLineReport {
        DerivationChecker.check(source).lines.filter { $0.status != .blank }[index]
    }

    // MARK: Parser

    func testParsesImplicitProductsScriptsAndFractions() throws {
        XCTAssertEqual(try MathParser.expression("2x^2"), .multiply(.number(2), .power(.symbol("x"), .number(2))))
        XCTAssertEqual(try MathParser.expression("\\frac12 x"), .multiply(.divide(.number(1), .number(2)), .symbol("x")))
        if case .multiply(.multiply(.inverse(.multiply(.transpose(.symbol("X")), .symbol("X"))), .transpose(.symbol("X"))), .symbol("y")) = try MathParser.expression("(X^TX)^{-1}X^Ty") {} else {
            XCTFail("(XᵀX)⁻¹Xᵀy reads as a product of an inverse, a transpose and a vector")
        }
        XCTAssertEqual(try MathParser.expression("\\hat\\beta_0"), .symbol("β̂_0"))
        XCTAssertEqual(try MathParser.expression("\\hat{\\beta}^{\\text{ridge}}"), .symbol("β̂^ridge"))
        XCTAssertEqual(try MathParser.expression("x'"), .symbol("x′"))
        XCTAssertEqual(try MathParser.expression("\\sqrt[3]{8}"), .power(.number(8), .divide(.number(1), .number(3))))
        XCTAssertEqual(try MathParser.expression("\\sin^2 x"), .power(.function("sin", [.symbol("x")]), .number(2)))
        XCTAssertEqual(try MathParser.expression("\\log 2x"), .function("log", [.multiply(.number(2), .symbol("x"))]))
        XCTAssertEqual(try MathParser.expression("|x - y|"), .absolute(.subtract(.symbol("x"), .symbol("y"))))
        XCTAssertEqual(try MathParser.expression("\\|x\\|_1"), .norm(.symbol("x"), 1))
        XCTAssertEqual(try MathParser.expression("\\left( a + b \\right)^2"), .power(.add(.symbol("a"), .symbol("b")), .number(2)))
    }

    func testReadsUnicodeFromPDFsAndChatAnswers() throws {
        XCTAssertEqual(try MathParser.expression("β̂"), .symbol("β̂"))
        XCTAssertEqual(try MathParser.expression("XᵀX"), .multiply(.transpose(.symbol("X")), .symbol("X")))
        XCTAssertEqual(try MathParser.expression("(XᵀX)⁻¹"), .inverse(.multiply(.transpose(.symbol("X")), .symbol("X"))))
        XCTAssertEqual(try MathParser.expression("λ‖β‖²"), .multiply(.symbol("λ"), .power(.norm(.symbol("β"), nil), .number(2))))
        let chain = try MathParser.chain("a − b ≤ c")
        XCTAssertEqual(chain.relations, [.lessEqual])
    }

    func testSumsDerivativesAndIntegrals() throws {
        XCTAssertEqual(try MathParser.expression("\\sum_{i=1}^N x_i y_i + c"),
                       .add(.sum(index: "i", lower: .number(1), upper: .symbol("N"), body: .multiply(.indexed("x", [.symbol("i")]), .indexed("y", [.symbol("i")]))), .symbol("c")))
        XCTAssertEqual(try MathParser.expression("\\frac{\\partial}{\\partial \\beta} \\beta^2"), .derivative(.power(.symbol("β"), .number(2)), variable: "β", order: 1))
        XCTAssertEqual(try MathParser.expression("\\frac{d^2 f}{dx^2}"), .derivative(.symbol("f"), variable: "x", order: 2))
        XCTAssertEqual(try MathParser.expression("\\int_0^1 x^2 + 1 \\, dx"), .integral(lower: .number(0), upper: .number(1), variable: "x", body: .add(.power(.symbol("x"), .number(2)), .number(1))))
        XCTAssertEqual(try MathParser.expression("\\frac{d}{2}"), .divide(.symbol("d"), .number(2)), "A fraction with d on top is a derivative only over a differential.")
    }

    func testReportsWhereAParseErrorIs() {
        let report = DerivationChecker.check("a + \\frac{1}{b")
        XCTAssertEqual(report.lines.first?.status, .error)
        XCTAssertNotNil(report.lines.first?.errorRange)
        let unknown = DerivationChecker.check("x = \\foo y")
        XCTAssertEqual(unknown.lines.first?.status, .error)
        XCTAssertEqual(unknown.lines.first?.errorRange?.location, 4, "The unknown command is underlined.")
    }

    // MARK: Identities

    func testIdentitiesHoldAndSlipsAreNamed() {
        XCTAssertEqual(statuses("(a+b)^2 = a^2 + 2ab + b^2"), [.holds])
        let wrong = line("(a+b)^2 = a^2 + b^2", 0)
        XCTAssertEqual(wrong.status, .fails)
        XCTAssertNotNil(wrong.detail, "A counterexample is shown.")
        XCTAssertTrue(line("(a-b)(a+b) = b^2 - a^2", 0).message.contains("Sign error"))
        XCTAssertTrue(line("\\frac{d}{dx} x^2 = x", 0).message.contains("factor of 2"), line("\\frac{d}{dx} x^2 = x", 0).message)
        XCTAssertTrue(line("(x+1)^2 = x^2 + 2x", 0).message.contains("constant"))
    }

    func testASlipInOneTermIsNamed() {
        let source = "X \\in \\mathbb{R}^{N\\times p}, \\lambda > 0\n\\frac{\\partial}{\\partial\\beta}\\left[(y - X\\beta)^T(y - X\\beta) + \\lambda\\beta^T\\beta\\right] = -2X^Ty + 2X^TX\\beta + \\lambda\\beta"
        let report = line(source, 1)
        XCTAssertEqual(report.status, .fails)
        XCTAssertEqual(report.message, "The term λβ should be 2 times as large")
        XCTAssertEqual(line("a^2 + 2ab + b^2 = (a+b)^2 + 2ab", 0).message, "The term 2ab should not be there")
        XCTAssertEqual(MathText.render(try! MathParser.expression("(X^TX + \\lambda I)^{-1}X^Ty")), "(XᵀX + λI)⁻¹Xᵀy")
    }

    func testAChainContinuesFromThePreviousLine() {
        let source = """
        (a+b)^3
        = (a+b)(a^2 + 2ab + b^2)
        &= a^3 + 3a^2b + 3ab^2 + b^3
        = a^3 + b^3
        """
        XCTAssertEqual(statuses(source), [.comment, .holds, .holds, .fails])
    }

    func testLogarithmsAreCheckedWithPositiveNumbers() {
        let report = line("\\log(ab) = \\log a + \\log b", 0)
        XCTAssertEqual(report.status, .holds)
        XCTAssertTrue(report.message.contains("positive"))
        XCTAssertEqual(statuses("e^{a+b} = e^a e^b"), [.holds])
    }

    // MARK: Matrices

    func testLeastSquaresAlgebraWithInferredShapes() {
        let source = """
        X \\in \\mathbb{R}^{N \\times p}, y \\in \\mathbb{R}^N
        (y - X\\beta)^T(y - X\\beta) = y^Ty - 2\\beta^TX^Ty + \\beta^TX^TX\\beta
        """
        let report = DerivationChecker.check(source)
        XCTAssertEqual(report.lines.map(\.status), [.declaration, .holds], report.lines.map(\.message).joined(separator: " | "))
        let beta = report.symbols.first { $0.name == "β" }
        XCTAssertEqual(beta?.origin, .inferred)
        XCTAssertEqual(beta?.type, .matrix(.param("p"), .constant(1), .general), "β is inferred to be a vector of length p from Xβ.")
    }

    func testShapesAreInferredWithoutDeclarations() {
        // Xᵀ makes X a matrix, Xᵀy makes y a vector: the classic identity holds, a transposition slip does not.
        XCTAssertEqual(statuses("(AB)^T = B^TA^T"), [.holds])
        let report = line("A, B \\in \\mathbb{R}^{n\\times n}\n(AB)^T = A^TB^T", 1)
        XCTAssertEqual(report.status, .fails)
        let transposed = line("X \\in \\mathbb{R}^{N\\times p}, y \\in \\mathbb{R}^N\nX^Ty = y^TX", 1)
        XCTAssertEqual(transposed.status, .fails)
        XCTAssertTrue(transposed.message.contains("Transposed"), transposed.message)
    }

    func testShapeErrorsAreExplained() {
        let report = line("X \\in \\mathbb{R}^{N\\times p}, y \\in \\mathbb{R}^N\nXy = y", 1)
        XCTAssertEqual(report.status, .fails)
        XCTAssertTrue(report.message.contains("multiply"), report.message)
    }

    func testGradientOfTheRidgeObjective() {
        let source = """
        X \\in \\mathbb{R}^{N \\times p}, \\lambda > 0
        \\frac{\\partial}{\\partial \\beta} \\left[(y - X\\beta)^T(y - X\\beta) + \\lambda \\beta^T\\beta\\right] = -2X^T(y - X\\beta) + 2\\lambda\\beta
        """
        XCTAssertEqual(statuses(source), [.declaration, .holds])
        let wrong = source.replacingOccurrences(of: "+ 2\\lambda\\beta", with: "+ \\lambda\\beta")
        XCTAssertEqual(statuses(wrong), [.declaration, .fails])
    }

    func testNormalEquationsFollowFromTheGradient() {
        let source = """
        X \\in \\mathbb{R}^{N \\times p}, y \\in \\mathbb{R}^N
        -2X^T(y - X\\beta) = 0
        X^TX\\beta = X^Ty
        \\beta = (X^TX)^{-1}X^Ty
        \\beta = X^{T}y
        """
        let report = DerivationChecker.check(source)
        XCTAssertEqual(report.lines.map(\.status), [.declaration, .given, .holds, .holds, .fails], report.lines.map(\.message).joined(separator: " | "))
        XCTAssertTrue(report.lines[2].message.contains("Follows from line 2"), report.lines[2].message)
        XCTAssertTrue(report.lines[3].message.contains("Solves line 3"), report.lines[3].message)
    }

    func testIndexedFamiliesOfVectors() {
        let source = """
        x_i \\in \\mathbb{R}^p
        \\sum_{i=1}^N (x_i^T\\beta)^2 = \\beta^T\\left(\\sum_{i=1}^N x_i x_i^T\\right)\\beta
        """
        XCTAssertEqual(statuses(source), [.declaration, .holds])
    }

    // MARK: Inequalities, sums, integrals, definitions

    func testInequalitiesLookForCounterexamples() {
        XCTAssertEqual(statuses("(a+b)^2 \\le 2a^2 + 2b^2"), [.holds])
        XCTAssertEqual(statuses("a^2 \\le a"), [.fails])
        XCTAssertEqual(statuses("\\|x + y\\| \\le \\|x\\| + \\|y\\|\nx \\in \\mathbb{R}^n, y \\in \\mathbb{R}^n"), [.holds, .declaration])
    }

    func testSumsWithSymbolicBounds() {
        XCTAssertEqual(statuses("\\sum_{i=1}^n i = \\frac{n(n+1)}{2}"), [.holds])
        XCTAssertEqual(statuses("\\sum_{i=1}^n i^2 = \\frac{n(n+1)}{2}"), [.fails])
        XCTAssertEqual(statuses("\\sum_i x_i^2 \\ge 0"), [.holds])
    }

    func testDefiniteIntegrals() {
        XCTAssertEqual(statuses("\\int_0^1 x^2 \\, dx = \\frac{1}{3}"), [.holds])
        XCTAssertEqual(statuses("k \\in \\mathbb{N}\n\\int_0^\\infty x^k e^{-x} \\, dx = k!"), [.declaration, .holds])
        XCTAssertEqual(statuses("\\int_{-\\infty}^{\\infty} e^{-x^2/2} \\, dx = \\sqrt{2\\pi}"), [.holds])
    }

    func testDefinitionsAreExpandedInLaterSteps() {
        let source = """
        f(x) := x^2 + 1
        f(2) = 5
        \\text{RSS}(\\beta) = (y - X\\beta)^T(y - X\\beta)
        \\frac{\\partial \\text{RSS}}{\\partial \\beta} = -2X^T(y - X\\beta)
        """
        let report = DerivationChecker.check(source)
        XCTAssertEqual(report.lines.map(\.status), [.definition, .holds, .definition, .holds], report.lines.map(\.message).joined(separator: " | "))
        XCTAssertTrue(statuses("RSS(\\beta) = \\|y - X\\beta\\|^2\nRSS(\\beta) = (y-X\\beta)^T(y - X\\beta)").allSatisfy { $0 == .definition || $0 == .holds })
    }

    func testCommentsProseAndDisplayWrappersAreIgnored() {
        let source = """
        % expand the square
        Taking derivatives with respect to the coefficients gives
        \\begin{align*}
        (a+b)^2 &= a^2 + 2ab + b^2 \\\\
        &= b^2 + 2ab + a^2
        \\end{align*}
        """
        XCTAssertEqual(statuses(source), [.comment, .comment, .holds, .holds])
    }

    func testUnsupportedConstructsAreSaidSo() {
        let report = line("\\mathbb{E}[X + Y] = \\mathbb{E}[X] + \\mathbb{E}[Y]", 0)
        XCTAssertEqual(report.status, .unchecked)
        XCTAssertTrue(report.message.contains("expectation"), report.message)
    }

    func testAssumptionsShapeTheDraws() {
        XCTAssertEqual(statuses("Assume x > 0\n\\sqrt{x^2} = x"), [.declaration, .holds])
        XCTAssertEqual(statuses("\\sqrt{x^2} = x"), [.fails], "Without the assumption, x < 0 is a counterexample.")
        XCTAssertEqual(statuses("0 < p < 1\np(1-p) \\le \\frac{1}{4}"), [.declaration, .holds])
    }

    func testCounterexamplesNameTheValues() {
        let report = line("\\lambda \\in \\mathbb{R}\n(1 + \\lambda)^2 = 1 + \\lambda^2", 1)
        XCTAssertEqual(report.status, .fails)
        XCTAssertTrue(report.detail?.contains("λ =") == true, report.detail ?? "")
        XCTAssertTrue(report.detail?.contains("left =") == true)
    }

    // MARK: Worked derivations

    func testRidgeFromObjectiveToSolution() {
        let source = """
        X \\in \\mathbb{R}^{N\\times p}, y \\in \\mathbb{R}^N, \\lambda > 0
        RSS(\\beta) = (y - X\\beta)^T(y - X\\beta) + \\lambda\\beta^T\\beta
        \\frac{\\partial RSS}{\\partial\\beta} = -2X^T(y - X\\beta) + 2\\lambda\\beta
        -2X^T(y - X\\beta) + 2\\lambda\\beta = 0
        (X^TX + \\lambda I)\\beta = X^Ty
        \\hat\\beta^{ridge} = (X^TX + \\lambda I)^{-1}X^Ty
        """
        let report = DerivationChecker.check(source)
        XCTAssertEqual(report.lines.map(\.status), [.declaration, .definition, .holds, .given, .holds, .holds], report.lines.map(\.message).joined(separator: " | "))
        XCTAssertTrue(report.lines[5].message.contains("solves line 5 for β"), report.lines[5].message)
        let wrong = source.replacingOccurrences(of: "(X^TX + \\lambda I)^{-1}X^Ty", with: "(X^TX)^{-1}X^Ty")
        XCTAssertEqual(DerivationChecker.check(wrong).lines.last?.status, .fails, "Ordinary least squares does not solve the ridge equations.")
    }

    func testDerivativesOfDefinedAndArbitraryFunctions() {
        XCTAssertEqual(statuses("\\sigma(x) := \\frac{1}{1 + e^{-x}}\n\\sigma'(x) = \\sigma(x)(1 - \\sigma(x))\n\\sigma'(x) = \\sigma(x)^2"), [.definition, .holds, .fails])
        XCTAssertEqual(statuses("\\frac{d}{dx} f(g(x)) = f'(g(x)) g'(x)"), [.holds], "The chain rule holds for arbitrary smooth f and g.")
        XCTAssertEqual(statuses("\\frac{d}{dx} f(g(x)) = f'(x) g'(x)"), [.fails])
    }

    func testSolvingAnEquationStepByStep() {
        XCTAssertEqual(statuses("x^2 - 5x + 6 = 0\n(x-2)(x-3) = 0\nx = 2\nx = 4"), [.given, .holds, .holds, .fails])
    }

    func testMatrixIdentitiesWithoutDeclarations() {
        XCTAssertEqual(statuses("(A + UCV)^{-1} = A^{-1} - A^{-1}U(C^{-1} + VA^{-1}U)^{-1}VA^{-1}"), [.holds])
        XCTAssertEqual(statuses("\\operatorname{tr}(AB) = \\operatorname{tr}(BA)"), [.holds])
        XCTAssertEqual(statuses("X \\in \\mathbb{R}^{N\\times p}\nH = X(X^TX)^{-1}X^T\nH^2 = H\n\\operatorname{tr}(H) = p\n\\operatorname{tr}(H) = N"), [.declaration, .definition, .holds, .holds, .fails])
    }
}
