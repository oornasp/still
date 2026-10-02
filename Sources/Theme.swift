import AppKit
import CoreText

/// Localized string lookup. Keys are the English strings themselves.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

enum Theme {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255,
                green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    /// Neutral tint: black on light surfaces, white on dark ones.
    static func ink(_ alpha: CGFloat) -> NSColor {
        dynamic(light: NSColor(white: 0, alpha: alpha), dark: NSColor(white: 1, alpha: alpha))
    }

    static let focus = dynamic(light: rgb(0xEE5A3B), dark: rgb(0xFF7A5C))
    static let shortBreak = dynamic(light: rgb(0x2E9C78), dark: rgb(0x5CCBA2))
    static let longBreak = dynamic(light: rgb(0x5468E6), dark: rgb(0x8E99FF))

    static func accent(for phase: Phase) -> NSColor {
        switch phase {
        case .focus: return focus
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular,
                     rounded: Bool = false, monoDigits: Bool = false) -> NSFont {
        var descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        if rounded, let r = descriptor.withDesign(.rounded) { descriptor = r }
        if monoDigits {
            descriptor = descriptor.addingAttributes([
                .featureSettings: [[
                    NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
                ]],
            ])
        }
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

enum Fmt {
    /// "24:59" — remaining time rounded up, so a fresh session reads "25:00".
    static func clock(_ remaining: TimeInterval) -> String {
        let s = max(0, Int(remaining.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "25m" — whole minutes, rounded up.
    static func minutes(_ remaining: TimeInterval) -> String {
        String(format: L("%dm"), max(0, Int((remaining / 60).rounded(.up))))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return String(format: L("%d min"), m) }
        if m == 0 { return String(format: L("%dh"), h) }
        return String(format: L("%dh %dm"), h, m)
    }

    static func sessions(_ n: Int) -> String {
        n == 1 ? L("1 session") : String(format: L("%d sessions"), n)
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

extension NSView {
    /// Resolves a dynamic color against this view's appearance.
    func cgColor(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }
}

func makeLabel(_ text: String = "", font: NSFont, color: NSColor = .labelColor,
               alignment: NSTextAlignment = .left) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor = color
    label.alignment = alignment
    label.lineBreakMode = .byClipping
    label.maximumNumberOfLines = 1
    return label
}
