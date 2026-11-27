// Draws the Lagoon app icon. Run: swift Assets/make-icon.swift Assets/AppIcon-1024.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a) }

// macOS icon grid: 824 pt body with a 100 pt margin, ~185 pt corner radius.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Drop shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: c(0, 20, 40, 0.35).cgColor)
c(10, 60, 90).setFill(); shape.fill()
ctx.restoreGState()

// Water: deep blue at the top to turquoise shallows at the bottom.
ctx.saveGState(); shape.addClip()
NSGradient(colors: [c(6, 40, 92), c(10, 110, 170), c(40, 200, 205), c(150, 240, 225)],
           atLocations: [0, 0.4, 0.78, 1], colorSpace: .sRGB)!.draw(in: body, angle: -90)
// Soft light from the top-left.
NSGradient(colors: [c(255, 255, 255, 0.18), c(255, 255, 255, 0)])!
    .draw(fromCenter: NSPoint(x: 330, y: 820), radius: 0, toCenter: NSPoint(x: 330, y: 820), radius: 520, options: [])
// Ripples spreading out from under the island.
for (i, r) in [150.0, 250, 360].enumerated() {
    let p = NSBezierPath(); p.appendArc(withCenter: NSPoint(x: 512, y: 640), radius: r, startAngle: 200, endAngle: 340)
    p.lineWidth = 14 - CGFloat(i) * 3
    c(255, 255, 255, 0.28 - CGFloat(i) * 0.07).setStroke(); p.stroke()
}
ctx.restoreGState()

// The island: a black pill near the top, like the notch.
let pill = NSRect(x: 232, y: 640, width: 560, height: 150)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: c(0, 0, 0, 0.45).cgColor)
NSColor.black.setFill(); NSBezierPath(roundedRect: pill, xRadius: 75, yRadius: 75).fill()
ctx.restoreGState()

// Cover art square on the left of the pill.
let art = NSRect(x: pill.minX + 38, y: pill.midY - 37, width: 74, height: 74)
ctx.saveGState(); NSBezierPath(roundedRect: art, xRadius: 18, yRadius: 18).addClip()
NSGradient(colors: [c(60, 220, 230), c(20, 120, 220)])!.draw(in: art, angle: -45)
ctx.restoreGState()

// Wave bars on the right, same blue as the app's default wave.
let heights: [CGFloat] = [46, 86, 62, 100, 54]
for (i, h) in heights.enumerated() {
    let x = pill.maxX - 60 - CGFloat(heights.count - 1 - i) * 30 - 16
    let bar = NSRect(x: x, y: pill.midY - h / 2, width: 16, height: h)
    c(40, 150, 255).setFill(); NSBezierPath(roundedRect: bar, xRadius: 8, yRadius: 8).fill()
}

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
