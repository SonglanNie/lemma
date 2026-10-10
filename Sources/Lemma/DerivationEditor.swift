import SwiftUI
import AppKit
import WebKit
import LemmaCore

/// A derivation beside the page: LaTeX steps on the left of a gutter that says, for each line, whether it holds;
/// the steps typeset below with what Lemma found. Checking runs as the reader types, like an editor's diagnostics.
struct DerivationEditor: View {
    @Bindable var store: StudyStore
    let derivationID: UUID
    @State private var showSource = true
    @State private var renaming = false
    @State private var title = ""

    var body: some View {
        if let derivation = store.derivation(derivationID) {
            let report = store.derivationReports[derivationID]
            VStack(spacing: 0) {
                header(derivation, report)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    if let origin = derivation.origin { LabSourceCard(store: store, source: origin, expanded: $showSource, compact: true) }
                    if let report, !report.symbols.isEmpty {
                        DerivationSymbolsStrip(symbols: report.symbols) { symbol in declare(symbol, in: derivation) }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                ResizablePair(store: store, id: "derivation.panes", axis: .horizontal, minimumFirst: 130, minimumSecond: 90) {
                    DerivationTextEditor(text: derivation.source, report: report, derivationID: derivationID, focus: store.derivationFocus) { text in
                        store.updateDerivation(derivationID) { $0.source = text }
                    }
                    .frame(maxHeight: .infinity)
                } second: {
                    ScrollView {
                        DerivationStepsPreview(steps: steps(derivation, report)) { line in store.derivationFocus = (derivationID, line, UUID()) }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                }
                footer(report)
            }
            .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .sheet(isPresented: $renaming) { renameSheet }
        } else {
            PaneEmptyState(symbol: "function", title: "Derivation closed", message: "This derivation belongs to another book or was deleted.")
        }
    }

    private func header(_ derivation: Derivation, _ report: DerivationReport?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "function").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.lemmaOlive)
            Text(derivation.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).layoutPriority(-1)
                .onTapGesture(count: 2) { title = derivation.title; renaming = true }
                .help("Double-click to rename")
            if let origin = derivation.origin {
                Text(store.shortPageText(origin.pageIndex)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
            Spacer(minLength: 4)
            if let report { DerivationVerdictPill(report: report) }
            Menu {
                Button("Rename…") { title = derivation.title; renaming = true }
                Button("Copy as LaTeX") { copyLaTeX(derivation) }
                Button("Export as Markdown…") { exportMarkdown(derivation) }
                Divider()
                Button("Insert Declarations from the Book") { insertBookDeclarations(derivation) }
                Divider()
                Button("Delete Derivation", role: .destructive) { store.deleteDerivation(derivationID) }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20).accessibilityLabel("Derivation actions")
            Button { store.closeSideEditor("derivation:\(derivationID)") } label: { Image(systemName: "xmark") }
                .help("Close the derivation (it is kept with the book)").accessibilityLabel("Close derivation")
        }
        .buttonStyle(.borderless).font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 10).frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func footer(_ report: DerivationReport?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "dice").font(.system(size: 10))
            Text("Each step is tested on random values: a counterexample shows it is wrong; agreement is evidence, not a proof.")
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5)).foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename derivation").font(.headline)
            TextField("Title", text: $title).textFieldStyle(.roundedBorder).frame(width: 320)
                .onSubmit(commitRename)
            HStack {
                Spacer()
                Button("Cancel") { renaming = false }.keyboardShortcut(.cancelAction)
                Button("Rename", action: commitRename).keyboardShortcut(.defaultAction)
            }
        }.padding(18)
    }

    private func commitRename() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { store.updateDerivation(derivationID) { $0.title = trimmed } }
        renaming = false
    }

    /// One row per line of the source, with its verdict, for the typeset preview.
    private func steps(_ derivation: Derivation, _ report: DerivationReport?) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for (index, raw) in derivation.source.components(separatedBy: "\n").enumerated() {
            let text = raw.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let status = report?.status(ofLine: index) ?? .comment
            let line = report?.lines.first { $0.line == index && $0.status == status }
            if status == .blank { continue }
            var latex = DerivationChecker.strip(text).replacingOccurrences(of: "&", with: " ")
            if latex.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if text.hasPrefix("%") || text.hasPrefix("//") || text.hasPrefix("#") {
                rows.append(["line": index, "status": "comment", "text": String(text.drop(while: { "%/# ".contains($0) })), "latex": ""])
                continue
            }
            latex = latex.replacingOccurrences(of: "\\\\", with: " ")
            rows.append(["line": index, "status": status.rawValue, "latex": latex, "text": text,
                         "message": line?.message ?? "", "detail": line?.detail ?? ""])
        }
        return rows
    }

    /// Writes an inferred type as a declaration at the top, so the reader can see and change it.
    private func declare(_ symbol: DerivationSymbol, in derivation: Derivation) {
        guard symbol.origin == .inferred, let type = symbol.type else { return }
        let name = DerivationTemplate.latex(symbol.name)
        let declaration: String
        switch type {
        case let .scalar(domain):
            declaration = domain == .positive ? "\(name) > 0" : "\(name) \\in \\mathbb{R}"
        case let .matrix(rows, columns, _):
            declaration = columns == .constant(1) ? "\(name) \\in \\mathbb{R}^{\(rows)}" : "\(name) \\in \\mathbb{R}^{\(rows) \\times \(columns)}"
        }
        insertAtTop(declaration, in: derivation)
    }

    private func insertBookDeclarations(_ derivation: Derivation) {
        let lines = store.notationDeclarations(near: derivation.origin?.pageIndex ?? store.reader.pageNumber - 1)
        guard !lines.isEmpty else { store.status = "The book's notation gives no sizes for the symbols on this page."; return }
        insertAtTop(lines.joined(separator: "\n"), in: derivation)
    }

    /// Inserts lines after the leading comments.
    private func insertAtTop(_ text: String, in derivation: Derivation) {
        var lines = derivation.source.components(separatedBy: "\n")
        let index = lines.firstIndex { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("%") } ?? lines.count
        lines.insert(contentsOf: text.components(separatedBy: "\n"), at: index)
        store.updateDerivation(derivationID) { $0.source = lines.joined(separator: "\n") }
    }

    private func copyLaTeX(_ derivation: Derivation) {
        let body = derivation.source.components(separatedBy: "\n")
            .filter { let t = $0.trimmingCharacters(in: .whitespaces); return !t.isEmpty && !t.hasPrefix("%") }
            .joined(separator: " \\\\\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\\begin{align*}\n\(body)\n\\end{align*}\n", forType: .string)
        store.status = "Copied the derivation as an align* block."
    }

    private func exportMarkdown(_ derivation: Derivation) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = derivation.title.replacingOccurrences(of: "/", with: "-") + ".md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.derivationMarkdown(derivation).write(to: url, atomically: true, encoding: .utf8) }
        catch { store.error = "Could not export the derivation: \(error.localizedDescription)" }
    }
}

/// “5 ✓ · 1 ✗” in the derivation's header.
struct DerivationVerdictPill: View {
    let report: DerivationReport

    var body: some View {
        HStack(spacing: 6) {
            if report.holds > 0 { Label("\(report.holds)", systemImage: "checkmark").foregroundStyle(Color.green) }
            if report.fails > 0 { Label("\(report.fails)", systemImage: "xmark").foregroundStyle(Color.red) }
            if report.unchecked > 0 { Label("\(report.unchecked)", systemImage: "questionmark").foregroundStyle(Color.orange) }
            if report.holds + report.fails + report.unchecked == 0 { Text("No steps yet").foregroundStyle(.secondary) }
        }
        .labelStyle(DerivationCountStyle())
        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
        .padding(.horizontal, 7).frame(height: 18)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .help("\(report.holds) steps hold, \(report.fails) fail, \(report.unchecked) cannot be checked by drawing numbers")
        .accessibilityElement(children: .combine)
    }
}

private struct DerivationCountStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) { configuration.icon.font(.system(size: 8.5, weight: .bold)); configuration.title }
    }
}

/// What each symbol is: declared, inferred from its use (click to write it as a declaration), a size, or defined.
struct DerivationSymbolsStrip: View {
    let symbols: [DerivationSymbol]
    let declare: (DerivationSymbol) -> Void

    var body: some View {
        // One line, scrolled sideways, so the editor keeps its height in a narrow side tab.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) { ForEach(symbols) { symbol in chip(symbol) } }
        }
    }

    private func chip(_ symbol: DerivationSymbol) -> some View {
        let inferred = symbol.origin == .inferred
        return HStack(spacing: 4) {
            Text(MathNames.display(symbol.name)).font(.system(size: 12, design: .serif).italic())
            Text(symbol.detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6).frame(height: 20)
        .background(background(symbol.origin), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(style: StrokeStyle(lineWidth: 0.75, dash: inferred ? [2.5, 2] : []))
            .foregroundStyle(inferred ? Color.secondary.opacity(0.6) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { if inferred { declare(symbol) } }
        .help(help(symbol))
        .accessibilityElement(children: .combine)
        .accessibilityHint(inferred ? "Writes this type as a declaration" : "")
    }

    private func background(_ origin: DerivationSymbol.Origin) -> Color {
        switch origin {
        case .declared: Color.lemmaOlive.opacity(0.13)
        case .inferred: Color.clear
        case .size: Color.primary.opacity(0.05)
        case .defined: Color.blue.opacity(0.10)
        }
    }

    private func help(_ symbol: DerivationSymbol) -> String {
        switch symbol.origin {
        case .declared: "Declared in the derivation"
        case .inferred: "Inferred from how the symbol is used · click to write it as a declaration you can change"
        case .size: "A size: drawn as a small whole number"
        case .defined: "Defined in the derivation; later steps use its definition"
        }
    }
}

// MARK: - Source editor

/// LaTeX colours in an editor's spirit: commands like keywords, numbers, relations, comments.
@MainActor enum DerivationStyle {
    static var font: NSFont { ThemeManager.shared.style == .vscode ? EditorFont.nsFont(EditorFont.size + 0.5) : NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular) }
    static var bold: NSFont { ThemeManager.shared.style == .vscode ? EditorFont.nsFont(EditorFont.size + 0.5, bold: true) : NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold) }
    static var textColor: NSColor { ThemeManager.shared.style == .vscode ? ThemeManager.shared.colors.ns(.editorForeground) : .textColor }

    private static func dynamic(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: value.0 / 255, green: value.1 / 255, blue: value.2 / 255, alpha: 1)
        }
    }

    static let command = dynamic((155, 35, 147), (252, 95, 163))
    static let number = dynamic((28, 0, 207), (208, 191, 105))
    static let relation = dynamic((83, 84, 21), (190, 192, 125))
    static let comment = dynamic((93, 108, 121), (127, 140, 152))
    static let punctuation = dynamic((120, 124, 116), (130, 136, 126))

    private enum Role { case command, number, relation, punctuation, comment }
    private static let patterns: [(NSRegularExpression, Role, Bool)] = [
        (try! NSRegularExpression(pattern: #"\\[A-Za-z]+"#), .command, false),
        (try! NSRegularExpression(pattern: #"(?<![A-Za-z])\d+(?:\.\d+)?"#), .number, false),
        (try! NSRegularExpression(pattern: #"\\(?:le|ge|leq|geq|ne|neq|approx|coloneqq|in)\b|:=|[=<>]"#), .relation, true),
        (try! NSRegularExpression(pattern: #"[{}&]|\\[,;!: ]|\\\\"#), .punctuation, false),
        (try! NSRegularExpression(pattern: #"(?m)^\s*(?:%|//).*$"#), .comment, false)
    ]

    /// The theme's token colours in the VS Code style; Lemma's own in the Classic style.
    private static func color(_ role: Role) -> NSColor {
        if ThemeManager.shared.style == .vscode {
            let theme = ThemeManager.shared.colors
            switch role {
            case .command: return theme.token(.command)
            case .number: return theme.token(.number)
            case .relation: return theme.token(.operator)
            case .punctuation: return theme.token(.punctuation)
            case .comment: return theme.token(.comment)
            }
        }
        switch role {
        case .command: return command
        case .number: return number
        case .relation: return relation
        case .punctuation: return punctuation
        case .comment: return comment
        }
    }

    static func colour(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        storage.addAttribute(.font, value: font, range: full)
        storage.addAttribute(.foregroundColor, value: textColor, range: full)
        let text = storage.string
        for (regex, role, isBold) in patterns {
            let colour = color(role)
            for match in regex.matches(in: text, range: full) {
                storage.addAttribute(.foregroundColor, value: colour, range: match.range)
                if isBold { storage.addAttribute(.font, value: bold, range: match.range) }
            }
        }
    }
}

final class DerivationTextView: NSTextView {
    nonisolated(unsafe) private var themeObserver: NSObjectProtocol?
    deinit { if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, themeObserver == nil else { return }
        themeObserver = NotificationCenter.default.addObserver(forName: .lemmaThemeChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let storage = self.textStorage, storage.length > 0 else { return }
                storage.beginEditing(); DerivationStyle.colour(storage); storage.endEditing()
                self.insertionPointColor = DerivationStyle.textColor
            }
        }
    }
    override func insertTab(_ sender: Any?) { insertText("  ", replacementRange: selectedRange()) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if window?.firstResponder === self, flags == .command, event.charactersIgnoringModifiers == "/" { toggleComment(); return true }
        return super.performKeyEquivalent(with: event)
    }

    /// ⌘/ comments or uncomments the selected lines with “%”.
    private func toggleComment() {
        let text = string as NSString
        let range = text.lineRange(for: selectedRange())
        var lines = text.substring(with: range).components(separatedBy: "\n")
        let trailing = lines.last == "" && lines.count > 1
        if trailing { lines.removeLast() }
        let commented = lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("%") || $0.trimmingCharacters(in: .whitespaces).isEmpty }
        let toggled = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if commented, let index = line.firstIndex(of: "%") {
                var copy = line; copy.remove(at: index)
                if copy[index...].first == " " { copy.remove(at: index) }
                return copy
            }
            return "% " + line
        }.joined(separator: "\n") + (trailing ? "\n" : "")
        guard shouldChangeText(in: range, replacementString: toggled) else { return }
        textStorage?.replaceCharacters(in: range, with: toggled)
        didChangeText()
    }
}

/// The editor's gutter: line numbers and, for each step, its verdict, with the reason as a tooltip.
final class DerivationGutter: NSRulerView, NSViewToolTipOwner {
    var reports: [Int: DerivationLineReport] = [:] { didSet { needsDisplay = true } }
    private var marks: [(rect: CGRect, line: Int)] = []

    override var requiredThickness: CGFloat { 46 }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        NSColor.windowBackgroundColor.withAlphaComponent(0.6).setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        CGRect(x: bounds.maxX - 0.5, y: bounds.minY, width: 0.5, height: bounds.height).fill()
        let text = textView.string as NSString
        // Line starts, to number lines (not wrapped fragments).
        var starts: [Int] = [0]
        var index = 0
        while index < text.length {
            let range = text.range(of: "\n", options: [], range: NSRange(location: index, length: text.length - index))
            if range.location == NSNotFound { break }
            starts.append(range.location + 1); index = range.location + 1
        }
        let visible = textView.visibleRect
        layout.ensureLayout(forBoundingRect: visible, in: container)
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let inset = textView.textContainerOrigin
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor]
        marks = []
        removeAllToolTips()
        func drawLine(_ line: Int, fragment: CGRect) {
            let y = convert(CGPoint(x: 0, y: fragment.minY + inset.y), from: textView).y
            let number = "\(line + 1)" as NSString
            let size = number.size(withAttributes: attributes)
            let top = min(y, convert(CGPoint(x: 0, y: fragment.maxY + inset.y), from: textView).y)
            number.draw(at: CGPoint(x: 24 - size.width, y: top + (fragment.height - size.height) / 2), withAttributes: attributes)
            guard let report = reports[line], let symbol = Self.symbol(for: report.status) else { return }
            let markRect = CGRect(x: 28, y: top + (fragment.height - 13) / 2, width: 13, height: 13)
            let configuration = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold).applying(.init(paletteColors: [.white, symbol.color]))
            NSImage(systemSymbolName: symbol.name, accessibilityDescription: report.status.rawValue)?.withSymbolConfiguration(configuration)?.draw(in: markRect)
            marks.append((markRect, line))
            addToolTip(markRect.insetBy(dx: -3, dy: -3), owner: self, userData: nil)
        }
        var drawnLines = Set<Int>()
        layout.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, glyphRange, _ in
            let character = layout.characterIndexForGlyph(at: glyphRange.location)
            // The fragment that starts a line carries its number.
            var low = 0, high = starts.count - 1
            while low < high { let mid = (low + high + 1) / 2; if starts[mid] <= character { low = mid } else { high = mid - 1 } }
            if character == starts[low], !drawnLines.contains(low) {
                drawnLines.insert(low)
                drawLine(low, fragment: fragment)
            }
        }
        // An empty last line has no fragment of its own.
        if text.length == 0 || text.hasSuffix("\n") {
            let extra = layout.extraLineFragmentRect
            if extra.height > 0 { drawLine(starts.count - 1, fragment: extra) }
        }
    }

    static func symbol(for status: DerivationLineReport.Status) -> (name: String, color: NSColor)? {
        switch status {
        case .holds: ("checkmark.circle.fill", .systemGreen)
        case .fails: ("xmark.circle.fill", .systemRed)
        case .error: ("exclamationmark.circle.fill", .systemRed)
        case .unchecked: ("questionmark.circle.fill", .systemOrange)
        case .given: ("circle.fill", .lemmaOlive)
        case .definition: ("equal.circle.fill", .systemBlue)
        case .declaration: ("tag.circle.fill", .lemmaOlive)
        case .comment, .blank: nil
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let mark = marks.first(where: { $0.rect.insetBy(dx: -3, dy: -3).contains(point) }), let report = reports[mark.line] else { return "" }
        return [report.message, report.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

struct DerivationTextEditor: NSViewRepresentable {
    let text: String
    let report: DerivationReport?
    let derivationID: UUID
    let focus: (id: UUID, line: Int, token: UUID)?
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = DerivationTextView(usingTextLayoutManager: false)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.enabledTextCheckingTypes = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.usesFindBar = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.font = DerivationStyle.font
        textView.typingAttributes = [.font: DerivationStyle.font, .foregroundColor: NSColor.textColor]
        textView.insertionPointColor = NSColor.lemmaOlive
        textView.string = text
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.setAccessibilityLabel("Derivation steps in LaTeX")
        if let storage = textView.textStorage { storage.beginEditing(); DerivationStyle.colour(storage); storage.endEditing() }

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        let gutter = DerivationGutter(scrollView: scroll, orientation: .verticalRuler)
        gutter.clientView = textView
        scroll.verticalRulerView = gutter
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.textView = textView
        context.coordinator.gutter = gutter
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrolled(_:)), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.apply(report: report)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            if let storage = textView.textStorage { storage.beginEditing(); DerivationStyle.colour(storage); storage.endEditing() }
            textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            DispatchQueue.main.async { [weak gutter = context.coordinator.gutter] in gutter?.needsDisplay = true }
        }
        context.coordinator.apply(report: report)
        if let focus, focus.id == derivationID, focus.token != context.coordinator.focusToken {
            context.coordinator.focusToken = focus.token
            let lines = text.components(separatedBy: "\n")
            let location = lines.prefix(max(0, min(focus.line, lines.count - 1))).reduce(0) { $0 + ($1 as NSString).length + 1 }
            let lineLength = focus.line < lines.count ? (lines[focus.line] as NSString).length : 0
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: location + lineLength, length: 0))
                textView.scrollRangeToVisible(NSRange(location: location, length: lineLength))
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: DerivationTextEditor
        weak var textView: NSTextView?
        weak var gutter: DerivationGutter?
        var focusToken: UUID?
        private var appliedReport: DerivationReport?

        init(_ parent: DerivationTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.onChange(view.string)
            gutter?.needsDisplay = true
        }

        @objc func scrolled(_ notification: Notification) { gutter?.needsDisplay = true }

        /// Verdicts in the gutter and dotted underlines where a step fails, as an editor shows diagnostics.
        func apply(report: DerivationReport?) {
            guard appliedReport != report, let textView, let layout = textView.layoutManager else { return }
            appliedReport = report
            var byLine: [Int: DerivationLineReport] = [:]
            for line in report?.lines ?? [] {
                if let existing = byLine[line.line], DerivationChecker.rank(existing.status) >= DerivationChecker.rank(line.status) { continue }
                byLine[line.line] = line
            }
            gutter?.reports = byLine
            let length = (textView.string as NSString).length
            layout.removeTemporaryAttribute(.underlineStyle, forCharacterRange: NSRange(location: 0, length: length))
            layout.removeTemporaryAttribute(.underlineColor, forCharacterRange: NSRange(location: 0, length: length))
            for line in report?.lines ?? [] where line.status.isProblem {
                guard let range = line.errorRange, NSMaxRange(range) <= length, range.length > 0 else { continue }
                layout.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue,
                                               .underlineColor: line.status == .error ? NSColor.systemRed : NSColor.systemRed.withAlphaComponent(0.85)],
                                              forCharacterRange: range)
            }
        }

        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            nonisolated(unsafe) let storage = textStorage
            MainActor.assumeIsolated { DerivationStyle.colour(storage) }
        }
    }
}

// MARK: - Typeset preview

struct DerivationStepsPreview: View {
    let steps: [[String: Any]]
    let onSelect: (Int) -> Void
    @State private var height: CGFloat = 80

    var body: some View {
        StepsWebSurface(steps: steps, height: $height, onSelect: onSelect)
            .frame(height: height)
            .accessibilityLabel("Typeset steps with their verdicts")
    }
}

private struct StepsWebSurface: NSViewRepresentable {
    let steps: [[String: Any]]
    @Binding var height: CGFloat
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    /// The typeset page comes from the previews' shared web views (MathPreview.swift): no web content process of its own.
    func makeNSView(context: Context) -> MathWebHost {
        context.coordinator.onSelect = onSelect
        context.coordinator.steps = steps
        return MathWebHost(client: context.coordinator)
    }

    func updateNSView(_ host: MathWebHost, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.steps = steps
        context.coordinator.render()
    }

    static func dismantleNSView(_ host: MathWebHost, coordinator: Coordinator) { host.release() }

    @MainActor final class Coordinator: NSObject, MathWebClient {
        var steps: [[String: Any]] = []
        var onSelect: ((Int) -> Void)?
        private var rendered: String?
        var height: Binding<CGFloat>
        weak var view: MathWebView?
        init(height: Binding<CGFloat>) { self.height = height }

        func mathPageLoaded(_ view: MathWebView) { rendered = nil; render() }

        func render() {
            guard let view, view.pageLoaded, let data = try? JSONSerialization.data(withJSONObject: steps), let json = String(data: data, encoding: .utf8), rendered != json else { return }
            rendered = json
            view.callAsyncJavaScript("renderSteps(JSON.parse(steps))", arguments: ["steps": json], in: nil, in: .page, completionHandler: nil)
        }

        func mathMessage(_ name: String, body: Any) {
            if name == "stepClicked", let line = body as? NSNumber { onSelect?(line.intValue); return }
            guard name == "studyHeight", let value = body as? NSNumber else { return }
            let measured = min(max(CGFloat(value.doubleValue), 24), 20000)
            if abs(height.wrappedValue - measured) > 1 { height.wrappedValue = measured }
        }
    }
}
