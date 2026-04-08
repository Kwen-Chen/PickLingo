import AppKit
import Foundation

struct IconSize {
    let size: Int
    let filename: String
}

let outputDir: String
if CommandLine.arguments.count > 1 {
    outputDir = CommandLine.arguments[1]
} else {
    outputDir = "PickLingo/Resources/Assets.xcassets/AppIcon.appiconset"
}

let fm = FileManager.default
try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let sizes: [IconSize] = [
    .init(size: 16, filename: "icon_16x16.png"),
    .init(size: 32, filename: "icon_16x16@2x.png"),
    .init(size: 32, filename: "icon_32x32.png"),
    .init(size: 64, filename: "icon_32x32@2x.png"),
    .init(size: 128, filename: "icon_128x128.png"),
    .init(size: 256, filename: "icon_128x128@2x.png"),
    .init(size: 256, filename: "icon_256x256.png"),
    .init(size: 512, filename: "icon_256x256@2x.png"),
    .init(size: 512, filename: "icon_512x512.png"),
    .init(size: 1024, filename: "icon_512x512@2x.png")
]

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return NSColor(calibratedRed: r, green: g, blue: b, alpha: alpha)
}

func drawSparkle(center: CGPoint, radius: CGFloat, insetRatio: CGFloat, fill: NSColor) {
    let inset = radius * insetRatio
    let points = [
        CGPoint(x: center.x, y: center.y + radius),
        CGPoint(x: center.x + inset, y: center.y + inset),
        CGPoint(x: center.x + radius, y: center.y),
        CGPoint(x: center.x + inset, y: center.y - inset),
        CGPoint(x: center.x, y: center.y - radius),
        CGPoint(x: center.x - inset, y: center.y - inset),
        CGPoint(x: center.x - radius, y: center.y),
        CGPoint(x: center.x - inset, y: center.y + inset)
    ]

    let path = NSBezierPath()
    path.move(to: points[0])
    for p in points.dropFirst() {
        path.line(to: p)
    }
    path.close()
    fill.setFill()
    path.fill()
}

for item in sizes {
    let size = CGFloat(item.size)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create bitmap for \(item.filename)")
    }

    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create graphics context for \(item.filename)")
    }
    NSGraphicsContext.current = ctx

    NSColor.clear.setFill()
    rect.fill()

    // Flat rounded-square background.
    let corner = size * 0.225
    let bgRect = rect.insetBy(dx: size * 0.04, dy: size * 0.04)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: corner, yRadius: corner)
    color(0x1D4ED8).setFill()
    bgPath.fill()

    // Main sparkle (references menu bar symbol "sparkles").
    drawSparkle(
        center: CGPoint(x: size * 0.50, y: size * 0.57),
        radius: size * 0.23,
        insetRatio: 0.34,
        fill: color(0xFFFFFF)
    )

    // Secondary sparkle for "multi-tool" energy.
    drawSparkle(
        center: CGPoint(x: size * 0.73, y: size * 0.74),
        radius: size * 0.07,
        insetRatio: 0.34,
        fill: color(0xBFDBFE)
    )

    // Three module dots to hint plugin-based architecture.
    let dotRadius = max(1.0, size * 0.033)
    let dotY = size * 0.27
    let spacing = size * 0.11
    let startX = size * 0.50 - spacing
    for i in 0..<3 {
        let x = startX + CGFloat(i) * spacing
        let dotRect = NSRect(x: x - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        color(0x93C5FD).setFill()
        dotPath.fill()
    }

    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for \(item.filename)")
    }
    let outPath = (outputDir as NSString).appendingPathComponent(item.filename)
    try png.write(to: URL(fileURLWithPath: outPath))
    print("Wrote \(outPath)")
}
