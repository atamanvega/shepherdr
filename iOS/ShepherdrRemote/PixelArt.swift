import SwiftUI

/// Text in a 5×7 arcade font, drawn pixel by pixel. Lowercase shows as uppercase; a character the
/// font lacks shows as a space.
struct PixelText: View {
    let text: String
    var scale: CGFloat = 2
    var color: Color = Theme.phosphor
    /// A darker copy one pixel down and right, as arcade titles have.
    var shadow: Color?

    init(_ text: String, scale: CGFloat = 2, color: Color = Theme.phosphor, shadow: Color? = nil) {
        self.text = text
        self.scale = scale
        self.color = color
        self.shadow = shadow
    }

    static func width(of text: String, scale: CGFloat) -> CGFloat { CGFloat(max(0, text.count * 6 - 1)) * scale }

    var body: some View {
        let glyphs = Array(text.uppercased())
        let offset = shadow == nil ? 0 : scale
        Canvas { context, _ in
            let path = PixelFont.path(glyphs, scale: scale)
            if let shadow { context.fill(path.offsetBy(dx: scale, dy: scale), with: .color(shadow)) }
            context.fill(path, with: .color(color))
        }
        .frame(width: Self.width(of: text, scale: scale) + offset, height: 7 * scale + offset)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

enum PixelFont {
    static func path(_ glyphs: [Character], scale: CGFloat) -> Path {
        var path = Path()
        for (index, character) in glyphs.enumerated() {
            guard let rows = glyph[character] else { continue }
            for (y, row) in rows.enumerated() {
                for (x, bit) in row.enumerated() where bit == "#" {
                    path.addRect(CGRect(x: CGFloat(index * 6 + x) * scale, y: CGFloat(y) * scale, width: scale, height: scale))
                }
            }
        }
        return path
    }

    static let glyph: [Character: [String]] = [
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        "!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
        "?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
        ".": [".....", ".....", ".....", ".....", ".....", ".....", "..#.."],
        ",": [".....", ".....", ".....", ".....", ".....", "..#..", ".#..."],
        ":": [".....", "..#..", ".....", ".....", ".....", "..#..", "....."],
        "-": [".....", ".....", ".....", ".###.", ".....", ".....", "....."],
        "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
        "×": [".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "....."],
        "/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
        "'": ["..#..", "..#..", ".#...", ".....", ".....", ".....", "....."],
        "#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
        "(": ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."],
        ")": [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."],
        "=": [".....", ".....", "#####", ".....", "#####", ".....", "....."],
        "_": [".....", ".....", ".....", ".....", ".....", ".....", "#####"],
        "★": ["..#..", ".###.", "#####", ".###.", ".#.#.", "#...#", "....."],
        "▶": [".#...", ".##..", ".###.", ".####", ".###.", ".##..", ".#..."],
        "◀": ["...#.", "..##.", ".###.", "####.", ".###.", "..##.", "...#."],
        "▲": [".....", ".....", "..#..", ".###.", "#####", ".....", "....."],
        "▼": [".....", ".....", "#####", ".###.", "..#..", ".....", "....."],
        "✓": [".....", ".....", "....#", "...#.", "#.#..", ".#...", "....."],
        " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."]
    ]
}

/// A small picture drawn from rows of characters, each standing for a color in its palette; `.`
/// is transparent.
struct Sprite {
    let rows: [String]
    let palette: [Character: Color]

    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }

    func draw(in context: GraphicsContext, at origin: CGPoint, scale: CGFloat, flipped: Bool = false) {
        var paths: [Character: Path] = [:]
        let width = width
        for (y, row) in rows.enumerated() {
            for (x, key) in row.enumerated() where key != "." {
                let column = flipped ? width - 1 - x : x
                paths[key, default: Path()].addRect(CGRect(x: origin.x + CGFloat(column) * scale, y: origin.y + CGFloat(y) * scale,
                                                           width: scale, height: scale))
            }
        }
        for (key, path) in paths { if let color = palette[key] { context.fill(path, with: .color(color)) } }
    }
}

/// Shepherdr's flock and its dog, in pixels.
enum Flock {
    /// A sheep facing right, in a color, with curls in its wool; the second frame moves its legs.
    static func sheep(_ wool: Color, step: Bool = false) -> Sprite {
        Sprite(rows: [
            "...WW.WW.WW.....",
            "..WWWWWWWWWWW...",
            ".WWCWWWWCWWWWKK.",
            "WWWWWWCWWWWWKFFF",
            "WCWWWWWWWCWWKFEF",
            "WWWWCWWWWWWW.FFF",
            ".WWWWWWCWWWW..F.",
            "..WWWWWWWWWW....",
            "...K.K....K.K...",
            step ? "..K...K..K...K.." : "...K.K....K.K..."
        ], palette: ["W": wool, "C": wool.opacity(0.62), "F": wool.opacity(0.42), "K": wool.opacity(0.3), "E": Theme.text])
    }

    /// Shepherdr's dog running right, as the app's icon paints it; the second frame gathers its legs.
    static func dog(step: Bool = false) -> Sprite {
        let legs = step
            ? ["....TT.T...T.TT.....", "....T..T...T..T.....", "...TT..TT.TT..TT...."]
            : ["...TT.T.....T.TT....", "..TT..T.....T...TT..", ".TT...TT...TT....TT."]
        return Sprite(rows: [
            "..............K..K..",
            "..............KK.KK.",
            "..............KTTTK.",
            ".............KTTETTT",
            ".............KTTTTTN",
            "K...KKKKKKKKKKTTTP..",
            "KK.KKKKKKKKKKKTT....",
            ".KKTKKKKKKKKKTTT....",
            "...TTTTTTTTTTTT....."
        ] + legs, palette: ["K": Color(hex: 0x5A3A1E), "T": Color(hex: 0xD9A050), "N": Color(hex: 0x1A1A1A),
                            "E": Theme.phosphor, "P": Color(hex: 0xF07A8A)])
    }
}

/// A sprite as a view.
struct SpriteView: View {
    let sprite: Sprite
    var scale: CGFloat = 3

    var body: some View {
        Canvas { context, _ in sprite.draw(in: context, at: .zero, scale: scale) }
            .frame(width: CGFloat(sprite.width) * scale, height: CGFloat(sprite.height) * scale)
            .accessibilityHidden(true)
    }
}

/// Blinks what it wraps, twice a second, as arcade prompts do.
struct Blinking<Content: View>: View {
    var period: Double = 0.5
    @ViewBuilder let content: Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: period)) { timeline in
            content.opacity(Int(timeline.date.timeIntervalSinceReferenceDate / period) % 2 == 0 ? 1 : 0.12)
        }
    }
}
