import Foundation
import ServiceManagement

enum MenuBarStyle: Int {
    case icon, minutes, seconds
}

enum MenuBarIcon: Int, CaseIterable {
    case ring, panda

    var title: String { self == .ring ? L("Ring") : L("Panda") }
}

enum SoundTheme: Int, CaseIterable {
    case off, chime, bowl, wood

    var title: String {
        switch self {
        case .off: return L("Off")
        case .chime: return L("Chime")
        case .bowl: return L("Bowl")
        case .wood: return L("Wood")
        }
    }

    /// Bundled sound played when `phase` ends: a falling cue into a break,
    /// a rising one back into focus.
    func file(after phase: Phase) -> String? {
        let name: String
        switch self {
        case .off: return nil
        case .chime: name = "Chime"
        case .bowl: name = "Bowl"
        case .wood: name = "Wood"
        }
        return name + (phase == .focus ? "-Rest" : "-Focus")
    }
}

final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let focus = "focusMinutes"
        static let shortBreak = "shortBreakMinutes"
        static let longBreak = "longBreakMinutes"
        static let longBreakEvery = "longBreakEvery"
        static let autoStartBreaks = "autoStartBreaks"
        static let autoStartFocus = "autoStartFocus"
        static let menuBarStyle = "menuBarStyle"
        static let menuBarIcon = "menuBarIcon"
        static let soundTheme = "soundTheme"
        static let legacySound = "sound"
    }

    private init() {
        defaults.register(defaults: [
            Key.focus: 25,
            Key.shortBreak: 5,
            Key.longBreak: 15,
            Key.longBreakEvery: 4,
            Key.autoStartBreaks: true,
            Key.autoStartFocus: false,
            Key.menuBarStyle: MenuBarStyle.seconds.rawValue,
            Key.menuBarIcon: MenuBarIcon.panda.rawValue,
            Key.soundTheme: SoundTheme.chime.rawValue,
        ])
        // 1.0 stored a plain on/off switch.
        if defaults.object(forKey: Key.legacySound) != nil {
            if !defaults.bool(forKey: Key.legacySound) { soundTheme = .off }
            defaults.removeObject(forKey: Key.legacySound)
        }
    }

    var focusMinutes: Int {
        get { defaults.integer(forKey: Key.focus) }
        set { defaults.set(newValue, forKey: Key.focus) }
    }

    var shortBreakMinutes: Int {
        get { defaults.integer(forKey: Key.shortBreak) }
        set { defaults.set(newValue, forKey: Key.shortBreak) }
    }

    var longBreakMinutes: Int {
        get { defaults.integer(forKey: Key.longBreak) }
        set { defaults.set(newValue, forKey: Key.longBreak) }
    }

    var longBreakEvery: Int {
        get { max(1, defaults.integer(forKey: Key.longBreakEvery)) }
        set { defaults.set(newValue, forKey: Key.longBreakEvery) }
    }

    var autoStartBreaks: Bool {
        get { defaults.bool(forKey: Key.autoStartBreaks) }
        set { defaults.set(newValue, forKey: Key.autoStartBreaks) }
    }

    var autoStartFocus: Bool {
        get { defaults.bool(forKey: Key.autoStartFocus) }
        set { defaults.set(newValue, forKey: Key.autoStartFocus) }
    }

    var menuBarStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: defaults.integer(forKey: Key.menuBarStyle)) ?? .seconds }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarStyle) }
    }

    var menuBarIcon: MenuBarIcon {
        get { MenuBarIcon(rawValue: defaults.integer(forKey: Key.menuBarIcon)) ?? .panda }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarIcon) }
    }

    var soundTheme: SoundTheme {
        get { SoundTheme(rawValue: defaults.integer(forKey: Key.soundTheme)) ?? .chime }
        set { defaults.set(newValue.rawValue, forKey: Key.soundTheme) }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Still: launch at login change failed: \(error.localizedDescription)")
            }
        }
    }
}
