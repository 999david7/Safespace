// Renders the app icon to a 1024×1024 PNG: swift scripts/make-icon.swift <output.png>
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let size: CGFloat = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: ~824pt rounded square centred in 1024.
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.current?.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// Paper card with an ink globe, matching the app's monochrome theme.
NSColor.white.setFill()
shape.fill()

let center = NSPoint(x: size / 2, y: size / 2)
let radius = rect.width * 0.34
NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()

// Dotted latitudes.
NSColor.white.setFill()
let dot = radius * 0.062
for row in [-0.66, -0.4, -0.14, 0.14, 0.4, 0.66] as [CGFloat] {
    let y = center.y + row * radius
    let halfChord = radius * (1 - row * row).squareRoot() * 0.82
    let steps = max(2, Int(halfChord / (dot * 2.7)))
    for step in -steps...steps {
        let x = center.x + CGFloat(step) * (halfChord / CGFloat(steps))
        NSBezierPath(ovalIn: NSRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2)).fill()
    }
}

// A single yellow marker spike, like a login on the globe.
NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.25, alpha: 1).setStroke()
let spike = NSBezierPath()
spike.lineWidth = radius * 0.075
spike.move(to: NSPoint(x: center.x + radius * 0.62, y: center.y + radius * 0.62))
spike.line(to: NSPoint(x: center.x + radius * 0.95, y: center.y + radius * 0.95))
spike.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
