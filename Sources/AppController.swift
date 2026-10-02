import AppKit

final class AppController: NSObject, PanelActions {
    private let prefs = Preferences.shared
    private let model: TimerModel
    private let statusBar = StatusBarController()
    private let notifier = Notifier()
    private var panel: PanelController?
    private var panelVisible: Bool { panel?.isVisible == true }
    private var panelClosedAt = Date.distantPast

    /// One-shot timer, re-armed for the next moment something visible changes.
    private var timer: DispatchSourceTimer?
    private var screensAsleep = false
    private var scheduled: (id: String, end: Date)?

    override init() {
        model = TimerModel(prefs: prefs)
        super.init()
        statusBar.onPrimaryClick = { [weak self] in self?.togglePanel() }
        statusBar.onSecondaryClick = { [weak self] in self?.showMenu() }
        model.onChange = { [weak self] in self?.modelDidChange() }
        model.onComplete = { [weak self] in self?.sessionDidComplete($0) }
        notifier.onActivate = { [weak self] in self?.openPanel() }
        observeSystem()
        notifier.requestAuthorization()
        modelDidChange()
    }

    // MARK: - Rendering & scheduling

    private func modelDidChange() {
        syncNotification()
        render(animated: true)
        reschedule()
    }

    private func render(animated: Bool) {
        let now = Date()
        statusBar.render(model: model, style: prefs.menuBarStyle, icon: prefs.menuBarIcon, now: now)
        if panelVisible { panel?.update(now: now, animated: animated) }
    }

    /// Computes the next instant at which anything on screen would change and
    /// sleeps until then. Idle or paused → no timer at all.
    private func reschedule() {
        guard model.isRunning else {
            timer?.cancel()
            timer = nil
            return
        }
        let r = model.remaining()
        var delay = r
        var leeway = 1.0
        if !screensAsleep {
            let style = prefs.menuBarStyle
            if panelVisible || style == .seconds {
                delay = min(delay, r - (r.rounded(.up) - 1))
                leeway = 0.03
            } else if style == .minutes {
                delay = min(delay, r - ((r / 60).rounded(.up) - 1) * 60)
                leeway = 0.25
            }
            let step = model.total / statusBar.progressSteps(for: prefs.menuBarIcon)
            delay = min(delay, r - ((r / step).rounded(.up) - 1) * step)
        }
        delay = max(0, delay) + 0.015

        if timer == nil {
            let source = DispatchSource.makeTimerSource(queue: .main)
            source.setEventHandler { [weak self] in self?.tick() }
            source.resume()
            timer = source
        }
        timer?.schedule(wallDeadline: .now() + delay, repeating: .never,
                        leeway: .milliseconds(Int(leeway * 1000)))
    }

    private func tick() {
        if model.isRunning && model.remaining() <= 0 {
            model.complete()
        } else {
            render(animated: false)
            reschedule()
        }
    }

    // MARK: - Notifications

    private func syncNotification() {
        if let end = model.endDate {
            guard scheduled?.end != end else { return }
            if let scheduled { notifier.cancel(id: scheduled.id) }
            let id = "still.\(Int(end.timeIntervalSince1970))"
            let finishing = model.phase
            let title: String, body: String
            if finishing == .focus {
                let next = model.upcomingBreak
                let minutes = Int(model.duration(of: next) / 60)
                title = L("Focus complete")
                body = String(format: next == .longBreak ? L("Great work. Enjoy a %d-minute long break.")
                                                         : L("Nice work. Take a %d-minute break."), minutes)
            } else {
                title = L("Break's over")
                body = L("Ready for the next focus session?")
            }
            notifier.schedule(id: id, at: end, title: title, body: body,
                              soundName: prefs.soundTheme.file(after: finishing))
            scheduled = (id, end)
        } else if let scheduled {
            notifier.cancel(id: scheduled.id)
            self.scheduled = nil
        }
    }

    private func sessionDidComplete(_ phase: Phase) {
        // The system delivers the scheduled notification (with sound); just forget it.
        scheduled = nil
        if !notifier.isAuthorized, let file = prefs.soundTheme.file(after: phase) { notifier.play(file) }
    }

    // MARK: - Panel

    private func togglePanel() {
        if panelVisible {
            panel?.close()
        } else if Date().timeIntervalSince(panelClosedAt) > 0.25 {
            openPanel()
        }
    }

    private func openPanel(settings: Bool = false) {
        guard let button = statusBar.button else { return }
        if panel == nil {
            let controller = PanelController(model: model, prefs: prefs, actions: self)
            controller.onClosed = { [weak self] in
                guard let self else { return }
                self.panelClosedAt = Date()
                self.statusBar.setHighlighted(false)
                self.reschedule()
            }
            panel = controller
        }
        guard let panel else { return }
        if !panel.isVisible {
            panel.update(now: Date(), animated: false)
            panel.show(below: button)
            statusBar.setHighlighted(true)
            reschedule()
        }
        if settings { panel.showSettings() }
    }

    func closePanel() {
        panel?.close()
    }

    // MARK: - PanelActions

    func toggleTimer() { model.toggle() }
    func resetTimer() { model.reset() }
    func skipPhase() { model.skip() }
    func selectPhase(_ phase: Phase) { model.select(phase) }
    func preferencesChanged() { model.preferencesChanged() }

    func previewSound(_ theme: SoundTheme) {
        if let file = theme.file(after: .focus) { notifier.play(file) }
    }
    func quit() { NSApp.terminate(nil) }

    // MARK: - Menu (right-click)

    private func showMenu() {
        panel?.close()
        let menu = NSMenu()
        let primary: String
        switch model.state {
        case .running: primary = L("Pause")
        case .paused: primary = L("Resume")
        case .idle: primary = String(format: L("Start %@"), model.phase.title)
        }
        menu.addItem(item(primary, #selector(menuToggle)))
        let reset = item(L("Reset"), #selector(menuReset))
        reset.isEnabled = model.state != .idle
        menu.addItem(reset)
        menu.addItem(item(L("Skip"), #selector(menuSkip)))
        menu.addItem(.separator())
        menu.addItem(item(L("Settings…"), #selector(menuSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(L("Quit Still"), #selector(menuQuit), key: "q"))
        menu.autoenablesItems = false
        statusBar.popUp(menu)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func menuToggle() { model.toggle() }
    @objc private func menuReset() { model.reset() }
    @objc private func menuSkip() { model.skip() }
    @objc private func menuSettings() { DispatchQueue.main.async { self.openPanel(settings: true) } }
    @objc private func menuQuit() { quit() }

    // MARK: - System

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clockChanged), name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminate),
                                               name: NSApplication.willTerminateNotification, object: nil)
    }

    /// Display off → stop redrawing; only wake for the end of the session.
    @objc private func screensDidSleep() {
        screensAsleep = true
        statusBar.animationsSuspended = true
        reschedule()
    }

    @objc private func screensDidWake() {
        screensAsleep = false
        statusBar.animationsSuspended = false
        tick()
    }

    @objc private func systemDidWake() { tick() }
    @objc private func clockChanged() { tick() }

    @objc private func willTerminate() {
        if let scheduled { notifier.cancel(id: scheduled.id) }
    }
}
