import Foundation
import Observation
import ShepherdrRemote
import UIKit

/// Herd mode on the phone: the game in play, the table of high scores and the points popping up.
/// It follows the queue the Mac sends and what you type into sessions, and keeps the game and the
/// table on the phone, so that a game goes on after the app quits.
@MainActor @Observable
final class Arcade {
    /// Whether the queue's screen shows herd mode.
    static let modeKey = "herdMode"
    private static let gameKey = "herdGame", placedKey = "herdPlaced", scoresKey = "herdScores", initialsKey = "herdInitials"

    private(set) var game: HerdGame?
    private(set) var scores: [HerdScore]
    /// Where the finished game's score went in the table once its initials are in; -1 when it
    /// didn't make it.
    private(set) var placed: Int?
    /// The initials entered last, to start from next time.
    private(set) var lastInitials: String
    /// What just scored, popping up over whatever the phone shows.
    private(set) var popups: [Popup] = []

    struct Popup: Identifiable, Equatable {
        let id = UUID()
        let event: HerdEvent
        let date = Date()
    }

    /// Whether the phone reaches the Mac now; while it doesn't, the game's clock stops.
    @ObservationIgnored var isConnected: () -> Bool = { true }
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private let sound = ArcadeSound.shared

    init() {
        let defaults = UserDefaults.standard
        game = defaults.data(forKey: Self.gameKey).flatMap { try? JSONDecoder().decode(HerdGame.self, from: $0) }
        placed = defaults.object(forKey: Self.placedKey) as? Int
        scores = defaults.data(forKey: Self.scoresKey).flatMap { try? JSONDecoder().decode([HerdScore].self, from: $0) } ?? HerdScores.starting
        lastInitials = defaults.string(forKey: Self.initialsKey) ?? "AAA"
        startClock()
    }

    var isPlaying: Bool { game.map { !$0.isOver } ?? false }
    var highScore: Int { max(scores.first?.score ?? 0, game?.score ?? 0) }

    /// The finished game made the table and waits for its initials.
    var awaitsInitials: Bool {
        guard let game, game.isOver, placed == nil else { return false }
        return HerdScores.rank(of: game.score, in: scores) != nil
    }

    // MARK: Playing

    func start(with rows: [QueueRow]) {
        game = HerdGame(rows: rows, at: .now)
        placed = nil
        popups = []
        save()
        sound.play(.start)
    }

    /// A new queue from the Mac: score what changed.
    func observe(_ rows: [QueueRow]) {
        guard var game, !game.isOver else { return }
        let events = game.observe(rows, at: .now)
        self.game = game
        save()
        handle(events)
    }

    /// You typed into a pane from the phone. Only sessions astray count.
    func touch(_ pane: RemoteSessionID, rows: [QueueRow]?) {
        guard var game, !game.isOver, let rows, let session = Herd.session(of: pane, in: rows),
              game.strays(in: rows).contains(where: { $0.session == session }) else { return }
        game.touch(session, at: .now)
        self.game = game
        save()
    }

    func giveUp() {
        guard var game, !game.isOver else { return }
        game.giveUp(at: .now)
        self.game = game
        save()
        sound.play(.gameOver)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Puts the finished game's score in the table under these initials.
    func enter(initials: String) {
        guard let game, game.isOver, placed == nil else { return }
        let entry = HerdScore(initials: initials, score: game.score, date: game.ended ?? .now)
        let (table, rank) = HerdScores.inserting(entry, into: scores)
        scores = table
        placed = rank ?? -1
        lastInitials = HerdScores.initials(initials)
        save()
        sound.play(.entry)
    }

    /// Back to the title screen, for another game.
    func reset() {
        game = nil
        placed = nil
        popups = []
        save()
        sound.play(.coin)
    }

    func play(_ effect: ArcadeSound.Effect) { sound.play(effect) }

    // MARK: Events

    private func handle(_ events: [HerdEvent]) {
        guard !events.isEmpty else { return }
        for event in events where event.kind != .cleared && event.kind != .timeUp {
            popups.append(Popup(event: event))
        }
        if popups.count > 4 { popups.removeFirst(popups.count - 4) }
        let ids = Set(popups.map(\.id))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            self?.popups.removeAll { ids.contains($0.id) }
        }
        // One sound for the lot: the one that matters most.
        let kinds = events.map(\.kind)
        if kinds.contains(.cleared) {
            sound.play(.cleared)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else if kinds.contains(.timeUp) {
            sound.play(.gameOver)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } else if let scored = events.filter({ $0.points > 0 }).max(by: { $0.points < $1.points }) {
            sound.play(scored.kind == .closed ? .closed : scored.kind == .answered ? .answered : .backToWork)
            UIImpactFeedbackGenerator(style: scored.kind == .closed ? .heavy : .medium).impactOccurred()
        } else if kinds.contains(.strayed) {
            sound.play(.strayed)
        } else if kinds.contains(.closed) {
            sound.play(.select)
        }
    }

    /// Ends the game when its countdown runs out, and ticks through its last ten seconds. The
    /// clock stops while the app, in front, can't reach the Mac; it runs on while the app is away.
    private func startClock() {
        clock = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let now = ContinuousClock.now
                defer { last = now }
                guard let self, var game = self.game, !game.isOver else { continue }
                if !isConnected() {
                    let elapsed = now - last
                    game.hold(for: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
                    self.game = game
                    save()
                } else if let event = game.expire(at: .now) {
                    self.game = game
                    save()
                    handle([event])
                } else if game.deadline.timeIntervalSinceNow <= 10 {
                    sound.play(.tick)
                }
            }
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let game, let data = try? JSONEncoder().encode(game) { defaults.set(data, forKey: Self.gameKey) }
        else { defaults.removeObject(forKey: Self.gameKey) }
        if let placed { defaults.set(placed, forKey: Self.placedKey) } else { defaults.removeObject(forKey: Self.placedKey) }
        if let data = try? JSONEncoder().encode(scores) { defaults.set(data, forKey: Self.scoresKey) }
        defaults.set(lastInitials, forKey: Self.initialsKey)
    }
}
