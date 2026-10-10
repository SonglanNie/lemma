import XCTest
import AppKit
import LemmaCore

final class OCRTests: XCTestCase {
    @MainActor
    func testRecognizesEnglishAndFrenchInSourceOrder() async throws {
        let lines = [
            "Every continuous function on a compact set is bounded.",
            "Les hypothèses du théorème sont nécessaires.",
            "Toute fonction continue sur un compact est bornée."
        ]
        let png = try textImage(lines: lines)
        let text = try await RegionTextRecognizer.recognize(png: png)
        XCTAssertEqual(text, lines.joined(separator: "\n"))
    }

    @MainActor
    func testRejectsInvalidSourceImage() async throws {
        do {
            _ = try await RegionTextRecognizer.recognize(png: Data())
            XCTFail("Invalid image data should not produce source text.")
        } catch RegionTextRecognitionError.invalidImage {
            // The user gets an actionable capture error instead of an empty OCR result.
        }
    }

    @MainActor
    func testCancellationBeforeRecognition() async throws {
        let task = Task { try await RegionTextRecognizer.recognize(png: Data()) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled OCR task should not produce source text.")
        } catch is CancellationError {
        }
    }

    @MainActor
    private func textImage(lines: [String]) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 500,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1600, height: 500).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black
        ]
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 72, y: 380 - CGFloat(index) * 100), withAttributes: attributes)
        }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
