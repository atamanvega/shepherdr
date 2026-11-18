import Foundation

/// Herd mode: the queue as an arcade game. The sessions that stopped are sheep astray: putting
/// them back to work, answering them and closing the finished ones scores, and a queue with none
/// left astray wins. Ten minutes without doing anything ends the game.
public enum Herd {
    /// Why a session stopped, in the order the game deals with them.
    public enum Stray: Int, Comparable, Codable, Sendable, CaseIterable {
        /// Its agent asks a question or a permission.
        case needsYou
        /// Its agent finished a turn nobody looked at yet.
        case done
        /// Its agent waits for a prompt.
        case idle

        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// A session's place in the game: nil when it moves on its own (working, on hold), when its
    /// machine doesn't answer, and for shells and headings.
    public static func stray(_ row: QueueRow) -> Stray? {
        row.kind == .session ? stray(status: row.status) : nil
    }

    public static func stray(status: String?) -> Stray? {
        switch status {
        case "needsYou": .needsYou
        case "done": .done
        case "idle", "unknown": .idle
        default: nil
        }
    }

    /// Working or on hold: the session carries on without you.
    public static func isMoving(_ status: String?) -> Bool { status == "working" || status == "waiting" }

    /// The sessions astray: needing you first, then done, then idle, each in the queue's order.
    public static func strays(in rows: [QueueRow]) -> [QueueRow] {
        rows.enumerated()
            .compactMap { index, row in stray(row).map { (stray: $0, index: index, row: row) } }
            .sorted { ($0.stray, $0.index) < ($1.stray, $1.index) }
            .map(\.row)
    }

    /// The session a pane belongs to: its own, or the one whose tab it splits.
    public static func session(of pane: RemoteSessionID, in rows: [QueueRow]) -> RemoteSessionID? {
        rows.first { $0.session == pane || $0.panes.contains { $0.pane == pane } }?.session
    }

    static func key(_ session: RemoteSessionID) -> String { session.machineID + "/" + session.terminalID }
}

/// Something that happened in a game, for the score's popups and sounds.
public struct HerdEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A session that was done or idle works again after you prompted it.
        case backToWork
        /// A session that needed you moved on after you answered it.
        case answered
        /// A session you were in ended: `exit` closed it.
        case closed
        /// A session stopped and joined the strays.
        case strayed
        /// No session is astray anymore: the game is won.
        case cleared
        /// Ten minutes went by without you doing anything.
        case timeUp
    }

    public let kind: Kind
    /// The session's name; empty for the game's own events.
    public let title: String
    public let points: Int
    /// The multiplier the points got, 1 without a combo.
    public let combo: Int

    public init(kind: Kind, title: String, points: Int, combo: Int = 1) {
        self.kind = kind
        self.title = title
        self.points = points
        self.combo = combo
    }
}

/// One game of herd mode, from PRESS START to the queue cleared or the game over. It follows the
/// queue's snapshots and scores what changed in the sessions you touched from the phone.
public struct HerdGame: Codable, Equatable, Sendable {
    public enum Points {
        /// A done or idle session works again.
        public static let backToWork = 10
        /// A session that needed you moves on: 10 for setting it going and 40 for the answer.
        public static let answered = 50
        /// A finished session closed with `exit`.
        public static let closed = 100
        /// No session left astray.
        public static let cleared = 500
        /// For each minute under half an hour that clearing the queue took.
        public static let perMinuteLeft = 10
    }

    public enum Outcome: String, Codable, Sendable {
        case cleared, timeUp, gaveUp
    }

    /// How long the game waits for you to do something before it ends.
    public static let patience: TimeInterval = 10 * 60
    /// How long after your input a session's change still counts as yours.
    public static let touchWindow: TimeInterval = 3 * 60
    /// Scoring again within this long raises the multiplier.
    public static let comboWindow: TimeInterval = 90
    public static let maxCombo = 5

    public private(set) var started: Date
    public private(set) var score = 0
    public private(set) var combo = 1
    public private(set) var lastScored: Date?
    /// When you last scored or typed into a session astray: the countdown starts again from it.
    public private(set) var lastAction: Date
    public private(set) var backToWork = 0
    public private(set) var answered = 0
    public private(set) var closed = 0
    public private(set) var outcome: Outcome?
    public private(set) var ended: Date?
    public private(set) var clearBonus = 0
    public private(set) var timeBonus = 0
    /// Each session's status at the last snapshot, by `machine/terminal`. A session whose machine
    /// stopped answering keeps the status it had, so that it still counts as astray.
    private var statuses: [String: Seen]
    /// When you last typed into each session, by `machine/terminal`.
    private var touched: [String: Date] = [:]

    private struct Seen: Codable, Equatable, Sendable {
        var status: String?
        var title: String
    }

    /// A game that starts with the queue as it is now.
    public init(rows: [QueueRow], at now: Date) {
        started = now
        lastAction = now
        statuses = [:]
        for row in rows where row.kind == .session {
            if let session = row.session { statuses[Herd.key(session)] = Seen(status: row.status, title: row.title) }
        }
    }

    public var isOver: Bool { outcome != nil }
    /// When the game ends unless you do something.
    public var deadline: Date { lastAction.addingTimeInterval(Self.patience) }

    /// The sessions astray, in the order to deal with them, counting those whose machine stopped
    /// answering while astray.
    public func strays(in rows: [QueueRow]) -> [QueueRow] {
        Herd.strays(in: rows.map { row in
            guard row.kind == .session, row.status == "stale", let session = row.session,
                  let seen = statuses[Herd.key(session)], Herd.stray(status: seen.status) != nil else { return row }
            return QueueRow(id: row.id, kind: row.kind, session: row.session, number: row.number, depth: row.depth, title: row.title,
                            summary: row.summary, agent: row.agent, machine: row.machine, status: seen.status, needsYou: row.needsYou,
                            panes: row.panes, tree: row.tree, inGroup: row.inGroup, inProject: row.inProject, resources: row.resources)
        })
    }

    /// You typed into a session from the phone: what it does next scores, and the countdown starts again.
    public mutating func touch(_ session: RemoteSessionID, at now: Date) {
        guard !isOver else { return }
        touched[Herd.key(session)] = now
        lastAction = max(lastAction, now)
    }

    /// Stops the clock for a while, such as while the phone can't reach the Mac: you can't do
    /// anything then, so the time doesn't count.
    public mutating func hold(for seconds: TimeInterval) {
        guard !isOver, seconds > 0 else { return }
        started.addTimeInterval(seconds)
        lastAction.addTimeInterval(seconds)
    }

    /// Ends the game when the countdown ran out. Returns the event when it did.
    public mutating func expire(at now: Date) -> HerdEvent? {
        guard !isOver, now >= deadline else { return nil }
        outcome = .timeUp
        ended = deadline
        return HerdEvent(kind: .timeUp, title: "", points: 0)
    }

    public mutating func giveUp(at now: Date) {
        guard !isOver else { return }
        outcome = .gaveUp
        ended = now
    }

    /// Scores what changed since the last snapshot, and wins the game once nothing is astray.
    public mutating func observe(_ rows: [QueueRow], at now: Date) -> [HerdEvent] {
        if let timeUp = expire(at: now) { return [timeUp] }
        guard !isOver else { return [] }
        touched = touched.filter { now.timeIntervalSince($0.value) <= Self.touchWindow }
        var current: [String: QueueRow] = [:]
        for row in rows where row.kind == .session {
            if let session = row.session { current[Herd.key(session)] = row }
        }
        var events: [HerdEvent] = []

        for (key, row) in current.sorted(by: { $0.key < $1.key }) {
            let before = statuses[key]
            if row.status == "stale" { continue }
            defer { statuses[key] = Seen(status: row.status, title: row.title) }
            let was = before.flatMap { Herd.stray(status: $0.status) }
            if Herd.stray(row) != nil, was == nil {
                events.append(HerdEvent(kind: .strayed, title: row.title, points: 0))
            }
            guard let before, before.status != row.status, let was, touched[key] != nil else { continue }
            if was == .needsYou, row.status != "needsYou" {
                events.append(score(.answered, Points.answered, row.title, key, at: now))
            } else if Herd.isMoving(row.status) {
                events.append(score(.backToWork, Points.backToWork, row.title, key, at: now))
            }
        }

        for (key, before) in statuses.sorted(by: { $0.key < $1.key }) where current[key] == nil {
            statuses[key] = nil
            guard let was = Herd.stray(status: before.status), touched[key] != nil else { continue }
            // Closing a session that still needed you clears it, but only finished work scores.
            events.append(score(.closed, was == .needsYou ? 0 : Points.closed, before.title, key, at: now))
        }

        if strays(in: rows).isEmpty {
            outcome = .cleared
            ended = now
            clearBonus = Points.cleared
            timeBonus = max(0, 30 - Int(now.timeIntervalSince(started) / 60)) * Points.perMinuteLeft
            score += clearBonus + timeBonus
            events.append(HerdEvent(kind: .cleared, title: "", points: clearBonus + timeBonus))
        }
        return events
    }

    private mutating func score(_ kind: HerdEvent.Kind, _ base: Int, _ title: String, _ key: String, at now: Date) -> HerdEvent {
        touched[key] = nil
        lastAction = max(lastAction, now)
        switch kind {
        case .backToWork: backToWork += 1
        case .answered: answered += 1
        case .closed: closed += 1
        default: break
        }
        guard base > 0 else { return HerdEvent(kind: kind, title: title, points: 0) }
        if let lastScored, now.timeIntervalSince(lastScored) <= Self.comboWindow {
            combo = min(combo + 1, Self.maxCombo)
        } else {
            combo = 1
        }
        lastScored = now
        let points = base * combo
        score += points
        return HerdEvent(kind: kind, title: title, points: points, combo: combo)
    }
}

/// An entry in the table of the ten best scores.
public struct HerdScore: Codable, Equatable, Sendable {
    /// Three letters, as an arcade's table takes them.
    public let initials: String
    public let score: Int
    /// When it was made; nil for the table's starting entries.
    public let date: Date?

    public init(initials: String, score: Int, date: Date? = nil) {
        self.initials = initials
        self.score = score
        self.date = date
    }
}

public enum HerdScores {
    public static let size = 10
    /// The letters an initial can be, in the order the arrows go through them.
    public static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789. ")

    /// The table before anyone plays, to have something to beat.
    public static let starting: [HerdScore] = [
        ("DOG", 3000), ("BAA", 2500), ("TTY", 2000), ("SSH", 1500), ("GIT", 1200),
        ("CLI", 1000), ("ZZZ", 800), ("ACK", 600), ("NOP", 400), ("EOF", 200)
    ].map { HerdScore(initials: $0.0, score: $0.1) }

    /// Where a score would go in the table, or nil when it doesn't make it. A score that ties
    /// goes under the ones already there.
    public static func rank(of score: Int, in table: [HerdScore]) -> Int? {
        guard score > 0 else { return nil }
        let index = table.firstIndex { $0.score < score } ?? table.count
        return index < size ? index : nil
    }

    /// The table with the entry in its place, and that place; the table as it was when the score
    /// doesn't make it.
    public static func inserting(_ entry: HerdScore, into table: [HerdScore]) -> (table: [HerdScore], rank: Int?) {
        guard let rank = rank(of: entry.score, in: table) else { return (table, nil) }
        var table = table
        table.insert(HerdScore(initials: initials(entry.initials), score: entry.score, date: entry.date), at: rank)
        return (Array(table.prefix(size)), rank)
    }

    /// Three letters from the alphabet, uppercase, padded with spaces.
    public static func initials(_ text: String) -> String {
        let letters = text.uppercased().map { alphabet.contains($0) ? $0 : " " }
        return String((letters + Array(repeating: " ", count: 3)).prefix(3))
    }
}
