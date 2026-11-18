import Foundation

/// What tells a session apart once its terminal has a new ID, as after its machine's Herdr restarts:
/// Herdr brings each pane back in its workspace with the same pane ID, and resumes the agent's own
/// conversation in it, but in a new terminal.
public struct SessionFootprint: Codable, Hashable, Sendable {
    public let paneID: String
    public let workspaceName: String
    /// The agent's conversation, such as `claude:<session ID>`, when Herdr knows it.
    public let conversation: String?

    public init(paneID: String, workspaceName: String, conversation: String? = nil) {
        self.paneID = paneID
        self.workspaceName = workspaceName
        self.conversation = conversation
    }

    public init(_ pane: TerminalPane) {
        self.init(paneID: pane.paneID, workspaceName: pane.workspaceName, conversation: pane.conversation)
    }
}

/// Finds the sessions of a machine that came back in new terminals, so what Shepherdr kept for
/// them moves along instead of being dropped as closed.
public enum SessionRebinding {
    /// Each terminal that left, by ID, with the one its session came back in, from the machine's
    /// sessions as last seen (`before`) and as it shows them now, both by terminal ID.
    ///
    /// - A conversation that left one terminal and is in one new terminal moved there, as when
    ///   Herdr resumed it after a restart or you resumed it in another pane.
    /// - Once none of the terminals last seen is left, Herdr restarted: a session is the one in
    ///   the same pane of the same workspace.
    ///
    /// Anything two sessions share on either side matches nothing.
    public static func moves(from before: [String: SessionFootprint], to now: [String: SessionFootprint]) -> [String: String] {
        var gone = before.filter { now[$0.key] == nil }
        var fresh = now.filter { before[$0.key] == nil }
        guard !gone.isEmpty, !fresh.isEmpty else { return [:] }
        let restarted = gone.count == before.count
        var moves: [String: String] = [:]
        func pair(by key: (SessionFootprint) -> String?) {
            let left = unique(gone, key), right = unique(fresh, key)
            for (value, old) in left {
                guard let new = right[value] else { continue }
                // A conversation each side knows, and they differ: not the same session.
                if let was = gone[old]?.conversation, let isNow = fresh[new]?.conversation, was != isNow { continue }
                moves[old] = new
                gone[old] = nil
                fresh[new] = nil
            }
        }
        pair { $0.conversation }
        if restarted { pair { "\($0.workspaceName)\u{0}\($0.paneID)" } }
        return moves
    }

    /// Each value of `key` that exactly one terminal has, with that terminal.
    private static func unique(_ footprints: [String: SessionFootprint], _ key: (SessionFootprint) -> String?) -> [String: String] {
        var found: [String: String] = [:]
        var shared = Set<String>()
        for (terminal, footprint) in footprints {
            guard let value = key(footprint) else { continue }
            if found.updateValue(terminal, forKey: value) != nil { shared.insert(value) }
        }
        for value in shared { found[value] = nil }
        return found
    }
}
