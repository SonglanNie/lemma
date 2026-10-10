// Render the public ESL test passage with the application's actual renderer.
// Compile against LemmaCore's SwiftPM objects; see docs/VALIDATION.md.
import Foundation
import AppKit
import PDFKit
import LemmaCore

@main
struct RenderRegionQA {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "RenderRegionQA", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Expected source PDF and output PNG paths."])
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        guard let document = PDFDocument(url: source), let page = document.page(at: 63) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let region = PageRegion(x: 123.766, y: 131.672, width: 342.785, height: 126.919)
        let png = try PDFRegionRenderer.png(page: page, region: region)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: output, options: .atomic)
        let bitmap = NSBitmapImageRep(data: png)!
        print("ESL physical page 64; PNG \(bitmap.pixelsWide) x \(bitmap.pixelsHigh); \(png.count) bytes")
    }
}
