// Draws the app icon (a white dried fish on an orange tile) into an .iconset folder for iconutil.
// Usage: swift tools/make_icon.swift build/AppIcon.iconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let orange = NSColor(calibratedRed: 0.871, green: 0.525, blue: 0.153, alpha: 1)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, pixels) in sizes {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let side = CGFloat(pixels)
    let inset = side * 0.09
    let tile = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    orange.setFill()
    NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225).fill()

    // The same fish as the page's icon: viewBox 24 x 14, flipped to AppKit's upward y axis.
    let width = tile.width * 0.64
    let height = width * 14 / 24
    let originX = tile.midX - width / 2
    let originY = tile.midY - height / 2
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: originX + x / 24 * width, y: originY + (14 - y) / 14 * height)
    }
    let fish = NSBezierPath()
    fish.move(to: point(1, 7))
    fish.curve(to: point(16, 5), controlPoint1: point(4, 1.6), controlPoint2: point(11, 1))
    fish.line(to: point(22, 1))
    fish.line(to: point(22, 13))
    fish.line(to: point(16, 9))
    fish.curve(to: point(1, 7), controlPoint1: point(11, 13), controlPoint2: point(4, 12.4))
    fish.close()
    NSColor.white.setFill()
    fish.fill()
    let eye = point(5.4, 6)
    let radius = width * 0.035
    orange.setFill()
    NSBezierPath(ovalIn: NSRect(x: eye.x - radius, y: eye.y - radius, width: radius * 2, height: radius * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()

    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: output.appendingPathComponent("\(name).png"))
    }
}
