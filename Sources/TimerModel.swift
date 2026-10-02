import Foundation

enum Phase: Int, CaseIterable {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: return L("Focus")
        case .shortBreak: return L("Short Break")
        case .longBreak: return L("Long Break")
        }
    }
}

enum RunState: Equatable {
    case idle
    case running(end: Date)
    case paused(remaining: TimeInterval)
}

/// Pure timer state. Time is derived from an absolute end date, so nothing
/// needs to tick for the model to stay correct — the UI only polls it when
/// something on screen is about to change.
final class TimerModel {
    private let prefs: Preferences
    private let store = UserDefaults.standard

    private(set) var phase: Phase = .focus
    private(set) var state: RunState = .idle
    /// Focus sessions completed in the current cycle (resets after a long break).
    private(set) var cycle = 0
    private var sessionTotal: TimeInterval = 0

    private var statsDay = 0
    private var statsCount = 0
    private var statsSeconds: TimeInterval = 0

    var onChange: (() -> Void)?
    var onComplete: ((Phase) -> Void)?

    init(prefs: Preferences) {
        self.prefs = prefs
        restore()
    }

    // MARK: - Derived

    func duration(of phase: Phase) -> TimeInterval {
        let minutes: Int
        switch phase {
        case .focus: minutes = prefs.focusMinutes
        case .shortBreak: minutes = prefs.shortBreakMinutes
        case .longBreak: minutes = prefs.longBreakMinutes
        }
        return TimeInterval(max(1, minutes) * 60)
    }

    /// Length of the current session. Settings changes apply to the next session.
    var total: TimeInterval { state == .idle ? duration(of: phase) : sessionTotal }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var endDate: Date? {
        if case .running(let end) = state { return end }
        return nil
    }

    func remaining(at now: Date = Date()) -> TimeInterval {
        switch state {
        case .idle: return duration(of: phase)
        case .running(let end): return max(0, end.timeIntervalSince(now))
        case .paused(let remaining): return remaining
        }
    }

    /// Fraction of the session still remaining, 1 → 0.
    func progress(at now: Date = Date()) -> Double {
        let t = total
        return t > 0 ? min(1, max(0, remaining(at: now) / t)) : 0
    }

    /// The break that follows the current focus session.
    var upcomingBreak: Phase {
        cycle + 1 >= prefs.longBreakEvery ? .longBreak : .shortBreak
    }

    var todayCount: Int { statsDay == Self.dayStamp() ? statsCount : 0 }
    var todaySeconds: TimeInterval { statsDay == Self.dayStamp() ? statsSeconds : 0 }

    // MARK: - Actions

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        switch state {
        case .running:
            return
        case .idle:
            sessionTotal = duration(of: phase)
            state = .running(end: Date().addingTimeInterval(sessionTotal))
        case .paused(let remaining):
            state = .running(end: Date().addingTimeInterval(remaining))
        }
        commit()
    }

    func pause() {
        guard case .running(let end) = state else { return }
        state = .paused(remaining: max(0, end.timeIntervalSinceNow))
        commit()
    }

    func reset() {
        guard state != .idle else { return }
        state = .idle
        commit()
    }

    func select(_ newPhase: Phase) {
        guard newPhase != phase || state != .idle else { return }
        phase = newPhase
        if phase == .focus && cycle >= prefs.longBreakEvery { cycle = 0 }
        state = .idle
        commit()
    }

    func skip() {
        advance(completed: false)
    }

    func complete() {
        guard isRunning else { return }
        advance(completed: true)
    }

    func preferencesChanged() {
        onChange?()
    }

    private func advance(completed: Bool) {
        let finished = phase
        let wasRunning = isRunning
        if finished == .focus {
            if completed {
                recordFocus(sessionTotal)
                cycle += 1
            }
            phase = cycle >= prefs.longBreakEvery ? .longBreak : .shortBreak
        } else {
            if finished == .longBreak || cycle >= prefs.longBreakEvery { cycle = 0 }
            phase = .focus
        }
        state = .idle
        sessionTotal = duration(of: phase)

        if completed { onComplete?(finished) }

        let autoStart = phase == .focus ? prefs.autoStartFocus : prefs.autoStartBreaks
        if (completed || wasRunning) && autoStart {
            start()
        } else {
            commit()
        }
    }

    // MARK: - Stats

    private static func dayStamp(_ date: Date = Date()) -> Int {
        Int(Calendar.current.startOfDay(for: date).timeIntervalSinceReferenceDate)
    }

    private func recordFocus(_ seconds: TimeInterval) {
        let today = Self.dayStamp()
        if statsDay != today {
            statsDay = today
            statsCount = 0
            statsSeconds = 0
        }
        statsCount += 1
        statsSeconds += seconds
    }

    // MARK: - Persistence

    private enum Key {
        static let phase = "state.phase"
        static let kind = "state.kind"
        static let value = "state.value"
        static let total = "state.total"
        static let cycle = "state.cycle"
        static let statsDay = "stats.day"
        static let statsCount = "stats.count"
        static let statsSeconds = "stats.seconds"
    }

    private func commit() {
        save()
        onChange?()
    }

    private func save() {
        store.set(phase.rawValue, forKey: Key.phase)
        store.set(cycle, forKey: Key.cycle)
        store.set(sessionTotal, forKey: Key.total)
        switch state {
        case .idle:
            store.set(0, forKey: Key.kind)
        case .running(let end):
            store.set(1, forKey: Key.kind)
            store.set(end.timeIntervalSinceReferenceDate, forKey: Key.value)
        case .paused(let remaining):
            store.set(2, forKey: Key.kind)
            store.set(remaining, forKey: Key.value)
        }
        store.set(statsDay, forKey: Key.statsDay)
        store.set(statsCount, forKey: Key.statsCount)
        store.set(statsSeconds, forKey: Key.statsSeconds)
    }

    private func restore() {
        phase = Phase(rawValue: store.integer(forKey: Key.phase)) ?? .focus
        cycle = store.integer(forKey: Key.cycle)
        sessionTotal = store.double(forKey: Key.total)
        let value = store.double(forKey: Key.value)
        switch store.integer(forKey: Key.kind) {
        case 1:
            let end = Date(timeIntervalSinceReferenceDate: value)
            state = end > Date() ? .running(end: end) : .idle
        case 2:
            state = value > 0 ? .paused(remaining: value) : .idle
        default:
            state = .idle
        }
        if sessionTotal <= 0 { sessionTotal = duration(of: phase) }
        statsDay = store.integer(forKey: Key.statsDay)
        statsCount = store.integer(forKey: Key.statsCount)
        statsSeconds = store.double(forKey: Key.statsSeconds)
    }
}
