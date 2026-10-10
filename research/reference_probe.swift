// Prints the reference definitions and mentions Lemma finds on chosen pages of a PDF.
// Build after `swift build`:
//   swiftc -parse-as-library -I .build/debug/Modules research/reference_probe.swift \
//     .build/debug/LemmaCore.build/*.swift.o -o artifacts/v06-qa/reference-probe
// Run: artifacts/v06-qa/reference-probe <pdf> <first page> <last page> [crop directory]   (1-based physical pages)
import Foundation
import PDFKit
import LemmaCore

@main
struct ReferenceProbe {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 4, let document = PDFDocument(url: URL(fileURLWithPath: args[1])),
              let first = Int(args[2]), let last = Int(args[3]) else {
            print("usage: reference-probe <pdf> <first> <last>"); return
        }
        for number in first...last {
            guard let page = document.page(at: number - 1) else { continue }
            let started = Date()
            let definitions = PageReferenceAnalyzer.definitions(on: page, pageIndex: number - 1)
            let mentions = PageReferenceAnalyzer.mentions(on: page, in: document)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            print("— PDF page \(number) (\(ms) ms): \(definitions.count) definitions, \(mentions.count) mentions")
            for target in definitions {
                if args.count >= 5, let png = try? PDFRegionRenderer.png(page: page, region: target.region, scale: 2) {
                    let name = "p\(number)-" + target.key.spokenTitle.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "") + ".png"
                    try? png.write(to: URL(fileURLWithPath: args[4]).appendingPathComponent(name))
                }
                let r = target.region, a = target.anchor
                print(String(format: "  DEF %@  anchor (%.1f, %.1f, %.1f×%.1f)  region y %.1f–%.1f x %.1f–%.1f", target.key.spokenTitle, a.x, a.y, a.width, a.height, r.y, r.y + r.height, r.x, r.x + r.width))
            }
            for mention in mentions {
                print("  REF \(mention.key.spokenTitle) “\(mention.text.replacingOccurrences(of: "\n", with: "⏎"))” lines \(mention.rects.count)")
            }
        }
    }
}
