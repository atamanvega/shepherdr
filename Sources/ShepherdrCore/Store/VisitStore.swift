import Foundation
import Observation

/// When you last looked at each session, and at Compass: the quick switcher (⌘T) offers what you
/// saw last first. Identifiers and times only, saved on this Mac like priorities.
@MainActor @Observable
public final class VisitStore {
    /// Somewhere ⌘T can take you.
    public enum Place: Hashable, Codable, Sendable {
        case session(Agent.ID)
        case compass
    }

    public private(set) var visits: [Place: Date]
    @ObservationIgnored private let defaults: UserDefaults
    static let storageKey = "visits.v1"
    /// Older visits are forgotten beyond this many places.
    static let limit = 200

    private struct Record: Codable {
        let place: Place
        let date: Date
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let records = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
        visits = Dictionary(records.map { ($0.place, $0.date) }, uniquingKeysWith: max)
    }

    public func record(_ place: Place, at date: Date = Date()) {
        visits[place] = date
        if visits.count > Self.limit {
            let kept = visits.sorted { $0.value > $1.value }.prefix(Self.limit)
            visits = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        save()
    }

    /// Visits to sessions that came back in new terminals, as after their machine's Herdr
    /// restarted, count for the new terminals.
    public func rebind(_ moves: [Agent.ID: Agent.ID]) {
        var changed = false
        for (old, new) in moves {
            guard let date = visits.removeValue(forKey: .session(old)) else { continue }
            visits[.session(new)] = max(date, visits[.session(new)] ?? .distantPast)
            changed = true
        }
        if changed { save() }
    }

    private func save() {
        let records = visits.map { Record(place: $0.key, date: $0.value) }
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.storageKey) }
    }

    /// The places given, the one visited most recently first, without the one you're on. Places
    /// never visited follow in the order given.
    public func recentFirst<Item>(_ items: [Item], place: (Item) -> Place, excluding current: Place?) -> [Item] {
        items.enumerated()
            .filter { place($0.element) != current }
            .sorted { lhs, rhs in
                switch (visits[place(lhs.element)], visits[place(rhs.element)]) {
                case let (left?, right?): left != right ? left > right : lhs.offset < rhs.offset
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}
