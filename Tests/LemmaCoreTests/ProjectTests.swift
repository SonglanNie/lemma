import XCTest
import LemmaCore

final class ProjectTests: XCTestCase {
    func testProjectRoundTripAndPortableExportKeepImagesCitationsAndAnnotations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(root: root)
        var project = ResearchProject(title: "Uniqueness", question: "When is the minimizer unique?", bookIDs: ["book-a"])
        let anchor = SourceAnchor(pageIndex: 82, pageLabel: "64", region: PageRegion(x: 50, y: 100, width: 250, height: 80),
                                  quote: "Full column rank\nimplies uniqueness.", imageName: "original.png")
        let source = ProjectPassage(number: 1, bookID: "book-b", bookTitle: "A second book", title: "Normal equations", section: "Least squares",
                                    anchor: anchor, annotation: "The rank assumption matters.")
        project.collect(source); project.synthesis = "Strict convexity gives uniqueness \(source.citation).\n\n$$X^TX \\succ 0$$"
        let image = Data([137, 80, 78, 71, 13, 10, 26, 10])
        try repository.saveImage(image, projectID: project.id, name: anchor.imageName)
        try repository.save([project])
        XCTAssertEqual(try repository.load(), [project])
        XCTAssertEqual(project.bookIDs, ["book-a", "book-b"])
        XCTAssertEqual(project.nextSourceNumber, 2)
        let destination = root.appendingPathComponent("export")
        try repository.export(project, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("assets/original.png")), image)
        let markdown = try String(contentsOf: destination.appendingPathComponent("Research.md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("p. 64 · PDF page 83"))
        XCTAssertTrue(markdown.contains("[S1](lemma://open?book=book-b&page=83)"))
        XCTAssertTrue(markdown.contains("> Full column rank\n> implies uniqueness."))
        XCTAssertTrue(markdown.contains("Reader's annotation:\n\nThe rank assumption matters."))
        XCTAssertTrue(markdown.contains("$$X^TX \\succ 0$$"))
        XCTAssertEqual(try JSONDecoder().decode(ResearchProject.self, from: Data(contentsOf: destination.appendingPathComponent("project.json"))), project)
    }

    func testStableSourceNumbersSurviveRemovalAndArchive() throws {
        var project = ResearchProject(title: "Sparsity")
        func passage(_ number: Int) -> ProjectPassage {
            ProjectPassage(number: number, bookID: "book", bookTitle: "Book", title: "Source", section: "",
                anchor: SourceAnchor(pageIndex: 1, pageLabel: "2", region: PageRegion(x: 0, y: 0, width: 10, height: 10), quote: "", imageName: "\(number).png"))
        }
        project.collect(passage(project.nextSourceNumber)); project.collect(passage(project.nextSourceNumber))
        let citation = project.passages[1].citation
        project.passages.removeFirst()
        project.collect(passage(project.nextSourceNumber))
        XCTAssertEqual(project.passages.map(\.number), [2, 3])
        XCTAssertEqual(project.passages[0].citation, citation)
        project.archived = true
        let decoded = try JSONDecoder().decode(ResearchProject.self, from: JSONEncoder().encode(project))
        XCTAssertTrue(decoded.archived)
        XCTAssertEqual(decoded.passages.count, 2, "Archive retains the evidence and the writing.")
    }
}
