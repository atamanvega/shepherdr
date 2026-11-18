import Foundation
import Testing
@testable import ShepherdrCore

@Suite struct RestartCheckTests {
    private let box = Machine(profileID: "box", name: "buildbox", target: "box", session: "agents", isEnabled: true)

    private func agent(_ name: String, kind: String, conversation: String? = nil) -> Agent {
        Agent(id: .init(machineID: box.id, terminalID: "term-\(name)"), name: name, kind: kind, state: .idle, reportedState: "idle",
              workspaceID: "w1", workspaceName: name, tabID: "w1:t1", tabName: "1", paneID: "w1:p1", directory: nil, project: nil,
              summary: nil, isLaunchPending: false, conversation: conversation)
    }

    @Test func aLinuxMachineSaysWhatItHas() throws {
        let readiness = try RestartCheck.parse("""
        Welcome to buildbox
        shepherdr-restarts 1
        system Linux
        agent claude
        agent codex
        integration claude current
        integration codex not installed
        integration pi not installed
        python3 yes
        codex-daemon true
        service enabled agents herdr-agents.service
        service disabled default herdr.service
        linger no
        shepherdr-restarts end
        """)
        #expect(readiness.system == "Linux")
        #expect(readiness.agents == ["claude": .current, "codex": .missing])
        #expect(readiness.hasPython == true && readiness.codexSharesServer == true && readiness.lingers == false)
        #expect(readiness.startsHerdr(session: "agents") && !readiness.startsHerdr(session: "default"))
        // An integration for an agent the machine doesn't have counts for nothing.
        let bare = try RestartCheck.parse("shepherdr-restarts 1\nsystem Darwin\nintegration claude current\nshepherdr-restarts end")
        #expect(bare.agents.isEmpty && bare.isMac)
        #expect(throws: HerdrFailure.self) { try RestartCheck.parse("shepherdr-restarts 1\nsystem Linux") }
    }

    @Test func findingsSayWhatARestartCostsAndOfferWhatShepherdrCanDo() throws {
        let readiness = try RestartCheck.parse("""
        shepherdr-restarts 1
        system Linux
        agent claude
        agent codex
        integration claude current
        integration codex outdated
        python3 yes
        codex-daemon true
        linger unknown
        shepherdr-restarts end
        """)
        let sessions = [agent("planner", kind: "claude", conversation: "claude:1"), agent("fixer", kind: "codex"),
                        agent("notes", kind: "opencode")]
        let findings = RestartCheck.findings(readiness, machine: box, herdrVersion: "0.9.2", sessions: sessions)
        #expect(findings.map(\.id) == ["integration-claude", "herdr", "integration-codex", "codex-server", "service", "unrecorded"])
        #expect(findings.first?.isReady == true)
        #expect(findings.first { $0.id == "integration-codex" }?.fix == .installIntegration("codex"))
        #expect(findings.first { $0.id == "codex-server" }?.fix == .stopCodexSharedServer)
        #expect(findings.first { $0.id == "service" }?.fix == .startAtBoot(session: "agents"))
        // Only agents Herdr resumes count, and only those without a conversation.
        #expect(findings.last?.text.hasPrefix("1 session would come back as a shell") == true)
        #expect(findings.last?.text.contains("fixer") == true)

        // Up to date, started with the machine, and every conversation recorded: all is ready.
        var ready = readiness
        ready.agents = ["claude": .current]
        ready.codexSharesServer = false
        ready.services = [.init(name: "herdr-agents.service", session: "agents", isEnabled: true)]
        ready.lingers = true
        let allReady = RestartCheck.findings(ready, machine: box, herdrVersion: "0.9.5", sessions: [sessions[0]]).allSatisfy(\.isReady)
        #expect(allReady)
        // Started only once you log in.
        ready.lingers = false
        #expect(RestartCheck.findings(ready, machine: box, herdrVersion: "0.9.5", sessions: []).first { $0.id == "service" }?.hint != nil)
    }

    @Test func fixesRunFixedScriptsWithTheirOneArgument() {
        let install = RestartCheck.fixScript(.installIntegration("claude"))
        #expect(install.arguments == ["claude"] && install.script.contains("integration install \"$1\""))
        #expect(RestartCheck.fixScript(.stopCodexSharedServer).script.contains("features disable daemon_auto_start"))
        let boot = RestartCheck.fixScript(.startAtBoot(session: "agents"))
        #expect(boot.arguments == ["agents"])
        // Set up for the next start: the server running now is left alone.
        #expect(boot.script.contains("systemctl --user enable \"$name\"") && !boot.script.contains("--now"))
        #expect(!boot.script.contains("launchctl"))
    }

    @Test func theServiceScriptWritesAUnitForTheSession() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("restart-\(UUID().uuidString)")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        // Stand-ins, so the script runs as on Linux without touching this Mac.
        for (tool, body) in [("herdr", "exit 0"), ("uname", "echo Linux"), ("systemctl", "echo \"$@\" >> \"$HOME/systemctl.log\""),
                             ("loginctl", "case $1 in show-user) echo no ;; enable-linger) exit 1 ;; esac"), ("id", "echo dev")] {
            let file = bin.appendingPathComponent(tool)
            try "#!/bin/sh\n\(body)\n".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", RestartCheck.startAtBootScript, "sh", "agents"]
        process.environment = ["HOME": home.path, "PATH": "\(bin.path):/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(said.contains("sudo loginctl enable-linger dev"))
        let unit = try String(contentsOf: home.appendingPathComponent(".config/systemd/user/herdr-agents.service"), encoding: .utf8)
        #expect(unit.contains("Environment=HERDR_SESSION=agents"))
        #expect(unit.contains("Environment=LANG=C.UTF-8"))
        #expect(unit.contains("ExecStart=\"\(bin.path)/herdr\" server"))
        #expect(unit.contains("Environment=\"PATH=\(bin.path):"))
        let calls = try String(contentsOf: home.appendingPathComponent("systemctl.log"), encoding: .utf8)
        #expect(calls == "--user daemon-reload\n--user enable herdr-agents.service\n")
        // A session name that isn't one is refused before anything is written.
        let refused = Process()
        refused.executableURL = URL(fileURLWithPath: "/bin/sh")
        refused.arguments = ["-c", RestartCheck.startAtBootScript, "sh", "a b;rm"]
        refused.environment = ["HOME": home.path, "PATH": "\(bin.path):/usr/bin:/bin"]
        refused.standardError = Pipe()
        try refused.run()
        refused.waitUntilExit()
        #expect(refused.terminationStatus == 2)
    }
}

struct HerdrReleaseTests {
    @Test func machinesBehindTheRecommendedReleaseAreAskedToUpdate() {
        #expect(HerdrRelease.isBehind("0.9.2") && HerdrRelease.isBehind("0.9.4") && HerdrRelease.isBehind("v0.8.9"))
        #expect(!HerdrRelease.isBehind("0.9.5") && !HerdrRelease.isBehind("0.10.0"))
        // A version Shepherdr can't read, or none, isn't asked about.
        #expect(!HerdrRelease.isBehind("nightly") && !HerdrRelease.isBehind(nil))
        #expect(HerdrRelease.summary([(name: "This Mac", version: "0.9.3"), (name: "buildbox", version: "0.9.2")])
                == "This Mac runs 0.9.3, buildbox 0.9.2")
    }
}
