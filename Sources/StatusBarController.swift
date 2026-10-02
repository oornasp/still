import AppKit

/// The menu bar item: a ring or the panda, plus optional countdown text.
/// Ring icons are quantized into steps and only redrawn when the step changes.
/// The panda is a layer masked by its frames and flipped through them by a
/// Core Animation keyframe loop, so the render server animates it and this
/// process never wakes up per frame (swapping NSStatusItem images costs ~4% CPU
/// at 10 fps). The loop is removed whenever the menu bar can't be seen.
final class StatusBarController: NSObject {
    static let ringSteps: Double = 48

    var onPrimaryClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    /// Display off → hold the current frame.
    var animationsSuspended = false { didSet { if animationsSuspended != oldValue { updateAnimation() } } }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var iconKey = -1
    private var title: String?

    private var pandaPose: PandaPose?
    private var frames: [PandaFrame] = []
    private let pandaLayer = CALayer()
    private let pandaMask = CALayer()
    private lazy var placeholder = NSImage(size: Panda.size)
    private var appearanceObservation: NSKeyValueObservation?
    private lazy var font: NSFont = {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
    }()

    var button: NSStatusBarButton? { item.button }

    override init() {
        super.init()
        item.autosaveName = "StillTimer"
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.imagePosition = .imageOnly
        button.imageHugsTitle = true
        button.wantsLayer = true
        pandaMask.contentsGravity = .resize
        pandaLayer.mask = pandaMask
        pandaLayer.isHidden = true
        button.layer?.addSublayer(pandaLayer)
        button.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(layoutPanda),
                                               name: NSView.frameDidChangeNotification, object: button)
        if let window = button.window {
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
            self?.updatePandaColor()
        }
    }

    /// Progress resolution of the current icon, so the app can wake exactly
    /// when the next visible step is due.
    func progressSteps(for icon: MenuBarIcon) -> Double {
        icon == .panda ? Double(Panda.bambooSteps) : Self.ringSteps
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            onSecondaryClick?()
        } else {
            onPrimaryClick?()
        }
    }

    func setHighlighted(_ highlighted: Bool) {
        button?.highlight(highlighted)
    }

    func popUp(_ menu: NSMenu) {
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    func render(model: TimerModel, style: MenuBarStyle, icon: MenuBarIcon, now: Date) {
        guard let button = item.button else { return }

        if icon == .panda {
            let pose: PandaPose
            switch model.state {
            case .idle: pose = .sleeping
            case .paused: pose = .waiting
            case .running where model.phase == .focus:
                let steps = Double(Panda.bambooSteps)
                pose = .eating(bamboo: max(1, Int((model.progress(at: now) * steps).rounded(.up))))
            case .running: pose = .trotting
            }
            showPanda(pose)
        } else {
            showPanda(nil)
            let iconStyle: IconStyle
            switch model.state {
            case .idle: iconStyle = .idle
            case .running: iconStyle = model.phase == .focus ? .focus : .rest
            case .paused: iconStyle = .paused
            }
            let step = iconStyle == .idle ? Int(Self.ringSteps) : Int((model.progress(at: now) * Self.ringSteps).rounded(.up))
            let key = iconStyle.rawValue * 1000 + step
            if key != iconKey {
                iconKey = key
                button.image = Self.icon(iconStyle, fraction: Double(step) / Self.ringSteps)
            }
        }

        let remaining = model.remaining(at: now)
        let text: String
        switch style {
        case .icon: text = ""
        case .minutes: text = Fmt.minutes(remaining)
        case .seconds: text = Fmt.clock(remaining)
        }
        if text != title {
            title = text
            if text.isEmpty {
                button.attributedTitle = NSAttributedString()
                button.imagePosition = .imageOnly
            } else {
                button.attributedTitle = NSAttributedString(string: text, attributes: [.font: font])
                button.imagePosition = .imageLeading
            }
            let phase = model.phase.title
            button.setAccessibilityLabel(text.isEmpty ? "Still, \(phase)" : "Still, \(phase), \(text)")
            layoutPanda()
        }
    }

    // MARK: - Panda animation

    private func showPanda(_ pose: PandaPose?) {
        guard pose != pandaPose else { return }
        pandaPose = pose
        iconKey = -1
        guard let pose else {
            frames = []
            pandaMask.removeAllAnimations()
            pandaLayer.isHidden = true
            return
        }
        frames = Panda.sequence(pose)
        if item.button?.image !== placeholder { item.button?.image = placeholder }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pandaLayer.isHidden = false
        pandaMask.contents = frames[0].cgImage
        CATransaction.commit()
        layoutPanda()
        updatePandaColor()
        updateAnimation()
    }

    private var isOnScreen: Bool {
        item.button?.window?.occlusionState.contains(.visible) ?? true
    }

    private func updateAnimation() {
        pandaMask.removeAnimation(forKey: "frames")
        guard frames.count > 1, !pandaLayer.isHidden, !animationsSuspended, isOnScreen else { return }
        let total = frames.reduce(0) { $0 + $1.duration }
        var elapsed = 0.0
        var keyTimes: [NSNumber] = []
        for frame in frames {
            keyTimes.append(NSNumber(value: elapsed / total))
            elapsed += frame.duration
        }
        keyTimes.append(1)
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames.map { $0.cgImage as Any }
        animation.keyTimes = keyTimes
        animation.calculationMode = .discrete
        animation.duration = total
        animation.repeatCount = .infinity
        pandaMask.add(animation, forKey: "frames")
    }

    @objc private func layoutPanda() {
        guard let button = item.button, let cell = button.cell, !pandaLayer.isHidden else { return }
        let rect = cell.imageRect(forBounds: button.bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pandaLayer.frame = rect
        pandaMask.frame = pandaLayer.bounds
        CATransaction.commit()
    }

    /// Template images follow the menu bar's appearance; so does the panda.
    private func updatePandaColor() {
        guard let button = item.button else { return }
        var color = CGColor.black
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.withAlphaComponent(1).cgColor
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pandaLayer.backgroundColor = color
        CATransaction.commit()
    }

    @objc private func occlusionChanged() {
        updateAnimation()
    }

    // MARK: - Ring icon

    enum IconStyle: Int {
        case idle, focus, rest, paused
    }

    /// 16pt template glyph. Track at low alpha, remaining time as a full-alpha arc.
    static func icon(_ style: IconStyle, fraction: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let lineWidth: CGFloat = 1.6
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.4

            let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2))
            track.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(style == .idle ? 1 : 0.28).setStroke()
            track.stroke()

            NSColor.black.set()
            switch style {
            case .idle:
                NSBezierPath(ovalIn: NSRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)).fill()
            case .focus, .paused:
                if fraction > 0 {
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                                  endAngle: 90 - 360 * fraction, clockwise: true)
                    arc.lineWidth = lineWidth
                    arc.lineCapStyle = .round
                    arc.stroke()
                }
                if style == .paused {
                    NSBezierPath(roundedRect: NSRect(x: center.x - 2.5, y: center.y - 2.5, width: 1.7, height: 5),
                                 xRadius: 0.6, yRadius: 0.6).fill()
                    NSBezierPath(roundedRect: NSRect(x: center.x + 0.8, y: center.y - 2.5, width: 1.7, height: 5),
                                 xRadius: 0.6, yRadius: 0.6).fill()
                }
            case .rest:
                // Breaks drain as a soft pie instead of a ring.
                if fraction > 0 {
                    let pie = NSBezierPath()
                    pie.move(to: center)
                    pie.appendArc(withCenter: center, radius: radius - 2, startAngle: 90,
                                  endAngle: 90 - 360 * fraction, clockwise: true)
                    pie.close()
                    pie.fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
