import Foundation

/// A dense real matrix, row-major. Vectors are n × 1 matrices.
public struct MathMatrix: Equatable, Sendable {
    public var rows: Int
    public var columns: Int
    public var values: [Double]

    public init(rows: Int, columns: Int, values: [Double]) {
        precondition(values.count == rows * columns)
        self.rows = rows; self.columns = columns; self.values = values
    }

    public init(rows: Int, columns: Int, repeating value: Double = 0) {
        self.init(rows: rows, columns: columns, values: Array(repeating: value, count: rows * columns))
    }

    public static func identity(_ n: Int, scale: Double = 1) -> MathMatrix {
        var matrix = MathMatrix(rows: n, columns: n)
        for i in 0..<n { matrix[i, i] = scale }
        return matrix
    }

    public subscript(row: Int, column: Int) -> Double {
        get { values[row * columns + column] }
        set { values[row * columns + column] = newValue }
    }

    public var shapeText: String { "\(rows)×\(columns)" }
    public var isSquare: Bool { rows == columns }
    public var maxAbs: Double { values.reduce(0) { max($0, abs($1)) } }
    public var isFinite: Bool { values.allSatisfy(\.isFinite) }

    public var transposed: MathMatrix {
        var result = MathMatrix(rows: columns, columns: rows)
        for i in 0..<rows { for j in 0..<columns { result[j, i] = self[i, j] } }
        return result
    }

    public func map(_ transform: (Double) -> Double) -> MathMatrix {
        MathMatrix(rows: rows, columns: columns, values: values.map(transform))
    }

    public static func + (a: MathMatrix, b: MathMatrix) -> MathMatrix {
        MathMatrix(rows: a.rows, columns: a.columns, values: zip(a.values, b.values).map(+))
    }

    public static func - (a: MathMatrix, b: MathMatrix) -> MathMatrix {
        MathMatrix(rows: a.rows, columns: a.columns, values: zip(a.values, b.values).map(-))
    }

    public static func * (a: MathMatrix, b: MathMatrix) -> MathMatrix {
        var result = MathMatrix(rows: a.rows, columns: b.columns)
        for i in 0..<a.rows {
            for k in 0..<a.columns {
                let aik = a[i, k]
                if aik == 0 { continue }
                for j in 0..<b.columns { result.values[i * b.columns + j] += aik * b.values[k * b.columns + j] }
            }
        }
        return result
    }

    public static func * (s: Double, a: MathMatrix) -> MathMatrix { a.map { s * $0 } }

    public var trace: Double { (0..<min(rows, columns)).reduce(0) { $0 + self[$1, $1] } }

    /// LU decomposition with partial pivoting; nil when the matrix is singular to working precision.
    private func lu() -> (lu: MathMatrix, pivots: [Int], sign: Double)? {
        guard isSquare else { return nil }
        let n = rows
        var a = self
        var pivots = Array(0..<n)
        var sign = 1.0
        let scale = max(maxAbs, 1e-300)
        for k in 0..<n {
            var best = k
            for i in (k + 1)..<max(k + 1, n) where abs(a[i, k]) > abs(a[best, k]) { best = i }
            if abs(a[best, k]) <= 1e-12 * scale { return nil }
            if best != k {
                for j in 0..<n { let t = a[k, j]; a[k, j] = a[best, j]; a[best, j] = t }
                pivots.swapAt(k, best); sign = -sign
            }
            for i in (k + 1)..<max(k + 1, n) {
                let factor = a[i, k] / a[k, k]
                a[i, k] = factor
                if factor == 0 { continue }
                for j in (k + 1)..<n { a[i, j] -= factor * a[k, j] }
            }
        }
        return (a, pivots, sign)
    }

    public var determinant: Double {
        guard let (lu, _, sign) = lu() else { return 0 }
        return (0..<rows).reduce(sign) { $0 * lu[$1, $1] }
    }

    /// The inverse, or nil when the matrix is singular or badly conditioned.
    public var inverse: MathMatrix? {
        guard let (lu, pivots, _) = lu() else { return nil }
        let n = rows
        var result = MathMatrix(rows: n, columns: n)
        for column in 0..<n {
            // Solve L U x = P e_column.
            var x = [Double](repeating: 0, count: n)
            for i in 0..<n { x[i] = pivots[i] == column ? 1 : 0 }
            for i in 0..<n { for k in 0..<i { x[i] -= lu[i, k] * x[k] } }
            for i in stride(from: n - 1, through: 0, by: -1) {
                for k in (i + 1)..<max(i + 1, n) { x[i] -= lu[i, k] * x[k] }
                x[i] /= lu[i, i]
            }
            for i in 0..<n { result[i, column] = x[i] }
        }
        // Reject results that lost all precision (a nearly singular matrix).
        let check = self * result
        let error = (0..<n).reduce(0.0) { worst, i in max(worst, (0..<n).reduce(0.0) { max($0, abs(check[i, $1] - (i == $1 ? 1 : 0))) }) }
        guard error < 1e-6, result.isFinite else { return nil }
        return result
    }

    /// Solves the least-squares problem min ‖A x − b‖ (or the minimum-norm solution when underdetermined).
    public static func leastSquares(_ a: MathMatrix, _ b: MathMatrix, ridge: Double = 0) -> MathMatrix? {
        if a.rows >= a.columns {
            let at = a.transposed
            var normal = at * a
            for i in 0..<normal.rows { normal[i, i] += ridge * max(1, normal[i, i]) }
            guard let inverse = normal.inverse else { return nil }
            return inverse * (at * b)
        }
        let at = a.transposed
        var gram = a * at
        for i in 0..<gram.rows { gram[i, i] += ridge * max(1, gram[i, i]) }
        guard let inverse = gram.inverse else { return nil }
        return at * (inverse * b)
    }
}

/// A value of an expression: a number, a matrix, or c·I whose size comes from what it meets.
public enum MathValue: Equatable, Sendable {
    case scalar(Double)
    case matrix(MathMatrix)
    case identity(Double)

    /// A 1 × 1 matrix (xᵀy) is a number.
    var normalized: MathValue {
        if case let .matrix(m) = self, m.rows == 1, m.columns == 1 { return .scalar(m.values[0]) }
        return self
    }

    var scalar: Double? {
        switch normalized { case let .scalar(v): v; default: nil }
    }

    var isFinite: Bool {
        switch self {
        case let .scalar(v): v.isFinite
        case let .matrix(m): m.isFinite
        case let .identity(c): c.isFinite
        }
    }

    public var shapeText: String {
        switch normalized {
        case .scalar: "a number"
        case let .matrix(m): m.columns == 1 ? "a vector of length \(m.rows)" : m.shapeText
        case .identity: "the identity"
        }
    }

    /// A short description for a counterexample: “2.31”, “3×1 [0.42, −1.3, 0.07]”.
    public var summary: String {
        switch normalized {
        case let .scalar(v): return MathFormat.number(v)
        case let .matrix(m):
            let shown = m.values.prefix(4).map(MathFormat.number).joined(separator: ", ")
            return "\(m.shapeText) [\(shown)\(m.values.count > 4 ? ", …" : "")]"
        case let .identity(c): return c == 1 ? "I" : "\(MathFormat.number(c))·I"
        }
    }
}

public enum MathFormat {
    /// A number as a reader would want to see it in a counterexample: 4 significant digits.
    public static func number(_ value: Double) -> String {
        if value.isNaN { return "undefined" }
        if value.isInfinite { return value > 0 ? "∞" : "−∞" }
        if value == value.rounded(), abs(value) < 1e6 { return String(Int(value)).replacingOccurrences(of: "-", with: "−") }
        let magnitude = abs(value)
        let text: String
        if magnitude >= 1e5 || magnitude < 1e-3 { text = String(format: "%.3e", value) }
        else { text = String(format: "%.4g", value) }
        return text.replacingOccurrences(of: "-", with: "−")
    }
}
