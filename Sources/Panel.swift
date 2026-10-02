import AppKit

/// Root of the drop-down: hosts the timer and settings panes and handles keys.
final class PanelRootView: NSView {
    private let model: TimerModel
    private let prefs: Preferences
    private weak var actions: PanelActions?

    let main: MainPane
    private var settings: SettingsPane?
    private(set) var showingSettings = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(model: TimerModel, prefs: Preferences, actions: PanelActions) {
        self.model = model
        self.prefs = prefs
        self.actions = actions
        let frame = NSRect(x: 0, y: 0, width: PanelLayout.width, height: PanelLayout.height)
        main = MainPane(frame: frame, model: model, prefs: prefs, actions: actions)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = PanelLayout.cornerRadius
        layer?.masksToBounds = true
        addSubview(main)
        main.onOpenSettings = { [weak self] in self?.setSettingsVisible(true) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(now: Date, animated: Bool) {
        main.update(now: now, animated: animated)
    }

    func setSettingsVisible(_ visible: Bool, animated: Bool = true) {
        guard visible != showingSettings else { return }
        showingSettings = visible
        let pane = settingsPane()
        guard animated else {
            for (view, shown) in [(main as NSView, !visible), (pane, visible)] {
                view.isHidden = !shown
                view.alphaValue = 1
                view.setFrameOrigin(.zero)
            }
            return
        }
        let incoming: NSView = visible ? pane : main
        let outgoing: NSView = visible ? main : pane
        let shift: CGFloat = visible ? 28 : -28

        incoming.isHidden = false
        incoming.alphaValue = 0
        incoming.setFrameOrigin(NSPoint(x: shift, y: 0))
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            incoming.animator().alphaValue = 1
            incoming.animator().setFrameOrigin(.zero)
            outgoing.animator().alphaValue = 0
            outgoing.animator().setFrameOrigin(NSPoint(x: -shift, y: 0))
        }, completionHandler: { [weak self] in
            guard let self, self.showingSettings == visible else { return }
            outgoing.isHidden = true
            outgoing.setFrameOrigin(.zero)
        })
        window?.makeFirstResponder(self)
    }

    private func settingsPane() -> SettingsPane {
        if let settings { return settings }
        let pane = SettingsPane(frame: bounds, prefs: prefs)
        pane.isHidden = true
        pane.onBack = { [weak self] in self?.setSettingsVisible(false) }
        pane.onChange = { [weak self] in self?.actions?.preferencesChanged() }
        pane.onPreviewSound = { [weak self] in self?.actions?.previewSound($0) }
        addSubview(pane)
        settings = pane
        return pane
    }

    // MARK: - Keyboard

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "q": actions?.quit()
        case "w": actions?.closePanel()
        case ",": setSettingsVisible(!showingSettings)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // esc
            showingSettings ? setSettingsVisible(false) : actions?.closePanel()
            return
        }
        guard !showingSettings else { return super.keyDown(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case " ": actions?.toggleTimer()
        case "r": actions?.resetTimer()
        case "s": actions?.skipPhase()
        case "1": actions?.selectPhase(.focus)
        case "2": actions?.selectPhase(.shortBreak)
        case "3": actions?.selectPhase(.longBreak)
        default: super.keyDown(with: event)
        }
    }
}

/// Borderless panel that can take keyboard focus without activating the app.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the drop-down window. The window is built once and reused: re-creating
/// it on every open churns window-server surfaces and fragments the heap,
/// which costs more memory over a day than simply keeping it around.
final class PanelController: NSObject, NSWindowDelegate {
    var onClosed: (() -> Void)?
    private(set) var isVisible = false

    private let panel: FloatingPanel
    private let root: PanelRootView
    private var clickMonitor: Any?

    init(model: TimerModel, prefs: Preferences, actions: PanelActions) {
        root = PanelRootView(model: model, prefs: prefs, actions: actions)
        panel = FloatingPanel(contentRect: root.frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.delegate = self
        panel.contentView = Self.makeBackground(hosting: root)
    }

    /// Frosted material rather than Liquid Glass: glass barely blurs what's
    /// behind it, which makes a text-heavy panel unreadable over busy windows.
    private static func makeBackground(hosting content: NSView) -> NSView {
        content.autoresizingMask = [.width, .height]
        let effect = NSVisualEffectView(frame: content.frame)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = NSImage(size: content.frame.size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: PanelLayout.cornerRadius, yRadius: PanelLayout.cornerRadius).fill()
            return true
        }
        effect.addSubview(content)
        return effect
    }

    func update(now: Date, animated: Bool) {
        root.update(now: now, animated: animated)
    }

    func showSettings() {
        root.setSettingsVisible(true)
    }

    func show(below button: NSStatusBarButton) {
        guard !isVisible, let buttonWindow = button.window else { return }
        isVisible = true
        root.setSettingsVisible(false, animated: false)
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = root.frame.size
        var x = anchor.minX
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        panel.setFrame(NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height),
                       display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(root)
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] _ in self?.close()
        }
    }

    func close() {
        guard isVisible else { return }
        isVisible = false
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
            self.onClosed?()
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}
