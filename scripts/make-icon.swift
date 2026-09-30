// Renders the app icon (an RJ45 plug on a cable) into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// Draws the icon on a 1024×1024 canvas (origin bottom-left).
func drawIcon() {
    // Background: macOS-style rounded square with a blue gradient.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: rgb(0x3B8CFF), ending: rgb(0x1646A8))!.draw(in: tile, angle: -90)

    // Cable leaving the bottom of the plug.
    let cable = NSBezierPath()
    cable.move(to: NSPoint(x: 512, y: 100))
    cable.line(to: NSPoint(x: 512, y: 300))
    cable.lineWidth = 92
    rgb(0xE8EEF8).setStroke()
    cable.stroke()

    // Strain-relief boot.
    let boot = NSBezierPath()
    boot.move(to: NSPoint(x: 440, y: 250))
    boot.line(to: NSPoint(x: 584, y: 250))
    boot.line(to: NSPoint(x: 640, y: 350))
    boot.line(to: NSPoint(x: 384, y: 350))
    boot.close()
    rgb(0xD5DEEC).setFill()
    boot.fill()

    // Plug body.
    let body = NSBezierPath(roundedRect: NSRect(x: 342, y: 340, width: 340, height: 440), xRadius: 34, yRadius: 34)
    rgb(0xFFFFFF, 0.96).setFill()
    body.fill()

    // Latch clip.
    let latch = NSBezierPath(roundedRect: NSRect(x: 452, y: 390, width: 120, height: 210), xRadius: 16, yRadius: 16)
    rgb(0xB9C7DD).setFill()
    latch.fill()

    // Eight gold contacts.
    rgb(0xE0A526).setFill()
    for pin in 0..<8 {
        let x = 382 + CGFloat(pin) * 36.5
        NSBezierPath(roundedRect: NSRect(x: x, y: 650, width: 20, height: 100), xRadius: 5, yRadius: 5).fill()
    }
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, pixels) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()

    try rep.representation(using: .png, properties: [:])!
        .write(to: output.appendingPathComponent("\(name).png"))
}
