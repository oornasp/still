// Draws the Still app icon at every size and packs it into AppIcon.icns.
// Usage: swift scripts/make_icon.swift <output-dir>
import AppKit

let outDir = CommandLine.arguments.dropFirst().first ?? "Resources"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Superellipse ("squircle") close to the macOS icon silhouette.
func squircle(in rect: NSRect, exponent n: CGFloat = 5) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c >= 0 ? 1 : -1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s >= 0 ? 1 : -1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
    }
    path.close()
    return path
}

func drawIcon(size px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let k = CGFloat(px) / 1024
    ctx.scaleBy(x: k, y: k)

    // Body on the standard 824pt grid, with the usual soft drop shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.32)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 22
    shadow.set()
    rgb(0x1C1C1F).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(starting: rgb(0x2E2E33), ending: rgb(0x141416))!.draw(in: body, angle: -90)
    // Faint top light, like a lacquered surface.
    NSGradient(colors: [NSColor(white: 1, alpha: 0.07), NSColor(white: 1, alpha: 0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Inner hairline edge.
    let edge = squircle(in: body.insetBy(dx: 2, dy: 2))
    edge.lineWidth = 3
    NSColor(white: 1, alpha: 0.06).setStroke()
    edge.stroke()

    let center = NSPoint(x: 512, y: 512)
    let radius: CGFloat = 232
    let lineWidth: CGFloat = 62

    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = lineWidth
    NSColor(white: 1, alpha: 0.07).setStroke()
    track.stroke()

    // Remaining-time arc: from 12 o'clock, three quarters around.
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 180, clockwise: true)
    arc.lineWidth = lineWidth
    arc.lineCapStyle = .round
    let arcCG = arc.cgPath.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)

    // Warm glow beneath the arc.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46, color: rgb(0xFF6A45, 0.55).cgColor)
    ctx.addPath(arcCG)
    ctx.setFillColor(rgb(0xF4603F).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(arcCG)
    ctx.clip()
    NSGradient(starting: rgb(0xFF9B73), ending: rgb(0xE9472A))!
        .draw(from: NSPoint(x: 760, y: 760), to: NSPoint(x: 260, y: 300), options: [])
    ctx.restoreGState()

    // The still point.
    let dot: CGFloat = 30
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: rgb(0xFF6A45, 0.5).cgColor)
    rgb(0xFF7F5E).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)).fill()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: base * scale).representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
    }
}
try drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "docs/icon.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print("wrote \(outDir)/AppIcon.icns")
