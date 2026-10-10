import XCTest
import LemmaCore

final class LassoTests: XCTestCase {
    func testOrthogonalDesignMatchesIndependentSoftThresholdAndProducesExactZeros() {
        let parameters = RidgeParameters(lambda: 120, correlation: 0)
        let result = LassoExperiment.run(parameters: parameters)
        let data = result.samples, n = Double(data.count)
        let mean = data.reduce(0) { $0 + $1.target } / n
        let z1 = data.reduce(0) { $0 + $1.x1 * ($1.target - mean) } / n
        let z2 = data.reduce(0) { $0 + $1.x2 * ($1.target - mean) } / n
        func shrink(_ z: Double) -> Double { max(0, abs(z) - parameters.lambda / (2 * n)) * (z < 0 ? -1 : 1) }
        XCTAssertEqual(result.beta1, shrink(z1), accuracy: 1e-12); XCTAssertEqual(result.beta2, shrink(z2), accuracy: 1e-12)
        XCTAssertEqual(result.beta2, 0); XCTAssertNotEqual(result.beta1, 0)
        let zero = LassoExperiment.run(parameters: .init(lambda: 200, correlation: 0))
        XCTAssertEqual(zero.beta1, 0); XCTAssertEqual(zero.beta2, 0)
    }

    func testCorrelatedAndRankDeficientSolutionsSatisfyLassoOptimalityConditions() {
        for parameters in [RidgeParameters(lambda: 20, correlation: 0.95), .init(lambda: 45, correlation: -0.8),
                           .init(lambda: 30, correlation: 1), .init(lambda: 30, correlation: -1)] {
            let result = LassoExperiment.run(parameters: parameters)
            let gradient = result.samples.reduce((0.0, 0.0)) { value, sample in
                let residual = sample.fitted - sample.target
                return (value.0 + 2 * sample.x1 * residual, value.1 + 2 * sample.x2 * residual)
            }
            for (coefficient, g) in [(result.beta1, gradient.0), (result.beta2, gradient.1)] {
                if coefficient == 0 { XCTAssertLessThanOrEqual(abs(g), parameters.lambda + 1e-8) }
                else { XCTAssertEqual(g + parameters.lambda * (coefficient > 0 ? 1 : -1), 0, accuracy: 1e-8) }
            }
            XCTAssertEqual(result.samples.reduce(0) { $0 + $1.fitted - $1.target }, 0, accuracy: 1e-10)
            if abs(parameters.correlation) == 1 { XCTAssertTrue(result.isRankDeficient) }
        }
    }

    func testLassoRecordAndReproductionDataExportWithTheirSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = WorkspaceRepository(root: root)
        let anchor = SourceAnchor(pageIndex: 4, pageLabel: "5", region: .init(x: 20, y: 30, width: 100, height: 40), quote: "L1", imageName: "source.png")
        var note = StudyNote(anchor: anchor, question: "Why exact zeros?")
        let record = ExperimentRecord(kind: .lasso, noteID: note.id, source: anchor, prediction: "The smaller coefficient will reach zero first.",
            observation: "At lambda 120 beta two was zero.", startingParameters: .init(correlation: 0), parameters: .init(lambda: 120, correlation: 0), predictedAt: .now)
        note.experiments = [record]
        var workspace = StudyWorkspace(id: "lasso", title: "Lasso study", sourcePath: "/study.pdf", sourceBookmark: nil, fingerprint: "lasso")
        workspace.notes = [note]
        try repository.saveImage(Data([1]), workspaceID: workspace.id, name: anchor.imageName); try repository.save(workspace)
        let restored = try XCTUnwrap(repository.load(id: workspace.id))
        XCTAssertEqual(restored.notes.first?.experiments.first?.kind, .lasso)
        let destination = root.appendingPathComponent("export"); try repository.export(restored, to: destination)
        let path = destination.appendingPathComponent("experiments/\(ExperimentExport.stem(record))")
        let csv = try String(contentsOf: URL(fileURLWithPath: path.path + "-samples.csv"), encoding: .utf8)
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.count, 41)
        let first = rows[1].split(separator: ",").compactMap { Double($0) }
        let result = LassoExperiment.run(parameters: record.parameters)
        XCTAssertEqual(first[4], result.samples[0].fitted, accuracy: 1e-12)
        let markdown = repository.markdown(for: restored)
        XCTAssertTrue(markdown.contains("Lasso experiment")); XCTAssertTrue(markdown.contains("alpha = λ / (2n)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path + ".py"))
    }
}
