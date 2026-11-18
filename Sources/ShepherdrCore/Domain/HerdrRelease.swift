import Foundation

/// The Herdr release Shepherdr asks every machine to run.
public enum HerdrRelease {
    /// 0.9.4 keeps agents' sessions when a Mac restarts and writes its saves whole; 0.9.5 shows
    /// Claude Code's questions as blocked in named sessions and drops the Codex hooks that warned
    /// at every start.
    public static let recommended = AppVersion("0.9.5")!
    public static let notes = URL(string: "https://github.com/herdrdev/herdr/releases")!

    /// Whether a Herdr server of this version should be updated. An unknown version isn't asked.
    public static func isBehind(_ version: String?) -> Bool {
        guard let version, let parsed = AppVersion(version) else { return false }
        return parsed < recommended
    }

    /// `This Mac runs 0.9.3, buildbox 0.9.2`: the machines that should update, from the names and
    /// versions given.
    public static func summary(_ machines: [(name: String, version: String)]) -> String {
        machines.enumerated().map { index, machine in
            index == 0 ? "\(machine.name) runs \(machine.version)" : "\(machine.name) \(machine.version)"
        }.joined(separator: ", ")
    }
}
