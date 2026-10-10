import Foundation

public struct InkPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum InkColor: String, Codable, CaseIterable, Sendable {
    case graphite, blue, red, green
    public var label: String { rawValue.capitalized }
    public var hex: String {
        switch self { case .graphite: "#303030"; case .blue: "#2359b0"; case .red: "#b02d36"; case .green: "#32713e" }
    }
}

/// Points and line width are in the original PDF page's coordinates, independent of zoom.
public struct InkStroke: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var pageIndex: Int
    public var points: [InkPoint]
    public var color: InkColor
    public var width: Double
    public init(id: UUID = UUID(), pageIndex: Int, points: [InkPoint], color: InkColor = .graphite, width: Double = 1.5) {
        self.id = id; self.pageIndex = pageIndex; self.points = points; self.color = color; self.width = width
    }

    public func distance(to point: InkPoint) -> Double {
        guard let first = points.first else { return .infinity }
        var best = hypot(point.x - first.x, point.y - first.y)
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
            let t = length == 0 ? 0 : max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length))
            best = min(best, hypot(point.x - a.x - t * dx, point.y - a.y - t * dy))
        }
        return best
    }
}

public enum InkExport {
    public static func svg(strokes: [InkStroke]) -> String {
        let xs = strokes.flatMap(\.points).map(\.x), ys = strokes.flatMap(\.points).map(\.y)
        let padding = (strokes.map(\.width).max() ?? 1.5) + 4
        let minX = (xs.min() ?? 0) - padding, maxY = (ys.max() ?? 0) + padding
        let width = max(1, (xs.max() ?? 0) - minX + padding)
        let height = max(1, maxY - (ys.min() ?? 0) + padding)
        let paths = strokes.map { stroke in
            let points = stroke.points.map { "\($0.x - minX),\(maxY - $0.y)" }.joined(separator: " ")
            return "<polyline points=\"\(points)\" fill=\"none\" stroke=\"\(stroke.color.hex)\" stroke-width=\"\(stroke.width)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
        }.joined(separator: "\n")
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(width) \(height)\"><rect width=\"100%\" height=\"100%\" fill=\"white\"/>\n\(paths)\n</svg>\n"
    }
}
