@preconcurrency import AVFoundation
import Foundation

/// Herd mode's 8-bit sounds, synthesized on the phone: square and triangle waves, as a game
/// console's sound chip makes them. They mix with other audio and follow the silent switch, and
/// stay quiet while you dictate.
@MainActor
final class ArcadeSound {
    enum Effect: CaseIterable {
        case coin, start, select, backToWork, answered, closed, strayed, cleared, gameOver, tick, entry
    }

    static let shared = ArcadeSound()
    static let enabledKey = "herdSound"

    private var players: [AVAudioPlayer] = []
    private var cache: [Effect: Data] = [:]

    var isEnabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    func play(_ effect: Effect) {
        guard isEnabled, !Dictation.isListening else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .ambient { try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers]) }
        try? session.setActive(true)
        let data = cache[effect] ?? Synth.wave(Self.music(effect))
        cache[effect] = data
        guard let player = try? AVAudioPlayer(data: data) else { return }
        players.removeAll { !$0.isPlaying }
        players.append(player)
        player.volume = 0.55
        player.play()
    }

    /// Each sound's voices, played together.
    private static func music(_ effect: Effect) -> [[Synth.Note]] {
        typealias N = Synth.Note
        let n = Synth.frequency
        switch effect {
        case .coin:
            return [[N(n("B5"), 0.06, duty: 0.25), N(n("E6"), 0.32, duty: 0.25)]]
        case .entry:
            return [[N(n("E6"), 0.06, duty: 0.25), N(n("B6"), 0.3, duty: 0.25)]]
        case .start:
            return [[N(n("G5"), 0.06), N(n("C6"), 0.06), N(n("E6"), 0.06), N(n("G6"), 0.12), N(n("E6"), 0.06), N(n("G6"), 0.26)]]
        case .select:
            return [[N(n("A6"), 0.03, duty: 0.125, volume: 0.35)]]
        case .tick:
            return [[N(n("E5"), 0.05, duty: 0.25, volume: 0.35)]]
        case .backToWork:
            return [[N(n("E6"), 0.05), N(n("A6"), 0.1)]]
        case .answered:
            return [[N(n("C6"), 0.045), N(n("E6"), 0.045), N(n("G6"), 0.045), N(n("C7"), 0.14)]]
        case .closed:
            return [[N(n("C5"), 0.24, to: n("C7")), N(n("G6"), 0.06), N(n("C7"), 0.22)],
                    [N(0, 0.24), N(n("C4"), 0.28, wave: .triangle, volume: 0.6)]]
        case .strayed:
            // A bleat: a wobbling square that sags a little.
            return [[N(430, 0.42, to: 360, vibrato: 19, volume: 0.32)]]
        case .cleared:
            return [[N(n("C5"), 0.1), N(n("E5"), 0.1), N(n("G5"), 0.1), N(n("C6"), 0.2), N(0, 0.05),
                     N(n("A5"), 0.1), N(n("C6"), 0.1), N(n("E6"), 0.1), N(n("G6"), 0.5)],
                    [N(n("C3"), 0.3, wave: .triangle, volume: 0.6), N(n("G3"), 0.3, wave: .triangle, volume: 0.6),
                     N(n("A3"), 0.3, wave: .triangle, volume: 0.6), N(n("G3"), 0.55, wave: .triangle, volume: 0.6)]]
        case .gameOver:
            return [[N(n("G4"), 0.2), N(n("F#4"), 0.2), N(n("F4"), 0.2), N(n("E4"), 0.7, vibrato: 6)],
                    [N(n("G2"), 0.6, wave: .triangle, volume: 0.6), N(n("C2"), 0.7, wave: .triangle, volume: 0.6)]]
        }
    }
}

/// A tiny sound chip: notes in, a WAV file out.
enum Synth {
    static let rate = 22_050.0

    enum Wave { case square, triangle }

    struct Note {
        /// Hertz; 0 is a rest.
        var frequency: Double
        var duration: Double
        /// Slides to this frequency by the note's end.
        var to: Double?
        var wave: Wave = .square
        /// The square's share of high: 0.5 is hollow, 0.125 thin and buzzy.
        var duty: Double = 0.5
        /// Wobbles the pitch this many times a second.
        var vibrato: Double = 0
        var volume: Double = 0.5

        init(_ frequency: Double, _ duration: Double, to: Double? = nil, wave: Wave = .square, duty: Double = 0.5,
             vibrato: Double = 0, volume: Double = 0.5) {
            self.frequency = frequency
            self.duration = duration
            self.to = to
            self.wave = wave
            self.duty = duty
            self.vibrato = vibrato
            self.volume = volume
        }
    }

    /// `A4` is 440 Hz; `F#4` and `Bb3` work too.
    static func frequency(_ name: String) -> Double {
        let semitones: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var characters = Array(name)
        guard let first = characters.first, var semitone = semitones[first] else { return 0 }
        characters.removeFirst()
        if characters.first == "#" { semitone += 1; characters.removeFirst() }
        else if characters.first == "b" { semitone -= 1; characters.removeFirst() }
        let octave = Int(String(characters)) ?? 4
        let midi = Double(12 * (octave + 1) + semitone)
        return 440 * pow(2, (midi - 69) / 12)
    }

    /// The voices mixed, as a 16-bit mono WAV.
    static func wave(_ voices: [[Note]]) -> Data {
        let tracks = voices.map(samples)
        let length = tracks.map(\.count).max() ?? 0
        var mixed = [Int16](repeating: 0, count: length)
        for index in 0..<length {
            let sum = tracks.reduce(0.0) { $0 + (index < $1.count ? $1[index] : 0) }
            mixed[index] = Int16(max(-1, min(1, sum * 0.6)) * 32_000)
        }
        return wav(mixed)
    }

    private static func samples(_ notes: [Note]) -> [Double] {
        var output: [Double] = []
        var phase = 0.0
        for note in notes {
            let count = Int(note.duration * rate)
            for index in 0..<count {
                let progress = Double(index) / Double(max(1, count))
                guard note.frequency > 0 else { output.append(0); continue }
                var frequency = note.frequency + ((note.to ?? note.frequency) - note.frequency) * progress
                if note.vibrato > 0 { frequency *= 1 + 0.05 * sin(2 * .pi * note.vibrato * Double(index) / rate) }
                phase = (phase + frequency / rate).truncatingRemainder(dividingBy: 1)
                let value = switch note.wave {
                case .square: phase < note.duty ? 1.0 : -1.0
                case .triangle: 4 * abs(phase - 0.5) - 1
                }
                // A click-free start, a slow fade, and a quick release at the end.
                let attack = min(1, Double(index) / (0.004 * rate))
                let release = min(1, Double(count - index) / (0.012 * rate))
                output.append(value * note.volume * attack * release * (1 - 0.5 * progress))
            }
        }
        return output
    }

    private static func wav(_ samples: [Int16]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        for sample in samples { append(sample) }
        return data
    }
}
