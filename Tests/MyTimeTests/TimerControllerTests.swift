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

    /// A stable local-noon date used by tests that mix boot simulation with
    /// synthetic `now` values. Noon keeps offsets up to several hours on the
    /// same calendar day regardless of the machine's timezone.
    private func localNoon(year: Int = 2026, month: Int = 4, day: Int = 18) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = 12; c.minute = 0
        return Calendar.current.date(from: c)!
    }

    private func startOfDay(_ d: Date) -> Date {
        Calendar.current.startOfDay(for: d)
    }

    // MARK: - Commands

    func testStartSetsActive() {
        let t0 = localNoon()
        ctl.startNew(client: "A", activity: "X", now: t0)
        XCTAssertEqual(ctl.state, .active)
        XCTAssertEqual(ctl.currentEntry?.client, "A")
        XCTAssertEqual(ctl.currentEntry?.status, .active)
        XCTAssertNotNil(currentStore.load())
    }

    func testPauseResumeAccumulatesPausedSeconds() {
        let t0 = localNoon()
        ctl.startNew(client: "A", now: t0)
        ctl.pause(now: t0.addingTimeInterval(100))
        XCTAssertEqual(ctl.state, .paused)
        ctl.resume(now: t0.addingTimeInterval(160))
        XCTAssertEqual(ctl.state, .active)
        XCTAssertEqual(ctl.currentEntry?.pausedSeconds, 60)
    }

    func testStopCalculatesDuration() {
        let t0 = localNoon()
        ctl.startNew(client: "A", now: t0)
        ctl.pause(now: t0.addingTimeInterval(100))
        ctl.resume(now: t0.addingTimeInterval(160))
        ctl.stop(now: t0.addingTimeInterval(1000))
        XCTAssertEqual(ctl.state, .inactive)
        XCTAssertNil(currentStore.load())
        let entries = journal.readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].date, startOfDay(t0))
        XCTAssertEqual(entries[0].durationSeconds, 940) // 1000 - 60 paused
    }

    func testStartNewAutoStopsExisting() {
        let t0 = localNoon()
        ctl.startNew(client: "A", now: t0)
        ctl.startNew(client: "B", now: t0.addingTimeInterval(300))
        let entries = journal.readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].client, "A")
        XCTAssertEqual(entries[0].durationSeconds, 300)
        XCTAssertEqual(ctl.currentEntry?.client, "B")
    }

    func testStopFromPausedResumesFirst() {
        let t0 = localNoon()
        ctl.startNew(client: "A", now: t0)
        ctl.pause(now: t0.addingTimeInterval(100))
        ctl.stop(now: t0.addingTimeInterval(200))
        let entries = journal.readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].durationSeconds, 100) // 200 - 100 paused
    }

    // MARK: - Boot recovery

    func testBootRecoversPausedAsPaused() {
        let t0 = localNoon()
        ctl.startNew(client: "A", activity: "Dev", now: t0)
        ctl.pause(now: t0.addingTimeInterval(500))
        let ctl2 = TimerController(journal: journal, currentStore: currentStore,
                                   now: t0.addingTimeInterval(600))
        XCTAssertEqual(ctl2.state, .paused)
        XCTAssertTrue(journal.readAll().isEmpty)
        let cur = currentStore.load()
        XCTAssertEqual(cur?.status, .paused)
        XCTAssertEqual(cur?.endTime, t0.addingTimeInterval(500))
        XCTAssertEqual(cur?.client, "A")
    }

    func testBootRecoversActiveAsPausedPreservingEndTime() {
        let t0 = localNoon()
        ctl.startNew(client: "A", now: t0)
        let ctl2 = TimerController(journal: journal, currentStore: currentStore, now: t0)
        XCTAssertEqual(ctl2.state, .paused)
        XCTAssertTrue(journal.readAll().isEmpty)
        let cur = currentStore.load()
        XCTAssertEqual(cur?.status, .paused)
        XCTAssertEqual(cur?.endTime, t0)
    }

    func testBootResumeAfterCrashAccumulatesAwayTime() {
        let t0 = localNoon()
        ctl.startNew(client: "A", now: t0)
        ctl.heartbeat(now: t0.addingTimeInterval(3600))
        let ctl2 = TimerController(journal: journal, currentStore: currentStore,
                                   now: t0.addingTimeInterval(3600))
        XCTAssertEqual(ctl2.state, .paused)
        ctl2.resume(now: t0.addingTimeInterval(7200))
        ctl2.stop(now: t0.addingTimeInterval(7200))
        let entries = journal.readAll()
        XCTAssertEqual(entries.count, 1)
        // 1h worked + 1h away-paused. duration = 7200 - 3600 paused = 3600.
        XCTAssertEqual(entries[0].durationSeconds, 3600)
        XCTAssertEqual(entries[0].date, startOfDay(t0))
    }

    // MARK: - Heartbeat

    func testHeartbeatUpdatesCurrentStoreNotJournal() {
        let t0 = localNoon()
        ctl.startNew(client: "A", now: t0)
        ctl.heartbeat(now: t0.addingTimeInterval(3600))
        XCTAssertEqual(ctl.state, .active)
        XCTAssertTrue(journal.readAll().isEmpty)
        let cur = currentStore.load()
        XCTAssertEqual(cur?.endTime, t0.addingTimeInterval(3600))
        XCTAssertEqual(cur?.status, .active)
    }

    func testBootAfterHeartbeatRecoversPausedAtHeartbeatTime() {
        let t0 = localNoon()
        ctl.startNew(client: "A", now: t0)
        ctl.heartbeat(now: t0.addingTimeInterval(3600))
        let ctl2 = TimerController(journal: journal, currentStore: currentStore,
                                   now: t0.addingTimeInterval(3600))
        XCTAssertEqual(ctl2.state, .paused)
        XCTAssertTrue(journal.readAll().isEmpty)
        XCTAssertEqual(ctl2.currentEntry?.endTime, t0.addingTimeInterval(3600))
    }

    // MARK: - Midnight close

    func testHeartbeatClosesActiveAcrossMidnight() {
        let cal = Calendar.current
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 18; c.hour = 23; c.minute = 30
        let t0 = cal.date(from: c)!
        ctl.startNew(client: "A", activity: "Dev", now: t0)
        let tMid = t0.addingTimeInterval(20 * 60)  // 23:50
        ctl.heartbeat(now: tMid)
        let tNext = t0.addingTimeInterval(60 * 60) // 00:30 next day
        ctl.heartbeat(now: tNext)

        let entries = journal.readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].date, cal.startOfDay(for: t0))
        XCTAssertEqual(entries[0].client, "A")
        XCTAssertEqual(entries[0].activity, "Dev")
        XCTAssertEqual(entries[0].durationSeconds, 20 * 60)
        XCTAssertNil(currentStore.load())
        XCTAssertEqual(ctl.state, .inactive)
        XCTAssertNil(ctl.currentEntry)
    }

    func testHeartbeatClosesPausedAcrossMidnight() {
        let cal = Calendar.current
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 18; c.hour = 22; c.minute = 0
        let t0 = cal.date(from: c)!
        ctl.startNew(client: "A", activity: "Dev", now: t0)
        let tPause = t0.addingTimeInterval(60 * 60)  // 23:00
        ctl.pause(now: tPause)
        let tNext = t0.addingTimeInterval(3 * 60 * 60)  // 01:00 next day
        ctl.heartbeat(now: tNext)

        let entries = journal.readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].date, cal.startOfDay(for: t0))
        XCTAssertEqual(entries[0].durationSeconds, 60 * 60)
        XCTAssertNil(currentStore.load())
        XCTAssertEqual(ctl.state, .inactive)
    }

    func testBootClosesActiveLeftoverAcrossMidnight() {
        let cal = Calendar.current
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 18; c.hour = 22; c.minute = 0
        let t0 = cal.date(from: c)!
        ctl.startNew(client: "A", activity: "Dev", now: t0)
        ctl.heartbeat(now: t0.addingTimeInterval(60 * 60))  // 23:00

        let tBoot = t0.addingTimeInterval(12 * 60 * 60)  // 10:00 next day
        let ctl2 = TimerController(journal: journal, currentStore: currentStore, now: tBoot)

        let entries = journal.readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].date, cal.startOfDay(for: t0))
        XCTAssertEqual(entries[0].durationSeconds, 60 * 60)
        XCTAssertEqual(ctl2.state, .inactive)
        XCTAssertNil(currentStore.load())
    }

    func testBootClosesPausedLeftoverAcrossMidnight() {
        let cal = Calendar.current
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 18; c.hour = 22; c.minute = 0
        let t0 = cal.date(from: c)!
        ctl.startNew(client: "A", activity: "Dev", now: t0)
        let tPause = t0.addingTimeInterval(60 * 60)  // 23:00
        ctl.pause(now: tPause)

        let tBoot = t0.addingTimeInterval(12 * 60 * 60)  // 10:00 next day
        let ctl2 = TimerController(journal: journal, currentStore: currentStore, now: tBoot)

        let entries = journal.readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].date, cal.startOfDay(for: t0))
        XCTAssertEqual(entries[0].durationSeconds, 60 * 60)
        XCTAssertEqual(ctl2.state, .inactive)
        XCTAssertNil(currentStore.load())
    }

    func testBootClosesLeftoverWhereEndTimeAlreadyOnNextDay() {
        // Legacy shape from an earlier build: paused entry whose endTime has
        // drifted past startTime's day. startTime still anchors the journal
        // date, so the row is attributed to startTime's day.
        let cal = Calendar.current
        var sc = DateComponents()
        sc.year = 2026; sc.month = 4; sc.day = 18; sc.hour = 23; sc.minute = 26
        let start = cal.date(from: sc)!
        var ec = DateComponents()
        ec.year = 2026; ec.month = 4; ec.day = 19; ec.hour = 7; ec.minute = 31
        let end = cal.date(from: ec)!
        let stale = CurrentEntry(startTime: start, client: "C", activity: "X",
                                 status: .paused, endTime: end, pausedSeconds: 27000)
        currentStore.save(stale)

        let ctl2 = TimerController(journal: journal, currentStore: currentStore, now: end)
        let entries = journal.readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].date, cal.startOfDay(for: start))
        XCTAssertEqual(entries[0].client, "C")
        let expectedDuration = max(0, Int(end.timeIntervalSince(start)) - 27000)
        XCTAssertEqual(entries[0].durationSeconds, expectedDuration)
        XCTAssertEqual(ctl2.state, .inactive)
        XCTAssertNil(currentStore.load())
    }

    // MARK: - Misc

    func testRecentCombosDeduped() {
        let t0 = localNoon()
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
