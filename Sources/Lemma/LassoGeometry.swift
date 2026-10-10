import SwiftUI
import Charts
import LemmaCore

private struct GeometryPoint: Identifiable {
    let id: Int
    let series: String
    let x: Double
    let y: Double
}

struct LassoGeometry: View {
    let result: RidgeResult
    private var contours: [GeometryPoint] {
        guard !result.isRankDeficient else { return [] }
        let ls = RidgeExperiment.run(parameters: .init(lambda: 0, correlation: result.parameters.correlation,
            seed: result.parameters.seed, sampleCount: result.parameters.sampleCount))
        let solutionRadius = sqrt(max(0, (result.residualSumOfSquares - ls.residualSumOfSquares) / Double(result.parameters.sampleCount)))
        let plusAtSolution = (result.beta1 - ls.beta1 + result.beta2 - ls.beta2) / sqrt(2)
        let minusAtSolution = (result.beta1 - ls.beta1 - result.beta2 + ls.beta2) / sqrt(2)
        let rawAngle = atan2(minusAtSolution * sqrt(1 - result.parameters.correlation), plusAtSolution * sqrt(1 + result.parameters.correlation))
        let solutionAngle = rawAngle < 0 ? rawAngle + 2 * .pi : rawAngle
        var radii = [0.35, 0.7, 1.05]
        if solutionRadius > 1e-8 { radii.append(solutionRadius) }
        return radii.enumerated().flatMap { level, radius in
            var angles = (0...72).map { Double($0) / 72 * 2 * .pi }
            if level == 3 { angles.append(solutionAngle); angles.sort() }
            return angles.enumerated().map { index, angle in
                let plus = radius * cos(angle) / sqrt(1 + result.parameters.correlation)
                let minus = radius * sin(angle) / sqrt(1 - result.parameters.correlation)
                return GeometryPoint(id: level * 100 + index, series: level == 3 ? "RSS at solution" : "RSS contour \(level + 1)",
                    x: ls.beta1 + (plus + minus) / sqrt(2), y: ls.beta2 + (plus - minus) / sqrt(2))
            }
        }
    }
    private var diamond: [GeometryPoint] {
        let r = result.l1Norm
        return [(r, 0.0), (0.0, r), (-r, 0.0), (0.0, -r), (r, 0.0)].enumerated().map {
            GeometryPoint(id: $0.offset + 400, series: "L₁ boundary", x: $0.element.0, y: $0.element.1)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why the axes matter").font(.headline)
            if result.isRankDeficient {
                Text("At |ρ| = 1 the RSS contours are degenerate. Use a full-rank design to inspect the ellipses.").font(.callout).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(contours) { point in
                        LineMark(x: .value("β₁", point.x), y: .value("β₂", point.y), series: .value("Contour", point.series))
                            .foregroundStyle(Color.secondary.opacity(point.series == "RSS at solution" ? 1 : 0.6))
                            .lineStyle(StrokeStyle(lineWidth: point.series == "RSS at solution" ? 2 : 1))
                    }
                    ForEach(diamond) { point in
                        LineMark(x: .value("β₁", point.x), y: .value("β₂", point.y), series: .value("Boundary", point.series))
                            .foregroundStyle(Color.lemmaOlive).lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    RuleMark(x: .value("β₁ = 0", 0)).foregroundStyle(.secondary.opacity(0.4))
                    RuleMark(y: .value("β₂ = 0", 0)).foregroundStyle(.secondary.opacity(0.4))
                    PointMark(x: .value("β₁", result.beta1), y: .value("β₂", result.beta2))
                        .foregroundStyle(Color(nsColor: .systemRed)).symbolSize(75)
                }
                .chartXScale(domain: -3.5...3.5).chartYScale(domain: -3.5...3.5)
                .chartPlotStyle { $0.clipped() }
                .chartXAxisLabel("β₁").chartYAxisLabel("β₂").frame(width: 310, height: 310)
                .accessibilityLabel("RSS ellipses and the L1 diamond with the current Lasso solution")
                Text("Gray: equal RSS. \(result.parameters.lambda == 0 ? "At λ = 0 the solution is the least-squares center." : "The brighter contour passes through the current solution.") Olive: |β₁| + |β₂| = \(result.l1Norm.formatted(.number.precision(.fractionLength(3)))). Red: the penalized solution. A diamond corner lies on an axis, where one coefficient is zero. The diamond’s radius follows this λ’s solution.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
