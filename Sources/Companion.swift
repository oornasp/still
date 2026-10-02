import AppKit

/// The menu bar panda. Every pose is drawn procedurally as a 22 × 18 pt
/// template image, so it stays crisp at any scale and tints with the menu bar
/// like a system glyph. A panda's white fur is drawn as an outline and its
/// black markings (ears, eye patches, limbs, shoulder band) as solid fills.
///
/// The panda mirrors the session: asleep when idle, sitting with folded arms
/// when paused, calmly chewing bamboo while you focus — the stalk shrinks as
/// the session runs down — and trotting about during breaks.
enum PandaPose: Hashable {
    case sleeping
    case waiting
    case eating(bamboo: Int)
    case trotting
}

struct PandaFrame {
    let image: NSImage
    let cgImage: CGImage?
    let duration: TimeInterval

    init(image: NSImage, duration: TimeInterval) {
        self.image = image
        self.cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        self.duration = duration
    }
}

enum Panda {
    static let size = NSSize(width: 22, height: 18)
    /// How many lengths the bamboo stalk is quantized into.
    static let bambooSteps = 6

    private static var cache: [PandaPose: [PandaFrame]] = [:]

    /// Looping frame sequence for a pose. A single frame means "hold still".
    static func sequence(_ pose: PandaPose) -> [PandaFrame] {
        if let frames = cache[pose] { return frames }
        let frames: [PandaFrame]
        switch pose {
        case .sleeping:
            frames = [PandaFrame(image: image { drawSleeping($0) }, duration: .infinity)]
        case .waiting:
            frames = [PandaFrame(image: image { drawSitting($0, bamboo: nil, bite: 0, eyes: .open, cx: 11) }, duration: .infinity)]
        case .eating(let bamboo):
            // Long stillness, a few chews, more stillness, a blink.
            let length = CGFloat(bamboo) / CGFloat(bambooSteps)
            let still = image { drawSitting($0, bamboo: length, bite: 0, eyes: .open) }
            let blink = image { drawSitting($0, bamboo: length, bite: 0, eyes: .blink) }
            let chew = [0.5, 1, 0.6, 1, 0.5].map { b in image { drawSitting($0, bamboo: length, bite: b, eyes: .open) } }
            frames = [PandaFrame(image: still, duration: 4)]
                + chew.map { PandaFrame(image: $0, duration: 0.14) }
                + [PandaFrame(image: still, duration: 3.4), PandaFrame(image: blink, duration: 0.15)]
        case .trotting:
            frames = (0..<8).map { i in
                PandaFrame(image: image { drawTrotting($0, t: Double(i) / 8) }, duration: 0.1)
            }
        }
        cache[pose] = frames
        return frames
    }

    /// Rasterized once at Retina scale, so swapping frames never re-runs vector drawing.
    private static func image(_ draw: (CGContext) -> Void) -> NSImage {
        let scale: CGFloat = 2
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return NSImage(size: size) }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(.black)
        ctx.setStrokeColor(.black)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        draw(ctx)
        let image = ctx.makeImage().map { NSImage(cgImage: $0, size: size) } ?? NSImage(size: size)
        image.isTemplate = true
        return image
    }

    // MARK: - Shape helpers

    private static let outline: CGFloat = 1.15

    private static func ellipsePath(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, angle: CGFloat = 0) -> CGPath {
        var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
        return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: &t)
    }

    private static func fill(_ ctx: CGContext, _ path: CGPath) {
        ctx.addPath(path)
        ctx.fillPath()
    }

    /// White fur: erase whatever is behind, then draw the outline.
    private static func fur(_ ctx: CGContext, _ path: CGPath) {
        ctx.setBlendMode(.clear)
        fill(ctx, path)
        ctx.setBlendMode(.normal)
        ctx.setLineWidth(outline)
        ctx.addPath(path)
        ctx.strokePath()
    }

    private static func punch(_ ctx: CGContext, _ path: CGPath) {
        ctx.setBlendMode(.clear)
        fill(ctx, path)
        ctx.setBlendMode(.normal)
    }

    private static func limb(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, width: CGFloat = 2.6) {
        ctx.setLineWidth(width)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }

    // MARK: - Front-facing head

    private static func frontHead(_ ctx: CGContext, _ c: CGPoint, tilt: CGFloat = 0, eyes: Eyes) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: tilt)
        let o = CGPoint.zero
        fill(ctx, ellipsePath(CGPoint(x: -3.3, y: 3.3), 1.6, 1.6))   // ears
        fill(ctx, ellipsePath(CGPoint(x: 3.3, y: 3.3), 1.6, 1.6))
        fur(ctx, ellipsePath(o, 4.3, 3.9))
        fill(ctx, ellipsePath(CGPoint(x: -1.75, y: 0.15), 1.15, 1.55, angle: 0.55))  // eye patches
        fill(ctx, ellipsePath(CGPoint(x: 1.75, y: 0.15), 1.15, 1.55, angle: -0.55))
        switch eyes {
        case .open:
            punch(ctx, ellipsePath(CGPoint(x: -1.55, y: 0.45), 0.5, 0.5))
            punch(ctx, ellipsePath(CGPoint(x: 1.55, y: 0.45), 0.5, 0.5))
        case .closed:
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(0.55)
            for x in [-1.6, 1.6] as [CGFloat] {
                ctx.move(to: CGPoint(x: x - 0.6, y: 0.5))
                ctx.addQuadCurve(to: CGPoint(x: x + 0.6, y: 0.5), control: CGPoint(x: x, y: -0.15))
                ctx.strokePath()
            }
            ctx.setBlendMode(.normal)
        case .blink:
            break
        }
        fill(ctx, ellipsePath(CGPoint(x: 0, y: -1.6), 0.7, 0.45))     // nose
        ctx.restoreGState()
    }

    private enum Eyes { case open, closed, blink }

    // MARK: - Poses

    /// Front-facing, sitting. `bamboo` is the remaining stalk (0...1) or nil
    /// for empty paws; `bite` (0...1) lifts the stalk to the mouth.
    private static func drawSitting(_ ctx: CGContext, bamboo: CGFloat?, bite: Double, eyes: Eyes,
                                    cx: CGFloat = 10, tilt: CGFloat = 0) {
        let dip = CGFloat(bite) * 0.5

        fill(ctx, ellipsePath(CGPoint(x: cx - 3.6, y: 1.9), 2.2, 1.6))  // feet
        fill(ctx, ellipsePath(CGPoint(x: cx + 3.6, y: 1.9), 2.2, 1.6))
        fur(ctx, ellipsePath(CGPoint(x: cx, y: 5.6), 4.9, 4.3))           // belly

        if let bamboo {
            // Stalk held in the right paw, leaning toward the mouth when biting.
            let hand = CGPoint(x: cx + 2.6, y: 5.4 + dip)
            let angle = 0.42 - CGFloat(bite) * 0.32
            let full: CGFloat = 10.5
            let length = max(1.2, full * bamboo)
            let tip = CGPoint(x: hand.x + sin(angle) * length, y: hand.y + cos(angle) * length)
            let bottom = CGPoint(x: hand.x - sin(angle) * 1.6, y: hand.y - cos(angle) * 1.6)
            limb(ctx, bottom, tip, width: 1.1)
            // Nodes along the stalk
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(0.45)
            var d: CGFloat = 2.8
            while d < length - 0.6 {
                let p = CGPoint(x: hand.x + sin(angle) * d, y: hand.y + cos(angle) * d)
                let n = CGPoint(x: cos(angle) * 0.7, y: -sin(angle) * 0.7)
                ctx.move(to: CGPoint(x: p.x - n.x, y: p.y - n.y))
                ctx.addLine(to: CGPoint(x: p.x + n.x, y: p.y + n.y))
                ctx.strokePath()
                d += 2.8
            }
            ctx.setBlendMode(.normal)
            if bamboo > 0.5 { // leaves until it's been eaten down
                fill(ctx, ellipsePath(CGPoint(x: tip.x + 1.2, y: tip.y - 0.2), 1.5, 0.5, angle: -0.5))
                fill(ctx, ellipsePath(CGPoint(x: tip.x - 0.2, y: tip.y + 1.0), 1.4, 0.45, angle: 1.1))
            }
            limb(ctx, CGPoint(x: cx - 3.8, y: 8.0), CGPoint(x: cx - 1.2, y: 5.6))       // left arm across belly
            limb(ctx, CGPoint(x: cx + 3.8, y: 8.0), hand)                                // right arm holds stalk
        } else {
            // Paws folded on the belly.
            limb(ctx, CGPoint(x: cx - 3.8, y: 8.0), CGPoint(x: cx - 0.6, y: 5.2))
            limb(ctx, CGPoint(x: cx + 3.8, y: 8.0), CGPoint(x: cx + 0.6, y: 5.2))
        }
        frontHead(ctx, CGPoint(x: cx, y: 12.4 - dip - abs(tilt) * 1.5), tilt: CGFloat(bite) * 0.12 + tilt, eyes: eyes)
    }

    /// Side view, facing right, mid-trot.
    private static func drawTrotting(_ ctx: CGContext, t: Double) {
        let phase = CGFloat(t * 2 * .pi)
        let bob = 0.55 * abs(sin(phase))
        let body = CGPoint(x: 9.8, y: 7.6 + bob)
        let shoulder = CGPoint(x: body.x + 3.4, y: body.y - 1.0)
        let hip = CGPoint(x: body.x - 3.6, y: body.y - 1.0)
        let swing: CGFloat = 0.55
        func foot(_ from: CGPoint, _ angle: CGFloat) -> CGPoint {
            let length: CGFloat = 4.3
            return CGPoint(x: from.x + length * sin(angle), y: from.y - length * cos(angle))
        }
        // Far legs (the other diagonal pair), softened for depth.
        ctx.setAlpha(0.5)
        let farShoulder = CGPoint(x: shoulder.x - 1.1, y: shoulder.y)
        let farHip = CGPoint(x: hip.x + 1.1, y: hip.y)
        limb(ctx, farShoulder, foot(farShoulder, -swing * sin(phase)))
        limb(ctx, farHip, foot(farHip, swing * sin(phase)))
        ctx.setAlpha(1)

        fur(ctx, ellipsePath(body, 6.0, 3.8))
        // Black saddle over the shoulders, down into the front leg.
        ctx.saveGState()
        ctx.addPath(ellipsePath(body, 6.0, 3.8))
        ctx.clip()
        fill(ctx, ellipsePath(CGPoint(x: shoulder.x - 0.4, y: body.y + 0.4), 1.7, 4.2, angle: -0.3))
        ctx.restoreGState()
        limb(ctx, shoulder, foot(shoulder, swing * sin(phase)), width: 2.8)
        limb(ctx, hip, foot(hip, -swing * sin(phase)), width: 2.8)

        let head = CGPoint(x: 16.9, y: 10.0 + bob * 0.6)
        fill(ctx, ellipsePath(CGPoint(x: head.x - 1.6, y: head.y + 2.6), 1.45, 1.45))   // ear
        fur(ctx, ellipsePath(CGPoint(x: head.x + 2.4, y: head.y - 0.9), 1.7, 1.25))     // snout
        fur(ctx, ellipsePath(head, 3.1, 2.9))
        ctx.setBlendMode(.clear)                                                         // re-open snout seam
        fill(ctx, ellipsePath(CGPoint(x: head.x + 2.4, y: head.y - 0.9), 1.1, 0.7))
        ctx.setBlendMode(.normal)
        fill(ctx, ellipsePath(CGPoint(x: head.x + 0.9, y: head.y + 0.3), 0.95, 1.25, angle: -0.6))
        punch(ctx, ellipsePath(CGPoint(x: head.x + 1.15, y: head.y + 0.6), 0.38, 0.38))
        fill(ctx, ellipsePath(CGPoint(x: head.x + 3.9, y: head.y - 0.5), 0.6, 0.5))     // nose
    }

    /// Front view, nodding off with eyes closed.
    private static func drawSleeping(_ ctx: CGContext) {
        drawSitting(ctx, bamboo: nil, bite: 0, eyes: .closed, cx: 9, tilt: 0.28)
        ctx.setLineWidth(0.9)
        for (x, y, s) in [(15.6, 10.8, 2.3), (18.6, 14.0, 1.7)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.move(to: CGPoint(x: x, y: y + s))
            ctx.addLine(to: CGPoint(x: x + s, y: y + s))
            ctx.addLine(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + s, y: y))
            ctx.strokePath()
        }
    }
}
