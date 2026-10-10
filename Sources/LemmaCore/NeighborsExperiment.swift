import Foundation

/// ESL §2.3.3's simulation: two classes, each a mixture of ten Gaussian clusters.
/// BLUE means come from N((1,0)ᵀ, I), ORANGE means from N((0,1)ᵀ, I); every observation picks one of its
/// class's means with probability 1/10 and adds N(0, I/5) noise. The design follows the book; the random
/// draw is Lemma's own, so values resemble Figures 2.1–2.5 without matching them exactly.
public struct MixtureSample: Equatable, Sendable {
    public var x1: Double
    public var x2: Double
    /// ORANGE is coded 1 and BLUE 0, as in the book's regression.
    public var orange: Bool
    public init(x1: Double, x2: Double, orange: Bool) { self.x1 = x1; self.x2 = x2; self.orange = orange }
}

public struct NeighborsErrorPoint: Identifiable, Equatable, Sendable {
    public var id: Int { k }
    public var k: Int
    /// The book's horizontal axis: effective degrees of freedom N/k.
    public var degreesOfFreedom: Double
    public var trainingError: Double
    public var testError: Double
}

/// Class decisions on a regular grid over the plotted region, for every k at once.
public struct DecisionGrid: Sendable {
    public let minX1: Double, maxX1: Double, minX2: Double, maxX2: Double
    public let columns: Int, rows: Int
    /// For each cell, the number of ORANGE points among its j nearest training points, j = 0…N.
    let orangeCounts: [[UInt16]]
    public let linearOrange: [Bool]
    public let bayesOrange: [Bool]
    /// log p(x | ORANGE) − log p(x | BLUE) at cell centres, for the Bayes boundary.
    public let bayesMargin: [Double]

    public func center(column: Int, row: Int) -> (x1: Double, x2: Double) {
        (minX1 + (Double(column) + 0.5) / Double(columns) * (maxX1 - minX1), minX2 + (Double(row) + 0.5) / Double(rows) * (maxX2 - minX2))
    }

    /// The k-nearest-neighbour class of each cell: ORANGE when the average 0/1 response exceeds 0.5.
    public func neighborsOrange(k: Int) -> [Bool] { orangeCounts.map { 2 * Int($0[k]) > k } }
}

public struct MixtureModel: Sendable {
    public static let datasetVersion = 1
    public let seed: UInt64
    public let blueMeans: [(Double, Double)]
    public let orangeMeans: [(Double, Double)]
    public let training: [MixtureSample]
    public let test: [MixtureSample]
    /// Least squares on the 0/1 response with an intercept: ŷ = β₀ + β₁x₁ + β₂x₂.
    public let linear: (beta0: Double, beta1: Double, beta2: Double)
    public let linearTrainingError: Double
    public let linearTestError: Double
    public let bayesTestError: Double
    public let curve: [NeighborsErrorPoint]
    public let grid: DecisionGrid

    public func errors(k: Int) -> NeighborsErrorPoint? { curve.first { $0.k == k } }
}

public enum NeighborsExperiment {
    public static let noiseVariance = 0.2
    public static let trainingPerClass = 100
    public static let testPerClass = 5_000
    /// Odd k avoid ties in the 0.5 rule; 199 uses every other training point.
    public static let neighborCounts = Array(stride(from: 1, through: 199, by: 2))
    public static let description = "ESL §2.3.3 design: 10 means per class from N((1,0)ᵀ, I) for BLUE and N((0,1)ᵀ, I) for ORANGE; each point picks a mean with probability 1/10 and adds N(0, I/5). 100 training points per class, 10,000 test points. Lemma’s random draw differs from the book’s."

    public static func model(seed: UInt64 = 17, gridSize: Int = 72) -> MixtureModel {
        var random = GaussianSource(seed: seed)
        let blueMeans = (0..<10).map { _ in (1 + random.normal(), random.normal()) }
        let orangeMeans = (0..<10).map { _ in (random.normal(), 1 + random.normal()) }
        let sd = noiseVariance.squareRoot()
        func draw(_ count: Int, _ means: [(Double, Double)], orange: Bool) -> [MixtureSample] {
            (0..<count).map { _ in
                let mean = means[random.index(10)]
                return MixtureSample(x1: mean.0 + sd * random.normal(), x2: mean.1 + sd * random.normal(), orange: orange)
            }
        }
        let training = draw(trainingPerClass, blueMeans, orange: false) + draw(trainingPerClass, orangeMeans, orange: true)
        let test = draw(testPerClass, blueMeans, orange: false) + draw(testPerClass, orangeMeans, orange: true)
        let linear = leastSquares(training)
        func linearOrange(_ x1: Double, _ x2: Double) -> Bool { linear.0 + linear.1 * x1 + linear.2 * x2 > 0.5 }
        func errorRate(_ samples: [MixtureSample], _ classify: (MixtureSample) -> Bool) -> Double {
            Double(samples.filter { classify($0) != $0.orange }.count) / Double(samples.count)
        }
        func bayesMargin(_ x1: Double, _ x2: Double) -> Double {
            logDensity(x1, x2, orangeMeans) - logDensity(x1, x2, blueMeans)
        }
        let curve = errorCurve(training: training, test: test)
        let xs = training.map(\.x1), ys = training.map(\.x2)
        let minX1 = xs.min()! - 0.4, maxX1 = xs.max()! + 0.4, minX2 = ys.min()! - 0.4, maxX2 = ys.max()! + 0.4
        var counts: [[UInt16]] = [], linearCells: [Bool] = [], bayesCells: [Bool] = [], margins: [Double] = []
        for row in 0..<gridSize {
            for column in 0..<gridSize {
                let x1 = minX1 + (Double(column) + 0.5) / Double(gridSize) * (maxX1 - minX1)
                let x2 = minX2 + (Double(row) + 0.5) / Double(gridSize) * (maxX2 - minX2)
                counts.append(cumulativeOrange(x1, x2, training: training))
                linearCells.append(linearOrange(x1, x2))
                let margin = bayesMargin(x1, x2)
                margins.append(margin); bayesCells.append(margin > 0)
            }
        }
        let grid = DecisionGrid(minX1: minX1, maxX1: maxX1, minX2: minX2, maxX2: maxX2, columns: gridSize, rows: gridSize,
                                orangeCounts: counts, linearOrange: linearCells, bayesOrange: bayesCells, bayesMargin: margins)
        return MixtureModel(seed: seed, blueMeans: blueMeans, orangeMeans: orangeMeans, training: training, test: test,
                            linear: (linear.0, linear.1, linear.2),
                            linearTrainingError: errorRate(training) { linearOrange($0.x1, $0.x2) },
                            linearTestError: errorRate(test) { linearOrange($0.x1, $0.x2) },
                            bayesTestError: errorRate(test) { bayesMargin($0.x1, $0.x2) > 0 },
                            curve: curve, grid: grid)
    }

    /// Solves the 3×3 normal equations XᵀXβ = Xᵀy with X = [1, x₁, x₂].
    public static func leastSquares(_ samples: [MixtureSample]) -> (Double, Double, Double) {
        var a = [[Double]](repeating: [0, 0, 0], count: 3), b = [0.0, 0, 0]
        for sample in samples {
            let row = [1, sample.x1, sample.x2], y = sample.orange ? 1.0 : 0
            for i in 0..<3 { b[i] += row[i] * y; for j in 0..<3 { a[i][j] += row[i] * row[j] } }
        }
        // Gaussian elimination with partial pivoting; XᵀX is positive definite for these data.
        for column in 0..<3 {
            let pivot = (column..<3).max { abs(a[$0][column]) < abs(a[$1][column]) }!
            a.swapAt(column, pivot); b.swapAt(column, pivot)
            for row in (column + 1)..<3 {
                let factor = a[row][column] / a[column][column]
                for j in column..<3 { a[row][j] -= factor * a[column][j] }
                b[row] -= factor * b[column]
            }
        }
        var beta = [0.0, 0, 0]
        for row in stride(from: 2, through: 0, by: -1) {
            beta[row] = (b[row] - ((row + 1)..<3).reduce(0) { $0 + a[row][$1] * beta[$1] }) / a[row][row]
        }
        return (beta[0], beta[1], beta[2])
    }

    /// Number of ORANGE points among the j nearest training points, for j = 0…N. Ties keep training order.
    static func cumulativeOrange(_ x1: Double, _ x2: Double, training: [MixtureSample]) -> [UInt16] {
        var distances: [(distance: Double, index: Int)] = []
        distances.reserveCapacity(training.count)
        for (index, sample) in training.enumerated() {
            let dx: Double = sample.x1 - x1, dy: Double = sample.x2 - x2
            distances.append((dx * dx + dy * dy, index))
        }
        distances.sort { (a: (distance: Double, index: Int), b: (distance: Double, index: Int)) -> Bool in
            a.distance == b.distance ? a.index < b.index : a.distance < b.distance
        }
        var counts = [UInt16](repeating: 0, count: training.count + 1)
        for position in 0..<distances.count {
            counts[position + 1] = counts[position] + (training[distances[position].index].orange ? 1 : 0)
        }
        return counts
    }

    /// Training and test misclassification for every odd k, from one sort per point.
    static func errorCurve(training: [MixtureSample], test: [MixtureSample]) -> [NeighborsErrorPoint] {
        func mistakes(_ samples: [MixtureSample]) -> [Int] {
            var wrong = [Int](repeating: 0, count: training.count + 1)
            for sample in samples {
                let counts = cumulativeOrange(sample.x1, sample.x2, training: training)
                for k in neighborCounts where (2 * Int(counts[k]) > k) != sample.orange { wrong[k] += 1 }
            }
            return wrong
        }
        let trainingWrong = mistakes(training), testWrong = mistakes(test)
        let trainingCount = Double(training.count), testCount = Double(test.count)
        return neighborCounts.map { k -> NeighborsErrorPoint in
            let degrees: Double = trainingCount / Double(k)
            let trainingError: Double = Double(trainingWrong[k]) / trainingCount
            let testError: Double = Double(testWrong[k]) / testCount
            return NeighborsErrorPoint(k: k, degreesOfFreedom: degrees, trainingError: trainingError, testError: testError)
        }
    }

    /// log of the class density (1/10) Σₖ φ(x; mₖ, I/5), computed stably.
    static func logDensity(_ x1: Double, _ x2: Double, _ means: [(Double, Double)]) -> Double {
        let exponents = means.map { mean -> Double in
            let dx = x1 - mean.0, dy = x2 - mean.1
            return -(dx * dx + dy * dy) / (2 * noiseVariance)
        }
        let largest = exponents.max()!
        return largest + log(exponents.reduce(0) { $0 + exp($1 - largest) }) - log(Double(means.count)) - log(2 * Double.pi * noiseVariance)
    }

    /// Segments of the zero level of a grid of values (marching squares), in data coordinates.
    public static func zeroContour(_ grid: DecisionGrid) -> [((Double, Double), (Double, Double))] {
        var segments: [((Double, Double), (Double, Double))] = []
        func value(_ column: Int, _ row: Int) -> Double { grid.bayesMargin[row * grid.columns + column] }
        for row in 0..<(grid.rows - 1) {
            for column in 0..<(grid.columns - 1) {
                let corners = [(column, row), (column + 1, row), (column + 1, row + 1), (column, row + 1)]
                var crossings: [(Double, Double)] = []
                for edge in 0..<4 {
                    let a = corners[edge], b = corners[(edge + 1) % 4]
                    let va = value(a.0, a.1), vb = value(b.0, b.1)
                    guard (va > 0) != (vb > 0) else { continue }
                    let t = va / (va - vb)
                    let pa = grid.center(column: a.0, row: a.1), pb = grid.center(column: b.0, row: b.1)
                    crossings.append((pa.x1 + t * (pb.x1 - pa.x1), pa.x2 + t * (pb.x2 - pa.x2)))
                }
                if crossings.count == 2 { segments.append((crossings[0], crossings[1])) }
                else if crossings.count == 4 { segments.append((crossings[0], crossings[1])); segments.append((crossings[2], crossings[3])) }
            }
        }
        return segments
    }
}

/// Deterministic uniform and Gaussian draws (SplitMix64 and Box–Muller).
struct GaussianSource {
    private var state: UInt64
    private var spare: Double?
    init(seed: UInt64) { state = seed &* 0x9e3779b97f4a7c15 &+ 0x2545f4914f6cdd1d }

    mutating func uniform() -> Double {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        value ^= value >> 31
        return (Double(value >> 11) + 0.5) / 9_007_199_254_740_992
    }

    mutating func index(_ count: Int) -> Int { min(count - 1, Int(uniform() * Double(count))) }

    mutating func normal() -> Double {
        if let spare { self.spare = nil; return spare }
        let radius = (-2 * log(uniform())).squareRoot(), angle = 2 * Double.pi * uniform()
        spare = radius * sin(angle)
        return radius * cos(angle)
    }
}
