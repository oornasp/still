// Dev tool: renders the panel panes and menu bar glyphs to PNGs for visual review.
// Build & run: ./tools/snapshot.sh <out-dir>
import AppKit

final class NoopActions: PanelActions {
    func toggleTimer() {}
    func resetTimer() {}
    func skipPhase() {}
    func selectPhase(_ phase: Phase) {}
    func preferencesChanged() {}
    func previewSound(_ theme: SoundTheme) {}
    func closePanel() {}
    func quit() {}
}

let out = CommandLine.arguments.dropFirst().first ?? "."
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)

let prefs = Preferences.shared
let actions = NoopActions()

func render(_ view: NSView, _ appearance: NSAppearance.Name, backdrop: NSColor, name: String) {
    let size = view.frame.size
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance)
    let host = FillView(frame: NSRect(origin: .zero, size: size))
    host.fill = backdrop
    host.addSubview(view)
    window.contentView = host
    window.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    CATransaction.flush()
    RunLoop.current.run(until: Date().addingTimeInterval(0.8)) // let animations settle

    let scale: CGFloat = 2
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                               pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.cgContext.scaleBy(x: scale, y: scale)
    host.layer!.render(in: ctx.cgContext)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    window.orderOut(nil)
    print("wrote \(name).png")
}

let lightGlass = NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
let darkGlass = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)

// Build up some history: two completed focus sessions.
let model = TimerModel(prefs: prefs)
for _ in 0..<2 {
    model.start(); model.complete() // focus → break (auto-started)
    model.skip()                    // break → focus (idle)
}
model.start()

func mainPane(_ now: Date) -> PanelRootView {
    let root = PanelRootView(model: model, prefs: prefs, actions: actions)
    root.update(now: now, animated: false)
    return root
}

let later = Date().addingTimeInterval(372)
render(mainPane(later), .darkAqua, backdrop: darkGlass, name: "main-dark")
render(mainPane(later), .aqua, backdrop: lightGlass, name: "main-light")

model.pause()
render(mainPane(Date()), .darkAqua, backdrop: darkGlass, name: "main-paused-dark")
model.select(.shortBreak)
render(mainPane(Date()), .aqua, backdrop: lightGlass, name: "main-idle-break-light")

for (appearance, backdrop, name) in [(NSAppearance.Name.darkAqua, darkGlass, "settings-dark"),
                                     (.aqua, lightGlass, "settings-light")] {
    let pane = SettingsPane(frame: NSRect(x: 0, y: 0, width: PanelLayout.width, height: PanelLayout.height), prefs: prefs)
    render(pane, appearance, backdrop: backdrop, name: name)
}

// Menu bar glyphs, drawn large on light and dark strips.
func glyphSheet(_ icons: [NSImage], cell: NSSize, zoom: CGFloat, name: String) {
    let pad: CGFloat = 6
    let w = (cell.width + pad) * CGFloat(icons.count) + pad, rowH = cell.height + pad * 2
    let sheet = NSImage(size: NSSize(width: w * zoom, height: rowH * 2 * zoom), flipped: false) { _ in
        for (row, (bg, fg)) in [(NSColor(white: 0.93, alpha: 1), NSColor.black),
                                (NSColor(white: 0.14, alpha: 1), NSColor.white)].enumerated() {
            let y = CGFloat(row) * rowH * zoom
            bg.setFill()
            NSRect(x: 0, y: y, width: w * zoom, height: rowH * zoom).fill()
            for (i, icon) in icons.enumerated() {
                let tinted = NSImage(size: cell, flipped: false) { r in
                    icon.draw(in: r); fg.set(); r.fill(using: .sourceAtop); return true
                }
                tinted.draw(in: NSRect(x: (pad + CGFloat(i) * (cell.width + pad)) * zoom, y: y + pad * zoom,
                                       width: cell.width * zoom, height: cell.height * zoom))
            }
        }
        return true
    }
    try! NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    print("wrote \(name).png")
}

glyphSheet([(StatusBarController.IconStyle.idle, 1.0), (.focus, 0.75), (.focus, 0.4), (.rest, 0.6), (.paused, 0.6)]
    .map { StatusBarController.icon($0.0, fraction: $0.1) }, cell: NSSize(width: 16, height: 16), zoom: 6, name: "ring-icons")

let eating = Panda.sequence(.eating(bamboo: 6))
var poses = [Panda.sequence(.sleeping)[0].image, Panda.sequence(.waiting)[0].image, eating[0].image, eating[2].image,
             Panda.sequence(.eating(bamboo: 3))[0].image, Panda.sequence(.eating(bamboo: 1))[0].image]
poses += Panda.sequence(.trotting).map(\.image)
glyphSheet(poses, cell: Panda.size, zoom: 5, name: "panda-poses")

// A slice of menu bar showing the panda next to the countdown.
func menuBarMock(_ image: NSImage, text: String, dark: Bool, name: String) {
    let zoom: CGFloat = 4, size = NSSize(width: 92, height: 24)
    let fg: NSColor = dark ? .white : .black
    let mock = NSImage(size: NSSize(width: size.width * zoom, height: size.height * zoom), flipped: false) { _ in
        (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.94, alpha: 1)).setFill()
        NSRect(x: 0, y: 0, width: size.width * zoom, height: size.height * zoom).fill()
        let tinted = NSImage(size: image.size, flipped: false) { r in
            image.draw(in: r); fg.set(); r.fill(using: .sourceAtop); return true
        }
        tinted.draw(in: NSRect(x: 10 * zoom, y: 3 * zoom, width: image.size.width * zoom, height: image.size.height * zoom))
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13 * zoom, weight: .regular)
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: fg])
            .draw(at: NSPoint(x: 36 * zoom, y: 4.5 * zoom))
        return true
    }
    try! NSBitmapImageRep(data: mock.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    print("wrote \(name).png")
}
menuBarMock(eating[0].image, text: "18:48", dark: false, name: "menubar-focus-light")
menuBarMock(Panda.sequence(.trotting)[2].image, text: "4:12", dark: true, name: "menubar-break-dark")
