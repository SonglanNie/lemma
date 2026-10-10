import Foundation

/// A small executable notebook kept with a book: Python cells beside the passage that prompted them.
/// Cells run only when the reader runs them, in a local Python process (`LabKernel`).
public struct LabNotebook: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Where in the book the notebook started, when it came from a passage, an equation or a note.
    public var source: LabSource?
    public var cells: [LabCell]

    public init(id: UUID = UUID(), title: String, source: LabSource? = nil, cells: [LabCell] = []) {
        self.id = id; self.title = title; self.source = source; self.cells = cells
        createdAt = .now; updatedAt = .now
    }

    private enum CodingKeys: String, CodingKey { case id, title, createdAt, updatedAt, source, cells }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Lab"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        source = try c.decodeIfPresent(LabSource.self, forKey: .source)
        cells = try c.decodeIfPresent([LabCell].self, forKey: .cells) ?? []
    }

    /// Code of every code cell, in order, as one script.
    public var script: String { cells.filter { $0.kind == .code }.map(\.source).joined(separator: "\n\n") }
    /// Asset names of every image output.
    public var imageNames: [String] { cells.flatMap(\.outputs).compactMap(\.imageName) }
}

/// The passage a notebook came from: its page, region and words, named as the reader saw it (“Equation (3.44)”).
public struct LabSource: Codable, Equatable, Sendable {
    public var pageIndex: Int
    public var region: PageRegion?
    public var label: String
    public var quote: String
    public init(pageIndex: Int, region: PageRegion? = nil, label: String, quote: String = "") {
        self.pageIndex = pageIndex; self.region = region; self.label = label; self.quote = quote
    }
}

public struct LabCell: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case code, text }
    public var id: UUID
    public var kind: Kind
    public var source: String
    public var outputs: [LabOutput]
    /// The kernel's execution counter when the cell last ran, shown as “[3]”.
    public var executionCount: Int?
    public var lastRunAt: Date?
    public var duration: Double?

    public init(id: UUID = UUID(), kind: Kind = .code, source: String = "", outputs: [LabOutput] = []) {
        self.id = id; self.kind = kind; self.source = source; self.outputs = outputs
    }

    private enum CodingKeys: String, CodingKey { case id, kind, source, outputs, executionCount, lastRunAt, duration }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .code
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        outputs = try c.decodeIfPresent([LabOutput].self, forKey: .outputs) ?? []
        executionCount = try c.decodeIfPresent(Int.self, forKey: .executionCount)
        lastRunAt = try c.decodeIfPresent(Date.self, forKey: .lastRunAt)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
    }

    public var hasError: Bool { outputs.contains { $0.kind == .error } }
}

public struct LabOutput: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case stdout, stderr, result, error, image }
    public var kind: Kind
    /// Text for streams and results; for errors the exception line, with the traceback in `detail`.
    public var text: String
    public var detail: String?
    /// The PNG's asset name for images.
    public var imageName: String?

    public init(kind: Kind, text: String = "", detail: String? = nil, imageName: String? = nil) {
        self.kind = kind; self.text = text; self.detail = detail; self.imageName = imageName
    }

    /// Text outputs are capped so a runaway loop cannot bloat the workspace.
    public static let textLimit = 60_000

    /// Appends stream text to the last output when it is the same stream, as a terminal would.
    public static func append(_ text: String, stream kind: Kind, to outputs: inout [LabOutput]) {
        guard !text.isEmpty else { return }
        if let last = outputs.indices.last, outputs[last].kind == kind {
            guard outputs[last].text.count < textLimit else { return }
            outputs[last].text += text
            if outputs[last].text.count >= textLimit {
                outputs[last].text = String(outputs[last].text.prefix(textLimit)) + "\n… output truncated by Lemma"
            }
        } else {
            outputs.append(LabOutput(kind: kind, text: text.count > textLimit ? String(text.prefix(textLimit)) + "\n… output truncated by Lemma" : text))
        }
    }
}

// MARK: - Starting cells

public enum LabTemplate {
    /// The opening cells for a notebook started from a passage: the source quoted as text, then a code cell to work in.
    /// With `quoteSource`, the passage's words open the notebook as a text cell; otherwise the source card shows it.
    public static func cells(for source: LabSource?, sectionTitle: String? = nil, bookTitle: String, quoteSource: Bool = true) -> [LabCell] {
        var text = ""
        if let source, quoteSource {
            text += "### \(source.label)\n\n"
            let quote = source.quote.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !quote.isEmpty { text += quote.prefix(12).map { "> \($0)" }.joined(separator: "\n") + "\n\n" }
            text += "*\(bookTitle)\(sectionTitle.flatMap { $0 == source.label ? nil : " · \($0)" } ?? "")*"
        }
        let header = source.map { "# \($0.label) · try it with small synthetic data.\n" } ?? ""
        let code = "import numpy as np\nimport matplotlib.pyplot as plt\n\nrng = np.random.default_rng(0)\n\(header)"
        return (text.isEmpty ? [] : [LabCell(kind: .text, source: text)]) + [LabCell(kind: .code, source: code)]
    }

    /// Fenced code blocks in an answer (```python … ```), for opening a saved explanation's code in the Lab.
    /// Unlabelled blocks count when they look like Python; blocks in other languages are left out.
    public static func codeBlocks(in markdown: String) -> [String] {
        var blocks: [String] = []
        var current: [String]?
        var language = ""
        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if current == nil {
                if line.hasPrefix("```") {
                    language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                    current = []
                }
            } else if line.hasPrefix("```") {
                let code = (current ?? []).joined(separator: "\n").trimmingCharacters(in: .newlines)
                let python = ["python", "py", "python3", "ipython"].contains(language)
                    || (language.isEmpty && looksLikePython(code))
                if python, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(code) }
                current = nil; language = ""
            } else {
                current?.append(rawLine)
            }
        }
        return blocks
    }

    static func looksLikePython(_ code: String) -> Bool {
        let cues = ["import ", "def ", "print(", "np.", "plt.", "for ", " = ", "return "]
        return cues.contains { code.contains($0) } && !code.contains(";\n") && !code.contains("{\n")
    }
}

// MARK: - Export

public enum LabExport {
    /// A Jupyter notebook (nbformat 4) with the outputs Lemma recorded; images are embedded as base64 PNG.
    public static func ipynb(_ notebook: LabNotebook, python: String? = nil, image: (String) -> Data?) throws -> Data {
        func lines(_ text: String) -> [String] {
            guard !text.isEmpty else { return [] }
            var result = text.components(separatedBy: "\n").map { $0 + "\n" }
            result[result.count - 1].removeLast()
            if result.last == "" { result.removeLast() }
            return result
        }
        var cells: [[String: Any]] = []
        if let source = notebook.source {
            var intro = "### \(source.label)\n\n"
            let quote = source.quote.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !quote.isEmpty { intro += quote.prefix(12).map { "> \($0)" }.joined(separator: "\n") + "\n\n" }
            intro += "*From Lemma: PDF page \(source.pageIndex + 1).*"
            cells.append(["cell_type": "markdown", "metadata": [String: Any](), "source": lines(intro)])
        }
        for cell in notebook.cells {
            switch cell.kind {
            case .text:
                cells.append(["cell_type": "markdown", "metadata": [String: Any](), "source": lines(cell.source)])
            case .code:
                var outputs: [[String: Any]] = []
                for output in cell.outputs {
                    switch output.kind {
                    case .stdout, .stderr:
                        outputs.append(["output_type": "stream", "name": output.kind.rawValue, "text": lines(output.text)])
                    case .result:
                        outputs.append(["output_type": "execute_result", "execution_count": cell.executionCount ?? NSNull(),
                                        "data": ["text/plain": lines(output.text)], "metadata": [String: Any]()])
                    case .error:
                        let parts = output.text.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        outputs.append(["output_type": "error", "ename": parts.first ?? "Error", "evalue": parts.count > 1 ? parts[1] : "",
                                        "traceback": (output.detail ?? output.text).components(separatedBy: "\n")])
                    case .image:
                        guard let name = output.imageName, let data = image(name) else { continue }
                        outputs.append(["output_type": "display_data", "data": ["image/png": data.base64EncodedString(), "text/plain": ["<Figure>"]],
                                        "metadata": [String: Any]()])
                    }
                }
                cells.append(["cell_type": "code", "metadata": [String: Any](), "execution_count": cell.executionCount ?? NSNull(),
                              "source": lines(cell.source), "outputs": outputs])
            }
        }
        let document: [String: Any] = [
            "nbformat": 4, "nbformat_minor": 5,
            "metadata": ["kernelspec": ["name": "python3", "display_name": "Python 3", "language": "python"],
                         "language_info": ["name": "python", "version": python ?? ""],
                         "lemma": ["title": notebook.title, "created": ISO8601DateFormatter().string(from: notebook.createdAt)]],
            "cells": cells.enumerated().map { offset, cell in var cell = cell; cell["id"] = String(format: "cell-%04d", offset); return cell }
        ]
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// The notebook as a plain Python script, text cells kept as comments.
    public static func python(_ notebook: LabNotebook, bookTitle: String) -> String {
        var output = "# \(notebook.title)\n# From Lemma, \(bookTitle)"
        if let source = notebook.source { output += " · \(source.label), PDF page \(source.pageIndex + 1)" }
        output += "\n"
        for cell in notebook.cells {
            switch cell.kind {
            case .text:
                output += "\n" + cell.source.components(separatedBy: "\n").map { $0.isEmpty ? "#" : "# \($0)" }.joined(separator: "\n") + "\n"
            case .code:
                output += "\n# %%\n" + cell.source + "\n"
            }
        }
        return output
    }

    /// Where the script goes beside an exported notebook: “Ridge path.py” next to “Ridge path.ipynb”.
    public static func scriptURL(beside notebookURL: URL) -> URL {
        notebookURL.deletingPathExtension().appendingPathExtension("py")
    }

    /// Writes the notebook as .ipynb at `url` and, with `script`, its code as a .py beside it (replacing either file).
    public static func write(_ notebook: LabNotebook, to url: URL, bookTitle: String, python: String?, script: Bool,
                             image: (String) -> Data?) throws {
        try ipynb(notebook, python: python, image: image).write(to: url, options: .atomic)
        if script { try self.python(notebook, bookTitle: bookTitle).write(to: scriptURL(beside: url), atomically: true, encoding: .utf8) }
    }

    /// The name a figure is saved under: “Ridge path, cell 3.png”, or “Ridge path, cell 3, figure 2.png” for a cell
    /// with several figures. Cells count from 1, text cells included, as they appear in the notebook.
    public static func figureFileName(for notebook: LabNotebook, imageName: String) -> String {
        let stem = (fileName(for: notebook, extension: "png") as NSString).deletingPathExtension
        guard let index = notebook.cells.firstIndex(where: { $0.outputs.contains { $0.imageName == imageName } }) else { return stem + ".png" }
        let figures = notebook.cells[index].outputs.compactMap(\.imageName)
        let figure = figures.count > 1 ? figures.firstIndex(of: imageName).map { ", figure \($0 + 1)" } ?? "" : ""
        return "\(stem), cell \(index + 1)\(figure).png"
    }

    /// A file name that is safe on every file system: “Ridge path.ipynb”.
    public static func fileName(for notebook: LabNotebook, extension ext: String) -> String {
        let cleaned = notebook.title.map { "/\\:?*\"<>|".contains($0) ? "-" : $0 }
        let base = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(base.isEmpty ? "Lab" : String(base.prefix(80))).\(ext)"
    }
}
