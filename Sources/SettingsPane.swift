import AppKit

final class SettingsPane: NSView {
    var onBack: (() -> Void)?
    var onChange: (() -> Void)?
    var onPreviewSound: ((SoundTheme) -> Void)?

    private let prefs: Preferences

    override var isFlipped: Bool { true }

    init(frame: NSRect, prefs: Preferences) {
        self.prefs = prefs
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let back = CircleButton(symbol: "chevron.left", pointSize: 12, weight: .semibold)
        back.frame = NSRect(x: 10, y: 12, width: 28, height: 28)
        back.toolTip = L("Back") + "  esc"
        back.onPress = { [weak self] in self?.onBack?() }
        addSubview(back)

        let title = makeLabel(L("Settings"), font: Theme.font(13, .semibold))
        title.sizeToFit()
        title.setFrameOrigin(NSPoint(x: 40, y: (back.frame.midY - title.frame.height / 2).rounded()))
        addSubview(title)

        let minutes: (Int) -> String = { String(format: L("%d min"), $0) }
        let sessions: (Int) -> String = { Fmt.sessions($0) }

        var y = sectionHeader(L("Timer"), y: 54)
        let timer = card(rows: 4, y: y)
        stepperRow(timer, 0, L("Focus"), prefs.focusMinutes, 5...120, 5, minutes) { $0.focusMinutes = $1 }
        stepperRow(timer, 1, L("Short Break"), prefs.shortBreakMinutes, 1...30, 1, minutes) { $0.shortBreakMinutes = $1 }
        stepperRow(timer, 2, L("Long Break"), prefs.longBreakMinutes, 5...60, 5, minutes) { $0.longBreakMinutes = $1 }
        stepperRow(timer, 3, L("Long break every"), prefs.longBreakEvery, 2...8, 1, sessions) { $0.longBreakEvery = $1 }

        y = sectionHeader(L("General"), y: timer.frame.maxY + 14)
        let general = card(rows: 6, y: y)

        let icon = PillSelector(items: MenuBarIcon.allCases.map(\.title), font: Theme.font(11, .medium))
        icon.frame.size = NSSize(width: 124, height: 22)
        icon.setSelected(prefs.menuBarIcon.rawValue, animated: false)
        icon.onSelect = { [weak self, weak icon] index in
            guard let self, let icon else { return }
            icon.setSelected(index, animated: true)
            self.prefs.menuBarIcon = MenuBarIcon(rawValue: index) ?? .panda
            self.onChange?()
        }
        row(general, 0, L("Menu bar icon"), control: icon)

        let style = PillSelector(items: [L("Off"), Fmt.minutes(1500), Fmt.clock(1500)],
                                 font: Theme.font(11, .medium, monoDigits: true))
        style.frame.size = NSSize(width: 138, height: 22)
        style.setSelected(prefs.menuBarStyle.rawValue, animated: false)
        style.onSelect = { [weak self, weak style] index in
            guard let self, let style else { return }
            style.setSelected(index, animated: true)
            self.prefs.menuBarStyle = MenuBarStyle(rawValue: index) ?? .seconds
            self.onChange?()
        }
        row(general, 1, L("Menu bar time"), control: style)

        toggleRow(general, 2, L("Auto-start breaks"), prefs.autoStartBreaks) { $0.autoStartBreaks = $1 }
        toggleRow(general, 3, L("Auto-start focus"), prefs.autoStartFocus) { $0.autoStartFocus = $1 }

        let sound = PillSelector(items: SoundTheme.allCases.map(\.title), font: Theme.font(11, .medium))
        sound.frame.size = NSSize(width: 188, height: 22)
        sound.setSelected(prefs.soundTheme.rawValue, animated: false)
        sound.onSelect = { [weak self, weak sound] index in
            guard let self, let sound, let theme = SoundTheme(rawValue: index) else { return }
            sound.setSelected(index, animated: true)
            self.prefs.soundTheme = theme
            self.onChange?()
            self.onPreviewSound?(theme)
        }
        row(general, 4, L("Sound"), control: sound)

        let login = Toggle(isOn: prefs.launchAtLogin)
        login.onChange = { [weak self, weak login] on in
            guard let self else { return }
            self.prefs.launchAtLogin = on
            login?.setOn(self.prefs.launchAtLogin, animated: true)
        }
        row(general, 5, L("Launch at login"), control: login)
    }

    // MARK: - Builders

    private func sectionHeader(_ text: String, y: CGFloat) -> CGFloat {
        let label = makeLabel(font: Theme.font(10.5, .semibold), color: .tertiaryLabelColor)
        label.attributedStringValue = NSAttributedString(string: text.uppercased(), attributes: [
            .font: Theme.font(10.5, .semibold), .foregroundColor: NSColor.tertiaryLabelColor, .kern: 0.8,
        ])
        label.sizeToFit()
        label.setFrameOrigin(NSPoint(x: 24, y: y))
        addSubview(label)
        return label.frame.maxY + 5
    }

    private func card(rows: Int, y: CGFloat) -> CardView {
        let card = CardView(frame: NSRect(x: 12, y: y, width: bounds.width - 24,
                                          height: CGFloat(rows) * CardView.rowHeight), rows: rows)
        addSubview(card)
        return card
    }

    private func row(_ card: CardView, _ index: Int, _ title: String, control: NSView) {
        let rowY = CGFloat(index) * CardView.rowHeight
        let label = makeLabel(title, font: Theme.font(12.5))
        label.sizeToFit()
        label.setFrameOrigin(NSPoint(x: 12, y: (rowY + (CardView.rowHeight - label.frame.height) / 2).rounded()))
        card.addSubview(label)

        let size = control.frame.size
        control.setFrameOrigin(NSPoint(x: card.bounds.width - 10 - size.width,
                                       y: (rowY + (CardView.rowHeight - size.height) / 2).rounded()))
        card.addSubview(control)
    }

    private func stepperRow(_ card: CardView, _ index: Int, _ title: String, _ value: Int,
                            _ range: ClosedRange<Int>, _ step: Int, _ format: @escaping (Int) -> String,
                            apply: @escaping (Preferences, Int) -> Void) {
        let stepper = ValueStepper(value: value, range: range, step: step, format: format)
        stepper.onChange = { [weak self] value in
            guard let self else { return }
            apply(self.prefs, value)
            self.onChange?()
        }
        row(card, index, title, control: stepper)
    }

    private func toggleRow(_ card: CardView, _ index: Int, _ title: String, _ isOn: Bool,
                           apply: @escaping (Preferences, Bool) -> Void) {
        let toggle = Toggle(isOn: isOn)
        toggle.onChange = { [weak self] on in
            guard let self else { return }
            apply(self.prefs, on)
            self.onChange?()
        }
        row(card, index, title, control: toggle)
    }
}
