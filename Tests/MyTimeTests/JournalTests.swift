import XCTest
@testable import MyTime

final class JournalTests: XCTestCase {
    var tmpURL: URL!
    var journal: Journal!

    override func setUp() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mytime-test-\(UUID().uuidString).csv")
        tmpURL = tmp
        journal = Journal(url: tmp)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpURL)
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return Calendar.current.date(from: c)!
    }

    func testAppendAndRead() {
        let e = TimerEntry(date: day(2026, 4, 18), client: "ClientA",
                           activity: "Dev", durationSeconds: 3600)
        journal.appendNew(e)
        let read = journal.readAll()
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].date, day(2026, 4, 18))
        XCTAssertEqual(read[0].client, "ClientA")
        XCTAssertEqual(read[0].activity, "Dev")
        XCTAssertEqual(read[0].durationSeconds, 3600)
    }

    func testMultipleAppendsPreserveOrder() {
        for i in 0..<3 {
            let e = TimerEntry(date: day(2026, 4, 18 + i), client: "C\(i)",
                               activity: "", durationSeconds: 60)
            journal.appendNew(e)
        }
        let read = journal.readAll()
        XCTAssertEqual(read.count, 3)
        XCTAssertEqual(read.map { $0.client }, ["C0", "C1", "C2"])
    }

    func testCSVEscapingForClientWithComma() {
        let e = TimerEntry(date: day(2026, 4, 18), client: "A, Inc.",
                           activity: "x\"y", durationSeconds: 60)
        journal.appendNew(e)
        let read = journal.readAll()
        XCTAssertEqual(read[0].client, "A, Inc.")
        XCTAssertEqual(read[0].activity, "x\"y")
    }

    func testMigrateLegacyFormat() {
        // Pre-seed the file with the old 6-column header + one row, then
        // let the Journal migrate it on first access.
        let legacy = """
        START_TIME,CLIENT,ACTIVITY,END_TIME,DURATION_SECONDS,PAUSED_SECONDS
        2026-04-18T23:26:27,MyApps,Travel,2026-04-19T07:31:17,1670,27420
        """
        try? legacy.write(to: tmpURL, atomically: true, encoding: .utf8)
        let read = journal.readAll()
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].date, day(2026, 4, 18))
        XCTAssertEqual(read[0].client, "MyApps")
        XCTAssertEqual(read[0].activity, "Travel")
        XCTAssertEqual(read[0].durationSeconds, 1670)
        // The on-disk file should now have the new header.
        let text = try? String(contentsOf: tmpURL, encoding: .utf8)
        XCTAssertTrue(text?.hasPrefix("DATE,CLIENT,ACTIVITY,DURATION_SECONDS") ?? false)
    }
}
