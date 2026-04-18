import XCTest
@testable import MyTime

final class CSVTests: XCTestCase {
    func testEscapeSimple() {
        XCTAssertEqual(CSV.escape("hello"), "hello")
    }
    func testEscapeWithComma() {
        XCTAssertEqual(CSV.escape("a,b"), "\"a,b\"")
    }
    func testEscapeWithQuotes() {
        XCTAssertEqual(CSV.escape("a\"b"), "\"a\"\"b\"")
    }
    func testEscapeWithNewline() {
        XCTAssertEqual(CSV.escape("a\nb"), "\"a\nb\"")
    }
    func testParseSimpleLine() {
        XCTAssertEqual(CSV.parseLine("a,b,c"), ["a","b","c"])
    }
    func testParseQuoted() {
        XCTAssertEqual(CSV.parseLine("\"a,b\",c"), ["a,b","c"])
    }
    func testParseEscapedQuotes() {
        XCTAssertEqual(CSV.parseLine("\"a\"\"b\",c"), ["a\"b","c"])
    }
    func testParseAllWithQuotedNewlines() {
        let text = "a,b\n\"x\ny\",z\n"
        let rows = CSV.parseAll(text)
        XCTAssertEqual(rows[0], ["a","b"])
        XCTAssertEqual(rows[1], ["x\ny","z"])
    }
}
