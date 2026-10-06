import AppKit

// Original app mark built from the native SF Symbols controller glyph.
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let inset = CGFloat(pixels) * 0.07
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: CGFloat(pixels) * 0.22, yRadius: CGFloat(pixels) * 0.22)
        NSColor(calibratedRed: 0.085, green: 0.105, blue: 0.105, alpha: 1).setFill(); shape.fill()
        NSColor(calibratedRed: 0.78, green: 0.92, blue: 0.84, alpha: 0.25).setStroke(); shape.lineWidth = max(CGFloat(pixels) * 0.006, 1); shape.stroke()
        if let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [NSColor(calibratedRed: 0.8, green: 0.94, blue: 0.86, alpha: 1)])) {
            let width = CGFloat(pixels) * 0.58
            let height = width * symbol.size.height / symbol.size.width
            symbol.draw(in: NSRect(x: (CGFloat(pixels) - width) / 2, y: (CGFloat(pixels) - height) / 2, width: width, height: height))
        }
        NSGraphicsContext.restoreGraphicsState()
        if let png = bitmap.representation(using: .png, properties: [:]) {
            let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
        }
    }
}
