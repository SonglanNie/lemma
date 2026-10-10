import Foundation
import PDFKit

/// A page's text and printed label, as the library-wide search reads them.
public struct PageText: Codable, Equatable, Sendable {
    public let text: String
    public let label: String
    public init(text: String, label: String) { self.text = text; self.label = label }
}

/// Each book's page texts, kept beside its analysis as `Indexes/<fingerprint>/pagetext.json`.
public enum PageTextFile {
    public static let name = "pagetext.json"

    public static func read(_ url: URL) -> [PageText]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([PageText].self, from: data)
    }

    public static func write(_ pages: [PageText], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(pages).write(to: url, options: .atomic)
    }

    /// Reads every page's text. PDFKit keeps what text extraction builds for as long as its document lives, so the
    /// pages are read in batches, each from a fresh document drained by its own pool.
    public static func extract(source: URL, batch: Int = 40, isCancelled: () -> Bool = { false }) -> [PageText]? {
        guard let count = autoreleasepool(invoking: { PDFDocument(url: source)?.pageCount }) else { return nil }
        var pages: [PageText] = []
        pages.reserveCapacity(count)
        var start = 0
        while start < count {
            if isCancelled() { return nil }
            let end = min(count, start + max(1, batch))
            let read = autoreleasepool { () -> Bool in
                guard let document = PDFDocument(url: source) else { return false }
                for index in start..<end {
                    autoreleasepool {
                        let page = document.page(at: index)
                        pages.append(PageText(text: page?.string ?? "", label: page?.label ?? String(index + 1)))
                    }
                }
                return true
            }
            guard read else { return nil }
            start = end
        }
        return pages
    }
}
