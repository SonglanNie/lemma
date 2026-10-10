import SwiftUI
import LemmaCore

/// Arrows mean "this note uses this reference", as chosen by the reader.
/// They are not inferred or verified proof dependencies.
struct DependencyMapPane: View {
    @Bindable var store: StudyStore
    @State private var focusID: UUID?
    @Environment(\.dismiss) private var dismiss

    private var focused: StudyNote? { store.linkedNote(id: focusID ?? store.selectedNoteID ?? UUID()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Dependencies & references").font(.title2.weight(.semibold))
                    Text("Reader supplied links. Arrows point from a note to the reference it uses.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let note = focused {
                HStack(alignment: .top, spacing: 16) {
                    mapColumn("Referenced by", links: store.workspace?.incomingLinks(to: note.id) ?? [], incoming: true)
                    ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Inspecting").font(.caption).foregroundStyle(.secondary)
                        Label(note.kind.label, systemImage: note.kind.symbol).font(.caption.weight(.medium)).foregroundStyle(Color.lemmaOlive)
                        Text(note.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text("PDF page \(note.anchor.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                        if !note.assumptions.isEmpty {
                            Text("Reader assumptions").font(.caption.weight(.medium))
                            Text(note.assumptions).font(.callout).textSelection(.enabled)
                        }
                        if !note.notation.isEmpty { Text(note.notation).font(.callout).textSelection(.enabled) }
                        if !note.body.isEmpty { MathPreview(text: note.body) }
                        HStack {
                            Button("Open note") { store.openLinkedNote(note.id); dismiss() }
                            Button("Go to source") { store.reader.go(to: note.anchor); dismiss() }
                        }.buttonStyle(.link).font(.caption)
                    }.padding(16).frame(width: 250, alignment: .topLeading)
                        .background(Color.lemmaOlive.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    }.frame(width: 250)
                    mapColumn("Uses", links: store.workspace?.outgoingLinks(from: note.id) ?? [], incoming: false)
                }
                Text("Inspect a node to follow its links without changing the PDF or notebook selection. A link records your reading of the source; it does not certify a proof.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                PaneEmptyState(symbol: "point.3.connected.trianglepath.dotted", title: "Choose a source note", message: "Capture claims and definitions, then add Definition, Assumption, or Related links. Their connections appear here.")
            }
        }.padding(24).frame(width: 870, height: 540)
            .onAppear { focusID = store.selectedNoteID }
    }

    private func mapColumn(_ title: String, links: [NoteLink], incoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if links.isEmpty { Text(incoming ? "No referring notes." : "No linked references yet.").font(.callout).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(links) { link in
                        if let target = store.linkedNote(id: incoming ? link.sourceNoteID : link.targetNoteID) {
                            Button { focusID = target.id } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    if !incoming { Image(systemName: "arrow.right").foregroundStyle(.secondary) }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Label(link.kind.label, systemImage: link.kind.symbol).font(.caption).foregroundStyle(.secondary)
                                        Text(target.title).font(.callout.weight(.medium)).multilineTextAlignment(.leading).lineLimit(3)
                                        Text("PDF page \(target.anchor.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                                        if !link.usage.isEmpty { Text(link.usage).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
                                    }
                                    if incoming { Image(systemName: "arrow.right").foregroundStyle(.secondary) }
                                }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).accessibilityLabel("Inspect dependency node: \(target.title)")
                            Divider()
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
