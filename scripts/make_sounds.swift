// Synthesizes Still's sound themes. Each theme has two cues:
//   <Theme>-Rest.caf  — focus finished, time to rest (falling)
//   <Theme>-Focus.caf — break finished, back to work (rising)
// Usage: swift scripts/make_sounds.swift <output-dir>
import Foundation

let sampleRate = 24_000.0
let outDir = CommandLine.arguments.dropFirst().first ?? "Resources"

struct Partial { let ratio: Double; let amp: Double; let decay: Double }

struct Instrument {
    let partials: [Partial]
    let attack: Double
    /// Each partial is doubled with this detune (Hz) for a slow shimmer.
    var beat: Double = 0

    func sample(_ freq: Double, _ t: Double) -> Double {
        var s = 0.0
        for p in partials {
            let f = freq * p.ratio
            var tone = sin(2 * .pi * f * t)
            if beat > 0 { tone = 0.5 * tone + 0.5 * sin(2 * .pi * (f + beat * p.ratio) * t) }
            s += p.amp * exp(-p.decay * t) * tone
        }
        return s * min(1, t / attack)
    }
}

/// Soft glassy bell.
let chime = Instrument(partials: [
    Partial(ratio: 1.0, amp: 1.0, decay: 2.8), Partial(ratio: 2.0, amp: 0.22, decay: 4.5),
    Partial(ratio: 3.01, amp: 0.08, decay: 7.0), Partial(ratio: 4.17, amp: 0.035, decay: 10.0),
], attack: 0.004)

/// Singing bowl: deep, inharmonic modes that ring for seconds and gently beat.
let bowl = Instrument(partials: [
    Partial(ratio: 1.0, amp: 1.0, decay: 0.85), Partial(ratio: 2.71, amp: 0.45, decay: 1.4),
    Partial(ratio: 5.15, amp: 0.16, decay: 2.6), Partial(ratio: 8.43, amp: 0.05, decay: 4.0),
], attack: 0.012, beat: 1.6)

/// Wooden marimba knock: warm and short.
let wood = Instrument(partials: [
    Partial(ratio: 1.0, amp: 1.0, decay: 9.0), Partial(ratio: 3.93, amp: 0.22, decay: 16.0),
    Partial(ratio: 9.24, amp: 0.05, decay: 30.0),
], attack: 0.0015)

typealias Note = (freq: Double, at: Double, gain: Double)

func render(_ instrument: Instrument, _ notes: [Note], length: Double) -> [Int16] {
    let count = Int(length * sampleRate)
    var buffer = [Double](repeating: 0, count: count)
    for note in notes {
        for i in Int(note.at * sampleRate)..<count {
            buffer[i] += note.gain * instrument.sample(note.freq, Double(i) / sampleRate - note.at)
        }
    }
    // Fade the tail to true silence and normalize to about -7 dBFS.
    let fade = Int(min(0.4, length * 0.25) * sampleRate)
    for i in 0..<fade { buffer[count - 1 - i] *= Double(i) / Double(fade) }
    let peak = buffer.map(abs).max() ?? 1
    return buffer.map { Int16(($0 / peak * 0.45 * 32_767).rounded()) }
}

func writeWAV(_ samples: [Int16], to path: String) throws {
    var data = Data()
    func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    let bytes = samples.count * 2
    data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + bytes))
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
    put(UInt32(sampleRate)); put(UInt32(sampleRate * 2)); put(UInt16(2)); put(UInt16(16))
    data.append(contentsOf: Array("data".utf8)); put(UInt32(bytes))
    for s in samples { put(s) }
    try data.write(to: URL(fileURLWithPath: path))
}

let G4 = 392.00, C5 = 523.25, D5 = 587.33, E5 = 659.25, G5 = 783.99, C6 = 1046.50, E6 = 1318.51

let themes: [(name: String, instrument: Instrument, length: Double, rest: [Note], focus: [Note])] = [
    ("Chime", chime, 1.7,
     [(C6, 0, 0.75), (G5, 0.17, 1.0)],
     [(G5, 0, 0.7), (C6, 0.13, 0.8), (E6, 0.26, 0.55)]),
    ("Bowl", bowl, 3.6,
     [(G4, 0, 1.0)],
     [(G4, 0, 0.8), (D5, 0.45, 0.7)]),
    ("Wood", wood, 0.9,
     [(E5, 0, 1.0), (C5, 0.15, 0.9)],
     [(C5, 0, 0.8), (E5, 0.11, 0.85), (G5, 0.22, 0.9)]),
]

for theme in themes {
    for (cue, notes) in [("Rest", theme.rest), ("Focus", theme.focus)] {
        let name = "\(theme.name)-\(cue)"
        let wav = NSTemporaryDirectory() + name + ".wav"
        try writeWAV(render(theme.instrument, notes, length: theme.length), to: wav)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        task.arguments = ["-f", "caff", "-d", "LEI16", wav, "\(outDir)/\(name).caf"]
        try task.run()
        task.waitUntilExit()
        print("wrote \(outDir)/\(name).caf")
    }
}
