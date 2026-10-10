import AppKit
import Foundation

// Lemma's app icon, drawn at every size of a macOS iconset: a white serif λ on an olive tile, the mark Lemma also shows
// in its tour and title bar. Proportions follow macOS's icon grid: an 824 pt rounded square with continuous corners
// centred on a 1024 pt canvas, a soft shadow under it.

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// The macOS icon tile: a superellipse (|x|^n + |y|^n = 1, n = 5), close to the continuous-corner shape of system icons.
func continuousRect(_ rect: CGRect, radius _: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0
    let (cx, cy, a, b) = (rect.midX, rect.midY, rect.width / 2, rect.height / 2)
    let steps = 720
    for step in 0...steps {
        let t = Double(step) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * CGFloat(copysign(pow(abs(c), 2 / n), c))
        let y = cy + b * CGFloat(copysign(pow(abs(s), 2 / n), s))
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func drawIcon(in context: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = continuousRect(tile, radius: 185)

    // Shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.32))
    context.addPath(tilePath); context.setFillColor(color(0x4A4D12)); context.fillPath()
    context.restoreGState()

    // The tile: olive, a little lighter at the top, with a hairline of light along its edge (the tour's colours).
    context.saveGState()
    context.addPath(tilePath); context.clip()
    let tileGradient = CGGradient(colorsSpace: space, colors: [color(0x6B6E21), color(0x4A4D12)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(tileGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.addPath(tilePath); context.setStrokeColor(color(0xFFFFFF, 0.18)); context.setLineWidth(16); context.strokePath()
    context.restoreGState()

    // The λ in white, set in the system serif and centred a little above the middle.
    let size: CGFloat = 0.66 * 824
    let descriptor = NSFont.systemFont(ofSize: size, weight: .medium).fontDescriptor.withDesign(.serif)!
    let font = NSFont(descriptor: descriptor, size: size)!
    let glyph = NSAttributedString(string: "λ", attributes: [.font: font, .foregroundColor: NSColor.white])
    let line = CTLineCreateWithAttributedString(glyph)
    let bounds = CTLineGetImageBounds(line, context)
    context.textPosition = CGPoint(x: 512 - bounds.midX, y: 512 - bounds.midY + 0.02 * 824)
    CTLineDraw(line, context)
}

for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128),
                       ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name + ".png"))
}
