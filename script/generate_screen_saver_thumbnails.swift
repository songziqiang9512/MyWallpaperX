#!/usr/bin/env swift
import AppKit

// Run after changing AppIcon; these static resources never render at runtime.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("MyWallpaperX/Assets.xcassets/AppIcon.appiconset")
let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog.appendingPathComponent("Contents.json"))) as? [String: Any]
let entries = contents?["images"] as? [[String: String]]
guard let entry = entries?.first(where: { $0["idiom"] == "mac" && $0["size"] == "512x512" && $0["scale"] == "2x" }),
      let filename = entry["filename"], let icon = NSImage(contentsOf: catalog.appendingPathComponent(filename)) else {
    throw CocoaError(.fileReadCorruptFile)
}

for scale in [1, 2] {
    let width = 90 * scale, height = 58 * scale, side = 52 * scale
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.coderInvalidValue) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
    icon.draw(in: NSRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
    let name = scale == 1 ? "thumbnail.png" : "thumbnail@2x.png"
    try data.write(to: root.appendingPathComponent("ScreenSaverSources/" + name), options: .atomic)
    print("Generated \(name): \(width)×\(height)")
}
