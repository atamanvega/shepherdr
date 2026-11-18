import Foundation
import Testing
@testable import ShepherdrCore

@Suite @MainActor struct SessionRebindingTests {
    private func footprint(_ pane: String, _ workspace: String = "Orchard", _ conversation: String? = nil) -> SessionFootprint {
        SessionFootprint(paneID: pane, workspaceName: workspace, conversation: conversation)
    }

    private func defaults() -> UserDefaults {
        let name = "rebinding-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func machine(_ id: String?, online: Bool = true, panes: [(terminal: String, pane: String, workspace: String, conversation: String?)]) -> MachineState {
        var state = MachineState(machine: Machine(profileID: id, name: id ?? "Local", target: id, session: "default", isEnabled: true))
        state.connection = online ? .online : .notRunning
        state.snapshot = MachineSnapshot(version: "0.9.3", protocolVersion: 22, workspaces: [], agents: [], panes: panes.map {
            var pane = TerminalPane(terminalID: $0.terminal, paneID: $0.pane, workspaceID: String($0.pane.prefix { $0 != ":" }),
                                    tabID: "t", workspaceName: $0.workspace, title: "", directory: nil)
            pane.conversation = $0.conversation
            return pane
        })
        return state
    }

    // MARK: Matching

    @Test func afterARestartEachPaneCarriesOnItsSession() {
        let before = ["term-a": footprint("w1:p1", "Orchard", "claude:1"), "term-b": footprint("w1:p2"), "term-c": footprint("w2:p1", "Review")]
        let after = ["term-x": footprint("w1:p1", "Orchard", "claude:1"), "term-y": footprint("w1:p2"), "term-z": footprint("w2:p1", "Review")]
        #expect(SessionRebinding.moves(from: before, to: after) == ["term-a": "term-x", "term-b": "term-y", "term-c": "term-z"])
        // Herdr resumes a conversation before its agent says so again: the pane is enough.
        #expect(SessionRebinding.moves(from: ["term-a": footprint("w1:p1", "Orchard", "claude:1")], to: ["term-x": footprint("w1:p1")])
            == ["term-a": "term-x"])
    }

    @Test func whileOtherSessionsStayAPaneIsNotEnough() {
        // A new pane where one closed is a new session, unless it carries on the same conversation.
        let before = ["term-a": footprint("w1:p1"), "term-b": footprint("w1:p2", "Orchard", "codex:7"), "term-c": footprint("w2:p1")]
        let after = ["term-c": footprint("w2:p1"), "term-x": footprint("w1:p1"), "term-y": footprint("w3:p1", "Elsewhere", "codex:7")]
        #expect(SessionRebinding.moves(from: before, to: after) == ["term-b": "term-y"])
    }

    @Test func whatTwoSessionsShareOrDisagreeOnMatchesNothing() {
        // Two panes report one conversation, as a shared Codex server can make them: neither is trusted.
        let shared = ["term-a": footprint("w1:p1", "A", "codex:1"), "term-b": footprint("w1:p2", "B", "codex:1")]
        let again = ["term-x": footprint("w5:p1", "C", "codex:1"), "term-y": footprint("w6:p1", "D")]
        #expect(SessionRebinding.moves(from: shared, to: again).isEmpty)
        // The same pane with another conversation is another session.
        #expect(SessionRebinding.moves(from: ["term-a": footprint("w1:p1", "A", "claude:1")], to: ["term-x": footprint("w1:p1", "A", "claude:2")]).isEmpty)
        // Nor does a pane of a workspace that came back under another name.
        #expect(SessionRebinding.moves(from: ["term-a": footprint("w1:p1", "A")], to: ["term-x": footprint("w1:p1", "B")]).isEmpty)
        #expect(SessionRebinding.moves(from: [:], to: ["term-x": footprint("w1:p1")]).isEmpty)
    }

    @Test func footprintsAreKeptAcrossLaunchesAndWaitForSessions() {
        let defaults = defaults()
        let store = SessionFootprintStore(defaults: defaults)
        let box = "remote:box"
        #expect(store.observe([machine("box", panes: [("term-a", "w1:p1", "Orchard", "claude:1"), ("term-b", "w1:p2", "Orchard", nil)])]).isEmpty)

        // Shepherdr quits; meanwhile Herdr restarts on the machine. Starting, it shows nothing yet.
        let relaunched = SessionFootprintStore(defaults: defaults)
        #expect(relaunched.observe([machine("box", panes: [])]).isEmpty)
        // A machine that doesn't answer shows its old sessions, which mean nothing.
        #expect(relaunched.observe([machine("box", online: false, panes: [("term-x", "w1:p1", "Orchard", nil)])]).isEmpty)
        let moves = relaunched.observe([machine("box", panes: [("term-x", "w1:p1", "Orchard", "claude:1"), ("term-y", "w1:p2", "Orchard", nil)])])
        #expect(moves == [Agent.ID(machineID: box, terminalID: "term-a"): Agent.ID(machineID: box, terminalID: "term-x"),
                          Agent.ID(machineID: box, terminalID: "term-b"): Agent.ID(machineID: box, terminalID: "term-y")])
        // Once seen, the new terminals are what the machine is compared with.
        #expect(relaunched.observe([machine("box", panes: [("term-x", "w1:p1", "Orchard", "claude:1"), ("term-y", "w1:p2", "Orchard", nil)])]).isEmpty)
        #expect(SessionFootprintStore(defaults: defaults).footprints[box]?.keys.sorted() == ["term-x", "term-y"])

        // A machine left with no sessions for a minute has none: a new one there is new.
        let start = Date()
        #expect(relaunched.observe([machine("box", panes: [])], now: start).isEmpty)
        #expect(relaunched.footprints[box] != nil)
        #expect(relaunched.observe([machine("box", panes: [])], now: start + 60).isEmpty)
        #expect(relaunched.footprints[box] == nil)
        #expect(relaunched.observe([machine("box", panes: [("term-n", "w1:p1", "Orchard", nil)])]).isEmpty)
    }

    // MARK: What moves along

    @Test func holdsFollowTheirSessionsAndAreWrittenToHerdrAgain() {
        let defaults = defaults()
        let store = SessionRelationStore(defaults: defaults)
        func id(_ terminal: String, _ machine: String = "remote:box") -> Agent.ID { Agent.ID(machineID: machine, terminalID: terminal) }
        let planner = id("term-a"), worker = id("term-b"), local = id("term-l", "local")
        store.setWaiting(planner, for: worker, true)
        store.setHolds([Hold(awaited: worker, phase: .started)], for: planner)
        store.setWaiting(local, for: planner, true)
        store.setCollapsed(planner, true)
        store.markSynced(planner)
        store.markSynced(local)
        var changes = 0
        store.onChange = { changes += 1 }

        store.rebind([planner: id("term-x"), worker: id("term-y")])
        #expect(store.holds == [id("term-x"): [Hold(awaited: id("term-y"), phase: .started)], local: [Hold(awaited: id("term-x"))]])
        #expect(store.isCollapsed(id("term-x")))
        // Their tokens went with the old panes: both waiting sessions are written to Herdr again.
        #expect(store.unsynced == [id("term-x"), local])
        #expect(changes == 1)
        #expect(SessionRelationStore(defaults: defaults).holds == store.holds)

        // Nothing to move changes nothing.
        store.rebind([id("term-q"): id("term-r")])
        #expect(changes == 1)
    }

    @Test func sessionsGoBackToTheirPlaceInTheQueue() {
        let defaults = defaults()
        let store = SessionOrderStore(defaults: defaults)
        func id(_ terminal: String) -> Agent.ID { Agent.ID(machineID: "remote:box", terminalID: terminal) }
        store.synchronize(with: [id("term-a"), id("term-b"), id("term-c")])
        _ = store.createGroup(named: "Release", with: id("term-b"))
        // The restored terminals were noticed first, at the end.
        store.synchronize(with: [id("term-x"), id("term-y")])

        store.rebind([id("term-a"): id("term-x"), id("term-b"): id("term-y")])
        #expect(store.orderedIDs == [id("term-x"), id("term-y"), id("term-c")])
        #expect(store.group(containing: id("term-y"))?.name == "Release")
        #expect(SessionOrderStore(defaults: defaults).orderedIDs == store.orderedIDs)
    }

    @Test func pagesVisitsAndMailFollowTheirSessions() {
        let defaults = defaults()
        let old = Agent.ID(machineID: "remote:box", terminalID: "term-a"), new = Agent.ID(machineID: "remote:box", terminalID: "term-x")
        let other = Agent.ID(machineID: "local", terminalID: "term-l")

        let states = SessionStateStore(defaults: defaults)
        var state = SessionStateStore.State()
        state.tabs = [URL(string: "https://github.com/theam/shepherdr/pull/30")!]
        states.set(state, for: old)
        states.lastSelection = old
        states.rebind([old: new])
        #expect(states.state(for: new) == state && states.state(for: old) == .init())
        #expect(states.lastSelection == new)

        let visits = VisitStore(defaults: defaults)
        visits.record(.session(old), at: Date(timeIntervalSince1970: 100))
        visits.rebind([old: new])
        #expect(VisitStore(defaults: defaults).visits == [.session(new): Date(timeIntervalSince1970: 100)])

        let mail = MailStore(defaults: defaults)
        mail.add(MailItem(id: "remote:box/1/0", letterID: "20261103T101502Z-7f3a9c", kind: .handoff, origin: "remote:box",
                          originName: "box", sender: old, senderName: "fixer", recipient: other, status: .queued, received: Date(),
                          folder: "/x", headline: nil, hasMessage: true, files: [], addressedTo: nil))
        mail.add(MailItem(id: "local/2/0", letterID: "20261103T101503Z-7f3a9d", kind: .handoff, origin: "local",
                          originName: "Local", sender: other, senderName: "lead", recipient: old, status: .queued, received: Date(),
                          folder: "/y", headline: nil, hasMessage: true, files: [], addressedTo: nil))
        mail.rebind([old: new])
        #expect(MailStore(defaults: defaults).items.map { [$0.sender, $0.recipient] } == [[new, other], [other, new]])
    }

    // MARK: State files

    @Test func stateFilesBringHoldsBackOntoSessionsHerdrRestored() throws {
        let box = "remote:box", here = "local"
        let footprints = ["remote:box": ["term-a": footprint("w1:p1", "planner", "claude:1"), "term-b": footprint("w2:p1", "worker")],
                          here: ["term-l": footprint("w1:p1", "notes", "codex:9")]]
        let holds: [Agent.ID: [Hold]] = [
            Agent.ID(machineID: box, terminalID: "term-a"): [Hold(awaited: Agent.ID(machineID: box, terminalID: "term-b"), phase: .started),
                                                            Hold(awaited: Agent.ID(machineID: here, terminalID: "term-l"))],
            // Waiting on this Mac, not on the machine the file is for.
            Agent.ID(machineID: here, terminalID: "term-l"): [Hold(awaited: Agent.ID(machineID: box, terminalID: "term-a"))],
        ]
        let file = SessionStateFile.make(holds: holds, on: box, footprints: footprints, names: [box: "box", here: "Studio"],
                                         instance: "0123456789ab", mac: "Studio")
        #expect(file.waits.count == 1)
        #expect(file.waits[0].waitsFor.map(\.machine) == ["here", "Studio"])
        let decoded = try JSONDecoder().decode(SessionStateFile.self, from: file.encoded())
        #expect(decoded == file)

        // Herdr restarted on the box: the same sessions, in new terminals.
        let now = ["remote:box": ["term-x": footprint("w1:p1", "planner", "claude:1"), "term-y": footprint("w2:p1", "worker"),
                                  "term-z": footprint("w3:p1", "other")],
                   here: ["term-l": footprint("w1:p1", "notes", "codex:9")]]
        let restored = decoded.holds(on: box, footprints: now, machines: ["Studio": here, "box": box])
        #expect(restored == [Agent.ID(machineID: box, terminalID: "term-x"): [
            Hold(awaited: Agent.ID(machineID: box, terminalID: "term-y"), phase: .started),
            Hold(awaited: Agent.ID(machineID: here, terminalID: "term-l"))]])
        // A machine it can't name, or a session it can't find, is left out.
        #expect(decoded.holds(on: box, footprints: now, machines: [:]).values.first?.count == 1)
        #expect(decoded.holds(on: box, footprints: [box: ["term-q": footprint("w9:p1", "else")]], machines: [:]).isEmpty)
    }
}
