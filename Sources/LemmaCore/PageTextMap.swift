import Foundation
import PDFKit

/// Maps between points on a page and offsets in `page.string`.
///
/// PDFKit's `characterIndex(at:)` and `characterBounds(at:)` count characters differently from `page.string` on some
/// pages · they skip the line breaks PDFKit adds to the string, so offsets drift by a character per line · while
/// `selection(for: NSRange)` agrees with the string. Every conversion here goes through selections, so offsets read
/// from the text (mentions, definitions, proofs) and points under the pointer stay in one index space.
public struct PageTextMap {
    public struct Line: Equatable {
        /// The line's characters in `page.string`, without its line break.
        public let range: NSRange
        public let rect: CGRect
    }

    public let lines: [Line]

    public init(page: PDFPage) {
        let text = (page.string ?? "") as NSString
        var lines: [Line] = []
        var start = 0
        while start < text.length {
            let lineRange = text.lineRange(for: NSRange(location: start, length: 0))
            var content = lineRange
            while content.length > 0, let scalar = UnicodeScalar(text.character(at: content.upperBound - 1)),
                  CharacterSet.newlines.contains(scalar) { content.length -= 1 }
            if content.length > 0, let selection = page.selection(for: content) {
                let rect = selection.bounds(for: page)
                if !rect.isNull, !rect.isEmpty, LayoutFragment.isSane(rect) { lines.append(Line(range: content, rect: rect)) }
            }
            guard lineRange.upperBound > start else { break }
            start = lineRange.upperBound
        }
        self.lines = lines
    }

    /// The line under a point, else the one nearest to it vertically (then horizontally).
    public func line(at point: CGPoint) -> Line? {
        if let inside = lines.filter({ $0.rect.insetBy(dx: -1, dy: -1).contains(point) }).min(by: { $0.rect.height < $1.rect.height }) { return inside }
        return lines.min { distance($0.rect, point) < distance($1.rect, point) }
    }

    private func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dy = point.y < rect.minY ? rect.minY - point.y : point.y > rect.maxY ? point.y - rect.maxY : 0
        let dx = point.x < rect.minX ? rect.minX - point.x : point.x > rect.maxX ? point.x - rect.maxX : 0
        return dy * 4 + dx
    }

    /// The offset of the character under a point (or the nearest one on its line), found by measuring prefixes of the line.
    public func location(at point: CGPoint, on page: PDFPage) -> Int? {
        guard let line = line(at: point) else { return nil }
        guard point.x > line.rect.minX else { return line.range.location }
        var low = 0, high = line.range.length - 1
        while low < high {
            let middle = (low + high) / 2
            let prefix = NSRange(location: line.range.location, length: middle + 1)
            let maxX = page.selection(for: prefix)?.bounds(for: page).maxX ?? line.rect.maxX
            if maxX < point.x { low = middle + 1 } else { high = middle }
        }
        return line.range.location + low
    }

    /// The first line whose top is at or below `y` (in reading order down the page): where text starting at a height begins.
    public func firstLine(atOrBelow y: CGFloat) -> Line? {
        lines.filter { $0.rect.maxY <= y + 2 }.max { $0.rect.maxY < $1.rect.maxY }
    }

    /// The rectangle of one character as the reader sees it.
    public static func bounds(of location: Int, on page: PDFPage) -> CGRect? {
        guard let rect = page.selection(for: NSRange(location: location, length: 1))?.bounds(for: page), !rect.isNull, !rect.isEmpty else { return nil }
        return rect
    }
}
