import Foundation

public enum ExperimentExport {
    public static func stem(_ record: ExperimentRecord) -> String { "\(record.kind.rawValue)-\(record.id.uuidString.lowercased())" }

    public static func write(_ record: ExperimentRecord, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if record.kind == .nearestNeighbors { try writeNeighbors(record, to: directory); return }
        let result = record.kind == .ridge ? RidgeExperiment.run(parameters: record.parameters) : LassoExperiment.run(parameters: record.parameters)
        let path = record.kind == .ridge ? RidgeExperiment.coefficientPath(parameters: record.parameters) : LassoExperiment.coefficientPath(parameters: record.parameters)
        let stem = stem(record)
        let samples = "id,x1,x2,y,fitted\n" + result.samples.map { "\($0.id),\($0.x1),\($0.x2),\($0.target),\($0.fitted)" }.joined(separator: "\n") + "\n"
        let coefficients = "lambda,beta1,beta2\n" + path.map { "\($0.lambda),\($0.beta1),\($0.beta2)" }.joined(separator: "\n") + "\n"
        try samples.write(to: directory.appendingPathComponent("\(stem)-samples.csv"), atomically: true, encoding: .utf8)
        try coefficients.write(to: directory.appendingPathComponent("\(stem)-path.csv"), atomically: true, encoding: .utf8)
        let script = """
        # Recreates Lemma's local synthetic illustration from the exact exported data.
        # Requires Python 3 and matplotlib. Run manually; Lemma executes no supplied code.
        # Dataset V\(record.datasetVersion), seed \(record.parameters.seed), n=\(record.parameters.sampleCount), rho=\(record.parameters.correlation).
        # \(record.kind == .ridge ? RidgeExperiment.objectiveDescription : LassoExperiment.objectiveDescription)
        from pathlib import Path
        import csv
        import matplotlib.pyplot as plt

        directory = Path(__file__).resolve().parent
        def read(name):
            with (directory / name).open(newline="") as stream:
                return [{key: float(value) for key, value in row.items()} for row in csv.DictReader(stream)]

        samples = read("\(stem)-samples.csv")
        path = read("\(stem)-path.csv")
        fig, axes = plt.subplots(1, 2, figsize=(10, 4))
        axes[0].plot([p["lambda"] for p in path], [p["beta1"] for p in path], label="beta 1")
        axes[0].plot([p["lambda"] for p in path], [p["beta2"] for p in path], linestyle="--", label="beta 2")
        axes[0].axvline(\(record.parameters.lambda), color="gray", linestyle=":")
        axes[0].set(xlabel="lambda", ylabel="Coefficient", title="\(record.kind.label) · synthetic data")
        axes[0].legend()
        axes[1].scatter([p["y"] for p in samples], [p["fitted"] for p in samples])
        limits = [min(p["y"] for p in samples), max(p["y"] for p in samples)]
        axes[1].plot(limits, limits, color="gray", linestyle="--")
        axes[1].set(xlabel="Observed y", ylabel="Fitted y", title="Training fit; no held-out evaluation")
        fig.tight_layout()
        fig.savefig(directory / "\(stem).png", dpi=180)
        """ + "\n"
        try script.write(to: directory.appendingPathComponent("\(stem).py"), atomically: true, encoding: .utf8)
    }

    /// The simulated training data, the error curves and a script that redraws Figures 2.1–2.4 for this draw.
    static func writeNeighbors(_ record: ExperimentRecord, to directory: URL) throws {
        let model = NeighborsExperiment.model(seed: record.parameters.seed, gridSize: 2)
        let settings = record.neighbors ?? NeighborsSettings()
        let stem = stem(record)
        let training = "x1,x2,class\n" + model.training.map { "\($0.x1),\($0.x2),\($0.orange ? "orange" : "blue")" }.joined(separator: "\n") + "\n"
        let curve = "k,degrees_of_freedom,training_error,test_error\n" + model.curve.map { "\($0.k),\($0.degreesOfFreedom),\($0.trainingError),\($0.testError)" }.joined(separator: "\n") + "\n"
        try training.write(to: directory.appendingPathComponent("\(stem)-training.csv"), atomically: true, encoding: .utf8)
        try curve.write(to: directory.appendingPathComponent("\(stem)-errors.csv"), atomically: true, encoding: .utf8)
        let script = """
        # Recreates Lemma's ESL §2.3 simulation plots from the exported data (seed \(record.parameters.seed), dataset V\(record.datasetVersion)).
        # Requires Python 3 and matplotlib. Run manually; Lemma executes no supplied code.
        # Linear regression: training error \(model.linearTrainingError), test error \(model.linearTestError). Bayes rule test error: \(model.bayesTestError).
        from pathlib import Path
        import csv
        import matplotlib.pyplot as plt

        directory = Path(__file__).resolve().parent
        with (directory / "\(stem)-training.csv").open(newline="") as stream:
            training = [(float(r["x1"]), float(r["x2"]), r["class"] == "orange") for r in csv.DictReader(stream)]
        with (directory / "\(stem)-errors.csv").open(newline="") as stream:
            curve = [{key: float(value) for key, value in row.items()} for row in csv.DictReader(stream)]

        k = \(settings.k)
        def knn_orange(x1, x2):
            nearest = sorted(training, key=lambda p: (p[0] - x1) ** 2 + (p[1] - x2) ** 2)[:k]
            return sum(1 for p in nearest if p[2]) / k > 0.5

        xs = [p[0] for p in training]; ys = [p[1] for p in training]
        lo1, hi1, lo2, hi2 = min(xs) - 0.4, max(xs) + 0.4, min(ys) - 0.4, max(ys) + 0.4
        steps = 70
        grid = [(lo1 + (i + 0.5) * (hi1 - lo1) / steps, lo2 + (j + 0.5) * (hi2 - lo2) / steps) for i in range(steps) for j in range(steps)]
        fig, axes = plt.subplots(1, 2, figsize=(12, 5.5))
        colors = ["#E69900" if knn_orange(x1, x2) else "#57ADE6" for x1, x2 in grid]
        axes[0].scatter([g[0] for g in grid], [g[1] for g in grid], c=colors, s=1.5)
        axes[0].scatter(xs, ys, facecolors="none", edgecolors=["#E69900" if p[2] else "#57ADE6" for p in training], s=28)
        axes[0].set(title=f"{k}-Nearest Neighbor Classifier (simulated draw)", xticks=[], yticks=[])
        dof = [p["degrees_of_freedom"] for p in curve]
        axes[1].plot(dof, [p["training_error"] for p in curve], label="Train")
        axes[1].plot(dof, [p["test_error"] for p in curve], label="Test")
        axes[1].axhline(\(model.bayesTestError), color="purple", linestyle="--", label="Bayes")
        axes[1].scatter([3, 3], [\(model.linearTrainingError), \(model.linearTestError)], marker="s", color=["C0", "C1"], label="Linear")
        axes[1].set(xscale="log", xlabel="Degrees of Freedom - N/k", ylabel="Test Error", title="Misclassification curves")
        axes[1].legend()
        fig.tight_layout()
        fig.savefig(directory / "\(stem).png", dpi=160)
        """ + "\n"
        try script.write(to: directory.appendingPathComponent("\(stem).py"), atomically: true, encoding: .utf8)
    }
}
