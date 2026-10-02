import AppKit

protocol PanelActions: AnyObject {
    func toggleTimer()
    func resetTimer()
    func skipPhase()
    func selectPhase(_ phase: Phase)
    func preferencesChanged()
    func previewSound(_ theme: SoundTheme)
    func closePanel()
    func quit()
}

enum PanelLayout {
    static let width: CGFloat = 300
    static let height: CGFloat = 436
    static let cornerRadius: CGFloat = 22
}

final class MainPane: NSView {
    var onOpenSettings: (() -> Void)?

    private let model: TimerModel
    private let prefs: Preferences
    private weak var actions: PanelActions?

    private let selector = PillSelector(items: Phase.allCases.map(\.title), font: Theme.font(12, .medium))
    private let ring = RingView()
    private let timeLabel = makeLabel(font: Theme.font(48, .light, rounded: true, monoDigits: true),
                                      alignment: .center)
    private let subLabel = makeLabel(font: Theme.font(11.5, .medium), color: .tertiaryLabelColor,
                                     alignment: .center)
    private let dots = DotsView()
    private let resetButton = CircleButton(symbol: "arrow.counterclockwise", pointSize: 14, weight: .semibold)
    private let playButton = PrimaryButton()
    private let skipButton = CircleButton(symbol: "forward.end.fill", pointSize: 13, weight: .semibold)
    private let separator = FillView()
    private let statsLabel = makeLabel(font: Theme.font(11.5), color: .secondaryLabelColor)
    private let settingsButton = CircleButton(symbol: "gearshape", pointSize: 13.5)
    private let quitButton = CircleButton(symbol: "power", pointSize: 13, weight: .semibold)

    private var renderedPhase: Phase?

    override var isFlipped: Bool { true }

    init(frame: NSRect, model: TimerModel, prefs: Preferences, actions: PanelActions) {
        self.model = model
        self.prefs = prefs
        self.actions = actions
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let w = bounds.width
        let ringSize: CGFloat = 192

        selector.frame = NSRect(x: (w - 252) / 2, y: 16, width: 252, height: 28)
        selector.onSelect = { [weak self] in self?.actions?.selectPhase(Phase(rawValue: $0) ?? .focus) }

        ring.frame = NSRect(x: (w - ringSize) / 2, y: 64, width: ringSize, height: ringSize)

        // Center the digits optically (cap height), not by the text box.
        let timeFont = timeLabel.font!
        let timeH = timeLabel.fittingSize.height
        let digitsCenter = ring.frame.midY - 5
        timeLabel.frame = NSRect(x: ring.frame.minX, y: (digitsCenter - (timeFont.ascender - timeFont.capHeight / 2)).rounded(),
                                 width: ringSize, height: timeH)
        let subH = subLabel.fittingSize.height
        subLabel.frame = NSRect(x: ring.frame.minX + 16, y: (digitsCenter + timeFont.capHeight / 2 + 10).rounded(),
                                width: ringSize - 32, height: subH)

        dots.frame = NSRect(x: 0, y: 274, width: w, height: 10)

        let playSize: CGFloat = 56, sideSize: CGFloat = 36, gap: CGFloat = 26
        let controlsY: CGFloat = 306
        playButton.frame = NSRect(x: (w - playSize) / 2, y: controlsY, width: playSize, height: playSize)
        resetButton.frame = NSRect(x: playButton.frame.minX - gap - sideSize, y: controlsY + (playSize - sideSize) / 2,
                                   width: sideSize, height: sideSize)
        skipButton.frame = NSRect(x: playButton.frame.maxX + gap, y: resetButton.frame.minY,
                                  width: sideSize, height: sideSize)
        playButton.onPress = { [weak self] in self?.actions?.toggleTimer() }
        resetButton.onPress = { [weak self] in self?.actions?.resetTimer() }
        skipButton.onPress = { [weak self] in self?.actions?.skipPhase() }
        resetButton.restingFill = 0.05
        skipButton.restingFill = 0.05
        resetButton.toolTip = L("Reset") + "  R"
        skipButton.toolTip = L("Skip") + "  S"

        separator.fill = Theme.ink(0.08)
        separator.frame = NSRect(x: 16, y: bounds.height - 46, width: w - 32, height: 0.5)

        let footerMid = bounds.height - 23
        let iconSize: CGFloat = 28
        quitButton.frame = NSRect(x: w - 12 - iconSize, y: footerMid - iconSize / 2, width: iconSize, height: iconSize)
        settingsButton.frame = quitButton.frame.offsetBy(dx: -iconSize - 2, dy: 0)
        settingsButton.onPress = { [weak self] in self?.onOpenSettings?() }
        quitButton.onPress = { [weak self] in self?.actions?.quit() }
        settingsButton.toolTip = L("Settings") + "  ⌘,"
        quitButton.toolTip = L("Quit Still") + "  ⌘Q"
        for button in [settingsButton, quitButton] { button.tint = .tertiaryLabelColor }

        let statsH = statsLabel.fittingSize.height
        statsLabel.frame = NSRect(x: 18, y: (footerMid - statsH / 2).rounded(),
                                  width: settingsButton.frame.minX - 24, height: statsH)

        for view in [selector, ring, timeLabel, subLabel, dots, resetButton, playButton, skipButton,
                     separator, statsLabel, settingsButton, quitButton] as [NSView] {
            addSubview(view)
        }
    }

    func update(now: Date, animated: Bool) {
        let phase = model.phase
        if phase != renderedPhase {
            let accent = Theme.accent(for: phase)
            let animate = animated && renderedPhase != nil
            selector.setSelected(phase.rawValue, animated: animate)
            ring.setColor(accent, animated: animate)
            playButton.color = accent
            renderedPhase = phase
        }

        let remaining = model.remaining(at: now)
        setText(timeLabel, Fmt.clock(remaining))
        ring.setProgress(model.progress(at: now), animated: animated)
        timeLabel.textColor = model.isPaused ? .secondaryLabelColor : .labelColor
        playButton.isPlaying = model.isRunning
        resetButton.isEnabled = model.state != .idle

        switch model.state {
        case .idle:
            setText(subLabel, L("Space to start"))
            subLabel.textColor = .tertiaryLabelColor
        case .running(let end):
            setText(subLabel, String(format: L("Ends at %@"), Fmt.time.string(from: end)))
            subLabel.textColor = .secondaryLabelColor
        case .paused:
            setText(subLabel, L("Paused"))
            subLabel.textColor = Theme.accent(for: phase)
        }

        dots.configure(total: prefs.longBreakEvery, done: model.cycle,
                       active: phase == .focus && model.state != .idle)
        renderStats()
    }

    private func renderStats() {
        let count = model.todayCount
        let detail = count == 0
            ? L("No sessions yet")
            : "\(Fmt.sessions(count)) · \(Fmt.duration(model.todaySeconds))"
        let text = NSMutableAttributedString(string: L("Today"), attributes: [
            .font: Theme.font(11.5, .semibold), .foregroundColor: NSColor.tertiaryLabelColor,
        ])
        text.append(NSAttributedString(string: "   " + detail, attributes: [
            .font: Theme.font(11.5), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        if statsLabel.attributedStringValue != text { statsLabel.attributedStringValue = text }
    }

    private func setText(_ label: NSTextField, _ text: String) {
        if label.stringValue != text { label.stringValue = text }
    }
}
