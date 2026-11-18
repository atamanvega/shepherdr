import Foundation

/// Who waits for whom among a machine's sessions, as one Shepherdr knows it, kept on that machine
/// in `~/.shepherdr/state/<instance>`. Sessions go by their footprints, which outlast a restart of
/// Herdr, so a Shepherdr that has no record of them, such as on a new Mac or after losing its
/// settings, takes the holds from there.
public struct SessionStateFile: Codable, Equatable, Sendable {
    public struct Session: Codable, Hashable, Sendable {
        /// `here` for the machine the file is on; any other by its name in the machine lists.
        public var machine: String
        public var pane: String
        public var workspace: String
        public var conversation: String?
        /// How far along the hold on this session is, for a session waited for.
        public var phase: HoldPhase?

        var footprint: SessionFootprint { SessionFootprint(paneID: pane, workspaceName: workspace, conversation: conversation) }
    }

    public struct Wait: Codable, Equatable, Sendable {
        public var session: Session
        public var waitsFor: [Session]
    }

    public static let here = "here"
    public var version = 1
    /// The Shepherdr that wrote it, and the Mac it runs on.
    public var instance: String
    public var mac: String
    public var waits: [Wait]

    /// The holds of the sessions on `machineID`, as footprints, from each machine's footprints and
    /// names by machine ID. Holds on sessions it has no footprint or name for are left out.
    public static func make(holds: [Agent.ID: [Hold]], on machineID: String, footprints: [String: [String: SessionFootprint]],
                            names: [String: String], instance: String, mac: String) -> SessionStateFile {
        func described(_ id: Agent.ID, phase: HoldPhase? = nil) -> Session? {
            guard let footprint = footprints[id.machineID]?[id.terminalID],
                  let machine = id.machineID == machineID ? here : names[id.machineID] else { return nil }
            return Session(machine: machine, pane: footprint.paneID, workspace: footprint.workspaceName,
                           conversation: footprint.conversation, phase: phase)
        }
        let waits = holds.compactMap { waiter, list -> Wait? in
            guard waiter.machineID == machineID, let session = described(waiter) else { return nil }
            let awaited = list.compactMap { described($0.awaited, phase: $0.phase) }
            return awaited.isEmpty ? nil : Wait(session: session, waitsFor: awaited)
        }.sorted { ($0.session.workspace, $0.session.pane) < ($1.session.workspace, $1.session.pane) }
        return SessionStateFile(instance: instance, mac: mac, waits: waits)
    }

    /// The holds it records, onto the sessions each machine shows now (`footprints`, by machine ID
    /// and terminal ID), with machine IDs by name. Sessions that can't be told apart are left out.
    public func holds(on machineID: String, footprints: [String: [String: SessionFootprint]],
                      machines: [String: String]) -> [Agent.ID: [Hold]] {
        func machine(of session: Session) -> String? { session.machine == Self.here ? machineID : machines[session.machine] }
        var wanted: [String: Set<SessionFootprint>] = [:]
        for wait in waits {
            for session in [wait.session] + wait.waitsFor {
                if let id = machine(of: session) { wanted[id, default: []].insert(session.footprint) }
            }
        }
        // Each recorded session is matched as if it had left a terminal of its own.
        var found: [String: [SessionFootprint: String]] = [:]
        for (id, prints) in wanted {
            let recorded = Dictionary(uniqueKeysWithValues: prints.enumerated().map { ("recorded-\($0.offset)", $0.element) })
            for (key, terminal) in SessionRebinding.moves(from: recorded, to: footprints[id] ?? [:]) {
                found[id, default: [:]][recorded[key]!] = terminal
            }
        }
        func current(_ session: Session) -> Agent.ID? {
            guard let id = machine(of: session), let terminal = found[id]?[session.footprint] else { return nil }
            return Agent.ID(machineID: id, terminalID: terminal)
        }
        var holds: [Agent.ID: [Hold]] = [:]
        for wait in waits {
            guard let waiter = current(wait.session), waiter.machineID == machineID else { continue }
            let list = wait.waitsFor.compactMap { session in current(session).map { Hold(awaited: $0, phase: session.phase ?? .pending) } }
            if !list.isEmpty { holds[waiter] = list }
        }
        return holds
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data()
    }
}
