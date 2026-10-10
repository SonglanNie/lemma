import XCTest
@testable import LemmaCore

final class LibraryEditingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func file(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("metadata-only fixture".utf8).write(to: url)
        return url
    }

    private func listed(_ collections: [LibraryCollection]) -> [String: [String]] {
        Dictionary(grouping: LibraryScanner.scan(collections).entries, by: \.collectionID)
            .mapValues { $0.map { URL(fileURLWithPath: $0.path).lastPathComponent }.sorted() }
    }

    func testMovingAPDFBetweenLibrariesKeepsTheFileAndSurvivesAScan() throws {
        let math = root.appendingPathComponent("math")
        let isl = try file("math/regression/ISL.pdf")
        _ = try file("math/options.pdf")
        let collections = [
            LibraryCollection(id: "quant", title: "Quant", kind: .studying, sources: [LibrarySource(path: math.path)]),
            LibraryCollection(id: "stats", title: "Stats", kind: .studying, sources: [])
        ]
        XCTAssertEqual(listed(collections)["quant"], ["ISL.pdf", "options.pdf"])

        let moved = LibraryEditing.moving(isl.path, from: "quant", to: "stats", in: collections)
        XCTAssertEqual(listed(moved)["quant"], ["options.pdf"], "The watched folder now excludes the PDF")
        XCTAssertEqual(listed(moved)["stats"], ["ISL.pdf"], "It became a source of its own in Stats")
        XCTAssertTrue(FileManager.default.fileExists(atPath: isl.path), "Nothing moves on disk")
        XCTAssertNotNil(moved[1].sources.first?.bookmark)
        XCTAssertTrue(LibraryEditing.lists(isl.path, in: moved[1]))
        XCTAssertFalse(LibraryEditing.lists(isl.path, in: moved[0]))

        let back = LibraryEditing.moving(isl.path, from: "stats", to: "quant", in: moved)
        XCTAssertEqual(listed(back)["quant"], ["ISL.pdf", "options.pdf"], "Moving back lifts the exclusion")
        XCTAssertNil(listed(back)["stats"])
        XCTAssertEqual(back[0].sources[0].excludedPaths, [])
        XCTAssertEqual(back[1].sources, [])

        let both = LibraryEditing.moving(isl.path, from: "quant", to: "stats", keepingSource: true, in: collections)
        XCTAssertEqual(listed(both)["quant"], ["ISL.pdf", "options.pdf"])
        XCTAssertEqual(listed(both)["stats"], ["ISL.pdf"], "⌥ lists it in both")
        XCTAssertEqual(LibraryEditing.moving(isl.path, from: "quant", to: "quant", in: collections), collections)
    }

    func testFoldersMoveBetweenLibrariesAndExclusionsHideTheirPDFs() throws {
        let math = root.appendingPathComponent("math")
        for name in ["math/poker/Theory.pdf", "math/poker/deep/Odds.pdf", "math/Calculus.pdf"] { _ = try file(name) }
        let poker = math.appendingPathComponent("poker")
        let collections = [
            LibraryCollection(id: "quant", title: "Quant", kind: .studying, sources: [LibrarySource(path: math.path)]),
            LibraryCollection(id: "poker", title: "Poker", kind: .studying, sources: [])
        ]
        let moved = LibraryEditing.moving(poker.path, isFolder: true, from: "quant", to: "poker", in: collections)
        XCTAssertEqual(listed(moved)["quant"], ["Calculus.pdf"])
        XCTAssertEqual(listed(moved)["poker"], ["Odds.pdf", "Theory.pdf"])
        XCTAssertEqual(moved[1].sources.first?.kind, .folder)
        let scan = LibraryScanner.scan(moved)
        XCTAssertEqual(scan.entries.first { $0.path.hasSuffix("Odds.pdf") }?.folder, "deep", "The new library shows the folder's own tree")

        // Lifting one PDF out of an excluded folder adds it on its own; removing a folder also drops sources inside it.
        let theory = poker.appendingPathComponent("Theory.pdf").path
        let one = LibraryEditing.adding(theory, to: "quant", in: moved)
        XCTAssertEqual(listed(one)["quant"], ["Calculus.pdf", "Theory.pdf"])
        let removed = LibraryEditing.removing(poker.path, from: "quant", in: one)
        XCTAssertEqual(listed(removed)["quant"], ["Calculus.pdf"])
        XCTAssertEqual(removed[0].sources.count, 1, "The single Theory source inside the removed folder went too")
    }

    func testRelocatingFollowsRenamedFilesAndFolders() throws {
        let stats = try file("books/ESL.pdf")
        let folder = root.appendingPathComponent("books")
        let collections = [
            LibraryCollection(id: "stats", title: "Stats", kind: .studying, sources: [LibrarySource(path: stats.path, kind: .file)]),
            LibraryCollection(id: "all", title: "All", kind: .studying, sources: [LibrarySource(path: folder.path, excludedPaths: [stats.path])])
        ]
        let renamed = folder.appendingPathComponent("Elements.pdf")
        try FileManager.default.moveItem(at: stats, to: renamed)
        let afterFile = LibraryEditing.relocating(stats.path, to: renamed.path, in: collections)
        XCTAssertEqual(afterFile[0].sources[0].path, renamed.path)
        XCTAssertNotNil(afterFile[0].sources[0].bookmark)
        XCTAssertEqual(afterFile[1].sources[0].excludedPaths, [renamed.path])
        XCTAssertEqual(listed(afterFile)["stats"], ["Elements.pdf"])
        XCTAssertNil(listed(afterFile)["all"])

        let library = root.appendingPathComponent("library")
        try FileManager.default.moveItem(at: folder, to: library)
        let afterFolder = LibraryEditing.relocating(folder.path, to: library.path, in: afterFile)
        XCTAssertEqual(afterFolder[0].sources[0].path, library.appendingPathComponent("Elements.pdf").path)
        XCTAssertEqual(afterFolder[1].sources[0].path, library.path)
        XCTAssertEqual(LibraryPaths.key(afterFolder[1].sources[0].excludedPaths[0]), LibraryPaths.key(library.appendingPathComponent("Elements.pdf").path))
        XCTAssertEqual(listed(afterFolder)["stats"], ["Elements.pdf"])

        let names = [LibraryPaths.key(renamed.path): "Elements of Statistical Learning", "/elsewhere/x.pdf": "X"]
        let moved = LibraryEditing.relocating(keys: names, from: folder.path, to: library.path)
        XCTAssertEqual(moved[LibraryPaths.key(library.appendingPathComponent("Elements.pdf").path)], "Elements of Statistical Learning")
        XCTAssertEqual(moved["/elsewhere/x.pdf"], "X")
    }

    func testLibrariesNestInsideTheLibraryNamedLikeTheirGroup() {
        let collections = [
            LibraryCollection(id: "quant", title: "Quant", kind: .studying, sources: []),
            LibraryCollection(id: "csd", title: "CSD", kind: .studying, parent: "School", sources: []),
            LibraryCollection(id: "poker", title: "Poker", kind: .studying, parent: "quant", sources: []),
            LibraryCollection(id: "papers", title: "Papers", kind: .papers, sources: [])
        ]
        XCTAssertEqual(LibraryEditing.host(of: "Quant", in: collections)?.id, "quant")
        XCTAssertNil(LibraryEditing.host(of: "School", in: collections), "School is a section of its own")
        XCTAssertEqual(LibraryEditing.children(of: collections[0], in: collections).map(\.id), ["poker"])

        XCTAssertFalse(LibraryEditing.canMove("quant", toParent: "School", in: collections), "A library with libraries inside stays at the top")
        XCTAssertFalse(LibraryEditing.canMove("quant", toParent: "Quant", in: collections), "Not into itself")
        XCTAssertTrue(LibraryEditing.canMove("papers", toParent: "Quant", in: collections))

        let nested = LibraryEditing.moving(collection: "papers", toParent: "Quant", before: "poker", in: collections)
        XCTAssertEqual(nested.map(\.id), ["quant", "csd", "papers", "poker"])
        XCTAssertEqual(nested[2].parent, "Quant")
        let top = LibraryEditing.moving(collection: "poker", toParent: nil, before: "quant", in: nested)
        XCTAssertEqual(top.map(\.id), ["poker", "quant", "csd", "papers"])
        XCTAssertNil(top[0].parent)

        let renamed = LibraryEditing.renaming(collection: "quant", to: "Quantitative", in: nested)
        XCTAssertEqual(renamed.first { $0.id == "quant" }?.title, "Quantitative")
        XCTAssertEqual(renamed.filter { $0.parent == "Quantitative" }.map(\.id), ["papers", "poker"], "Sub-libraries follow their library")
        XCTAssertEqual(renamed.first { $0.id == "csd" }?.parent, "School")
    }

    func testFileNamesAreCheckedBeforeAnythingMoves() {
        XCTAssertNil(LibraryEditing.problem(withFileName: "Elements of Statistical Learning"))
        XCTAssertNotNil(LibraryEditing.problem(withFileName: "  "))
        XCTAssertNotNil(LibraryEditing.problem(withFileName: "a/b"))
        XCTAssertNotNil(LibraryEditing.problem(withFileName: "a:b"))
        XCTAssertNotNil(LibraryEditing.problem(withFileName: ".hidden"))
        XCTAssertNotNil(LibraryEditing.problem(withFileName: String(repeating: "x", count: 300)))
    }

    func testNamesGivenInLemmaArePersistedByPath() throws {
        let repository = LibraryTitleRepository(root: root.appendingPathComponent("support"))
        XCTAssertEqual(repository.load(), [:])
        try repository.save(["/a.pdf": "A book"])
        XCTAssertEqual(repository.load(), ["/a.pdf": "A book"])
        XCTAssertEqual(LibraryPaths.title(of: "/x/The_Mathematics_of_Poker.pdf"), "The Mathematics of Poker")
    }
}
