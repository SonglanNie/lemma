import SwiftUI
import Charts
import AppKit
import LemmaCore

/// ESL §2.3: least squares and nearest neighbours on the book's simulated mixture (Figures 2.1–2.5).
/// The reader predicts first, then varies the classifier and k, and records what they observed.
struct NeighborsExperimentPane: View {
    static let bookLikeSeed: UInt64 = 77

    let noteID: UUID
    let noteTitle: String
    let source: SourceAnchor
    let onSave: (ExperimentRecord) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var recordID: UUID
    @State private var prediction: String
    @State private var observation: String
    @State private var predictedAt: Date?
    @State private var seed: UInt64
    @State private var settings: NeighborsSettings
    @State private var startingSettings: NeighborsSettings
    @State private var savedRecord: ExperimentRecord?
    @State private var model: MixtureModel?
    @State private var contour: [((Double, Double), (Double, Double))] = []
    @State private var saveFailed = false
    @State private var confirmClose = false

    init(noteID: UUID, noteTitle: String, source: SourceAnchor, storedRecord: ExperimentRecord? = nil, onSave: @escaping (ExperimentRecord) -> Bool) {
        self.noteID = noteID; self.noteTitle = noteTitle; self.source = source; self.onSave = onSave
        _recordID = State(initialValue: storedRecord?.id ?? UUID())
        _prediction = State(initialValue: storedRecord?.prediction ?? "")
        _observation = State(initialValue: storedRecord?.observation ?? "")
        _predictedAt = State(initialValue: storedRecord?.predictedAt)
        _seed = State(initialValue: storedRecord?.parameters.seed ?? Self.bookLikeSeed)
        _settings = State(initialValue: storedRecord?.neighbors ?? NeighborsSettings())
        _startingSettings = State(initialValue: storedRecord?.startingNeighbors ?? storedRecord?.neighbors ?? NeighborsSettings())
        _savedRecord = State(initialValue: storedRecord)
    }

    private var hasBegun: Bool { predictedAt != nil }
    private var hasUnsavedWork: Bool {
        if let savedRecord { return observation != savedRecord.observation || settings != savedRecord.neighbors }
        return hasBegun || !prediction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introduction
                    if !hasBegun { predictionStep } else { predictionSummary }
                    if hasBegun {
                        if let model { explorer(model) } else {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Simulating 10,200 points and every k…").font(.callout).foregroundStyle(.secondary) }
                        }
                        observationStep
                    }
                    conventions
                }.padding(24)
            }
            Divider()
            footer.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 600, idealHeight: 820)
        .interactiveDismissDisabled(hasUnsavedWork)
        .task(id: seed) { await simulate() }
        .alert("Leave without recording?", isPresented: $confirmClose) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) { dismiss() }
        } message: { Text("Your prediction, settings and observation will be discarded.") }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Least squares and nearest neighbours", systemImage: "circle.grid.cross").font(.title2.weight(.semibold))
            Text(noteTitle).font(.callout.weight(.medium)).lineLimit(2)
            Text("Source note · PDF page \(source.pageIndex + 1) · ESL §2.3, Figures 2.1–2.5").font(.caption).foregroundStyle(.secondary)
            Text("Two classes, each a mixture of ten Gaussian clusters. Compare the linear rule ŷ > 0.5 from (2.7) with k-nearest-neighbour averaging (2.8), on 200 training points and 10,000 fresh test points.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var predictionStep: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("My prediction").font(.headline)
            Text("As k grows from 1 to 199, what happens to the training error and to the test error? Where would you expect the best k, and how close can any rule get to the Bayes error?")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $prediction).font(.body).frame(minHeight: 90, maxHeight: 140).scrollContentBackground(.hidden)
                .padding(6).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6)).accessibilityLabel("Prediction before exploring")
            Button("Begin") { startingSettings = settings; predictedAt = .now }.buttonStyle(.borderedProminent)
                .disabled(prediction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var predictionSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("My prediction").font(.headline)
            Text(prediction).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Text("Written before exploring · \(predictedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func explorer(_ model: MixtureModel) -> some View {
        let current = settings.classifier == .linear ? nil : model.errors(k: settings.k)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 22) {
                MixturePlot(model: model, settings: settings, contour: contour)
                    .frame(width: 380, height: 380)
                    .accessibilityLabel("Training points and decision regions for \(settings.summary)")
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Classifier", selection: $settings.classifier) {
                        Text("Linear regression").tag(NeighborsSettings.Classifier.linear)
                        Text("Nearest neighbours").tag(NeighborsSettings.Classifier.neighbors)
                    }.pickerStyle(.segmented).labelsHidden()
                    if settings.classifier == .neighbors {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Neighbours k").font(.callout.weight(.medium))
                                Spacer()
                                Text("k = \(settings.k) · N/k ≈ \(Int((200 / Double(settings.k)).rounded()))").monospacedDigit().font(.callout)
                            }
                            Slider(value: Binding(get: { log(Double(settings.k)) }, set: { value in
                                let k = Int(exp(value).rounded())
                                settings.k = min(199, max(1, k % 2 == 0 ? k + 1 : k))
                            }), in: 0...log(199.0)).accessibilityLabel("Number of neighbours").accessibilityValue("\(settings.k)")
                            HStack {
                                ForEach([1, 15, 199], id: \.self) { k in Button("k = \(k)") { settings.k = k }.buttonStyle(.link) }
                            }.font(.caption)
                        }
                    }
                    Toggle("Bayes decision boundary (Figure 2.5)", isOn: $settings.showBayes).toggleStyle(.checkbox)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                        GridRow { Text("").gridColumnAlignment(.leading); Text("Training").foregroundStyle(.secondary); Text("Test (10,000)").foregroundStyle(.secondary) }
                        GridRow {
                            Text(settings.summary).fontWeight(.medium)
                            Text(percent(current?.trainingError ?? model.linearTrainingError)).monospacedDigit()
                            Text(percent(current?.testError ?? model.linearTestError)).monospacedDigit()
                        }
                        GridRow { Text("Linear regression"); Text(percent(model.linearTrainingError)).monospacedDigit(); Text(percent(model.linearTestError)).monospacedDigit() }
                        GridRow { Text("Bayes rule"); Text("-").foregroundStyle(.secondary); Text(percent(model.bayesTestError)).monospacedDigit() }
                    }.font(.callout).textSelection(.enabled)
                    Text("Misclassification rates. Training error always reaches 0 at k = 1, because each point is its own nearest neighbour.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("New random draw") { seed = UInt64.random(in: 1...999_999) }.buttonStyle(.link).font(.caption)
                        .help("Draw new cluster means and points from the same design")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Misclassification curves (Figure 2.4)").font(.headline)
                errorChart(model)
            }
        }
    }

    private func errorChart(_ model: MixtureModel) -> some View {
        Chart {
            ForEach(model.curve) { point in
                LineMark(x: .value("Degrees of freedom N/k", point.degreesOfFreedom), y: .value("Error", point.trainingError), series: .value("Set", "Train"))
                    .foregroundStyle(by: .value("Set", "Train"))
                LineMark(x: .value("Degrees of freedom N/k", point.degreesOfFreedom), y: .value("Error", point.testError), series: .value("Set", "Test"))
                    .foregroundStyle(by: .value("Set", "Test"))
            }
            RuleMark(y: .value("Bayes", model.bayesTestError)).foregroundStyle(Color.purple.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                .annotation(position: .top, alignment: .leading) { Text("Bayes").font(.caption2).foregroundStyle(.purple) }
            PointMark(x: .value("Degrees of freedom N/k", 3.0), y: .value("Error", model.linearTestError)).foregroundStyle(by: .value("Set", "Test")).symbol(.square).symbolSize(70)
            PointMark(x: .value("Degrees of freedom N/k", 3.0), y: .value("Error", model.linearTrainingError)).foregroundStyle(by: .value("Set", "Train")).symbol(.square).symbolSize(70)
            if settings.classifier == .neighbors {
                RuleMark(x: .value("Current k", 200 / Double(settings.k))).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: 1...200, type: .log)
        .chartXAxis { AxisMarks(values: [1, 2, 3, 5, 8, 12, 18, 29, 67, 200]) { AxisGridLine(); AxisTick(); AxisValueLabel() } }
        .chartXAxisLabel("Degrees of freedom N/k (squares: linear regression, 3 parameters)")
        .chartYAxisLabel("Misclassification")
        .chartForegroundStyleScale(["Train": Color(nsColor: .systemBlue), "Test": Color.orange])
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: 220)
        .accessibilityLabel("Training and test misclassification as k varies")
    }

    private var observationStep: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            Text("My observation").font(.headline)
            Text("Compare with your prediction. Which k would you choose without the test set, and why can the training error not choose it?")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $observation).font(.body).frame(minHeight: 90, maxHeight: 150).scrollContentBackground(.hidden)
                .padding(6).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6)).accessibilityLabel("Observation after exploring")
        }
    }

    private var conventions: some View {
        DisclosureGroup("Conventions and limits") {
            VStack(alignment: .leading, spacing: 8) {
                Text(NeighborsExperiment.description)
                Text("ORANGE is coded 1 and BLUE 0. Both rules predict ORANGE when the fitted value exceeds 0.5. Distances are Euclidean; odd k avoids ties; a training point counts as its own neighbour.")
                Text("The Bayes rule uses the true mixture densities, which are known only because the data are simulated. Draw \(seed)\(seed == Self.bookLikeSeed ? " (default, chosen to resemble the book’s error levels)" : "").")
                Text("Lemma computes everything locally and runs no supplied code. The export includes the data and a matplotlib script to recreate the plots.")
            }.font(.caption).textSelection(.enabled).padding(.top, 8)
        }.font(.callout).foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            if saveFailed {
                Label("Could not save. Your entries remain here.", systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout)
            } else if let savedRecord, !hasUnsavedWork {
                Text("Recorded with the source note · \(savedRecord.savedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { if hasUnsavedWork { confirmClose = true } else { dismiss() } }.keyboardShortcut(.cancelAction)
            if hasBegun {
                Button(savedRecord == nil ? "Record observation" : "Update observation", action: save).buttonStyle(.borderedProminent)
                    .disabled(observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hasUnsavedWork)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
    }

    private func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(1))) }

    private func simulate() async {
        model = nil
        let seed = seed
        let result = await Task.detached(priority: .userInitiated) { () -> (MixtureModel, [((Double, Double), (Double, Double))]) in
            let model = NeighborsExperiment.model(seed: seed)
            return (model, NeighborsExperiment.zeroContour(model.grid))
        }.value
        guard !Task.isCancelled, seed == self.seed else { return }
        model = result.0; contour = result.1
    }

    private func save() {
        guard let predictedAt else { return }
        let parameters = RidgeParameters(lambda: 0, correlation: 0, seed: seed, sampleCount: 200)
        var record = ExperimentRecord(id: recordID, kind: .nearestNeighbors, noteID: noteID, source: source, prediction: prediction,
                                      observation: observation, startingParameters: parameters, parameters: parameters,
                                      predictedAt: predictedAt, datasetVersion: MixtureModel.datasetVersion)
        record.neighbors = settings; record.startingNeighbors = startingSettings
        if onSave(record) { savedRecord = record; saveFailed = false } else { saveFailed = true }
    }
}

/// Training points over dotted decision regions, in the style of the book's figures.
struct MixturePlot: View {
    let model: MixtureModel
    let settings: NeighborsSettings
    let contour: [((Double, Double), (Double, Double))]

    static let orange = Color(red: 0.90, green: 0.60, blue: 0.0)
    static let blue = Color(red: 0.34, green: 0.68, blue: 0.90)

    var body: some View {
        let grid = model.grid
        let regions = settings.classifier == .linear ? grid.linearOrange : grid.neighborsOrange(k: settings.k)
        Canvas { context, size in
            func point(_ x1: Double, _ x2: Double) -> CGPoint {
                CGPoint(x: (x1 - grid.minX1) / (grid.maxX1 - grid.minX1) * size.width,
                        y: size.height - (x2 - grid.minX2) / (grid.maxX2 - grid.minX2) * size.height)
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for index in regions.indices {
                let centre = grid.center(column: index % grid.columns, row: index / grid.columns)
                let p = point(centre.x1, centre.x2)
                let dot = CGRect(x: p.x - 0.9, y: p.y - 0.9, width: 1.8, height: 1.8)
                context.fill(Path(ellipseIn: dot), with: .color(regions[index] ? Self.orange.opacity(0.75) : Self.blue.opacity(0.75)))
            }
            if settings.classifier == .linear, abs(model.linear.beta2) > 1e-9 {
                var path = Path()
                let x2 = { (x1: Double) in (0.5 - model.linear.beta0 - model.linear.beta1 * x1) / model.linear.beta2 }
                path.move(to: point(grid.minX1, x2(grid.minX1))); path.addLine(to: point(grid.maxX1, x2(grid.maxX1)))
                context.stroke(path, with: .color(.black), lineWidth: 1.4)
            }
            if settings.showBayes {
                var path = Path()
                for (a, b) in contour { path.move(to: point(a.0, a.1)); path.addLine(to: point(b.0, b.1)) }
                context.stroke(path, with: .color(.purple), style: StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
            }
            for sample in model.training {
                let p = point(sample.x1, sample.x2)
                context.stroke(Path(ellipseIn: CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4)),
                               with: .color(sample.orange ? Self.orange : Self.blue), lineWidth: 1.4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.secondary.opacity(0.5)))
    }
}
