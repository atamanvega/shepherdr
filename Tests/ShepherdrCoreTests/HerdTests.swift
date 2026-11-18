import Foundation
import Testing
@testable import ShepherdrCore

struct HerdTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func id(_ terminal: String) -> RemoteSessionID { RemoteSessionID(machineID: "local", terminalID: terminal) }

    private func row(_ terminal: String, _ status: String?, number: Int = 1, kind: QueueRow.Kind = .session,
                     panes: [RemotePane] = []) -> QueueRow {
        QueueRow(id: terminal, kind: kind, session: kind == .group ? nil : id(terminal), number: number, title: "s-\(terminal)",
                 status: status, panes: panes)
    }

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func straysNeedYouFirstThenDoneThenIdleEachInTheQueuesOrder() {
        let rows = [
            row("g", nil, kind: .group), row("a", "idle", number: 1), row("b", "working", number: 2), row("c", "done", number: 3),
            row("d", "needsYou", number: 4), row("e", "unknown", number: 5), row("f", "needsYou", number: 6), row("h", "waiting", number: 7),
            row("i", "stale", number: 8), row("j", "finished", kind: .shell), row("k", "done", number: 9)
        ]
        #expect(Herd.strays(in: rows).map(\.id) == ["d", "f", "c", "k", "a", "e"])
    }

    @Test func aPaneBelongsToTheSessionWhoseTabItSplits() {
        let rows = [row("a", "idle", panes: [RemotePane(pane: id("a"), title: "claude", isAgent: true),
                                             RemotePane(pane: id("a2"), title: "shell", isAgent: false)])]
        #expect(Herd.session(of: id("a2"), in: rows) == id("a"))
        #expect(Herd.session(of: id("a"), in: rows) == id("a"))
        #expect(Herd.session(of: id("zz"), in: rows) == nil)
    }

    @Test func onlyWhatYouTouchedScores() {
        var game = HerdGame(rows: [row("a", "idle"), row("b", "done"), row("c", "idle")], at: start)
        game.touch(id("a"), at: at(5))
        let events = game.observe([row("a", "working"), row("b", "working"), row("c", "idle")], at: at(10))
        #expect(events == [HerdEvent(kind: .backToWork, title: "s-a", points: 10)])
        #expect(game.score == 10)
        #expect(game.backToWork == 1)
        // The touch is spent: the next time a stops and starts again by itself, nothing scores.
        _ = game.observe([row("a", "done"), row("b", "working"), row("c", "idle")], at: at(20))
        #expect(game.observe([row("a", "working"), row("b", "working"), row("c", "idle")], at: at(30)).isEmpty)
    }

    @Test func answeringScoresFiftyAndCombosMultiply() {
        var game = HerdGame(rows: [row("a", "needsYou"), row("b", "needsYou"), row("c", "idle"), row("x", "idle")], at: start)
        game.touch(id("a"), at: at(1))
        #expect(game.observe([row("a", "working"), row("b", "needsYou"), row("c", "idle"), row("x", "idle")], at: at(2))
            == [HerdEvent(kind: .answered, title: "s-a", points: 50)])
        game.touch(id("b"), at: at(30))
        // Answering a question can also leave the agent done at once: it still counts.
        #expect(game.observe([row("a", "working"), row("b", "done"), row("c", "idle"), row("x", "idle")], at: at(40))
            == [HerdEvent(kind: .answered, title: "s-b", points: 100, combo: 2)])
        game.touch(id("c"), at: at(200))
        // Too long after the last points: the combo starts over.
        #expect(game.observe([row("a", "working"), row("b", "done"), row("c", "working"), row("x", "idle")], at: at(210))
            == [HerdEvent(kind: .backToWork, title: "s-c", points: 10)])
        #expect(game.score == 160)
        #expect(game.answered == 2)
    }

    @Test func closingAFinishedSessionScoresAHundredAndOneThatNeededYouNothing() {
        var game = HerdGame(rows: [row("a", "done"), row("b", "needsYou"), row("c", "idle"), row("x", "idle")], at: start)
        game.touch(id("a"), at: at(1))
        game.touch(id("b"), at: at(1))
        let events = game.observe([row("c", "idle"), row("x", "idle")], at: at(5))
        #expect(events == [HerdEvent(kind: .closed, title: "s-a", points: 100), HerdEvent(kind: .closed, title: "s-b", points: 0)])
        #expect(game.closed == 2)
        // A session that ends without you touching it doesn't score.
        #expect(game.observe([row("x", "idle")], at: at(6)).isEmpty)
    }

    @Test func touchesExpire() {
        var game = HerdGame(rows: [row("a", "idle"), row("x", "idle")], at: start)
        game.touch(id("a"), at: at(0))
        #expect(game.observe([row("a", "working"), row("x", "idle")], at: at(HerdGame.touchWindow + 1)).isEmpty)
    }

    @Test func sessionsThatStopAreAnnounced() {
        var game = HerdGame(rows: [row("a", "working"), row("x", "idle")], at: start)
        #expect(game.observe([row("a", "done"), row("x", "idle"), row("n", "idle")], at: at(5))
            == [HerdEvent(kind: .strayed, title: "s-a", points: 0), HerdEvent(kind: .strayed, title: "s-n", points: 0)])
        // done → idle is only someone looking at it.
        #expect(game.observe([row("a", "idle"), row("x", "idle"), row("n", "idle")], at: at(6)).isEmpty)
    }

    @Test func clearingTheQueueWinsWithABonusForTheTimeLeft() {
        var game = HerdGame(rows: [row("a", "needsYou"), row("b", "working"), row("s", "stale")], at: start)
        game.touch(id("a"), at: at(5 * 60))
        let events = game.observe([row("a", "working"), row("b", "working"), row("s", "stale")], at: at(5 * 60 + 30))
        #expect(events.last == HerdEvent(kind: .cleared, title: "", points: 500 + 250))
        #expect(game.outcome == .cleared)
        #expect(game.score == 50 + 750)
        #expect(game.timeBonus == 250)
        #expect(game.observe([row("a", "done")], at: at(400)).isEmpty)
    }

    @Test func aSessionAstrayWhoseMachineStopsAnsweringStillHasToBeHerded() {
        var game = HerdGame(rows: [row("a", "idle"), row("b", "working")], at: start)
        #expect(game.observe([row("a", "stale"), row("b", "working")], at: at(5)).isEmpty)
        #expect(game.strays(in: [row("a", "stale"), row("b", "working")]).map(\.status) == ["idle"])
        game.touch(id("a"), at: at(10))
        // Back online and working: it was idle all along, so it scores and clears the queue.
        let events = game.observe([row("a", "working"), row("b", "working")], at: at(20))
        #expect(events.map(\.kind) == [.backToWork, .cleared])
    }

    @Test func tenMinutesWithoutDoingAnythingEndTheGame() {
        var game = HerdGame(rows: [row("a", "idle"), row("b", "idle")], at: start)
        #expect(game.expire(at: at(HerdGame.patience - 1)) == nil)
        game.touch(id("a"), at: at(300))
        #expect(game.deadline == at(300 + HerdGame.patience))
        #expect(game.expire(at: at(HerdGame.patience + 1)) == nil)
        #expect(game.observe([row("a", "working"), row("b", "idle")], at: at(300 + HerdGame.patience)).map(\.kind) == [.timeUp])
        #expect(game.outcome == .timeUp)
        #expect(game.ended == at(300 + HerdGame.patience))
        #expect(game.score == 0)
    }

    @Test func theClockStopsWhileHeld() {
        var game = HerdGame(rows: [row("a", "idle"), row("b", "idle")], at: start)
        game.hold(for: 120)
        #expect(game.deadline == at(120 + HerdGame.patience))
        #expect(game.expire(at: at(HerdGame.patience + 60)) == nil)
        // The time bonus counts only the time you could play.
        game.touch(id("a"), at: at(120 + 10))
        game.touch(id("b"), at: at(120 + 10))
        _ = game.observe([row("a", "working"), row("b", "working")], at: at(120 + 30))
        #expect(game.timeBonus == 300)
    }

    @Test func givingUpEndsTheGameWithItsScore() {
        var game = HerdGame(rows: [row("a", "idle"), row("b", "idle")], at: start)
        game.touch(id("a"), at: at(1))
        _ = game.observe([row("a", "working"), row("b", "idle")], at: at(2))
        game.giveUp(at: at(3))
        #expect(game.outcome == .gaveUp)
        #expect(game.score == 10)
        #expect(game.observe([row("a", "working"), row("b", "working")], at: at(4)).isEmpty)
    }

    @Test func gamesSurviveARelaunch() throws {
        var game = HerdGame(rows: [row("a", "idle"), row("b", "idle")], at: start)
        game.touch(id("a"), at: at(1))
        var restored = try JSONDecoder().decode(HerdGame.self, from: JSONEncoder().encode(game))
        #expect(restored == game)
        #expect(restored.observe([row("a", "working"), row("b", "idle")], at: at(2)).map(\.points) == [10])
    }

    @Test func theTableKeepsTheTenBestAndTiesGoUnder() {
        let table = HerdScores.starting
        #expect(table.count == 10)
        #expect(HerdScores.rank(of: 5000, in: table) == 0)
        #expect(HerdScores.rank(of: 2500, in: table) == 2)
        #expect(HerdScores.rank(of: 201, in: table) == 9)
        #expect(HerdScores.rank(of: 200, in: table) == nil)
        #expect(HerdScores.rank(of: 0, in: []) == nil)
        #expect(HerdScores.rank(of: 1, in: []) == 0)
        let (inserted, rank) = HerdScores.inserting(HerdScore(initials: "jt", score: 1300), into: table)
        #expect(rank == 4)
        #expect(inserted.count == 10)
        #expect(inserted[4] == HerdScore(initials: "JT ", score: 1300))
        #expect(inserted.last?.initials == "NOP")
        #expect(HerdScores.initials("a-b/c") == "A B")
    }
}
