import AppKit

private let easeOut = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)

private func withoutAnimation(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

// MARK: - FillView

/// A view filled with a (dynamic) color, resolved against its appearance.
class FillView: NSView {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    var radius: CGFloat = 0 { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = cgColor(fill)
        layer?.cornerRadius = radius
    }
}

// MARK: - PressableView

/// Base for custom buttons: hover + press tracking with a springy scale.
class PressableView: NSView {
    var onPress: (() -> Void)?
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            alphaValue = isEnabled ? 1 : 0.3
            if !isEnabled { hovered = false; pressed = false }
        }
    }

    let content = CALayer()
    var pressScale: CGFloat = 0.9
    private(set) var hovered = false { didSet { if hovered != oldValue { stateDidChange() } } }
    private(set) var pressed = false {
        didSet {
            guard pressed != oldValue else { return }
            animatePress()
            stateDidChange()
        }
    }
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(content)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        withoutAnimation {
            content.bounds = bounds
            content.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        layoutContent()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { if isEnabled { hovered = true } }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside { onPress?() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        appearanceDidChange()
    }

    private func animatePress() {
        guard pressScale != 1 else { return }
        let target = pressed ? CATransform3DMakeScale(pressScale, pressScale, 1) : CATransform3DIdentity
        let animation: CABasicAnimation
        if pressed {
            animation = CABasicAnimation(keyPath: "transform")
            animation.duration = 0.09
            animation.timingFunction = easeOut
        } else {
            let spring = CASpringAnimation(keyPath: "transform")
            spring.damping = 14
            spring.stiffness = 320
            spring.mass = 1
            spring.duration = spring.settlingDuration
            animation = spring
        }
        animation.fromValue = content.presentation()?.transform ?? content.transform
        animation.toValue = target
        withoutAnimation { content.transform = target }
        content.add(animation, forKey: "press")
    }

    // Subclass hooks
    func layoutContent() {}
    func stateDidChange() {}
    func appearanceDidChange() {}
}

// MARK: - Symbol rendering

enum Symbol {
    static func image(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return base.withSymbolConfiguration(config)
    }
}

extension PressableView {
    /// Draws an SF Symbol into `layer`, pixel-aligned at the center of the view.
    func setSymbol(_ name: String, on layer: CALayer, pointSize: CGFloat, weight: NSFont.Weight,
                   color: NSColor, offset: CGPoint = .zero, fade: Bool = false) {
        let resolved = NSColor(cgColor: cgColor(color)) ?? color
        guard let image = Symbol.image(name, pointSize: pointSize, weight: weight, color: resolved) else { return }
        let scale = backingScale
        let size = image.size
        let origin = CGPoint(x: ((bounds.width - size.width) / 2 + offset.x) * scale,
                             y: ((bounds.height - size.height) / 2 + offset.y) * scale)
        CATransaction.begin()
        if fade {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.16
            layer.add(transition, forKey: "contents")
        }
        CATransaction.setDisableActions(true)
        layer.contents = image.layerContents(forContentsScale: scale)
        layer.contentsScale = scale
        layer.frame = CGRect(x: origin.x.rounded() / scale, y: origin.y.rounded() / scale,
                             width: size.width, height: size.height)
        CATransaction.commit()
    }
}

// MARK: - CircleButton

/// Quiet round icon button: background appears on hover.
final class CircleButton: PressableView {
    var symbol: String { didSet { if symbol != oldValue { renderIcon() } } }
    var tint: NSColor = .secondaryLabelColor { didSet { renderIcon() } }
    var hoverTint: NSColor = .labelColor
    var restingFill: CGFloat = 0 { didSet { renderBackground() } }

    private let pointSize: CGFloat
    private let weight: NSFont.Weight
    private let background = CALayer()
    private let icon = CALayer()

    init(symbol: String, pointSize: CGFloat, weight: NSFont.Weight = .medium) {
        self.symbol = symbol
        self.pointSize = pointSize
        self.weight = weight
        super.init(frame: .zero)
        content.addSublayer(background)
        content.addSublayer(icon)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutContent() {
        withoutAnimation {
            background.frame = bounds
            background.cornerRadius = bounds.height / 2
        }
        renderBackground()
        renderIcon()
    }

    override func stateDidChange() {
        renderBackground()
        renderIcon()
    }

    override func appearanceDidChange() {
        renderBackground()
        renderIcon()
    }

    private func renderBackground() {
        let alpha: CGFloat = pressed ? 0.14 : hovered ? 0.08 : restingFill
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        background.backgroundColor = cgColor(Theme.ink(alpha))
        CATransaction.commit()
    }

    private func renderIcon() {
        setSymbol(symbol, on: icon, pointSize: pointSize, weight: weight, color: hovered ? hoverTint : tint)
    }
}

// MARK: - PrimaryButton

/// The big play / pause disc.
final class PrimaryButton: PressableView {
    var color: NSColor = Theme.focus { didSet { renderColors() } }
    var isPlaying = false {
        didSet { if isPlaying != oldValue { renderIcon(fade: true) } }
    }

    private let disc = CALayer()
    private let sheen = CALayer()
    private let icon = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        content.addSublayer(disc)
        content.addSublayer(sheen)
        content.addSublayer(icon)
        disc.shadowOffset = CGSize(width: 0, height: -3)
        disc.shadowRadius = 10
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutContent() {
        withoutAnimation {
            for layer in [disc, sheen] {
                layer.frame = bounds
                layer.cornerRadius = bounds.height / 2
            }
            disc.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
        }
        renderColors()
        renderIcon()
    }

    override func stateDidChange() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        sheen.backgroundColor = pressed ? CGColor(gray: 0, alpha: 0.12)
            : hovered ? CGColor(gray: 1, alpha: 0.14) : CGColor(gray: 1, alpha: 0)
        CATransaction.commit()
    }

    override func appearanceDidChange() {
        renderColors()
        renderIcon()
    }

    private func renderColors() {
        let c = cgColor(color)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        disc.backgroundColor = c
        disc.shadowColor = c
        disc.shadowOpacity = isDarkAppearance ? 0.45 : 0.38
        CATransaction.commit()
    }

    private func renderIcon(fade: Bool = false) {
        // A play triangle looks off-center when geometrically centered; nudge it right.
        setSymbol(isPlaying ? "pause.fill" : "play.fill", on: icon, pointSize: 20, weight: .semibold,
                  color: .white, offset: CGPoint(x: isPlaying ? 0 : 1.5, y: 0), fade: fade)
    }
}

// MARK: - PillSelector

/// Segmented control with a sliding pill.
final class PillSelector: FillView {
    var onSelect: ((Int) -> Void)?
    private(set) var selected = 0

    private let pill = FillView()
    private var labels: [NSTextField] = []

    init(items: [String], font: NSFont) {
        super.init(frame: .zero)
        fill = Theme.ink(0.06)
        pill.fill = Theme.dynamic(light: .white, dark: NSColor(white: 1, alpha: 0.15))
        pill.layer?.shadowColor = .black
        pill.layer?.shadowOffset = CGSize(width: 0, height: -1)
        pill.layer?.shadowRadius = 2
        addSubview(pill)
        for item in items {
            let label = makeLabel(item, font: font, color: .secondaryLabelColor, alignment: .center)
            labels.append(label)
            addSubview(label)
        }
        applySelectionColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    private var segmentWidth: CGFloat { bounds.width / CGFloat(max(1, labels.count)) }

    private func pillFrame(for index: Int) -> NSRect {
        NSRect(x: CGFloat(index) * segmentWidth, y: 0, width: segmentWidth, height: bounds.height)
            .insetBy(dx: 2, dy: 2)
    }

    override func layout() {
        super.layout()
        radius = bounds.height / 2
        pill.radius = (bounds.height - 4) / 2
        pill.frame = pillFrame(for: selected)
        pill.layer?.shadowPath = CGPath(roundedRect: pill.bounds, cornerWidth: pill.radius,
                                        cornerHeight: pill.radius, transform: nil)
        for (i, label) in labels.enumerated() {
            let h = label.fittingSize.height
            label.frame = NSRect(x: CGFloat(i) * segmentWidth, y: (bounds.height - h) / 2,
                                 width: segmentWidth, height: h)
        }
    }

    override func updateLayer() {
        super.updateLayer()
        pill.layer?.shadowOpacity = isDarkAppearance ? 0 : 0.14
    }

    func setSelected(_ index: Int, animated: Bool) {
        guard index != selected, labels.indices.contains(index) else { return }
        selected = index
        applySelectionColors()
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = easeOut
                pill.animator().frame = pillFrame(for: index)
            }
        } else {
            pill.frame = pillFrame(for: index)
        }
    }

    private func applySelectionColors() {
        for (i, label) in labels.enumerated() {
            label.textColor = i == selected ? .labelColor : .secondaryLabelColor
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The segment labels are text fields, which swallow clicks; route every
    /// click inside the control to the control itself.
    override func hitTest(_ point: NSPoint) -> NSView? {
        !isHidden && frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let index = min(labels.count - 1, max(0, Int(x / segmentWidth)))
        if index != selected { onSelect?(index) }
    }
}

// MARK: - RingView

/// Progress ring. The arc starts at 12 o'clock and recedes counter-clockwise
/// as time runs out, like a mechanical kitchen timer.
final class RingView: NSView {
    var lineWidth: CGFloat = 6 { didSet { needsLayout = true } }
    private(set) var color: NSColor = Theme.focus
    private(set) var progress: Double = 1

    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for shape in [track, arc] {
            shape.fillColor = nil
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let radius = (min(bounds.width, bounds.height) - lineWidth) / 2
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                    startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        withoutAnimation {
            for shape in [track, arc] {
                shape.frame = bounds
                shape.path = path
                shape.lineWidth = lineWidth
            }
            arc.strokeEnd = CGFloat(progress)
        }
        renderColors(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderColors(animated: false)
    }

    func setProgress(_ value: Double, animated: Bool) {
        guard abs(value - progress) > 0.000_01 else { return }
        let from = arc.presentation()?.strokeEnd ?? CGFloat(progress)
        progress = value
        withoutAnimation { arc.strokeEnd = CGFloat(value) }
        if animated {
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = from
            animation.toValue = CGFloat(value)
            animation.duration = 0.6
            animation.timingFunction = easeOut
            arc.add(animation, forKey: "strokeEnd")
        }
    }

    func setColor(_ newColor: NSColor, animated: Bool) {
        color = newColor
        renderColors(animated: animated)
    }

    private func renderColors(animated: Bool) {
        CATransaction.begin()
        if animated { CATransaction.setAnimationDuration(0.45) } else { CATransaction.setDisableActions(true) }
        arc.strokeColor = cgColor(color)
        track.strokeColor = cgColor(Theme.ink(0.07))
        CATransaction.commit()
    }
}

// MARK: - DotsView

/// Focus sessions in the current cycle: filled = done, ring = in progress.
final class DotsView: NSView {
    private var total = 4
    private var done = 0
    private var active = false

    func configure(total: Int, done: Int, active: Bool) {
        let done = min(done, total)
        guard total != self.total || done != self.done || active != self.active else { return }
        self.total = total
        self.done = done
        self.active = active
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let d: CGFloat = 6, gap: CGFloat = 8
        let width = CGFloat(total) * d + CGFloat(max(0, total - 1)) * gap
        var x = ((bounds.width - width) / 2).rounded()
        let y = ((bounds.height - d) / 2).rounded()
        for i in 0..<total {
            let rect = NSRect(x: x, y: y, width: d, height: d)
            if i < done {
                Theme.focus.setFill()
                NSBezierPath(ovalIn: rect).fill()
            } else if i == done && active {
                Theme.focus.setStroke()
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.5
                ring.stroke()
            } else {
                Theme.ink(0.14).setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
            x += d + gap
        }
    }
}

// MARK: - CardView

/// Inset-grouped settings card with hairline row separators. Built from plain
/// colored layers: no draw(_:) backing store, nothing to re-render while the
/// settings pane slides in.
final class CardView: FillView {
    static let rowHeight: CGFloat = 32

    private var separators: [FillView] = []

    override var isFlipped: Bool { true }

    init(frame: NSRect, rows: Int) {
        super.init(frame: frame)
        fill = Theme.ink(0.045)
        radius = 12
        for i in 1..<max(1, rows) {
            let line = FillView(frame: NSRect(x: 12, y: CGFloat(i) * Self.rowHeight, width: frame.width - 24, height: 1))
            line.fill = Theme.ink(0.07)
            separators.append(line)
            addSubview(line)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        for line in separators { line.frame.size.height = 1 / backingScale }
    }
}

// MARK: - ValueStepper

/// "−  25 min  +"
final class ValueStepper: NSView {
    var onChange: ((Int) -> Void)?

    private(set) var value: Int
    private let range: ClosedRange<Int>
    private let step: Int
    private let format: (Int) -> String
    private let minus = CircleButton(symbol: "minus", pointSize: 9, weight: .bold)
    private let plus = CircleButton(symbol: "plus", pointSize: 9, weight: .bold)
    private let label = makeLabel(font: Theme.font(12.5, .medium, rounded: true, monoDigits: true),
                                  alignment: .center)

    static let size = NSSize(width: 118, height: 22)

    init(value: Int, range: ClosedRange<Int>, step: Int, format: @escaping (Int) -> String) {
        self.value = value
        self.range = range
        self.step = step
        self.format = format
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        for button in [minus, plus] {
            button.restingFill = 0.06
            addSubview(button)
        }
        addSubview(label)
        minus.frame = NSRect(x: 0, y: 0, width: 22, height: 22)
        plus.frame = NSRect(x: Self.size.width - 22, y: 0, width: 22, height: 22)
        let h = label.fittingSize.height
        label.frame = NSRect(x: 22, y: (22 - h) / 2, width: Self.size.width - 44, height: h)
        minus.onPress = { [weak self] in self?.nudge(-1) }
        plus.onPress = { [weak self] in self?.nudge(1) }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func nudge(_ direction: Int) {
        let next = min(range.upperBound, max(range.lowerBound, value + direction * step))
        guard next != value else { return }
        value = next
        refresh()
        onChange?(value)
    }

    private func refresh() {
        label.stringValue = format(value)
        minus.isEnabled = value > range.lowerBound
        plus.isEnabled = value < range.upperBound
    }
}

// MARK: - Toggle

/// Hand-drawn switch in the app's accent color, matching the rest of the panel.
final class Toggle: PressableView {
    static let size = NSSize(width: 32, height: 18)

    var onChange: ((Bool) -> Void)?
    private(set) var isOn: Bool

    private let track = CALayer()
    private let knob = CALayer()

    init(isOn: Bool) {
        self.isOn = isOn
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        pressScale = 1
        content.addSublayer(track)
        content.addSublayer(knob)
        knob.backgroundColor = .white
        knob.shadowColor = .black
        knob.shadowOpacity = 0.22
        knob.shadowRadius = 1.5
        knob.shadowOffset = CGSize(width: 0, height: -0.5)
        onPress = { [weak self] in
            guard let self else { return }
            self.setOn(!self.isOn, animated: true)
            self.onChange?(self.isOn)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setOn(_ on: Bool, animated: Bool) {
        guard on != isOn else { return }
        isOn = on
        render(animated: animated)
    }

    override func layoutContent() { render(animated: false) }
    override func stateDidChange() { render(animated: true) }
    override func appearanceDidChange() { render(animated: false) }

    override func accessibilityValue() -> Any? { isOn ? 1 : 0 }

    private func render(animated: Bool) {
        let d = bounds.height - 4
        let w = pressed ? d + 4 : d // the knob stretches while held
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.22)
            CATransaction.setAnimationTimingFunction(easeOut)
        } else {
            CATransaction.setDisableActions(true)
        }
        track.frame = bounds
        track.cornerRadius = bounds.height / 2
        track.backgroundColor = cgColor(isOn ? Theme.focus : Theme.ink(0.14))
        knob.frame = CGRect(x: isOn ? bounds.width - 2 - w : 2, y: 2, width: w, height: d)
        knob.cornerRadius = d / 2
        CATransaction.commit()
    }
}
