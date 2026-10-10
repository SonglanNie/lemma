import SwiftUI
import AppKit
import PDFKit
import LemmaCore

struct FormulaRequest: Identifiable {
    let id = UUID()
    let bookID: String
    let bookTitle: String
    let pageIndex: Int
    let region: PageRegion
    let label: String
    let quote: String
    let image: Data
    let reading: FormulaReading?
}

@MainActor
extension StudyStore {
    func readSelectedFormula() {
        guard let (page, rect, quote) = reader.selection else { return }
        readFormula(pageIndex: page, region: PageRegion(rect), quote: quote)
    }

    func readFormula(_ target: ReferenceTarget) {
        readFormula(pageIndex: target.pageIndex, region: target.region, quote: "", labelRegion: target.anchor, label: target.key.spokenTitle)
    }

    func readFormula(pageIndex: Int, region: PageRegion, quote: String, labelRegion: PageRegion? = nil, label: String? = nil) {
        guard let book = workspace, let page = document?.page(at: pageIndex) else { return }
        do {
            let image = try PDFRegionRenderer.png(page: page, region: region)
            let ink = PageInkScanner.scan(page)
            let rect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
            let tagRect = labelRegion.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
            let reading = FormulaReader.read(ink, in: rect.insetBy(dx: -1, dy: -1), label: tagRect)
            formulaRequest = FormulaRequest(bookID: book.id, bookTitle: book.title, pageIndex: pageIndex, region: region,
                label: label ?? labLabel(pageIndex: pageIndex, region: rect, page: page), quote: quote, image: image, reading: reading)
        } catch { self.error = "Could not read the selected formula: \(error.localizedDescription)" }
    }

    func deriveFormula(_ request: FormulaRequest, latex: String) {
        guard workspace?.id == request.bookID else { return }
        formulaRequest = nil
        let origin = LabSource(pageIndex: request.pageIndex, region: request.region, label: request.label, quote: request.quote)
        let source = derivationTemplate(for: origin) + "\n" + latex
        newDerivation(title: request.label, origin: origin, source: source)
    }
}

/// Read and correct locally, with the original always next to the transcription.
struct FormulaPane: View {
    @Bindable var store: StudyStore
    let request: FormulaRequest
    @State private var latex: String

    init(store: StudyStore, request: FormulaRequest) {
        self.store = store; self.request = request
        _latex = State(initialValue: request.reading?.latex ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Read Formula").font(.title2.weight(.semibold))
                    Text("\(request.label) · \(request.bookTitle) · \(store.shortPageText(request.pageIndex))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Done") { store.formulaRequest = nil }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ResizablePair(store: store, id: "formula.panes", axis: .vertical, minimumFirst: 280, minimumSecond: 320) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Original passage").font(.callout.weight(.semibold))
                    if let image = NSImage(data: request.image) {
                        ScrollView { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).background(.white) }
                            .accessibilityLabel("Original formula, unmodified")
                    }
                    Spacer(minLength: 0)
                }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.lemmaSidebar)
            } second: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("LaTeX").font(.callout.weight(.semibold)); Spacer(); status }
                    TextEditor(text: $latex).font(.system(size: 12.5, design: .monospaced)).frame(minHeight: 130, maxHeight: 220)
                        .overlay(Rectangle().stroke(Color(nsColor: .separatorColor))).accessibilityLabel("Formula LaTeX")
                    Text("Typeset preview").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    ScrollView { MathPreview(text: latex.isEmpty ? "" : "$$\n\(latex)\n$$") }
                    Text("Compare the transcription with the original. Recognizing every glyph does not verify its arrangement or mathematical meaning.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Text("Read from the PDF's glyph positions · on this Mac").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy LaTeX") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(latex, forType: .string) }
                    .disabled(latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Use in Derivation") { store.deriveFormula(request, latex: latex) }
                    .keyboardShortcut(.defaultAction).disabled(latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(16)
        }.frame(width: 860, height: 580)
    }

    @ViewBuilder private var status: some View {
        if let reading = request.reading {
            Text(reading.unknown == 0 ? "\(reading.glyphs) glyphs read" : "\(reading.unknown) unknown glyphs")
                .font(.caption).foregroundStyle(reading.unknown == 0 ? Color.secondary : Color.orange)
        } else {
            Text("No readable glyphs").font(.caption).foregroundStyle(.secondary)
        }
    }
}
