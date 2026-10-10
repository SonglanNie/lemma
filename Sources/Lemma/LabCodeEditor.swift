import SwiftUI
import AppKit
import LemmaCore

/// How a code cell asks to run, as in a notebook editor: ⌘↩ runs it, ⇧↩ runs and moves on, ⌥↩ runs and adds a cell below.
enum LabRunAction { case run, runAndAdvance, runAndInsert }

enum LabTerminalKey { case clear, interrupt, exit }

/// Syntax colours: the colour theme's token colours in the VS Code style (Menlo 12, as VS Code on macOS), Xcode's
/// default colours in the Classic style.
@MainActor enum LabCodeStyle {
    static var font: NSFont { ThemeManager.shared.style == .vscode ? EditorFont.nsFont() : NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) }
    static var outputFont: NSFont { ThemeManager.shared.style == .vscode ? EditorFont.nsFont(EditorFont.size - 0.5) : NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular) }
    static var textColor: NSColor { ThemeManager.shared.style == .vscode ? ThemeManager.shared.colors.ns(.editorForeground) : .textColor }

    static func attributed(_ code: String) -> AttributedString {
        let storage = NSTextStorage(string: code)
        highlight(storage)
        return AttributedString(storage)
    }

    private static func dynamic(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: value.0 / 255, green: value.1 / 255, blue: value.2 / 255, alpha: 1)
        }
    }

    static func color(for kind: PythonSyntax.Kind) -> NSColor {
        if ThemeManager.shared.style == .vscode {
            let theme = ThemeManager.shared.colors
            switch kind {
            case .keyword: return theme.token(.control)
            case .constant: return theme.token(.constant)
            case .string: return theme.token(.string)
            case .comment: return theme.token(.comment)
            case .number: return theme.token(.number)
            case .builtin: return theme.token(.builtin)
            case .definition: return theme.token(.function)
            case .decorator: return theme.token(.decorator)
            }
        }
        return switch kind {
        case .keyword, .constant: dynamic((155, 35, 147), (252, 95, 163))
        case .string: dynamic((196, 26, 22), (252, 106, 93))
        case .comment: dynamic((93, 108, 121), (127, 140, 152))
        case .number: dynamic((28, 0, 207), (208, 191, 105))
        case .builtin: dynamic((57, 0, 160), (161, 103, 230))
        case .definition: dynamic((15, 104, 160), (65, 161, 192))
        case .decorator: dynamic((100, 56, 32), (253, 143, 63))
        }
    }

    /// Applies the base style and token colours to a whole text storage.
    static func highlight(_ storage: NSTextStorage) {
        guard storage.length > 0 else { return }
        storage.beginEditing()
        colour(storage)
        storage.endEditing()
    }

    /// Sets fonts and colours; also called from the storage's `didProcessEditing`, where only attributes may change.
    static func colour(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        storage.addAttribute(.font, value: font, range: full)
        storage.addAttribute(.foregroundColor, value: textColor, range: full)
        for token in PythonSyntax.tokens(in: storage.string) where NSMaxRange(token.range) <= storage.length {
            storage.addAttribute(.foregroundColor, value: color(for: token.kind), range: token.range)
        }
    }
}

/// A code cell's text view: grows with its content instead of scrolling, indents like an editor, and runs on ⌘↩ / ⇧↩ / ⌥↩.
final class LabTextView: NSTextView {
    nonisolated(unsafe) private var themeObserver: NSObjectProtocol?
    deinit { if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, themeObserver == nil else { return }
        // A new colour theme recolours the code at once.
        themeObserver = NotificationCenter.default.addObserver(forName: .lemmaThemeChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let storage = self.textStorage else { return }
                LabCodeStyle.highlight(storage)
                self.font = LabCodeStyle.font
                self.typingAttributes = [.font: LabCodeStyle.font, .foregroundColor: LabCodeStyle.textColor]
                self.insertionPointColor = LabCodeStyle.textColor
            }
        }
    }
    var onRun: ((LabRunAction) -> Void)?
    /// Asks for completions of the dotted name before the caret (“np.lin”); the answer may come later.
    var onComplete: ((String, @escaping @MainActor ([String]) -> Void) -> Void)?
    private var completionCandidates: [String] = []
    /// In the console, Return runs complete input and Shift-Return starts a new line.
    var submitsOnReturn = false
    var onFocus: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMove: ((Int) -> Void)?
    /// Terminal keys in the console: ⌃L clears, ⌃C interrupts, ⌃D on empty input ends the session.
    var onTerminalKey: ((LabTerminalKey) -> Void)?
    static let inset = NSSize(width: 8, height: 7)
    /// The console's input sits flush after its prompt; cells keep the default inset.
    var inset = LabTextView.inset {
        didSet { textContainerInset = inset }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 36 || event.keyCode == 76, submitsOnReturn {
            if flags.contains(.shift) { insertNewline(nil); return }
            if flags.isDisjoint(with: [.command, .option, .control]) {
                if PythonSyntax.isComplete(string) { onRun?(.run) } else { insertNewline(nil) }
                return
            }
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            if flags.contains(.shift) { onRun?(.runAndAdvance); return }
            if flags.contains(.command) { onRun?(.run); return }
            if flags.contains(.option) { onRun?(.runAndInsert); return }
        }
        if event.keyCode == 53 { onEscape?(); return }
        if submitsOnReturn, flags == .control, let onTerminalKey {
            switch event.charactersIgnoringModifiers {
            case "l": onTerminalKey(.clear); return
            case "c": onTerminalKey(.interrupt); return
            case "d" where string.isEmpty: onTerminalKey(.exit); return
            default: break
            }
        }
        // Arrow keys leave the cell at its first or last line, as in a notebook.
        if flags.isDisjoint(with: [.shift, .command, .option, .control]) {
            if event.keyCode == 126, isOnFirstLine { onMove?(-1); return }
            if event.keyCode == 125, isOnLastLine { onMove?(1); return }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if window?.firstResponder === self, flags == .command, event.charactersIgnoringModifiers == "/" { toggleComment(); return true }
        if window?.firstResponder === self, flags == .command, event.keyCode == 36 { onRun?(.run); return true }
        return super.performKeyEquivalent(with: event)
    }

    private var isOnFirstLine: Bool {
        let location = selectedRange().location
        return !(string as NSString).substring(to: min(location, (string as NSString).length)).contains("\n")
    }
    private var isOnLastLine: Bool {
        let text = string as NSString
        let location = NSMaxRange(selectedRange())
        return !text.substring(from: min(location, text.length)).contains("\n")
    }

    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = text.substring(with: NSRange(location: lineRange.location, length: max(0, selectedRange().location - lineRange.location)))
        insertText("\n" + PythonSyntax.indentation(after: line), replacementRange: selectedRange())
    }

    override func insertTab(_ sender: Any?) {
        if selectedRange().length > 0 { shiftLines(by: 4); return }
        // After a name, Tab completes it from the kernel's variables, modules and attributes; elsewhere it indents.
        if let prefix = completionPrefix(), let onComplete {
            let location = selectedRange().location
            onComplete(prefix) { [weak self] matches in
                guard let self, self.selectedRange().location == location, self.window?.firstResponder === self else { return }
                self.present(matches, for: prefix)
            }
            return
        }
        insertText("    ", replacementRange: selectedRange())
    }

    /// The dotted name ending at the caret, when the caret follows a name.
    func completionPrefix() -> String? {
        let text = string as NSString
        let end = selectedRange().location
        var start = end
        while start > 0 {
            let c = text.character(at: start - 1)
            let identifier = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 || c == 46 || c > 127
            if identifier { start -= 1 } else { break }
        }
        guard start < end else { return nil }
        let prefix = text.substring(with: NSRange(location: start, length: end - start))
        guard let first = prefix.unicodeScalars.first, !CharacterSet.decimalDigits.contains(first), first != "." else { return nil }
        return prefix
    }

    /// Inserts a single completion directly, extends to the common prefix, or offers the list.
    func present(_ matches: [String], for prefix: String) {
        let partial = prefix.components(separatedBy: ".").last ?? prefix
        var words: [String] = []
        for match in matches {
            var word = match.components(separatedBy: ".").last ?? match
            if word.hasSuffix("(") { word.removeLast() }
            if word.hasPrefix(partial), word != partial, !words.contains(word) { words.append(word) }
        }
        guard !words.isEmpty else { return }
        if words.count == 1 { insertText(String(words[0].dropFirst(partial.count)), replacementRange: selectedRange()); return }
        let common = words.dropFirst().reduce(words[0]) { shared, word in String(zip(shared, word).prefix { $0 == $1 }.map(\.0)) }
        if common.count > partial.count { insertText(String(common.dropFirst(partial.count)), replacementRange: selectedRange()) }
        completionCandidates = words
        complete(nil)
    }

    override var rangeForUserCompletion: NSRange {
        let text = string as NSString
        let end = selectedRange().location
        var start = end
        while start > 0 {
            let c = text.character(at: start - 1)
            if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 || c > 127 { start -= 1 } else { break }
        }
        return NSRange(location: start, length: end - start)
    }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        let partial = (string as NSString).substring(with: charRange)
        let list = completionCandidates.filter { $0.hasPrefix(partial) }
        index.pointee = list.isEmpty ? -1 : 0
        return list.isEmpty ? nil : list
    }

    override func insertBacktab(_ sender: Any?) { shiftLines(by: -4) }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }

    /// Indents or dedents the selected lines.
    private func shiftLines(by amount: Int) {
        let text = string as NSString
        let range = text.lineRange(for: selectedRange())
        let lines = text.substring(with: range).components(separatedBy: "\n")
        let shifted = lines.enumerated().map { offset, line -> String in
            if offset == lines.count - 1 && line.isEmpty { return line }
            if amount > 0 { return String(repeating: " ", count: amount) + line }
            let spaces = min(-amount, line.prefix { $0 == " " }.count)
            return String(line.dropFirst(spaces))
        }.joined(separator: "\n")
        replace(range, with: shifted)
    }

    private func toggleComment() {
        let text = string as NSString
        let range = text.lineRange(for: selectedRange())
        var lines = text.substring(with: range).components(separatedBy: "\n")
        let trailing = lines.last == "" && lines.count > 1
        if trailing { lines.removeLast() }
        let toggled = PythonSyntax.toggleComment(lines).joined(separator: "\n") + (trailing ? "\n" : "")
        replace(range, with: toggled)
    }

    private func replace(_ range: NSRange, with replacement: String) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(location: range.location, length: (replacement as NSString).length))
    }

    /// The height needed to show every line at a given width. It is measured on a separate layout, so SwiftUI's
    /// size proposals never change the wrapping of the text on screen.
    private var heightMeasurement: (text: String, width: CGFloat, font: NSFont, padding: CGFloat, height: CGFloat)?

    func height(forWidth width: CGFloat) -> CGFloat {
        let font = self.font ?? LabCodeStyle.font
        let padding = textContainer?.lineFragmentPadding ?? 5
        let text = string
        if let measured = heightMeasurement, measured.text == text, measured.width == width,
           measured.font == font, measured.padding == padding { return measured.height }
        let storage = NSTextStorage(attributedString: textStorage ?? NSAttributedString(string: string))
        if storage.length == 0 { storage.setAttributedString(NSAttributedString(string: " ", attributes: [.font: font])) }
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: NSSize(width: max(40, width - inset.width * 2), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = padding
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container).height
        let height = ceil(max(used, manager.defaultLineHeight(for: font)) + inset.height * 2)
        heightMeasurement = (text, width, font, padding, height)
        return height
    }

    /// Keeps the wrapping width equal to the view's own width.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let width = max(40, newSize.width - inset.width * 2)
        if let container = textContainer, abs(container.containerSize.width - width) > 0.5 {
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
    }
}

/// A code cell's editor in SwiftUI. `focusToken` changes when the cell should take keyboard focus.
struct LabCodeEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int = 0
    var onRun: (LabRunAction) -> Void
    var onFocus: () -> Void = {}
    var onEscape: () -> Void = {}
    var onMove: (Int) -> Void = { _ in }
    var onTerminalKey: ((LabTerminalKey) -> Void)? = nil
    var onComplete: (String, @escaping @MainActor ([String]) -> Void) -> Void = { _, reply in reply([]) }
    var submitsOnReturn = false
    /// Text inset and line padding; the console passes zero so its input lines up with the transcript.
    var inset = LabTextView.inset
    var linePadding: CGFloat = 5

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> LabTextView {
        // TextKit 1: code cells are small, and TextKit 2's text checking re-ran on every colour change.
        let view = LabTextView(usingTextLayoutManager: false)
        view.isRichText = false
        view.enabledTextCheckingTypes = 0
        view.isAutomaticTextCompletionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.smartInsertDeleteEnabled = false
        view.usesFindBar = true
        view.drawsBackground = false
        view.inset = inset
        view.textContainer?.lineFragmentPadding = linePadding
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.clipsToBounds = true
        view.font = LabCodeStyle.font
        view.typingAttributes = [.font: LabCodeStyle.font, .foregroundColor: LabCodeStyle.textColor]
        view.insertionPointColor = LabCodeStyle.textColor
        view.string = text
        view.submitsOnReturn = submitsOnReturn
        view.delegate = context.coordinator
        view.textStorage?.delegate = context.coordinator
        view.setAccessibilityLabel("Python code")
        if let storage = view.textStorage { LabCodeStyle.highlight(storage) }
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ view: LabTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(view)
        if view.string != text {
            let selection = view.selectedRange()
            view.string = text
            if let storage = view.textStorage { LabCodeStyle.highlight(storage) }
            view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LabTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 420
        guard width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: LabCodeEditor
        var focusToken: Int
        init(_ parent: LabCodeEditor) { self.parent = parent; focusToken = parent.focusToken }

        func attach(_ view: LabTextView) {
            view.onRun = { [weak self, weak view] action in
                guard let self, let view else { return }
                self.parent.text = view.string
                self.parent.onRun(action)
            }
            view.onFocus = { [weak self] in self?.parent.onFocus() }
            view.onEscape = { [weak self, weak view] in view?.window?.makeFirstResponder(nil); self?.parent.onEscape() }
            view.onMove = { [weak self] delta in self?.parent.onMove(delta) }
            view.onTerminalKey = parent.onTerminalKey == nil ? nil : { [weak self] key in self?.parent.onTerminalKey?(key) }
            view.onComplete = { [weak self] prefix, reply in self?.parent.onComplete(prefix, reply) }
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? LabTextView else { return }
            parent.text = view.string
            view.invalidateIntrinsicContentSize()
        }

        /// Colours the code as part of each edit, the place AppKit expects attribute fix-ups.
        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            // Text storages of text views are edited on the main thread.
            nonisolated(unsafe) let storage = textStorage
            MainActor.assumeIsolated { LabCodeStyle.colour(storage) }
        }
    }
}
