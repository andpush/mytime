import XCTest
@testable import MyTime

final class ReportsTests: XCTestCase {
    func testGroupByClient() {
        let t0 = Date()
        let entries = [
            TimerEntry(startTime: t0.addingTimeInterval(-3600), client: "A", activity: "Dev",
                       endTime: t0.addingTimeInterval(-1800), durationSeconds: 1800, pausedSeconds: 0),
            TimerEntry(startTime: t0.addingTimeInterval(-1000), client: "B", activity: "Dev",
                       endTime: t0.addingTimeInterval(-400), durationSeconds: 600, pausedSeconds: 0),
            TimerEntry(startTime: t0.addingTimeInterval(-300), client: "A", activity: "Meeting",
                       endTime: t0.addingTimeInterval(-100), durationSeconds: 200, pausedSeconds: 0)
        ]
        let result = Reports.compute(entries: entries, period: .day, grouping: .client, now: t0)
        XCTAssertEqual(result.totalEntries, 3)
        XCTAssertEqual(result.totalSeconds, 2600)
        XCTAssertEqual(result.rows.first?.group, "A")
        XCTAssertEqual(result.rows.first?.seconds, 2000)
    }

    func testFormatHMS() {
        XCTAssertEqual(Reports.formatHMS(3661), "01:01:01")
        XCTAssertEqual(Reports.formatHMS(0), "00:00:00")
    }

    func testPeriodFilters() {
        let now = Date()
        let old = Date(timeIntervalSinceNow: -60 * 24 * 60 * 60)
        let entries = [
            TimerEntry(startTime: old, client: "Old", activity: "",
                       endTime: old.addingTimeInterval(100), durationSeconds: 100, pausedSeconds: 0),
            TimerEntry(startTime: now.addingTimeInterval(-3600), client: "New", activity: "",
                       endTime: now.addingTimeInterval(-1800), durationSeconds: 1800, pausedSeconds: 0)
        ]
        let week = Reports.compute(entries: entries, period: .week, grouping: .client, now: now)
        XCTAssertEqual(week.totalEntries, 1)
        XCTAssertEqual(week.rows.first?.group, "New")
    }
}
