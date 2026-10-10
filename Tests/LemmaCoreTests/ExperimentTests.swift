import XCTest
import LemmaCore

final class ExperimentTests: XCTestCase {
    func testSyntheticDesignIsDeterministicCenteredAndHasRequestedCorrelation() {
        let parameters = RidgeParameters(lambda: 3, correlation: 0.97, seed: 17)
        let result = RidgeExperiment.run(parameters: parameters)
        XCTAssertEqual(result, RidgeExperiment.run(parameters: parameters))
        let differentSeed = RidgeExperiment.run(parameters: RidgeParameters(lambda: 3, correlation: 0.97, seed: 18))
        XCTAssertNotEqual(result.samples, differentSeed.samples)
        let n = Double(result.samples.count)
        let x1 = result.samples.map(\.x1), x2 = result.samples.map(\.x2)
        XCTAssertEqual(x1.reduce(0, +) / n, 0, accuracy: 1e-12)
        XCTAssertEqual(x2.reduce(0, +) / n, 0, accuracy: 1e-12)
        XCTAssertEqual(x1.reduce(0) { $0 + $1 * $1 } / n, 1, accuracy: 1e-12)
        XCTAssertEqual(x2.reduce(0) { $0 + $1 * $1 } / n, 1, accuracy: 1e-12)
        XCTAssertEqual(zip(x1, x2).reduce(0) { $0 + $1.0 * $1.1 } / n, 0.97, accuracy: 1e-12)
    }

    func testLeastSquaresAndRidgeAreStationaryForTheStatedUnpenalizedInterceptObjective() {
        let scenarios = [RidgeParameters(lambda: 0, correlation: 0),
                         RidgeParameters(lambda: 0, correlation: 0.9999),
                         RidgeParameters(lambda: 2.5, correlation: 0.95),
                         RidgeParameters(lambda: 100, correlation: -1)]
        for parameters in scenarios {
            let result = RidgeExperiment.run(parameters: parameters)
            let residuals = result.samples.map { $0.fitted - $0.target }
            let interceptGradient = 2 * residuals.reduce(0, +)
            let beta1Gradient = 2 * zip(result.samples, residuals).reduce(0) { $0 + $1.0.x1 * $1.1 }
                + 2 * parameters.lambda * result.beta1
            let beta2Gradient = 2 * zip(result.samples, residuals).reduce(0) { $0 + $1.0.x2 * $1.1 }
                + 2 * parameters.lambda * result.beta2
            XCTAssertEqual(interceptGradient, 0, accuracy: 1e-8)
            XCTAssertEqual(beta1Gradient, 0, accuracy: 1e-8)
            XCTAssertEqual(beta2Gradient, 0, accuracy: 1e-8)
            let perturbedObjective = result.samples.reduce(0) { sum, sample in
                let residual = result.intercept + 0.1 + (result.beta1 + 0.2) * sample.x1
                    + (result.beta2 - 0.3) * sample.x2 - sample.target
                return sum + residual * residual
            } + parameters.lambda * (pow(result.beta1 + 0.2, 2) + pow(result.beta2 - 0.3, 2))
            XCTAssertLessThan(result.penalizedObjective, perturbedObjective)
        }
    }

    func testRidgeMatchesAnIndependentFullRankNormalEquationSolution() {
        let result = RidgeExperiment.run(parameters: RidgeParameters(lambda: 2.5, correlation: 0.4))
        let a = result.samples.reduce(0) { $0 + $1.x1 * $1.x1 } + 2.5
        let b = result.samples.reduce(0) { $0 + $1.x1 * $1.x2 }
        let d = result.samples.reduce(0) { $0 + $1.x2 * $1.x2 } + 2.5
        let c1 = result.samples.reduce(0) { $0 + $1.x1 * ($1.target - 1) }
        let c2 = result.samples.reduce(0) { $0 + $1.x2 * ($1.target - 1) }
        XCTAssertEqual(result.beta1, (d * c1 - b * c2) / (a * d - b * b), accuracy: 1e-12)
        XCTAssertEqual(result.beta2, (a * c2 - b * c1) / (a * d - b * b), accuracy: 1e-12)
    }

    func testIncreasingPenaltyShrinksNormRaisesTrainingRSSAndRetainsTheIntercept() {
        let fits = [0.0, 1, 100, 1e9].map {
            RidgeExperiment.run(parameters: RidgeParameters(lambda: $0, correlation: 0.99))
        }
        for pair in zip(fits, fits.dropFirst()) {
            XCTAssertGreaterThan(pair.0.coefficientNorm, pair.1.coefficientNorm)
            XCTAssertLessThan(pair.0.residualSumOfSquares, pair.1.residualSumOfSquares)
        }
        for fit in fits { XCTAssertEqual(fit.intercept, 1, accuracy: 1e-12) }
        XCTAssertLessThan(fits.last!.coefficientNorm, 1e-6)
        XCTAssertTrue(fits.last!.samples.allSatisfy { abs($0.fitted - 1) < 1e-6 })
    }

    func testExactCollinearityReturnsMinimumNormLeastSquaresAndFiniteRidge() {
        for correlation in [-1.0, 1.0] {
            let fit = RidgeExperiment.run(parameters: RidgeParameters(lambda: 0, correlation: correlation))
            XCTAssertTrue(fit.isRankDeficient)
            XCTAssertEqual(fit.beta2, correlation * fit.beta1, accuracy: 1e-12)
            let otherBeta1 = fit.beta1 + 3
            let otherBeta2 = fit.beta2 - correlation * 3
            XCTAssertGreaterThan(hypot(otherBeta1, otherBeta2), fit.coefficientNorm)
            for sample in fit.samples {
                XCTAssertEqual(fit.intercept + otherBeta1 * sample.x1 + otherBeta2 * sample.x2,
                               sample.fitted, accuracy: 1e-12)
            }
            let ridge = RidgeExperiment.run(parameters: RidgeParameters(lambda: 1, correlation: correlation))
            XCTAssertTrue(ridge.beta1.isFinite && ridge.beta2.isFinite && ridge.trainingMSE.isFinite)
            XCTAssertLessThan(ridge.coefficientNorm, fit.coefficientNorm)
        }
    }

    func testExperimentRecordRoundTripPreservesPredictionParametersAndSource() throws {
        let source = SourceAnchor(pageIndex: 3, pageLabel: "iv", region: PageRegion(x: 10, y: 20, width: 100, height: 40),
                                  quote: "The ridge estimator", imageName: "ridge.png")
        let record = ExperimentRecord(noteID: UUID(), source: source, prediction: "The norm will shrink.",
                                      observation: "The training RSS increased.", startingParameters: RidgeParameters(),
                                      parameters: RidgeParameters(lambda: 20, correlation: 1), predictedAt: Date(timeIntervalSince1970: 100))
        let decoded = try JSONDecoder().decode(ExperimentRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(RidgeExperiment.run(parameters: decoded.parameters), RidgeExperiment.run(parameters: record.parameters))
        XCTAssertThrowsError(try JSONDecoder().decode(RidgeParameters.self,
            from: Data(#"{"lambda":1,"correlation":2,"seed":17,"sampleCount":40}"#.utf8)))
    }
}
