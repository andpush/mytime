import XCTest
@testable import MyTime

final class TimerControllerTests: XCTestCase {
    var journalURL: URL!
    var currentURL: URL!
    var journal: Journal!
    var currentStore: CurrentStore!
    var ctl: TimerController!

    override func setUp() {
        let id = UUID().uuidString
        journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mytime-journal-\(id).csv")
        currentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mytime-current-\(id).csv")
        journal = Journal(url: journalURL)
        currentStore = CurrentStore(url: currentURL)
        ctl = TimerController(journal: journal, currentStore: currentStore)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: journalURL)
        try? FileManager.default.removeItem(at: currentURL)
    }

    func testStartSetsActive() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctl.startNew(client: "A", activity: "X", now: t0)
        XCTAssertEqual(ctl.state, .active)
        XCTAssertEqual(ctl.currentEntry?.client, "A")
        XCTAssertEqual(ctl.currentEntry?.status, .active)
        // current.csv persisted
        XCTAssertNotNil(currentStore.load())
    }

    func testPauseResumeAccumulatesPausedSeconds() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctl.startNew(client: "A", now: t0)
        ctl.pause(now: t0.addingTimeInterval(100))
        XCTAssertEqual(ctl.state, .paused)
        ctl.resume(now: t0.addingTimeInterval(160))
        XCTAssertEqual(ctl.state, .active)
        XCTAssertEqual(ctl.currentEntry?.pausedSeconds, 60)
    }

    func testStopCalculatesDuration() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctl.startNew(client: "A", now: t0)
        ctl.pause(now: t0.addingTimeInterval(100))
        ctl.resume(now: t0.addingTimeInterval(160))
        ctl.stop(now: t0.addingTimeInterval(1000))
        XCTAssertEqual(ctl.state, .inactive)
        XCTAssertNil(currentStore.load())
        let entries = journal.readAll()
        XCTAssertEqual(entries.last?.durationSeconds, 940) // 1000 - 60 paused
        XCTAssertEqual(entries.last?.pausedSeconds, 60)
    }

    func testStartNewAutoStopsExisting() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctl.startNew(client: "A", now: t0)
        ctl.startNew(client: "B", now: t0.addingTimeInterval(300))
        let entries = journal.readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].client, "A")
        XCTAssertEqual(entries[0].durationSeconds, 300)
        XCTAssertEqual(ctl.currentEntry?.client, "B")
    }

    func testStopFromPausedResumesFirst() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctl.startNew(client: "A", now: t0)
        ctl.pause(now: t0.addingTimeInterval(100))
        ctl.stop(now: t0.addingTimeInterval(200))
        let entries = journal.readAll()
        // paused for 100s (from 100 to stop@200 counted as paused), then resume+stop.
        XCTAssertEqual(entries.last?.pausedSeconds, 100)
        XCTAssertEqual(entries.last?.durationSeconds, 100) // 200 - 100 paused
    }

    func testBootRecoversPausedAsPaused() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctl.startNew(client: "A", activity: "Dev", now: t0)
        ctl.pause(now: t0.addingTimeInterval(500))
        // Simulate crash → new controller reads the leftover current.csv.
        let ctl2 = TimerController(journal: journal, currentStore: currentStore)
        XCTAssertEqual(ctl2.state, .paused)
        XCTAssertTrue(journal.readAll().isEmpty)
        let cur = currentStore.load()
        XCTAssertEqual(cur?.status, .paused)
        XCTAssertEqual(cur?.endTime, t0.addingTimeInterval(500))
        XCTAssertEqual(cur?.client, "A")
    }

    func testBootRecoversActiveAsPausedPreservingEndTime() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctl.startNew(client: "A", now: t0)
        // Simulate crash without heartbeat. current.csv endTime == startTime.
        let ctl2 = TimerController(journal: journal, currentStore: currentStore)
        XCTAssertEqual(ctl2.state, .paused)
        XCTAssertTrue(journal.readAll().isEmpty)
        let cur = currentStore.load()
        XCTAssertEqual(cur?.status, .paused)
        XCTAssertEqual(cur?.endTime, t0)
    }

    func testBootResumeAfterCrashAccumulatesAwayTime() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctl.startNew(client: "A", now: t0)
        ctl.heartbeat(now: t0.addingTimeInterval(3600))
        // Crash — boot recovers as paused at endTime=3600s.
        let ctl2 = TimerController(journal: journal, currentStore: currentStore)
        XCTAssertEqual(ctl2.state, .paused)
        // User comes back an hour later and resumes, then stops immediately.
        ctl2.resume(now: t0.addingTimeInterval(7200))
        ctl2.stop(now: t0.addingTimeInterval(7200))
        let entries = journal.readAll()
        XCTAssertEqual(entries.count, 1)
        // 1h worked + 1h away-paused. duration = 7200 - 3600 paused = 3600.
        XCTAssertEqual(entries[0].pausedSeconds, 3600)
        XCTAssertEqual(entries[0].durationSeconds, 3600)
    }

    func testHeartbeatUpdatesCurrentStoreNotJournal() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctl.startNew(client: "A", now: t0)
        ctl.heartbeat(now: t0.addingTimeInterval(3600))
        XCTAssertEqual(ctl.state, .active)
        XCTAssertTrue(journal.readAll().isEmpty)
        let cur = currentStore.load()
        XCTAssertEqual(cur?.endTime, t0.addingTimeInterval(3600))
        XCTAssertEqual(cur?.status, .active)
    }

    func testBootAfterHeartbeatRecoversPausedAtHeartbeatTime() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctl.startNew(client: "A", now: t0)
        ctl.heartbeat(now: t0.addingTimeInterval(3600))
        let ctl2 = TimerController(journal: journal, currentStore: currentStore)
        XCTAssertEqual(ctl2.state, .paused)
        XCTAssertTrue(journal.readAll().isEmpty)
        XCTAssertEqual(ctl2.currentEntry?.endTime, t0.addingTimeInterval(3600))
    }

    func testHeartbeatSplitsAcrossMidnight() {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 18
        comps.hour = 23; comps.minute = 30
        let t0 = cal.date(from: comps)!
        ctl.startNew(client: "A", activity: "Dev", now: t0)
        let t1 = t0.addingTimeInterval(60 * 60) // 00:30 next day
        ctl.heartbeat(now: t1)

        // First day closed into journal.
        let entries = journal.readAll()
        XCTAssertEqual(entries.count, 1)
        let midnight = cal.startOfDay(for: t1)
        XCTAssertEqual(entries[0].endTime, midnight)
        XCTAssertEqual(entries[0].durationSeconds, 1800)

        // Second day lives in current.csv as a fresh active entry.
        let cur = currentStore.load()
        XCTAssertEqual(cur?.startTime, midnight)
        XCTAssertEqual(cur?.client, "A")
        XCTAssertEqual(cur?.activity, "Dev")
        XCTAssertEqual(cur?.status, .active)
        XCTAssertEqual(cur?.endTime, t1)
        XCTAssertEqual(ctl.state, .active)
        XCTAssertEqual(ctl.currentEntry?.startTime, midnight)
    }

    func testBootIdempotentAfterCompletedStop() {
        // Stop appended to journal and cleared current.csv already. A second
        // boot must not append a duplicate row even if current.csv somehow
        // survived (defensive guard via startTime match).
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctl.startNew(client: "A", now: t0)
        ctl.stop(now: t0.addingTimeInterval(100))
        let beforeCount = journal.readAll().count
        // Simulate a stale current.csv whose start matches last journal row.
        let stale = CurrentEntry(startTime: t0, client: "A", activity: "",
                                 status: .active, endTime: t0.addingTimeInterval(50), pausedSeconds: 0)
        currentStore.save(stale)
        let ctl2 = TimerController(journal: journal, currentStore: currentStore)
        XCTAssertEqual(ctl2.state, .inactive)
        XCTAssertEqual(journal.readAll().count, beforeCount)
        XCTAssertNil(currentStore.load())
    }

    func testRecentCombosDeduped() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctl.startNew(client: "A", activity: "Dev", now: t0)
        ctl.stop(now: t0.addingTimeInterval(100))
        ctl.startNew(client: "B", activity: "Meeting", now: t0.addingTimeInterval(200))
        ctl.stop(now: t0.addingTimeInterval(300))
        ctl.startNew(client: "A", activity: "Dev", now: t0.addingTimeInterval(400))
        ctl.stop(now: t0.addingTimeInterval(500))
        let recents = ctl.recentCombos()
        XCTAssertEqual(recents.count, 2)
        XCTAssertEqual(recents[0].client, "A")
    }
}
