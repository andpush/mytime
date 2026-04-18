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

    func testAppendAndRead() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3600)
        let e = TimerEntry(startTime: start, client: "ClientA", activity: "Dev",
                           endTime: end, durationSeconds: 3600, pausedSeconds: 0)
        journal.appendNew(e)
        let read = journal.readAll()
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].client, "ClientA")
        XCTAssertEqual(read[0].activity, "Dev")
        XCTAssertEqual(read[0].durationSeconds, 3600)
    }

    func testMultipleAppendsPreserveOrder() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<3 {
            let s = t0.addingTimeInterval(TimeInterval(i * 1000))
            let e = TimerEntry(startTime: s, client: "C\(i)", activity: "",
                               endTime: s.addingTimeInterval(60), durationSeconds: 60, pausedSeconds: 0)
            journal.appendNew(e)
        }
        let read = journal.readAll()
        XCTAssertEqual(read.count, 3)
        XCTAssertEqual(read.map { $0.client }, ["C0", "C1", "C2"])
    }

    func testCSVEscapingForClientWithComma() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let e = TimerEntry(startTime: start, client: "A, Inc.", activity: "x\"y",
                           endTime: start.addingTimeInterval(60), durationSeconds: 60, pausedSeconds: 0)
        journal.appendNew(e)
        let read = journal.readAll()
        XCTAssertEqual(read[0].client, "A, Inc.")
        XCTAssertEqual(read[0].activity, "x\"y")
    }
}
