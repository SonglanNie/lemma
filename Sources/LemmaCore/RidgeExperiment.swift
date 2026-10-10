import Foundation

public enum ExperimentKind: String, Codable, CaseIterable, Sendable {
    case ridge, lasso, nearestNeighbors

    public var label: String {
        switch self {
        case .ridge: "Ridge regression"
        case .lasso: "Lasso regression"
        case .nearestNeighbors: "Least squares vs nearest neighbours"
        }
    }
}

/// The classifier shown in the ESL §2.3 simulation.
public struct NeighborsSettings: Codable, Equatable, Sendable {
    public enum Classifier: String, Codable, CaseIterable, Sendable { case linear, neighbors }
    public var classifier: Classifier
    public var k: Int
    public var showBayes: Bool
    public init(classifier: Classifier = .neighbors, k: Int = 15, showBayes: Bool = false) {
        self.classifier = classifier; self.k = k; self.showBayes = showBayes
    }
    public var summary: String { classifier == .linear ? "Linear regression of 0/1" : "\(k)-nearest neighbours" }
}

public struct RidgeParameters: Codable, Equatable, Sendable {
    public var lambda: Double
    public var correlation: Double
    public var seed: UInt64
    public var sampleCount: Int

    public init(lambda: Double = 1, correlation: Double = 0.95, seed: UInt64 = 17, sampleCount: Int = 40) {
        self.lambda = lambda; self.correlation = correlation
        self.seed = seed; self.sampleCount = sampleCount
    }

    /// The local illustration is deliberately small. This also bounds an imported record.
    public var isValid: Bool {
        lambda.isFinite && lambda >= 0 && correlation.isFinite && (-1...1).contains(correlation)
            && (8...200).contains(sampleCount)
    }

    private enum CodingKeys: String, CodingKey { case lambda, correlation, seed, sampleCount }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lambda = try c.decode(Double.self, forKey: .lambda)
        correlation = try c.decode(Double.self, forKey: .correlation)
        seed = try c.decode(UInt64.self, forKey: .seed)
        sampleCount = try c.decode(Int.self, forKey: .sampleCount)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ridge experiment parameters."))
        }
    }
}

public struct ExperimentRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ExperimentKind
    public var noteID: UUID
    public var source: SourceAnchor
    public var prediction: String
    public var observation: String
    public var startingParameters: RidgeParameters
    public var parameters: RidgeParameters
    public var predictedAt: Date
    public var savedAt: Date
    public var datasetVersion: Int
    /// The ESL §2.3 simulation's classifier settings; `parameters.seed` is its random draw.
    public var neighbors: NeighborsSettings?
    public var startingNeighbors: NeighborsSettings?

    public init(id: UUID = UUID(), kind: ExperimentKind = .ridge, noteID: UUID, source: SourceAnchor,
                prediction: String, observation: String, startingParameters: RidgeParameters,
                parameters: RidgeParameters, predictedAt: Date, savedAt: Date = .now, datasetVersion: Int = 1) {
        self.id = id; self.kind = kind; self.noteID = noteID; self.source = source
        self.prediction = prediction; self.observation = observation
        self.startingParameters = startingParameters; self.parameters = parameters
        self.predictedAt = predictedAt; self.savedAt = savedAt; self.datasetVersion = datasetVersion
    }
}

public struct RidgeSample: Identifiable, Equatable, Sendable {
    public var id: Int
    public var x1: Double
    public var x2: Double
    public var target: Double
    public var fitted: Double
}

public struct RidgeResult: Equatable, Sendable {
    public var kind: ExperimentKind = .ridge
    public var parameters: RidgeParameters
    public var beta1: Double
    public var beta2: Double
    public var intercept: Double
    public var residualSumOfSquares: Double
    public var samples: [RidgeSample]
    public var isRankDeficient: Bool

    public var coefficientNorm: Double { sqrt(beta1 * beta1 + beta2 * beta2) }
    public var l1Norm: Double { abs(beta1) + abs(beta2) }
    public var trainingMSE: Double { residualSumOfSquares / Double(samples.count) }
    public var penalizedObjective: Double {
        residualSumOfSquares + parameters.lambda * (kind == .ridge ? beta1 * beta1 + beta2 * beta2 : l1Norm)
    }
}

public struct RidgePathPoint: Identifiable, Equatable, Sendable {
    public var id: Int
    public var lambda: Double
    public var beta1: Double
    public var beta2: Double
}

/// A deterministic illustration of two correlated predictors, not a reproduction of a paper.
/// V1: centered predictors with sum(x_j²)/n = 1, y = 1 + 2*x1 - x2 + 0.25*e,
/// where e is a centered, unit-variance synthetic vector. No held-out claim is made.
public enum RidgeExperiment {
    public static let datasetVersion = 1
    public static let objectiveDescription = "RSS + λ(β₁² + β₂²); intercept unpenalized; RSS is a sum, not a mean."
    public static let dataDescription = "Synthetic V1: y = 1 + 2x₁ − x₂ + 0.25e. Predictors and e are centered with sum of squares / n = 1; corr(x₁, x₂) = ρ. Fixed seed; no held-out evaluation."

    public static func run(parameters: RidgeParameters) -> RidgeResult {
        precondition(parameters.isValid, "Ridge parameters must have λ ≥ 0, ρ in [-1, 1], and 8...200 observations.")
        let n = parameters.sampleCount
        var random = SplitMix64(seed: parameters.seed)
        let u = standardized((0..<n).map { _ in random.nextCentered() })
        let rawV = centered((0..<n).map { _ in random.nextCentered() })
        let projection = dot(u, rawV) / Double(n)
        let v = standardized(zip(rawV, u).map { $0 - projection * $1 })
        let noise = standardized((0..<n).map { _ in random.nextCentered() })
        let rho = parameters.correlation
        let independentScale = sqrt(max(0, (1 - rho) * (1 + rho)))
        let x2 = zip(u, v).map { rho * $0 + independentScale * $1 }
        let targets: [Double] = (0..<n).map { index in
            let signal = 2.0 * u[index] - x2[index]
            return 1.0 + signal + 0.25 * noise[index]
        }
        let targetMean = targets.reduce(0, +) / Double(n)
        let y = targets.map { $0 - targetMean }

        // Equal predictor norms make (x1+x2)/√2 and (x1−x2)/√2 orthogonal.
        // Work in those directions to avoid a determinant subtraction near |ρ| = 1.
        let rootTwo = sqrt(2.0)
        let plus = zip(u, x2).map { ($0 + $1) / rootTwo }
        let minus = zip(u, x2).map { ($0 - $1) / rootTwo }
        let plusEnergy = dot(plus, plus)
        let minusEnergy = dot(minus, minus)
        let rankDeficient = abs(rho) == 1
        func component(_ direction: [Double], energy: Double) -> Double {
            // At λ=0 choose the Moore–Penrose / minimum-norm least-squares solution.
            if parameters.lambda == 0 && energy == 0 { return 0 }
            return dot(direction, y) / (energy + parameters.lambda)
        }
        let plusCoefficient = component(plus, energy: plusEnergy)
        let minusCoefficient = component(minus, energy: minusEnergy)
        let beta1 = (plusCoefficient + minusCoefficient) / rootTwo
        let beta2 = (plusCoefficient - minusCoefficient) / rootTwo
        let x1Mean = u.reduce(0, +) / Double(n)
        let x2Mean = x2.reduce(0, +) / Double(n)
        let intercept = targetMean - beta1 * x1Mean - beta2 * x2Mean
        let samples = (0..<n).map { index in
            RidgeSample(id: index, x1: u[index], x2: x2[index], target: targets[index],
                        fitted: intercept + beta1 * u[index] + beta2 * x2[index])
        }
        let rss = samples.reduce(0) { sum, sample in
            let residual = sample.target - sample.fitted
            return sum + residual * residual
        }
        return RidgeResult(parameters: parameters, beta1: beta1, beta2: beta2, intercept: intercept,
                           residualSumOfSquares: rss, samples: samples, isRankDeficient: rankDeficient)
    }

    /// Dense near zero, with λ=0 present explicitly. All points use the same synthetic data.
    public static func coefficientPath(parameters: RidgeParameters) -> [RidgePathPoint] {
        (0...40).map { index in
            let lambda = pow(101, Double(index) / 40) - 1
            let result = run(parameters: RidgeParameters(lambda: lambda, correlation: parameters.correlation,
                                                         seed: parameters.seed, sampleCount: parameters.sampleCount))
            return RidgePathPoint(id: index, lambda: lambda, beta1: result.beta1, beta2: result.beta2)
        }
    }

    private static func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
    private static func centered(_ values: [Double]) -> [Double] {
        let mean = values.reduce(0, +) / Double(values.count)
        return values.map { $0 - mean }
    }
    private static func standardized(_ values: [Double]) -> [Double] {
        let values = centered(values)
        let scale = sqrt(Double(values.count) / dot(values, values))
        return values.map { $0 * scale }
    }
}

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func nextCentered() -> Double {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        value ^= value >> 31
        return 2 * Double(value >> 11) / 9_007_199_254_740_992 - 1
    }
}
