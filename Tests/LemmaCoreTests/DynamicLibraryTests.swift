import XCTest
@testable import LemmaCore

final class DynamicLibraryTests: XCTestCase {
    func testExplicitFileAndFolderRenamesPersistAndKeepExclusions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Original folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("Original.pdf")
        try Data("metadata-only fixture".utf8).write(to: source)
        let original = [
            LibraryCollection(id: "stats", title: "Stats", kind: .studying, sources: [LibrarySource(path: source.path, kind: .file)]),
            LibraryCollection(id: "quant", title: "Quant", kind: .studying, sources: [LibrarySource(path: folder.path, excludedPaths: [source.path])])
        ]
        let initial = LibraryScanner.scan(original)
        XCTAssertNotNil(initial.collections[0].sources[0].bookmark)
        XCTAssertNotNil(initial.collections[1].sources[0].bookmark)
        let renamed = folder.appendingPathComponent("Renamed.pdf")
        try FileManager.default.moveItem(at: source, to: renamed)
        let fileRename = LibraryScanner.scan(initial.collections)
        XCTAssertTrue(fileRename.issues.isEmpty)
        XCTAssertEqual(fileRename.entries.map(\.collectionID), ["stats"])
        XCTAssertEqual(fileRename.entries.map { LibraryPaths.key($0.path) }, [LibraryPaths.key(renamed.path)])
        XCTAssertEqual(fileRename.collections[1].sources[0].excludedPaths.map(LibraryPaths.key), [LibraryPaths.key(renamed.path)])

        let renamedFolder = root.appendingPathComponent("Renamed folder")
        try FileManager.default.moveItem(at: folder, to: renamedFolder)
        let folderRename = LibraryScanner.scan(fileRename.collections)
        XCTAssertTrue(folderRename.issues.isEmpty)
        XCTAssertEqual(folderRename.entries.map { LibraryPaths.key($0.path) }, [LibraryPaths.key(renamedFolder.appendingPathComponent("Renamed.pdf").path)])
        XCTAssertEqual(folderRename.entries.map(\.collectionID), ["stats"])
        let repository = LibraryCollectionRepository(root: root.appendingPathComponent("support"))
        try repository.save(folderRename.collections)
        let restored = LibraryScanner.scan(try XCTUnwrap(repository.load()))
        XCTAssertEqual(restored.entries, folderRename.entries)
        XCTAssertTrue(restored.issues.isEmpty)
        try FileManager.default.removeItem(at: renamedFolder)
        XCTAssertTrue(LibraryScanner.scan(restored.collections).entries.isEmpty)
        XCTAssertNotNil(LibraryScanner.scan(restored.collections).issues["stats"], "A genuinely missing source is still reported")
    }

    func testLegacySourceFollowsWorkspaceBookmarkEvenWhenBookAlreadyReopened() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("Original_book.pdf"), renamed = root.appendingPathComponent("New name.pdf")
        try Data("metadata-only fixture".utf8).write(to: original)
        let bookmark = try original.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        var workspace = StudyWorkspace(id: "book", title: "Original book", sourcePath: original.path, sourceBookmark: bookmark, fingerprint: "book")
        let collections = [LibraryCollection(id: "stats", title: "Stats", kind: .studying, sources: [LibrarySource(path: original.path, kind: .file)])]
        try FileManager.default.moveItem(at: original, to: renamed)
        let beforeReopen = LibraryScanner.scan(collections, workspaces: [workspace])
        XCTAssertTrue(beforeReopen.issues.isEmpty)
        XCTAssertEqual(beforeReopen.entries.map { LibraryPaths.key($0.path) }, [LibraryPaths.key(renamed.path)])
        XCTAssertEqual(beforeReopen.workspaceSources[workspace.id].map { LibraryPaths.key($0.path) }, LibraryPaths.key(renamed.path))

        workspace.sourcePath = renamed.path
        workspace.sourceBookmark = try renamed.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let alreadyReopened = LibraryScanner.scan(collections, workspaces: [workspace])
        XCTAssertTrue(alreadyReopened.issues.isEmpty)
        XCTAssertEqual(alreadyReopened.entries.map { LibraryPaths.key($0.path) }, [LibraryPaths.key(renamed.path)])
        XCTAssertNotNil(alreadyReopened.collections[0].sources[0].bookmark)
    }

    func testRecursiveDiscoveryExclusionsAndSourceChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Cours en promotion complète")
        let nested = folder.appendingPathComponent("03 Supports/Slides")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let stats = folder.appendingPathComponent("ISLP.pdf")
        let course = nested.appendingPathComponent("Ch2.PDF")
        for url in [stats, course, folder.appendingPathComponent(".hidden.pdf"), folder.appendingPathComponent("readme.txt")] { try Data("placeholder; indexing must not read PDF contents".utf8).write(to: url) }
        let quant = LibraryCollection(id: "quant", title: "Quant", kind: .studying, sources: [LibrarySource(path: folder.path, excludedPaths: [stats.path.precomposedStringWithCanonicalMapping])])
        let statsLibrary = LibraryCollection(id: "stats", title: "Stats", kind: .studying, sources: [LibrarySource(path: stats.path, kind: .file), LibrarySource(path: stats.path, kind: .file)])
        let first = LibraryScanner.scan([quant, statsLibrary])
        XCTAssertEqual(first.entries.filter { $0.collectionID == "quant" }.map(\.folder), ["03 Supports/Slides"])
        XCTAssertEqual(first.entries.filter { $0.collectionID == "stats" }.count, 1)
        XCTAssertTrue(first.issues.isEmpty)
        let moved = nested.appendingPathComponent("Renamed.pdf")
        try FileManager.default.moveItem(at: course, to: moved)
        XCTAssertEqual(LibraryScanner.scan([quant]).entries.map(\.title), ["Renamed"])
        let keyBeforeRemoval = LibraryPaths.key(moved.path)
        try FileManager.default.removeItem(at: moved)
        XCTAssertEqual(LibraryPaths.key(moved.path), keyBeforeRemoval, "Deleted PDFs keep the same canonical key for filesystem events")
        XCTAssertTrue(LibraryScanner.scan([quant]).entries.isEmpty)
        try FileManager.default.removeItem(at: stats)
        XCTAssertNotNil(LibraryScanner.scan([statsLibrary]).issues["stats"])
    }

    func testPublicDefaultsAndPersistentSources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("support")
        let defaults = LibraryCollection.publicDefaults(support: support)
        XCTAssertEqual(defaults.map(\.id), ["books", "papers"])
        XCTAssertEqual(defaults.first?.sources.first?.path, support.appendingPathComponent("Books").path)
        // Neither folder exists before the first download, and that is not reported as a problem.
        XCTAssertTrue(LibraryScanner.scan(defaults).issues.isEmpty)
        let repository = LibraryCollectionRepository(root: root)
        XCTAssertNil(try repository.load())
        try repository.save(defaults)
        XCTAssertEqual(try repository.load(), defaults)
    }
}
