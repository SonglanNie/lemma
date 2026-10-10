// A small research probe, not the Lemma application.
// Usage: swift research/pdfkit_probe.swift <source.pdf> <output-directory>
import Foundation
import AppKit
import PDFKit

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift research/pdfkit_probe.swift <source.pdf> <output-directory>\n", stderr)
    exit(1)
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let document = PDFDocument(url: source) else {
    fputs("Could not open PDF.\n", stderr)
    exit(1)
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// These three passages are specific to the corrected ESL second edition.
let targets = [
    (name: "least-squares", needle: "unique solution", equation: "(3.6)"),
    (name: "covariance", needle: "uncorrelated", equation: "(3.8)"),
    (name: "ridge", needle: "nonsingular", equation: "(3.44)")
]
var observations: [[String: Any]] = []
for target in targets {
    var match: (Int, PDFPage, String, NSRange)?
    for index in 0..<min(document.pageCount, 120) {
        guard let page = document.page(at: index), let text = page.string,
              text.contains(target.equation) else { continue }
        let range = (text as NSString).range(of: target.needle, options: .caseInsensitive)
        if range.location != NSNotFound {
            match = (index, page, text, range)
            break
        }
    }
    guard let (index, page, text, matchRange) = match else {
        observations.append(["target": target.name, "found": false])
        continue
    }
    let textLength = (text as NSString).length
    let start = max(0, matchRange.location - 180)
    let range = NSRange(location: start, length: min(480, textLength - start))
    let selection = page.selection(for: range)
    let box = page.bounds(for: .cropBox)
    let selectedBounds = selection?.bounds(for: page) ?? .zero

    let scale: CGFloat = 3
    let width = Int(ceil(box.width * scale))
    let height = Int(ceil(box.height * scale))
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw NSError(domain: "PDFProbe", code: 1) }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scale, y: scale)
    // PDFKit's draw(with:to:) already positions the requested display box.
    // Applying the crop-box origin again would visibly shift and clip the page.
    page.draw(with: .cropBox, to: context)
    guard let rendered = context.makeImage() else { throw NSError(domain: "PDFProbe", code: 2) }
    let bitmap = NSBitmapImageRep(cgImage: rendered)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PDFProbe", code: 3)
    }
    try png.write(to: output.appendingPathComponent("\(target.name)-page.png"))
    try text.write(to: output.appendingPathComponent("\(target.name)-native.txt"), atomically: true, encoding: .utf8)

    // CGImage cropping uses an upper-left origin; PDF page space uses lower-left.
    // Expand the text selection for context. This is not semantic equation detection.
    let padded = selectedBounds.insetBy(dx: -10, dy: -10).intersection(box)
    if !padded.isNull && !padded.isEmpty {
        let pixels = CGRect(
            x: (padded.minX - box.minX) * scale,
            y: (box.maxY - padded.maxY) * scale,
            width: padded.width * scale, height: padded.height * scale
        ).integral
        if let crop = rendered.cropping(to: pixels),
           let cropPNG = NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:]) {
            try cropPNG.write(to: output.appendingPathComponent("\(target.name)-selection.png"))
        }
    }
    observations.append([
        "target": target.name,
        "found": true,
        "physicalPageIndex": index,
        "physicalPageNumber": index + 1,
        "pdfPageLabel": page.label ?? "",
        "nativeTextUTF16Length": textLength,
        "selectionLineCount": selection?.selectionsByLine().count ?? 0,
        "selectionBounds": [selectedBounds.minX, selectedBounds.minY, selectedBounds.width, selectedBounds.height],
        "cropBox": [box.minX, box.minY, box.width, box.height],
        "renderScale": Double(scale),
        "renderPixels": [width, height]
    ])
}
let report: [String: Any] = [
    "sourceFileName": source.lastPathComponent,
    "pageCount": document.pageCount,
    "observations": observations,
    "scope": "Three phrase-selected pages in one PDF; no OCR, semantic parsing, browser, or UI test."
]
let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("report.json"))
print(String(decoding: json, as: UTF8.self))
