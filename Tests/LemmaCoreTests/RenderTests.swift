import XCTest
import PDFKit
import AppKit
import LemmaCore

final class RenderTests: XCTestCase {
    @MainActor
    func testSourceCropWithNonzeroOriginAndRotation() async throws {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var media = CGRect(x: 0, y: 0, width: 600, height: 800)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &media, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 90, y: 100, width: 70, height: 50))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 380, y: 500, width: 40, height: 40))
        context.endPDFPage(); context.closePDF()
        let document = try XCTUnwrap(PDFDocument(data: data as Data))
        let page = try XCTUnwrap(document.page(at: 0))
        page.setBounds(CGRect(x: 50, y: 70, width: 420, height: 560), for: .cropBox)
        let region = PageRegion(x: 90, y: 100, width: 70, height: 50)
        for rotation in [0, 90] {
            page.rotation = rotation
            // Reopen actual serialized PDF page geometry, rather than a mock page reference.
            let reopened = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(document.dataRepresentation())))
            let actualPage = try XCTUnwrap(reopened.page(at: 0))
            let png = try PDFRegionRenderer.png(page: actualPage, region: region)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
            XCTAssertEqual(bitmap.pixelsWide, rotation == 0 ? 210 : 150)
            XCTAssertEqual(bitmap.pixelsHigh, rotation == 0 ? 150 : 210)
            let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(center.redComponent, 0.95)
            XCTAssertLessThan(center.blueComponent, 0.05)
        }
    }

    @MainActor
    func testRegionRendersMatchTheFullPageRender() throws {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var media = CGRect(x: 0, y: 0, width: 600, height: 800)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &media, nil))
        context.beginPDFPage(nil)
        for index in 0..<40 {
            context.setFillColor(CGColor(red: CGFloat(index % 5) / 5, green: 0.3, blue: CGFloat(index % 3) / 3, alpha: 1))
            context.fillEllipse(in: CGRect(x: 13.3 * CGFloat(index), y: 17.7 * CGFloat(index), width: 41.5, height: 23.25))
        }
        context.endPDFPage(); context.closePDF()
        let document = try XCTUnwrap(PDFDocument(data: data as Data))
        let page = try XCTUnwrap(document.page(at: 0))
        page.setBounds(CGRect(x: 50, y: 70, width: 420, height: 560), for: .cropBox)
        for rotation in [0, 90, 180, 270] {
            page.rotation = rotation
            let reopened = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(document.dataRepresentation())))
            let actual = try XCTUnwrap(reopened.page(at: 0))
            for (region, scales) in [(PageRegion(x: 90.3, y: 100.7, width: 70.2, height: 50.9), [CGFloat(2), 3]),
                                     (PageRegion(x: 40, y: 60, width: 500, height: 700), [1]),
                                     (PageRegion(x: 300.5, y: 500.25, width: 160, height: 33.3), [2, 3])] {
                for scale in scales {
                    let fast = try XCTUnwrap(NSBitmapImageRep(data: PDFRegionRenderer.png(page: actual, region: region, scale: scale)))
                    let reference = try XCTUnwrap(NSBitmapImageRep(data: fullPageCrop(actual, region: region, scale: scale)))
                    let label = "rotation \(rotation), region \(region), scale \(scale)"
                    XCTAssertEqual(fast.pixelsWide, reference.pixelsWide, label)
                    XCTAssertEqual(fast.pixelsHigh, reference.pixelsHigh, label)
                    // The same pixels, but for a handful of anti-aliased edge pixels rounded one level apart.
                    let (different, largest) = try difference(fast, reference)
                    XCTAssertLessThanOrEqual(largest, 1, label)
                    XCTAssertLessThanOrEqual(different, max(4, fast.pixelsWide * fast.pixelsHigh / 2000), label)
                }
            }
        }
        // A cap on pixels lowers the scale for views, never for saved crops.
        let capped = try PDFRegionRenderer.image(page: page, region: PageRegion(x: 50, y: 70, width: 420, height: 560), scale: 3, maxPixels: 100_000)
        XCTAssertLessThanOrEqual(capped.width * capped.height, 100_000 + capped.width + capped.height + 1)
    }

    /// Pixels that differ between two images of the same size, and the largest difference in one channel (0–255).
    private func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) throws -> (Int, Int) {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return (Int.max, 255) }
        guard a.bitsPerPixel == b.bitsPerPixel, a.bytesPerRow == b.bytesPerRow, let p = a.bitmapData, let q = b.bitmapData else { return (Int.max, 255) }
        let bytes = a.bitsPerPixel / 8
        var different = 0, largest = 0
        for row in 0..<a.pixelsHigh {
            for column in 0..<a.pixelsWide {
                var delta = 0
                for channel in 0..<bytes {
                    let offset = row * a.bytesPerRow + column * bytes + channel
                    delta = max(delta, abs(Int(p[offset]) - Int(q[offset])))
                }
                if delta > 0 { different += 1; largest = max(largest, delta) }
            }
        }
        return (different, largest)
    }

    /// The renderer before 3.0: the whole page at `scale`, then the region cropped out of it.
    @MainActor
    private func fullPageCrop(_ page: PDFPage, region: PageRegion, scale: CGFloat) throws -> Data {
        let reference = try XCTUnwrap(page.pageRef)
        let box = reference.getBoxRect(.cropBox)
        let rotation = ((reference.rotationAngle % 360) + 360) % 360
        let size = rotation == 90 || rotation == 270 ? CGSize(width: box.height, height: box.width) : box.size
        let width = Int(ceil(size.width * scale)), height = Int(ceil(size.height * scale))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let pageTransform = reference.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true)
        let transform = pageTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        context.concatenate(transform)
        context.drawPDFPage(reference)
        let rectangle = CGRect(x: region.x, y: region.y, width: region.width, height: region.height).intersection(box)
        let rendered = try XCTUnwrap(context.makeImage())
        let transformed = rectangle.applying(transform)
        let pixels = CGRect(x: transformed.minX, y: CGFloat(height) - transformed.maxY, width: transformed.width, height: transformed.height).integral
        let crop = try XCTUnwrap(rendered.cropping(to: pixels))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:]))
    }
}
