import XCTest
@testable import LemmaCore

final class NeighborsExperimentTests: XCTestCase {
    /// Building a model sorts 15,000 neighbour lists; debug builds share one.
    private static let shared = NeighborsExperiment.model(seed: 17, gridSize: 30)

    func testSimulationFollowsTheBookDesignAndIsDeterministic() {
        let model = Self.shared
        let again = NeighborsExperiment.model(seed: 17, gridSize: 2)
        XCTAssertEqual(model.training, again.training, "The same seed reproduces the same draw.")
        XCTAssertEqual(model.curve, again.curve)
        XCTAssertNotEqual(model.training, NeighborsExperiment.model(seed: 18, gridSize: 2).training)
        XCTAssertEqual(model.training.count, 200); XCTAssertEqual(model.test.count, 10_000)
        XCTAssertEqual(model.training.filter(\.orange).count, 100)
        XCTAssertEqual(model.test.filter(\.orange).count, 5_000)
        XCTAssertEqual(model.blueMeans.count, 10); XCTAssertEqual(model.orangeMeans.count, 10)
        let blueCentre = model.blueMeans.reduce((0.0, 0.0)) { ($0.0 + $1.0 / 10, $0.1 + $1.1 / 10) }
        XCTAssertEqual(blueCentre.0, 1, accuracy: 0.9, "BLUE means centre on (1, 0).")
        XCTAssertEqual(blueCentre.1, 0, accuracy: 0.9)

        // Every point lies near one of its class's means: within 5 noise standard deviations.
        let sd = NeighborsExperiment.noiseVariance.squareRoot()
        for sample in model.training {
            let means = sample.orange ? model.orangeMeans : model.blueMeans
            XCTAssertTrue(means.contains { hypot(sample.x1 - $0.0, sample.x2 - $0.1) < 5 * sd })
        }
    }

    func testLeastSquaresSolvesTheNormalEquations() {
        let model = Self.shared
        let (b0, b1, b2) = model.linear
        var gradient = [0.0, 0, 0]
        for sample in model.training {
            let residual = (sample.orange ? 1.0 : 0) - (b0 + b1 * sample.x1 + b2 * sample.x2)
            gradient[0] += residual; gradient[1] += residual * sample.x1; gradient[2] += residual * sample.x2
        }
        for value in gradient { XCTAssertEqual(value, 0, accuracy: 1e-9, "Xᵀ(y − Xβ) = 0, as in (2.5).") }
        XCTAssertGreaterThan(b2 - b1, 0, "ORANGE lies toward larger x₂, BLUE toward larger x₁.")
    }

    func testErrorCurveMatchesDirectClassificationAndTheBooksShape() {
        let model = Self.shared
        func direct(k: Int, _ samples: [MixtureSample]) -> Double {
            let wrong = samples.filter { sample in
                let nearest = model.training.enumerated().sorted {
                    let a = hypot($0.element.x1 - sample.x1, $0.element.x2 - sample.x2), b = hypot($1.element.x1 - sample.x1, $1.element.x2 - sample.x2)
                    return a == b ? $0.offset < $1.offset : a < b
                }.prefix(k)
                let orange = Double(nearest.filter(\.element.orange).count) / Double(k) > 0.5
                return orange != sample.orange
            }.count
            return Double(wrong) / Double(samples.count)
        }
        for k in [1, 15, 51] {
            let point = try! XCTUnwrap(model.errors(k: k))
            XCTAssertEqual(point.trainingError, direct(k: k, model.training), accuracy: 1e-12)
            XCTAssertEqual(point.degreesOfFreedom, 200 / Double(k), accuracy: 1e-12)
        }
        XCTAssertEqual(model.errors(k: 15)?.testError ?? -1, direct(k: 15, model.test), accuracy: 1e-12, "All 10,000 test points.")
        XCTAssertEqual(model.errors(k: 1)?.trainingError, 0, "1-nearest neighbour fits every training point (Figure 2.3).")
        let best = model.curve.map(\.testError).min()!
        XCTAssertGreaterThan(model.errors(k: 1)!.testError, best + 0.02, "k = 1 overfits.")
        XCTAssertLessThanOrEqual(model.bayesTestError, best + 0.01, "The Bayes rule is the benchmark for every classifier.")
        XCTAssertLessThanOrEqual(model.bayesTestError, model.linearTestError + 0.01)
        XCTAssertGreaterThan(model.bayesTestError, 0.05, "The classes overlap; even the Bayes rule errs.")
    }

    func testGridDecisionsAndBayesBoundary() {
        let model = Self.shared
        let grid = model.grid
        XCTAssertEqual(grid.neighborsOrange(k: 15).count, 900)
        for (index, orange) in grid.neighborsOrange(k: 199).enumerated() where index % 97 == 0 {
            let centre = grid.center(column: index % grid.columns, row: index / grid.columns)
            let direct = NeighborsExperiment.cumulativeOrange(centre.x1, centre.x2, training: model.training)[199]
            XCTAssertEqual(orange, 2 * Int(direct) > 199)
        }
        let segments = NeighborsExperiment.zeroContour(grid)
        XCTAssertFalse(segments.isEmpty, "The Bayes boundary crosses the plotted region (Figure 2.5).")
        for (a, _) in segments.prefix(20) {
            let margin = NeighborsExperiment.logDensity(a.0, a.1, model.orangeMeans) - NeighborsExperiment.logDensity(a.0, a.1, model.blueMeans)
            XCTAssertLessThan(abs(margin), 1.5, "Contour points lie near equal class densities.")
        }
    }
}
