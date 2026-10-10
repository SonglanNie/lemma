import XCTest
import PDFKit
@testable import LemmaCore

final class FormulaReadingTests: XCTestCase {
    func testRealTypesetFormulasRetainTheirScriptsFractionsLimitsAndMatrices() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "formula-layout", withExtension: "pdf", subdirectory: "Fixtures"))
        let document = try XCTUnwrap(PDFDocument(url: url))
        let analysis = try XCTUnwrap(BookAnalyzer.analyze(document: document, outline: []))
        let targets = analysis.definitions.filter { $0.key.kind == .equation }
        XCTAssertEqual(targets.count, 7)
        var outputs: [String: String] = [:]
        for target in targets {
            let page = try XCTUnwrap(document.page(at: target.pageIndex))
            let ink = PageInkScanner.scan(page)
            let rect = CGRect(x: target.region.x, y: target.region.y, width: target.region.width, height: target.region.height)
            let label = CGRect(x: target.anchor.x, y: target.anchor.y, width: target.anchor.width, height: target.anchor.height)
            let reading = try XCTUnwrap(FormulaReader.read(ink, in: rect, label: label))
            XCTAssertEqual(reading.unknown, 0, "\(target.key.title): \(reading.latex)")
            XCTAssertFalse(reading.latex.contains("The "), "Prose must not enter the transcription.")
            outputs[target.key.number] = canonical(reading.latex)
            print("FORMULA \(target.key.number): \(reading.latex)")
        }
        XCTAssertEqual(outputs["1"], canonical(#"\hat{\beta}=(X^TX+\lambda I)^{-1}X^Ty"#))
        XCTAssertEqual(outputs["2"], canonical(#"\mathrm{RSS}(\beta)=\sum_{i=1}^{N}(y_i-x_i^T\beta)^2"#))
        XCTAssertEqual(outputs["3"], canonical(#"\frac{\partial}{\partial x}\sin(x^2)=2x\cos(x^2)"#))
        let matrix = try XCTUnwrap(outputs["4"])
        XCTAssertTrue(matrix.contains(#"a&b\\c&d"#), matrix)
        XCTAssertTrue(matrix.contains("matrix"), matrix)
        XCTAssertEqual(outputs["5"], canonical(#"\int_0^\infty e^{-x}dx=1"#))
        XCTAssertEqual(outputs["6"], canonical(#"r=\sqrt{x^2+y^2}"#))
        XCTAssertEqual(outputs["7"], canonical(#"f(x)=\frac{1}{1+\frac{1}{x}}"#))
    }

    func testUnknownGlyphsAreReportedAndEmptyInkHasNoTranscription() throws {
        XCTAssertNil(FormulaReader.read(PageInk()))
        let glyph = InkGlyph(name: "unrecognized_glyph", font: "UnknownMathFont", size: 10, x: 10, y: 20, width: 6)
        let reading = try XCTUnwrap(FormulaReader.read(PageInk(glyphs: [glyph])))
        XCTAssertFalse(reading.isComplete)
        XCTAssertEqual(reading.unknown, 1)
        XCTAssertTrue(reading.latex.contains("?"))
    }

    /// Remove only typesetting variants of the same TeX: whitespace, scalable delimiters,
    /// and braces around a single token. Multi-token exponents and fraction arguments remain intact.
    private func canonical(_ latex: String) -> String {
        var value = latex.replacingOccurrences(of: #"\left"#, with: "").replacingOccurrences(of: #"\right"#, with: "")
            // The PDF draws the same upright letters for \mathrm{RSS} and \operatorname{RSS}.
            .replacingOccurrences(of: #"\operatorname"#, with: #"\mathrm"#)
            .filter { !$0.isWhitespace }
        let expression = try! NSRegularExpression(pattern: #"\{([A-Za-z0-9]|\\[A-Za-z]+)\}"#)
        for _ in 0..<3 { value = expression.stringByReplacingMatches(in: value, range: NSRange(location: 0, length: (value as NSString).length), withTemplate: "$1") }
        return value
    }
}
