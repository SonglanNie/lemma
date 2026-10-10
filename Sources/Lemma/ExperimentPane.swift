import SwiftUI
import Charts
import AppKit
import LemmaCore

struct ExperimentPane: View {
    let noteID: UUID
    let noteTitle: String
    let source: SourceAnchor
    let kind: ExperimentKind
    let onSave: (ExperimentRecord) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var recordID: UUID
    @State private var prediction: String
    @State private var observation: String
    @State private var startingParameters: RidgeParameters
    @State private var parameters: RidgeParameters
    @State private var predictedAt: Date?
    @State private var savedRecord: ExperimentRecord?
    @State private var saveFailed = false
    @State private var showFits = false
    @State private var discardAction: DiscardAction?
    @FocusState private var focusedField: Field?

    private enum Field { case prediction, observation }
    private enum DiscardAction { case newPrediction, close }

    init(noteID: UUID, noteTitle: String, source: SourceAnchor, kind: ExperimentKind = .ridge, storedRecord: ExperimentRecord? = nil,
         onSave: @escaping (ExperimentRecord) -> Bool) {
        self.noteID = noteID; self.noteTitle = noteTitle; self.source = source; self.onSave = onSave
        self.kind = storedRecord?.kind ?? kind
        let initial = RidgeParameters(lambda: 1, correlation: (storedRecord?.kind ?? kind) == .ridge ? 0.95 : 0)
        _recordID = State(initialValue: storedRecord?.id ?? UUID())
        _prediction = State(initialValue: storedRecord?.prediction ?? "")
        _observation = State(initialValue: storedRecord?.observation ?? "")
        _startingParameters = State(initialValue: storedRecord?.startingParameters ?? initial)
        _parameters = State(initialValue: storedRecord?.parameters ?? initial)
        _predictedAt = State(initialValue: storedRecord?.predictedAt)
        _savedRecord = State(initialValue: storedRecord)
    }

    private var hasBegun: Bool { predictedAt != nil }
    private var hasUnsavedWork: Bool {
        if let savedRecord { return observation != savedRecord.observation || parameters != savedRecord.parameters }
        return hasBegun || !prediction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canSave: Bool { hasBegun && !observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasUnsavedWork }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introduction
                    predictionSection
                    if hasBegun {
                        let result = kind == .ridge ? RidgeExperiment.run(parameters: parameters) : LassoExperiment.run(parameters: parameters)
                        controls
                        resultSection(result)
                        observationSection
                    }
                    conventions
                }.padding(24)
            }
            Divider()
            footer.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(minWidth: 520, idealWidth: 680, minHeight: 460, idealHeight: 700)
        .interactiveDismissDisabled(hasUnsavedWork)
        .onAppear { if !hasBegun { focusedField = .prediction } }
        .alert(discardAction == .close ? "Leave without recording?" : "Start a new prediction?",
               isPresented: Binding(get: { discardAction != nil }, set: { if !$0 { discardAction = nil } })) {
            Button("Cancel", role: .cancel) { discardAction = nil }
            Button(discardAction == .close ? "Leave" : "Discard and start again", role: .destructive) {
                let action = discardAction; discardAction = nil
                if action == .close { dismiss() } else { reset() }
            }
        } message: { Text("Your unsaved prediction, settings, and observation will be discarded.") }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(kind.label, systemImage: "slider.horizontal.3").font(.title2.weight(.semibold))
            Text(noteTitle).font(.callout.weight(.medium)).lineLimit(3)
            Text("Source note · PDF page \(source.pageIndex + 1) · label \(source.pageLabel)")
                .font(.caption).foregroundStyle(.secondary)
            Text("Explore how correlated predictors and a coefficient penalty affect a fit. This local illustration uses synthetic data.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if kind == .lasso {
                Text("Increase λ to see coefficients become exactly zero. Compare this L₁ penalty with ridge’s smooth shrinkage.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("y = 1 + 2x₁ − x₂ + 0.25e")
                .font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
    }

    private var predictionSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("My prediction").font(.headline)
            if hasBegun {
                Text(prediction).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text("Written before manipulation · \(predictedAt!.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Starting λ = \(number(startingParameters.lambda)), ρ = \(number(startingParameters.correlation, digits: 3))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("What will happen to the coefficients and training error as λ increases? What changes when |ρ| approaches 1?")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Starting λ = 1, ρ = \(kind == .ridge ? "0.950" : "0.000") · 40 observations · seed 17").font(.caption).foregroundStyle(.secondary)
                textEditor("Prediction before manipulating the experiment", text: $prediction, field: .prediction)
                Button("Begin experiment") { startingParameters = parameters; predictedAt = .now; focusedField = nil }
                    .buttonStyle(.borderedProminent)
                    .disabled(prediction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Regularization λ").font(.callout.weight(.medium))
                    Spacer()
                    Text(number(parameters.lambda)).monospacedDigit().font(.callout)
                }
                Slider(value: Binding(get: { log10(parameters.lambda + 1) }, set: { value in
                    parameters.lambda = pow(10, value) - 1; saveFailed = false
                }), in: 0...log10(kind == .ridge ? 101 : 201))
                    .accessibilityLabel("Regularization lambda")
                    .accessibilityValue(number(parameters.lambda))
                HStack {
                    Button("Least squares · λ = 0") { parameters.lambda = 0; saveFailed = false }.buttonStyle(.link)
                    Spacer()
                    Text("\(kind == .ridge ? "100" : "200") · logarithmic slider").foregroundStyle(.secondary)
                }.font(.caption)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Predictor correlation ρ").font(.callout.weight(.medium))
                    Spacer()
                    Text(number(parameters.correlation, digits: 3)).monospacedDigit().font(.callout)
                }
                Slider(value: Binding(get: { parameters.correlation }, set: {
                    parameters.correlation = ($0 * 1000).rounded() / 1000
                    saveFailed = false
                }),
                       in: -1...1)
                    .accessibilityLabel("Predictor correlation")
                    .accessibilityValue(number(parameters.correlation, digits: 3))
                HStack {
                    Text("−1 · opposite columns")
                    Spacer()
                    Text("1 · identical columns")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Text("\(parameters.sampleCount) synthetic observations · seed \(parameters.seed). Changing λ keeps the data fixed; changing ρ rebuilds the predictors with the same seed.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resultSection(_ result: RidgeResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coefficient path").font(.headline)
            coefficientChart(result)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow { Text("β₁"); Text(number(result.beta1, digits: 3)).monospacedDigit(); Text("β₂"); Text(number(result.beta2, digits: 3)).monospacedDigit() }
                GridRow { Text("Intercept"); Text(number(result.intercept, digits: 3)).monospacedDigit(); Text("‖β‖₂"); Text(number(result.coefficientNorm, digits: 3)).monospacedDigit() }
                GridRow { Text("Training MSE"); Text(number(result.trainingMSE, digits: 4)).monospacedDigit(); Text("RSS"); Text(number(result.residualSumOfSquares, digits: 3)).monospacedDigit() }
            }.font(.callout).textSelection(.enabled)
            if kind == .lasso {
                Text("\([result.beta1, result.beta2].filter { $0 == 0 }.count) of 2 coefficients exactly zero · ‖β‖₁ = \(number(result.l1Norm, digits: 3))")
                    .font(.callout.weight(.medium)).textSelection(.enabled)
                LassoGeometry(result: result)
            }
            Text("Training MSE = RSS / n. These values describe these synthetic observations; they do not measure generalization.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if result.isRankDeficient {
                Label(parameters.lambda == 0
                      ? "At |ρ| = 1, least-squares coefficients are not unique. The displayed fit uses the minimum-norm solution."
                      : kind == .ridge ? "At |ρ| = 1 the predictors have rank 1. A positive λ gives a unique ridge coefficient vector."
                      : "At |ρ| = 1, Lasso can also have nonunique coefficients. One minimizing coefficient vector is shown; sparsity alone does not establish uniqueness.",
                      systemImage: "info.circle")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Observed and fitted values", isExpanded: $showFits) {
                fittedChart(result).padding(.top, 8)
                Text("The dashed line is y = ŷ. Moving away from it increases training error.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 5)
            }.font(.callout)
        }
    }

    private func coefficientChart(_ result: RidgeResult) -> some View {
        let path = kind == .ridge ? RidgeExperiment.coefficientPath(parameters: parameters) : LassoExperiment.coefficientPath(parameters: parameters)
        return Chart {
            ForEach(path) { point in
                LineMark(x: .value("λ", point.lambda), y: .value("Coefficient", point.beta1))
                    .foregroundStyle(by: .value("Coefficient", "β₁"))
                LineMark(x: .value("λ", point.lambda), y: .value("Coefficient", point.beta2))
                    .foregroundStyle(by: .value("Coefficient", "β₂"))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
            }
            RuleMark(x: .value("Current λ", parameters.lambda))
                .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            PointMark(x: .value("λ", parameters.lambda), y: .value("Coefficient", result.beta1))
                .foregroundStyle(by: .value("Coefficient", "β₁")).symbolSize(55)
            PointMark(x: .value("λ", parameters.lambda), y: .value("Coefficient", result.beta2))
                .foregroundStyle(by: .value("Coefficient", "β₂")).symbol(.diamond).symbolSize(65)
        }
        .chartForegroundStyleScale(["β₁": Color.lemmaOlive, "β₂": Color(nsColor: .systemBlue)])
        .chartXScale(domain: 0...(kind == .ridge ? 100.0 : 200.0))
        .chartXAxisLabel("Regularization λ")
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 205)
        .accessibilityLabel("Coefficient values as lambda varies at the current correlation")
        .accessibilityValue("Current lambda \(number(parameters.lambda)), beta one \(number(result.beta1, digits: 3)), beta two \(number(result.beta2, digits: 3))")
    }

    private func fittedChart(_ result: RidgeResult) -> some View {
        let values = result.samples.flatMap { [$0.target, $0.fitted] }
        let lower = (values.min() ?? 0) - 0.2
        let upper = (values.max() ?? 1) + 0.2
        return Chart {
            ForEach(result.samples) { sample in
                PointMark(x: .value("Observed y", sample.target), y: .value("Fitted ŷ", sample.fitted))
                    .foregroundStyle(Color.lemmaOlive).symbolSize(28)
            }
            LineMark(x: .value("Observed y", lower), y: .value("Fitted ŷ", lower))
                .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            LineMark(x: .value("Observed y", upper), y: .value("Fitted ŷ", upper))
                .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartXScale(domain: lower...upper).chartYScale(domain: lower...upper)
        .chartXAxisLabel("Observed y").chartYAxisLabel("Fitted ŷ")
        .frame(height: 185)
        .accessibilityLabel("Fitted versus observed synthetic values")
        .accessibilityValue("Training mean squared error \(number(result.trainingMSE, digits: 4))")
    }

    private var observationSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            Text("My observation").font(.headline)
            Text("Compare the result with your prediction. State the λ and ρ you tried and what remains unclear.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            textEditor("Observation after manipulating the experiment", text: $observation, field: .observation)
        }
    }

    private var conventions: some View {
        DisclosureGroup("Conventions and limits") {
            VStack(alignment: .leading, spacing: 9) {
                Text(kind == .ridge ? RidgeExperiment.objectiveDescription : LassoExperiment.objectiveDescription)
                Text(RidgeExperiment.dataDescription)
                Text("For |ρ| = 1 and λ = 0, a null direction is assigned coefficient zero to select the minimum-norm solution. The data are generated and fitted locally without executing supplied code.")
                if kind == .lasso { Text("The two-predictor convex objective is minimized by comparing the zero solution, each one-active solution, and valid signed two-active solutions. This is a small illustration, not a general Lasso solver.") }
                Text("This experiment is attached to your source note as an illustration. It does not reproduce the source’s data, methods, or results.")
                Link("\(kind.label) · scikit-learn documentation ↗", destination: URL(string: "https://scikit-learn.org/stable/modules/generated/sklearn.linear_model.\(kind == .ridge ? "Ridge" : "Lasso").html")!)
            }.font(.caption).textSelection(.enabled).padding(.top, 8)
        }.font(.callout).foregroundStyle(.secondary)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if saveFailed {
                Label("Could not save. Your entries remain here; try again.", systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.red)
            } else if let savedRecord, !hasUnsavedWork {
                Text("Recorded with the source note · \(savedRecord.savedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            } else if hasBegun {
                Text("Prediction, final settings, and observation are recorded together when you save.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if hasBegun {
                    Button("New prediction") { if hasUnsavedWork { discardAction = .newPrediction } else { reset() } }
                }
                Spacer()
                Button("Done") { if hasUnsavedWork { discardAction = .close } else { dismiss() } }.keyboardShortcut(.cancelAction)
                if hasBegun {
                    Button(savedRecord == nil ? "Record observation" : "Update observation", action: save)
                        .buttonStyle(.borderedProminent).disabled(!canSave).keyboardShortcut("s", modifiers: .command)
                }
            }
        }
    }

    private func textEditor(_ label: String, text: Binding<String>, field: Field) -> some View {
        TextEditor(text: text).font(.body).frame(minHeight: 95, maxHeight: 150).scrollContentBackground(.hidden)
            .padding(6).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(label).focused($focusedField, equals: field)
    }
    private func number(_ value: Double, digits: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
    private func save() {
        guard let predictedAt, canSave else { return }
        let record = ExperimentRecord(id: recordID, kind: kind, noteID: noteID, source: source, prediction: prediction,
                                      observation: observation, startingParameters: startingParameters,
                                      parameters: parameters, predictedAt: predictedAt)
        if onSave(record) { savedRecord = record; saveFailed = false }
        else { saveFailed = true }
    }
    private func reset() {
        recordID = UUID(); prediction = ""; observation = ""
        parameters = RidgeParameters(correlation: kind == .ridge ? 0.95 : 0); startingParameters = parameters
        predictedAt = nil; savedRecord = nil; saveFailed = false; showFits = false
        focusedField = .prediction
    }
}
