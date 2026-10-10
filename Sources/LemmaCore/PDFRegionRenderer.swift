import AppKit
import PDFKit

/// Renders a region of a PDF page (a source crop, an equation, a figure) without the reader's ink or page theme.
/// Only the region is drawn: the bitmap has the region's size, not the page's, so a crop of a large scan no longer
/// allocates the whole page at 3× (hundreds of megabytes) to keep a few lines of it.
@MainActor
public enum PDFRegionRenderer {
    /// The region as PNG at `scale` times its size in points: the exact pixels saved with notes, pins and exports
    /// (the same as rendering the whole page at that scale and cropping it).
    public static func png(page: PDFPage, region: PageRegion, scale: CGFloat = 3) throws -> Data {
        let image = try image(page: page, region: region, scale: scale)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw BridgeError.invalidImage }
        return png
    }

    /// The region as an image, without a PNG round trip, for views. `maxPixels` caps its area (the scale is lowered to
    /// fit); exports leave it nil to keep the exact scale.
    public static func image(page: PDFPage, region: PageRegion, scale: CGFloat = 3, maxPixels: Int? = nil) throws -> CGImage {
        guard let reference = page.pageRef else { throw BridgeError.invalidImage }
        return try render(reference, region: region, scale: scale, maxPixels: maxPixels)
    }

    /// The region as an image sized in points, for views (a hover, a thumbnail).
    public static func nsImage(page: PDFPage, region: PageRegion, scale: CGFloat = 2, maxPixels: Int? = 4_000_000) throws -> NSImage {
        let cgImage = try image(page: page, region: region, scale: scale, maxPixels: maxPixels)
        let box = CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
        return NSImage(cgImage: cgImage, size: NSSize(width: box.width, height: box.height))
    }

    /// The same, drawn on a utility thread from the page's Core Graphics page (which can be drawn from any thread), so a
    /// view never waits for it. Nil when the region is empty or the page cannot be drawn.
    public static func backgroundImage(page: PDFPage, region: PageRegion, scale: CGFloat = 2, maxPixels: Int? = 4_000_000) async -> CGImage? {
        guard let reference = page.pageRef else { return nil }
        let source = DrawablePage(page: reference)
        return await Task.detached(priority: .utility) {
            try? PDFRegionRenderer.render(source.page, region: region, scale: scale, maxPixels: maxPixels)
        }.value
    }

    /// Draws only the region: the page is placed exactly as a full render at `scale` would place it, translated so the
    /// region's pixels (rounded out to whole pixels, as cropping that render did) start at the bitmap's origin.
    nonisolated static func render(_ reference: CGPDFPage, region: PageRegion, scale requested: CGFloat, maxPixels: Int?) throws -> CGImage {
        let box = reference.getBoxRect(.cropBox)
        let rotation = ((reference.rotationAngle % 360) + 360) % 360
        let size = rotation == 90 || rotation == 270 ? CGSize(width: box.height, height: box.width) : box.size
        let rectangle = CGRect(x: region.x, y: region.y, width: region.width, height: region.height).intersection(box)
        guard size.width > 0, size.height > 0, !rectangle.isEmpty, !rectangle.isNull else { throw BridgeError.invalidImage }
        var scale = requested
        if let maxPixels, maxPixels > 0 {
            let area = rectangle.width * rectangle.height * scale * scale
            if area > CGFloat(maxPixels) { scale = max(0.05, scale * (CGFloat(maxPixels) / area).squareRoot()) }
        }
        let pageWidth = ceil(size.width * scale), pageHeight = ceil(size.height * scale)
        let pageTransform = reference.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true)
        let transform = pageTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        // The region in the full render's pixels, top-left origin as an image is cropped, kept inside that render.
        let transformed = rectangle.applying(transform)
        let pixels = CGRect(x: transformed.minX, y: pageHeight - transformed.maxY, width: transformed.width, height: transformed.height).integral
            .intersection(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let width = Int(pixels.width), height = Int(pixels.height)
        guard !pixels.isNull, width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BridgeError.invalidImage
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Whole-pixel translation: the page lands on the same pixel grid as in the full render.
        context.translateBy(x: -pixels.minX, y: -(pageHeight - pixels.maxY))
        context.concatenate(transform)
        context.drawPDFPage(reference)
        guard let image = context.makeImage() else { throw BridgeError.invalidImage }
        return image
    }
}

/// A Core Graphics page handed to a drawing thread. CGPDFPage is immutable and Core Graphics draws one from several
/// threads (PDFKit itself renders tiles that way).
private struct DrawablePage: @unchecked Sendable {
    let page: CGPDFPage
}
