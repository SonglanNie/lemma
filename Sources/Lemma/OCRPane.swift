import SwiftUI
import AppKit
import LemmaCore

@MainActor
struct OCRPane: View {
    let pngData: Data
    let pageLabel: String
    let sourceLabel: String
    let onCreateNote: (String) -> Void
    let initialText: String?
    let commitLabel: String
    private let sourceImage: NSImage?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isRecognizing = true
    @State private var message: String?
    @State private var copied = false
    @State private var sourceZoom = 1.0

    init(pngData: Data, pageLabel: String, sourceLabel: String, initialText: String? = nil, commitLabel: String = "Create source note", onCreateNote: @escaping (String) -> Void) {
        self.pngData = pngData
        self.pageLabel = pageLabel
        self.sourceLabel = sourceLabel
        self.onCreateNote = onCreateNote
        self.initialText = initialText; self.commitLabel = commitLabel
        _text = State(initialValue: initialText ?? ""); _isRecognizing = State(initialValue: initialText == nil)
        sourceImage = NSImage(data: pngData)
    }

    private var canUseText: Bool {
        !isRecognizing && (initialText != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(initialText == nil ? "Recognize source text" : "Review indexed OCR text").font(.title2.weight(.semibold))
                Text("\(sourceLabel) · \(pageLabel)").foregroundStyle(.secondary)
                Text("Local OCR · works offline").font(.caption).foregroundStyle(.secondary)
            }
            Text("Check the text against the image before using it. Equations, symbols and column order may be misread.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Source image").font(.headline)
                    ScrollView([.horizontal, .vertical]) {
                        if let sourceImage {
                            Image(nsImage: sourceImage).resizable().scaledToFit()
                                .frame(width: 340 * sourceZoom)
                                .padding(8)
                                .accessibilityLabel("\(sourceLabel), \(pageLabel)")
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    HStack {
                        Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                        Slider(value: $sourceZoom, in: 1...3).accessibilityLabel("Source image zoom")
                        Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                    }
                }.frame(width: 360)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Text to review").font(.headline)
                        Spacer()
                        if isRecognizing { ProgressView().controlSize(.small) }
                    }
                    TextEditor(text: $text).font(.body).disabled(isRecognizing)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Recognized source text, editable")
                    if isRecognizing {
                        Text("Reading text on this Mac…").font(.caption).foregroundStyle(.secondary)
                    } else if let message {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Edit any recognition errors here.").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.frame(maxHeight: .infinity)
            Divider()
            HStack {
                Button(copied ? "Copied" : "Copy text") {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(text, forType: .string)
                }.disabled(!canUseText)
                Spacer()
                Button(isRecognizing ? "Cancel" : "Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(commitLabel) { onCreateNote(text) }
                    .buttonStyle(.borderedProminent).disabled(!canUseText)
            }
        }.padding(26).frame(width: 900, height: 680)
        .onChange(of: text) { _, _ in copied = false }
        .task {
            guard initialText == nil else { return }
            do {
                let recognized = try await RegionTextRecognizer.recognize(png: pngData)
                guard !Task.isCancelled else { return }
                text = recognized
                isRecognizing = false
                if recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    message = "No text was found. Capture a larger or sharper passage, or transcribe it here."
                }
            } catch is CancellationError {
                // Closing the sheet cancels its task; no result is committed.
            } catch {
                guard !Task.isCancelled else { return }
                isRecognizing = false
                message = "Could not recognize this image. \(error.localizedDescription)"
            }
        }
    }
}
