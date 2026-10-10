import SwiftUI
import AppKit
import LemmaCore
import Observation

/// Set Up Python for the Lab: Lemma's own Python environment with NumPy, SciPy, Matplotlib, SymPy and pandas, made in
/// the background at low priority (`LabEnvironmentSetup`), with progress and Cancel. Notebooks use it from their next run.
@MainActor @Observable
final class LabPythonSetup {
    enum Phase: Equatable { case idle, running, finished, failed, cancelled }
    private(set) var phase: Phase = .idle
    private(set) var progress = LabEnvironmentSetup.Progress(step: .environment, detail: "", fraction: 0)
    private(set) var failure: String?
    private(set) var log = ""
    private(set) var result: LabInterpreter?
    /// The Python the environment is made from; nil for the best one found.
    var basePath: String?
    @ObservationIgnored weak var lab: LabRuntime?
    @ObservationIgnored private var job: LabEnvironmentSetup?

    var isRunning: Bool { phase == .running }

    /// Pythons on this Mac that can make the environment, the best first.
    var bases: [LabInterpreter] {
        guard let lab else { return [] }
        return LabEnvironment.bases(from: lab.interpreters, excluding: lab.environmentDirectory)
    }

    var base: LabInterpreter? { bases.first { $0.path == basePath } ?? bases.first }

    var environmentExists: Bool { lab.map { LabEnvironment.isComplete(at: $0.environmentDirectory) } ?? false }

    func start() {
        guard !isRunning, let lab, let base else { return }
        let job = LabEnvironmentSetup(base: base.path, directory: lab.environmentDirectory)
        self.job = job
        phase = .running; failure = nil; log = ""; result = nil
        progress = .init(step: .environment, detail: "Starting", fraction: 0)
        let report: @Sendable (LabEnvironmentSetup.Progress) -> Void = { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in self.apply(progress, from: job) }
        }
        Task.detached(priority: .utility) { [weak self] in
            let outcome = job.run(progress: report)
            let log = job.log
            guard let self else { return }
            await self.finish(job, outcome: outcome, log: log)
        }
    }

    private func apply(_ progress: LabEnvironmentSetup.Progress, from job: LabEnvironmentSetup) {
        guard self.job === job, phase == .running else { return }
        self.progress = progress
    }

    private func finish(_ job: LabEnvironmentSetup, outcome: LabEnvironmentSetup.Outcome, log: String) {
        guard self.job === job else { return }
        self.job = nil
        self.log = log
        switch outcome {
        case let .finished(interpreter):
            result = interpreter
            phase = .finished
            lab?.adoptEnvironment(interpreter)
        case let .failed(message):
            failure = message
            phase = .failed
            lab?.forgetEnvironment()
        case .cancelled:
            phase = .cancelled
            lab?.forgetEnvironment()
        }
    }

    func cancel() { job?.cancel() }

    /// Quitting: the running step stops before Lemma does (SIGTERM; with `force`, SIGKILL if it is still there).
    func stopForQuit(force: Bool) {
        guard let job else { return }
        if force { job.cancelAndWait(timeout: 0) } else { job.cancel() }
    }

    /// Removes Lemma's environment (Set Up can make it again); notebooks go back to the best other Python.
    func removeEnvironment() {
        guard !isRunning, let lab else { return }
        let directory = lab.environmentDirectory
        lab.forgetEnvironment()
        phase = .idle; result = nil; failure = nil
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: directory) }
    }
}

/// The Set Up Python for the Lab window: one at a time, beside the book. Closing it lets a setup go on; the Lab
/// sidebar shows its progress.
@MainActor
enum LabPythonSetupWindow {
    private static var window: NSWindow?
    private static weak var store: StudyStore?

    static func show(store: StudyStore) {
        if window == nil || self.store !== store {
            window?.close()
            let controller = NSHostingController(rootView: LabPythonSetupView(store: store))
            controller.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable]
            window.title = "Set Up Python for the Lab"
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            self.store = store
        }
        window?.makeKeyAndOrderFront(nil)
    }

    static func close() { window?.close() }

    static var isVisible: Bool { window?.isVisible == true }
}

struct LabPythonSetupView: View {
    @Bindable var store: StudyStore
    @State private var showLog = false
    @State private var confirmingRemoval = false

    private var lab: LabRuntime { store.lab }
    private var setup: LabPythonSetup { store.lab.setup }
    private var finding: Bool { lab.isDiscovering && lab.interpreters.isEmpty }
    private var noPython: Bool { !finding && lab.hasDiscovered && setup.bases.isEmpty && !setup.isRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "flask").font(.system(size: 24, weight: .medium)).foregroundStyle(Color.lemmaOlive).frame(width: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set Up Python for the Lab").font(.title3.weight(.semibold))
                    Text("Lemma makes a private Python environment for its notebooks and installs NumPy, SciPy, Matplotlib, SymPy and pandas in it. Other Python installations on this Mac are not changed.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if finding {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking for Python…") }
            } else if noPython {
                noPythonSection
            } else {
                switch setup.phase {
                case .running: runningSection
                case .finished: finishedSection
                case .idle, .failed, .cancelled: readySection
                }
            }
            buttons
        }
        .padding(20)
        .frame(width: 540, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .task { await store.discoverPython() }
        .alert("Remove Lemma's Python?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) { setup.removeEnvironment() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its packages are deleted. Notebooks use another Python on this Mac until you set it up again.")
        }
    }

    // MARK: Sections

    private var noPythonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Python 3 is not installed on this Mac", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text("Download the installer for macOS from python.org, run it, then choose Look Again here.")
                .fixedSize(horizontal: false, vertical: true)
            Text("If you use Homebrew, run \(Text("brew install python").font(.body.monospaced())) in Terminal instead.")
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    private var readySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if setup.phase == .failed {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Setup did not finish", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.red)
                    Text(setup.failure ?? "").fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if !setup.log.isEmpty {
                        DisclosureGroup("Details", isExpanded: $showLog) {
                            ScrollView {
                                Text(setup.log).font(.system(size: 11).monospaced()).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(height: 140)
                        }
                    }
                }
            } else if setup.phase == .cancelled {
                Text("Setup was cancelled and its unfinished environment removed.").foregroundStyle(.secondary)
            }
            if setup.bases.count > 1 {
                Picker("Made from", selection: Binding(get: { setup.base?.path ?? "" }, set: { setup.basePath = $0 })) {
                    ForEach(setup.bases) { base in Text("Python \(base.version) · \(base.path)").tag(base.path) }
                }
            } else if let base = setup.base {
                row("Made from", "Python \(base.version) · \(base.path)")
            }
            row("Location", (lab.environmentDirectory.path as NSString).abbreviatingWithTildeInPath)
            Text("pip downloads about 60 MB from the Python Package Index (pypi.org) and the environment takes about 400 MB. It runs at low priority, so you can keep reading; it takes a few minutes.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if setup.environmentExists, setup.phase == .idle {
                Text("Lemma's Python is set up. Setting it up again replaces it with fresh copies of the packages.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: setup.progress.fraction)
            Text(title(setup.progress.step)).font(.headline)
            Text(setup.progress.detail).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Text("You can close this window; the setup goes on, and the Lab sidebar shows how far it is.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var finishedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Python is ready", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            Text("Notebooks and the console now use Python \(setup.result?.version ?? "") with \(packages). A notebook already running switches the next time you run a cell, with fresh variables.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var packages: String {
        let names = ["numpy": "NumPy", "scipy": "SciPy", "matplotlib": "Matplotlib", "sympy": "SymPy", "pandas": "pandas"]
        let found = LabEnvironment.packages.filter { setup.result?.packages[$0] != nil }.compactMap { names[$0] }
        return found.isEmpty ? "its packages" : ListFormatter.localizedString(byJoining: found)
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 10) {
            if setup.environmentExists, !setup.isRunning, !noPython {
                Button("Remove Lemma's Python…") { confirmingRemoval = true }.buttonStyle(.link)
            }
            Spacer()
            if noPython {
                Button("Look Again") { Task { await store.discoverPython(force: true) } }.disabled(lab.isDiscovering)
                Button("Download Python from python.org") { NSWorkspace.shared.open(LabEnvironment.downloadPage) }.keyboardShortcut(.defaultAction)
            } else {
                switch setup.phase {
                case .running:
                    Button("Cancel") { setup.cancel() }.keyboardShortcut(.cancelAction)
                case .finished:
                    Button("Done") { LabPythonSetupWindow.close() }.keyboardShortcut(.defaultAction)
                case .idle, .failed, .cancelled:
                    Button("Close") { LabPythonSetupWindow.close() }.keyboardShortcut(.cancelAction)
                    Button(setup.phase == .idle ? (setup.environmentExists ? "Set Up Again" : "Set Up") : "Try Again") { setup.start() }
                        .keyboardShortcut(.defaultAction).disabled(setup.base == nil || finding)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(value).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }.font(.callout)
    }

    private func title(_ step: LabEnvironmentSetup.Step) -> String {
        switch step {
        case .environment: "Creating the environment"
        case .pip: "Updating pip"
        case .packages: "Downloading packages"
        case .install: "Installing packages"
        case .check: "Checking the packages"
        }
    }
}
