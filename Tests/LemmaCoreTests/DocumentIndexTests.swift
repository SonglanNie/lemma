import XCTest
import AppKit
import PDFKit
import LemmaCore

final class DocumentIndexTests: XCTestCase {
    @MainActor
    func testMixedTextAndScanIndexResumesAndFindsPageWithoutChangingPDF() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("mixed.pdf")
        let bytes = NSMutableData(); var box = CGRect(x: 0, y: 0, width: 600, height: 400)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: bytes)), mediaBox: &box, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("A searchable design matrix has one row per observation." as NSString).draw(at: CGPoint(x: 25, y: 270), withAttributes: [.font: NSFont.systemFont(ofSize: 24)])
        NSGraphicsContext.restoreGraphicsState(); context.endPDFPage(); context.closePDF()
        let pdf = try XCTUnwrap(PDFDocument(data: bytes as Data))
        let image = NSImage(size: box.size, flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("Regularization shrinks the coefficients." as NSString).draw(at: CGPoint(x: 25, y: 270), withAttributes: [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black])
            return true
        }
        pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: 1)
        XCTAssertTrue(pdf.write(to: source)); XCTAssertTrue(pdf.page(at: 1)?.string?.isEmpty ?? true)
        let original = try Data(contentsOf: source), id = try WorkspaceRepository.fingerprint(of: source)
        let repository = DocumentIndexRepository(root: root.appendingPathComponent("support"))
        try await DocumentIndexer.index(source: source, id: id, repository: repository, jobName: "test")
        let pages = try repository.pages(id)
        XCTAssertEqual(pages.count, 2); XCTAssertEqual(pages.map(\.origin), [.pdfText, .ocr])
        XCTAssertTrue(pages[1].text.contains("Regularization shrinks"))
        XCTAssertEqual(try repository.progress(id)?.status, .complete)
        let matches = PassageSearch.find("shrinks", in: [(id, pages)], byMeaning: false)
        XCTAssertEqual(matches.map(\.pageIndex), [1]); XCTAssertEqual(matches.first?.origin, .ocr)
        let pageURL = repository.directory(id).appendingPathComponent("page-1.json")
        let checkpoint = try Data(contentsOf: pageURL)
        try await DocumentIndexer.index(source: source, id: id, repository: repository, jobName: "resume")
        XCTAssertEqual(try Data(contentsOf: pageURL), checkpoint, "Resume must reuse the completed OCR page.")
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testSimilarityRankingKeepsProvenanceAndRejectsIncompatibleModels() {
        let a = TextEmbedding(language: "en", revision: 1, vector: [1, 0])
        let related = TextEmbedding(language: "en", revision: 1, vector: [0.9, 0.1])
        XCTAssertEqual(SemanticText.similarity(a, a) ?? 0, 1, accuracy: 1e-12)
        XCTAssertGreaterThan(SemanticText.similarity(a, related) ?? 0, 0.9)
        XCTAssertNil(SemanticText.similarity(a, TextEmbedding(language: "fr", revision: 1, vector: [1, 0])))
        XCTAssertNil(SemanticText.similarity(a, TextEmbedding(language: "en", revision: 2, vector: [1, 0])))
        let page = IndexedPage(pageIndex: 7, pageLabel: "vi", origin: .ocr, passages: [.init(text: "A sparse coefficient can be zero.")])
        let result = PassageSearch.find("SPARSE", in: [("scan", [page])], byMeaning: false)
        XCTAssertEqual(result.first?.workspaceID, "scan"); XCTAssertEqual(result.first?.pageIndex, 7)
        XCTAssertEqual(result.first?.pageLabel, "vi"); XCTAssertEqual(result.first?.exact, true)
        XCTAssertTrue(PassageSearch.find(" ", in: [("scan", [page])], byMeaning: true).isEmpty)
    }

    func testLocalSentenceEmbeddingCanRetrieveAnEnglishParaphrase() throws {
        let text = "Regularization prevents overfitting by penalizing large model coefficients."
        let query = "A penalty reduces overfitting in regression models."
        let embedding = try XCTUnwrap(SemanticText.embed(text), "This Mac must have its English sentence model for the native semantic check.")
        let page = IndexedPage(pageIndex: 2, pageLabel: "3", origin: .pdfText, passages: [.init(text: text, embedding: embedding)])
        let result = PassageSearch.find(query, in: [("study", [page])], byMeaning: true)
        XCTAssertEqual(result.first?.pageIndex, 2); XCTAssertEqual(result.first?.exact, false)
    }
}
