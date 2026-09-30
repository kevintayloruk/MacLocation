import AppKit

enum StatusIcon {
    /// An RJ45 (Ethernet) socket seen face-on: the jack outline with its latch
    /// notch at the bottom and the eight contacts along the top. Drawn as a
    /// template image so macOS tints it for light/dark menu bars.
    static func ethernetPort() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()

            let body = NSBezierPath()
            body.move(to: NSPoint(x: 2.5, y: 3.5))
            body.line(to: NSPoint(x: 15.5, y: 3.5))
            body.line(to: NSPoint(x: 15.5, y: 12))
            body.line(to: NSPoint(x: 12, y: 12))
            body.line(to: NSPoint(x: 12, y: 15))
            body.line(to: NSPoint(x: 6, y: 15))
            body.line(to: NSPoint(x: 6, y: 12))
            body.line(to: NSPoint(x: 2.5, y: 12))
            body.close()
            body.lineWidth = 1.5
            body.lineJoinStyle = .round
            body.stroke()

            for pin in 0..<8 {
                let x = 4.6 + CGFloat(pin) * 1.26
                NSBezierPath(rect: NSRect(x: x - 0.35, y: 5.5, width: 0.7, height: 3)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MacLocation"
        return image
    }
}
