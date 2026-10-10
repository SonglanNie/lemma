import Foundation

/// Exact two-predictor Lasso illustration: enumerate zero, one-active, and signed
/// two-active solutions, then evaluate the stated convex objective on the same data.
public enum LassoExperiment {
    public static let objectiveDescription = "RSS + λ(|β₁| + |β₂|); intercept unpenalized; RSS is a sum. Equivalent scikit-learn alpha = λ / (2n)."

    public static func run(parameters: RidgeParameters) -> RidgeResult {
        precondition(parameters.isValid)
        let leastSquares = RidgeExperiment.run(parameters: .init(lambda: 0, correlation: parameters.correlation, seed: parameters.seed, sampleCount: parameters.sampleCount))
        let data = leastSquares.samples, n = Double(data.count)
        let yMean = data.reduce(0) { $0 + $1.target } / n
        let x1Mean = data.reduce(0) { $0 + $1.x1 } / n, x2Mean = data.reduce(0) { $0 + $1.x2 } / n
        let x1 = data.map { $0.x1 - x1Mean }, x2 = data.map { $0.x2 - x2Mean }, y = data.map { $0.target - yMean }
        func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
        let a = dot(x1, x1), c = dot(x2, x2), b = dot(x1, x2)
        let q1 = dot(x1, y), q2 = dot(x2, y), threshold = parameters.lambda / 2
        func shrink(_ value: Double) -> Double { value > threshold ? value - threshold : value < -threshold ? value + threshold : 0 }
        if parameters.lambda == 0 { var result = leastSquares; result.kind = .lasso; return result }
        var candidates: [(Double, Double)] = [(0, 0), (shrink(q1) / a, 0), (0, shrink(q2) / c)]
        if !leastSquares.isRankDeficient {
            let determinant = a * c - b * b
            for sign1 in [-1.0, 1.0] {
                for sign2 in [-1.0, 1.0] {
                    let r1 = q1 - threshold * sign1, r2 = q2 - threshold * sign2
                    let beta1 = (c * r1 - b * r2) / determinant, beta2 = (a * r2 - b * r1) / determinant
                    if beta1 * sign1 > 0 && beta2 * sign2 > 0 { candidates.append((beta1, beta2)) }
                }
            }
        }
        func objective(_ coefficients: (Double, Double)) -> Double {
            let rss = y.indices.reduce(0) { sum, i in
                let residual = y[i] - x1[i] * coefficients.0 - x2[i] * coefficients.1
                return sum + residual * residual
            }
            return rss + parameters.lambda * (abs(coefficients.0) + abs(coefficients.1))
        }
        let coefficients = candidates.min { objective($0) < objective($1) }!
        let intercept = yMean - coefficients.0 * x1Mean - coefficients.1 * x2Mean
        let samples = data.map { sample in
            RidgeSample(id: sample.id, x1: sample.x1, x2: sample.x2, target: sample.target,
                fitted: intercept + coefficients.0 * sample.x1 + coefficients.1 * sample.x2)
        }
        let rss = samples.reduce(0) { $0 + pow($1.target - $1.fitted, 2) }
        return RidgeResult(kind: .lasso, parameters: parameters, beta1: coefficients.0, beta2: coefficients.1,
            intercept: intercept, residualSumOfSquares: rss, samples: samples, isRankDeficient: leastSquares.isRankDeficient)
    }

    public static func coefficientPath(parameters: RidgeParameters) -> [RidgePathPoint] {
        (0...60).map { index in
            let lambda = Double(index) / 60 * 200
            let result = run(parameters: .init(lambda: lambda, correlation: parameters.correlation, seed: parameters.seed, sampleCount: parameters.sampleCount))
            return RidgePathPoint(id: index, lambda: lambda, beta1: result.beta1, beta2: result.beta2)
        }
    }
}
