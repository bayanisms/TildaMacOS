import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus()
        let shape = NSBezierPath(roundedRect: NSRect(x: 55, y: 55, width: 914, height: 914), xRadius: 210, yRadius: 210)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.15, green: 0.2, blue: 0.29, alpha: 1), ending: NSColor(srgbRed: 0.045, green: 0.065, blue: 0.1, alpha: 1))!
        gradient.draw(in: shape, angle: -90)
        NSColor(white: 1, alpha: 0.13).setStroke(); shape.lineWidth = 3; shape.stroke()
        let accent = NSColor(srgbRed: 0.47, green: 0.84, blue: 0.69, alpha: 1)
        let bar = NSBezierPath(roundedRect: NSRect(x: 225, y: 758, width: 574, height: 22), xRadius: 11, yRadius: 11)
        accent.withAlphaComponent(0.5).setFill(); bar.fill()
        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: 270, y: 460))
        wave.curve(to: NSPoint(x: 511, y: 460), controlPoint1: NSPoint(x: 355, y: 630), controlPoint2: NSPoint(x: 418, y: 540))
        wave.curve(to: NSPoint(x: 753, y: 460), controlPoint1: NSPoint(x: 607, y: 380), controlPoint2: NSPoint(x: 678, y: 307))
        wave.lineWidth = 62; wave.lineCapStyle = .round; accent.setStroke(); wave.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
    }
}
// Store standard PNG representations directly in the modern ICNS container.
// This also works on Macs without the optional iconutil conversion services.
var chunks = Data()
func bigEndian(_ number: Int) -> Data {
    var value = UInt32(number).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
for (kind, file) in [("icp4", "16x16"), ("icp5", "32x32"), ("icp6", "32x32@2x"), ("ic07", "128x128"), ("ic08", "256x256"), ("ic09", "512x512"), ("ic10", "512x512@2x")] {
    let png = try Data(contentsOf: destination.appendingPathComponent("icon_\(file).png"))
    chunks.append(Data(kind.utf8)); chunks.append(bigEndian(png.count + 8)); chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndian(chunks.count + 8)); icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
