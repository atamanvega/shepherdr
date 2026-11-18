import Foundation

/// Each machine's sessions as Shepherdr last saw them, kept across launches: when Herdr restarts
/// on a machine, even while Shepherdr isn't running, its sessions come back in new terminals, and
/// these tell which old session each new terminal carries on.
@MainActor
public final class SessionFootprintStore {
    /// By machine ID, then terminal ID.
    public private(set) var footprints: [String: [String: SessionFootprint]]
    /// The machines Shepherdr had seen sessions of before this launch. One it hadn't, it may know
    /// from the state file it left there before losing its settings, or another Mac's.
    public let knownAtLaunch: Set<String>
    private let defaults: UserDefaults
    /// When each machine started showing no sessions at all.
    private var emptySince: [String: Date] = [:]
    static let storageKey = "sessionFootprints.v1"
    /// Herdr answers a moment before it has restored its sessions; a machine that shows none for
    /// longer has none.
    static let emptyPatience: TimeInterval = 60

    private struct Record: Codable {
        let machineID: String
        let terminalID: String
        let footprint: SessionFootprint
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let records = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
        var footprints: [String: [String: SessionFootprint]] = [:]
        for record in records { footprints[record.machineID, default: [:]][record.terminalID] = record.footprint }
        self.footprints = footprints
        knownAtLaunch = Set(footprints.keys)
    }

    /// Notes the sessions of each machine that answered, and returns those that came back in new
    /// terminals, each with its new ID. A machine that shows no sessions at all, as while its Herdr
    /// starts, is passed over until it shows some, or for a minute.
    public func observe(_ machines: [MachineState], now date: Date = Date()) -> [Agent.ID: Agent.ID] {
        var moves: [Agent.ID: Agent.ID] = [:]
        var changed = false
        for state in machines where state.connection == .online {
            guard let panes = state.snapshot?.panes else { continue }
            guard !panes.isEmpty else {
                let since = emptySince[state.id] ?? date
                emptySince[state.id] = since
                if date.timeIntervalSince(since) >= Self.emptyPatience, footprints.removeValue(forKey: state.id) != nil { changed = true }
                continue
            }
            emptySince[state.id] = nil
            let now = Dictionary(panes.map { ($0.terminalID, SessionFootprint($0)) }, uniquingKeysWith: { first, _ in first })
            let before = footprints[state.id] ?? [:]
            guard now != before else { continue }
            for (old, new) in SessionRebinding.moves(from: before, to: now) {
                moves[Agent.ID(machineID: state.id, terminalID: old)] = Agent.ID(machineID: state.id, terminalID: new)
            }
            footprints[state.id] = now
            changed = true
        }
        if changed { save() }
        return moves
    }

    private func save() {
        // Pane IDs, workspace names and conversation IDs only, like the rest of what's kept by session.
        let records = footprints.keys.sorted().flatMap { machineID in
            (footprints[machineID] ?? [:]).keys.sorted().map { terminalID in
                Record(machineID: machineID, terminalID: terminalID, footprint: footprints[machineID]![terminalID]!)
            }
        }
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.storageKey) }
    }
}
