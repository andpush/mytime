import XCTest
@testable import MyTime

final class ReportsTests: XCTestCase {
    private func day(_ offsetDays: Int, from now: Date) -> Date {
        let cal = Calendar.current
        let base = cal.startOfDay(for: now)
        return cal.date(byAdding: .day, value: offsetDays, to: base)!
    }

    func testGroupByClient() {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let entries = [
            TimerEntry(date: today, client: "A", activity: "Dev", durationSeconds: 1800),
            TimerEntry(date: today, client: "B", activity: "Dev", durationSeconds: 600),
            TimerEntry(date: today, client: "A", activity: "Meeting", durationSeconds: 200)
        ]
        let result = Reports.compute(entries: entries, period: .day, grouping: .client, now: now)
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
        let entries = [
            TimerEntry(date: day(-60, from: now), client: "Old",
                       activity: "", durationSeconds: 100),
            TimerEntry(date: day(-1, from: now), client: "New",
                       activity: "", durationSeconds: 1800)
        ]
        let week = Reports.compute(entries: entries, period: .week, grouping: .client, now: now)
        XCTAssertEqual(week.totalEntries, 1)
        XCTAssertEqual(week.rows.first?.group, "New")
    }
}
