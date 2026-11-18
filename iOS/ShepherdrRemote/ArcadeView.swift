import ShepherdrRemote
import SwiftUI

/// Herd mode: the queue as an arcade game. The sessions that stopped come first, needing you, then
/// done, then idle; the ones working graze in the pasture. Clear them all before the clock runs
/// out, and your initials go in the table.
struct ArcadeView: View {
    @Bindable var client: RelayClient
    let onQueue: () -> Void
    let onSettings: () -> Void
    @AppStorage(ArcadeSound.enabledKey) private var soundOn = true

    private var arcade: Arcade { client.arcade }
    private var rows: [QueueRow] { client.queue?.rows ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topBar
                ScoreBar(arcade: arcade)
                if let game = arcade.game {
                    if game.isOver { ResultScreen(arcade: arcade, game: game, onQueue: onQueue) }
                    else { PlayScreen(client: client, arcade: arcade, game: game, rows: rows, connected: client.phase == .connected) }
                } else {
                    AttractScreen(client: client, arcade: arcade, rows: rows)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button(action: onQueue) {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet").font(.system(size: 13))
                    Text("QUEUE").font(Theme.mono(12, .semibold)).tracking(2)
                }
                .foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
            Spacer()
            Circle().fill(client.phase == .connected ? Theme.phosphor : Theme.amber).frame(width: 7, height: 7)
            Text(client.mac?.name ?? "Mac").font(Theme.mono(11)).foregroundStyle(Theme.dim).lineLimit(1)
            Button {
                soundOn.toggle()
                if soundOn { arcade.play(.select) }
            } label: {
                Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill").font(.system(size: 15)).foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(soundOn ? "Mute" : "Sound On")
            Button(action: onSettings) {
                Image(systemName: "gearshape").font(.system(size: 16)).foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 4)
    }

    static func digits(_ score: Int) -> String { String(format: "%06d", min(score, 999_999)) }
}

/// Shepherdr's dog, your score and the best one, as an arcade's top line.
private struct ScoreBar: View {
    let arcade: Arcade

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("ArcadeDog").resizable().interpolation(.none).frame(width: 54, height: 54)
                .overlay(Rectangle().stroke(Theme.phosphor.opacity(0.5), lineWidth: 2))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                PixelText("1UP", color: Theme.red)
                PixelText(ArcadeView.digits(arcade.game?.score ?? 0), scale: 3, color: Theme.text)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                PixelText("HI SCORE", color: Theme.amber)
                PixelText(ArcadeView.digits(arcade.highScore), scale: 3, color: Theme.text)
            }
        }
    }
}

// MARK: Title

private struct AttractScreen: View {
    let client: RelayClient
    let arcade: Arcade
    let rows: [QueueRow]

    var body: some View {
        let strays = Herd.strays(in: rows)
        let moving = rows.filter { $0.kind == .session && Herd.isMoving($0.status) }.count
        VStack(spacing: 18) {
            Image("ArcadeTitle").resizable().interpolation(.none).scaledToFit()
                .frame(maxWidth: .infinity).padding(.top, 4)
                .accessibilityLabel("Shepherdr's dog and its sheep")
            PixelText("HERD MODE", scale: 4, color: Theme.amber, shadow: Theme.red.opacity(0.6))
            if client.queue == nil {
                PixelText("WAITING FOR THE MAC", color: Theme.dim)
            } else if strays.isEmpty {
                VStack(spacing: 8) {
                    PixelText("ALL SHEEP GRAZING", color: Theme.phosphor)
                    Text("Nothing to herd: every session is working or on hold.")
                        .font(Theme.mono(11)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                }
            } else {
                HStack(spacing: 18) {
                    PixelText("ASTRAY \(strays.count)", color: Theme.amber)
                    PixelText("GRAZING \(moving)", color: Theme.phosphor)
                }
                Button { arcade.start(with: rows) } label: {
                    Blinking { PixelText("PRESS START", scale: 3, color: Theme.phosphor) }
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .overlay(Rectangle().stroke(Theme.phosphor, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            HowToPlay()
            HighScoreTable(scores: arcade.scores, highlight: nil)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HowToPlay: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PixelText("HOW TO PLAY", color: Theme.cyan)
            line("▶ BACK TO WORK", "10", Theme.phosphor)
            line("! ANSWER", "50", Theme.amber)
            line("✓ EXIT WHEN DONE", "100", Theme.cyan)
            line("★ QUEUE CLEAR", "500", Theme.lilac)
            line("COMBO IN 90 S", "×5", Theme.red)
            Text("Prompt a session that stopped, answer the one that needs you, or leave the agent of one that's done, such as with /exit, all from this iPhone. Ten minutes without doing anything is GAME OVER.")
                .font(Theme.mono(10.5)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
    }

    private func line(_ label: String, _ points: String, _ color: Color) -> some View {
        HStack {
            PixelText(label, color: color)
            Spacer()
            PixelText(points, color: Theme.text)
        }
    }
}

// MARK: Playing

private struct PlayScreen: View {
    let client: RelayClient
    let arcade: Arcade
    let game: HerdGame
    let rows: [QueueRow]
    let connected: Bool
    @State private var confirmsGivingUp = false

    var body: some View {
        let strays = game.strays(in: rows)
        let moving = rows.filter { $0.kind == .session && Herd.isMoving($0.status) }
        VStack(alignment: .leading, spacing: 14) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let left = max(0, Int(game.deadline.timeIntervalSince(timeline.date).rounded(.up)))
                let combo = game.lastScored.map { timeline.date.timeIntervalSince($0) <= HerdGame.comboWindow } == true && game.combo > 1
                HStack {
                    if !connected {
                        Blinking { PixelText("CLOCK STOPPED", color: Theme.amber) }
                    } else if left <= 60 {
                        Blinking { PixelText(String(format: "TIME %02d:%02d", left / 60, left % 60), color: Theme.red) }
                    } else {
                        PixelText(String(format: "TIME %02d:%02d", left / 60, left % 60), color: Theme.text)
                    }
                    Spacer()
                    if combo { PixelText("COMBO ×\(game.combo)", color: Theme.amber) }
                }
            }
            if !connected {
                Text("Waiting for \(client.mac?.name ?? "the Mac"): the clock starts again once the phone reaches it.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true)
            }
            Pasture(grazing: moving.count)
            HStack(spacing: 16) {
                PixelText("ASTRAY \(strays.count)", color: Theme.amber)
                PixelText("GRAZING \(moving.filter { $0.status == "working" }.count)", color: Theme.phosphor)
                let held = moving.filter { $0.status == "waiting" }.count
                if held > 0 { PixelText("HOLD \(held)", color: Theme.lilac) }
            }
            ForEach(Herd.Stray.allCases, id: \.self) { kind in
                let herd = strays.filter { Herd.stray(status: $0.status) == kind }
                if !herd.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center) {
                            PixelText(Self.heading(kind), color: Self.color(kind))
                            Spacer()
                            Text(Self.hint(kind)).font(Theme.mono(10)).foregroundStyle(Theme.faint)
                        }
                        ForEach(herd) { row in
                            if let session = row.session {
                                NavigationLink(value: SessionLink(row: row, session: session)) { StrayCard(row: row, kind: kind) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            Button { confirmsGivingUp = true } label: {
                PixelText("GIVE UP", color: Theme.faint)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .confirmationDialog("Give up this game?", isPresented: $confirmsGivingUp, titleVisibility: .visible) {
                Button("Give Up", role: .destructive) { arcade.giveUp() }
                Button("Keep Playing", role: .cancel) {}
            } message: {
                Text("It ends now, with the points you have. Your sessions carry on as they are.")
            }
        }
    }

    static func heading(_ kind: Herd.Stray) -> String {
        switch kind {
        case .needsYou: "! NEEDS YOU"
        case .done: "✓ DONE"
        case .idle: "Z IDLE"
        }
    }

    static func hint(_ kind: Herd.Stray) -> String {
        switch kind {
        case .needsYou: "answer +50"
        case .done, .idle: "prompt +10 · exit +100"
        }
    }

    static func color(_ kind: Herd.Stray) -> Color {
        switch kind {
        case .needsYou: Theme.amber
        case .done: Theme.cyan
        case .idle: Theme.dim
        }
    }
}

/// A session astray: its sheep in the color of what it waits for, and what it last said.
private struct StrayCard: View {
    let row: QueueRow
    let kind: Herd.Stray

    var body: some View {
        let color = PlayScreen.color(kind)
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                SpriteView(sprite: Flock.sheep(color), scale: 3).padding(.top, 6)
                if kind == .needsYou { Blinking { PixelText("!", color: Theme.amber) }.offset(x: 4, y: -4) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(Theme.mono(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                if let summary = row.summary, !summary.isEmpty {
                    Text(summary).font(Theme.mono(10.5)).foregroundStyle(Theme.dim).lineLimit(2)
                }
                let detail = [row.agent, row.machine].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty { Text(detail).font(Theme.mono(10)).foregroundStyle(Theme.faint).lineLimit(1) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.faint).padding(.top, 10)
        }
        .padding(10)
        .background(Theme.panel)
        .overlay(Rectangle().stroke(color.opacity(0.55), lineWidth: 2))
        .contentShape(Rectangle())
    }
}

/// The sessions at work, as sheep running across a field with the dog behind them.
private struct Pasture: View {
    let grazing: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let ground = size.height - 6
                context.fill(Path(CGRect(x: 0, y: ground, width: size.width, height: 2)), with: .color(Theme.line))
                var grass = Path()
                for x in stride(from: 7.0, to: size.width, by: 23) {
                    grass.addRect(CGRect(x: x, y: ground - 4, width: 2, height: 4))
                    grass.addRect(CGRect(x: x + 4, y: ground - 2, width: 2, height: 2))
                }
                context.fill(grass, with: .color(Color(hex: 0x1E5A3A)))
                let lap = size.width + 90
                let count = min(grazing, 8)
                for index in 0..<count {
                    let speed = 16 + Double(index * 7 % 11)
                    let x = (Double(index) * 53 + time * speed).truncatingRemainder(dividingBy: lap) - 50
                    let step = Int(time * 5 + Double(index)) % 2 == 0
                    Flock.sheep(Theme.phosphor, step: step).draw(in: context, at: CGPoint(x: x, y: ground - 30), scale: 3)
                }
                let dog = (time * 22).truncatingRemainder(dividingBy: lap + 40) - 70
                Flock.dog(step: Int(time * 7) % 2 == 0).draw(in: context, at: CGPoint(x: dog, y: ground - 36), scale: 3)
            }
        }
        .frame(height: 50)
        .overlay(alignment: .center) {
            if grazing == 0 { PixelText("NO SHEEP GRAZING", color: Theme.faint).offset(y: -16) }
        }
        .accessibilityLabel("\(grazing) sessions working")
    }
}

// MARK: The end

private struct ResultScreen: View {
    let arcade: Arcade
    let game: HerdGame
    let onQueue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            if game.outcome == .cleared {
                TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
                    let colors = [Theme.phosphor, Theme.amber, Theme.cyan, Theme.lilac]
                    PixelText("QUEUE CLEAR!", scale: 4, color: colors[Int(timeline.date.timeIntervalSinceReferenceDate * 5) % colors.count],
                              shadow: Theme.faint)
                }
                Image("ArcadeTitle").resizable().interpolation(.none).scaledToFit().frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            } else {
                PixelText("GAME OVER", scale: 5, color: Theme.red, shadow: Color(hex: 0x5A1A18))
                PixelText(game.outcome == .timeUp ? "TIME UP" : "YOU GAVE UP", color: Theme.dim)
                SpriteView(sprite: Flock.sheep(Theme.faint), scale: 6)
            }
            VStack(spacing: 10) {
                tally("BACK TO WORK", "×\(game.backToWork)")
                tally("ANSWERED", "×\(game.answered)")
                tally("CLOSED", "×\(game.closed)")
                if game.outcome == .cleared {
                    tally("CLEAR BONUS", "\(game.clearBonus)")
                    tally("TIME BONUS", "\(game.timeBonus)")
                }
                HStack {
                    PixelText("SCORE", scale: 3, color: Theme.amber)
                    Spacer()
                    PixelText(ArcadeView.digits(game.score), scale: 3, color: Theme.text)
                }
                .padding(.top, 4)
            }
            .padding(12)
            .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
            if arcade.awaitsInitials {
                InitialsEntry(arcade: arcade)
            } else {
                HighScoreTable(scores: arcade.scores, highlight: arcade.placed.flatMap { $0 >= 0 ? $0 : nil })
                HStack(spacing: 14) {
                    Button { arcade.reset() } label: {
                        PixelText("PLAY AGAIN", color: Theme.phosphor)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .overlay(Rectangle().stroke(Theme.phosphor, lineWidth: 2))
                    }
                    Button {
                        arcade.reset()
                        onQueue()
                    } label: {
                        PixelText("QUEUE", color: Theme.dim)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tally(_ label: String, _ value: String) -> some View {
        HStack {
            PixelText(label, color: Theme.dim)
            Spacer()
            PixelText(value, color: Theme.text)
        }
    }
}

/// Three letters, picked with the arrows, as an arcade asks for them.
private struct InitialsEntry: View {
    let arcade: Arcade
    @State private var letters: [Character]
    @State private var slot = 0

    init(arcade: Arcade) {
        self.arcade = arcade
        _letters = State(initialValue: Array(HerdScores.initials(arcade.lastInitials)))
    }

    var body: some View {
        VStack(spacing: 14) {
            Blinking { PixelText("NEW HIGH SCORE!", scale: 3, color: Theme.amber) }
            PixelText("ENTER YOUR INITIALS", color: Theme.dim)
            HStack(spacing: 22) {
                ForEach(0..<3, id: \.self) { index in
                    VStack(spacing: 8) {
                        arrow("▲", index, by: 1)
                        Button {
                            slot = index
                            arcade.play(.select)
                        } label: {
                            VStack(spacing: 6) {
                                PixelText(String(letters[index]), scale: 7, color: slot == index ? Theme.phosphor : Theme.text)
                                Rectangle().fill(slot == index ? Theme.phosphor : Theme.line).frame(width: 35, height: 4)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Letter \(index + 1): \(String(letters[index]))")
                        arrow("▼", index, by: -1)
                    }
                }
            }
            Button {
                arcade.enter(initials: String(letters))
            } label: {
                PixelText("OK", scale: 3, color: Theme.background)
                    .padding(.horizontal, 26).padding(.vertical, 10)
                    .background(Theme.phosphor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private func arrow(_ glyph: String, _ index: Int, by step: Int) -> some View {
        Button {
            let alphabet = HerdScores.alphabet
            let position = alphabet.firstIndex(of: letters[index]) ?? 0
            letters[index] = alphabet[(position + step + alphabet.count) % alphabet.count]
            slot = index
            arcade.play(.select)
        } label: {
            PixelText(glyph, scale: 5, color: Theme.dim).padding(8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step > 0 ? "Next letter" : "Previous letter")
    }
}

/// The ten best scores, in an arcade's colors; the one just made blinks.
private struct HighScoreTable: View {
    let scores: [HerdScore]
    let highlight: Int?

    private static let colors = [Theme.amber, Theme.phosphor, Theme.cyan, Theme.lilac, Theme.red]

    var body: some View {
        VStack(spacing: 9) {
            PixelText("HIGH SCORES", scale: 3, color: Theme.amber, shadow: Theme.red.opacity(0.6)).padding(.bottom, 4)
            ForEach(Array(scores.prefix(HerdScores.size).enumerated()), id: \.offset) { index, entry in
                let line = HStack(spacing: 0) {
                    PixelText(Self.ordinal(index + 1), color: Self.colors[index % Self.colors.count]).frame(width: 60, alignment: .leading)
                    PixelText(ArcadeView.digits(entry.score), color: Theme.text)
                    Spacer()
                    PixelText(entry.initials, color: Self.colors[index % Self.colors.count])
                }
                if index == highlight { Blinking(period: 0.3) { line } } else { line }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    static func ordinal(_ rank: Int) -> String {
        switch rank {
        case 1: "1ST"
        case 2: "2ND"
        case 3: "3RD"
        default: "\(rank)TH"
        }
    }
}

// MARK: Popups

/// The points as they come, over whatever screen the phone shows.
struct ArcadePopups: View {
    let arcade: Arcade

    var body: some View {
        VStack(spacing: 6) {
            ForEach(arcade.popups) { popup in PopupView(popup: popup) }
        }
        .animation(.spring(duration: 0.3), value: arcade.popups)
        .allowsHitTesting(false)
    }
}

private struct PopupView: View {
    let popup: Arcade.Popup

    var body: some View {
        TimelineView(.animation) { timeline in
            let age = timeline.date.timeIntervalSince(popup.date)
            content
                .offset(y: -min(age, 2) * 8)
                .opacity(age < 1.6 ? 1 : max(0, 1 - (age - 1.6) / 0.5))
        }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private var content: some View {
        let event = popup.event
        let color: Color = switch event.kind {
        case .answered: Theme.amber
        case .closed: Theme.cyan
        case .strayed: Theme.dim
        default: Theme.phosphor
        }
        return HStack(spacing: 10) {
            if event.kind == .strayed {
                PixelText("BAA!", scale: 3, color: color)
            } else if event.points > 0 {
                PixelText("+\(event.points)", scale: 3, color: color)
            }
            VStack(alignment: .leading, spacing: 3) {
                PixelText(label(event), color: Theme.text)
                Text(event.title).font(Theme.mono(10)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            if event.combo > 1 { PixelText("×\(event.combo)", scale: 2, color: Theme.amber) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.panel.opacity(0.96))
        .overlay(Rectangle().stroke(color.opacity(0.7), lineWidth: 2))
    }

    private func label(_ event: HerdEvent) -> String {
        switch event.kind {
        case .backToWork: "BACK TO WORK"
        case .answered: "ANSWERED"
        case .closed: "CLOSED"
        case .strayed: "ASTRAY"
        case .cleared: "QUEUE CLEAR"
        case .timeUp: "TIME UP"
        }
    }
}
