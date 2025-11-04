//
//  VideoTimestampParserTests.swift
//  DayflowTests
//
//  Unit tests for VideoTimestampParser
//

import XCTest
@testable import Dayflow

final class VideoTimestampParserTests: XCTestCase {
    
    // MARK: - MM:SS Format Tests
    
    func testParseMMSS_Valid() {
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("00:00"), 0)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("00:30"), 30)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("01:00"), 60)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("05:30"), 330)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("10:45"), 645)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("59:59"), 3599)
    }
    
    func testParseMMSS_WithWhitespace() {
        XCTAssertEqual(VideoTimestampParser.parseTimestamp(" 05:30 "), 330)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("\t10:45\n"), 645)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("  00:00  "), 0)
    }
    
    func testParseMMSS_InvalidSeconds() {
        XCTAssertNil(VideoTimestampParser.parseTimestamp("05:60"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("05:99"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("10:-5"))
    }
    
    func testParseMMSS_InvalidMinutes() {
        XCTAssertNil(VideoTimestampParser.parseTimestamp("-1:30"))
    }
    
    func testParseMMSS_NonNumeric() {
        XCTAssertNil(VideoTimestampParser.parseTimestamp("MM:SS"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("ab:cd"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("5:3a"))
    }
    
    // MARK: - HH:MM:SS Format Tests
    
    func testParseHHMMSS_Valid() {
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("00:00:00"), 0)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("00:00:30"), 30)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("00:01:00"), 60)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("00:05:30"), 330)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("01:00:00"), 3600)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("01:30:45"), 5445)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("23:59:59"), 86399)
    }
    
    func testParseHHMMSS_WithWhitespace() {
        XCTAssertEqual(VideoTimestampParser.parseTimestamp(" 01:30:45 "), 5445)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("\t00:00:30\n"), 30)
    }
    
    func testParseHHMMSS_InvalidSeconds() {
        XCTAssertNil(VideoTimestampParser.parseTimestamp("01:30:60"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("00:00:99"))
    }
    
    func testParseHHMMSS_InvalidMinutes() {
        XCTAssertNil(VideoTimestampParser.parseTimestamp("01:60:00"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("00:99:30"))
    }
    
    func testParseHHMMSS_InvalidHours() {
        XCTAssertNil(VideoTimestampParser.parseTimestamp("-1:00:00"))
    }
    
    func testParseHHMMSS_NonNumeric() {
        XCTAssertNil(VideoTimestampParser.parseTimestamp("HH:MM:SS"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("1:2:3a"))
    }
    
    // MARK: - Malformed Input Tests
    
    func testParseMalformed_Empty() {
        XCTAssertNil(VideoTimestampParser.parseTimestamp(""))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("   "))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("\t\n"))
    }
    
    func testParseMalformed_WrongFormat() {
        XCTAssertNil(VideoTimestampParser.parseTimestamp("5"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("5:"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp(":30"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("::"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("1:2:3:4"))
    }
    
    func testParseMalformed_NoColons() {
        XCTAssertNil(VideoTimestampParser.parseTimestamp("530"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("10000"))
    }
    
    func testParseMalformed_SpecialCharacters() {
        XCTAssertNil(VideoTimestampParser.parseTimestamp("05@30"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("05.30"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("05-30"))
    }
    
    // MARK: - TimeInterval Tests
    
    func testParseAsTimeInterval_Valid() {
        XCTAssertEqual(VideoTimestampParser.parseTimestampAsTimeInterval("00:30"), 30.0)
        XCTAssertEqual(VideoTimestampParser.parseTimestampAsTimeInterval("05:30"), 330.0)
        XCTAssertEqual(VideoTimestampParser.parseTimestampAsTimeInterval("01:00:00"), 3600.0)
    }
    
    func testParseAsTimeInterval_Invalid() {
        XCTAssertNil(VideoTimestampParser.parseTimestampAsTimeInterval(""))
        XCTAssertNil(VideoTimestampParser.parseTimestampAsTimeInterval("invalid"))
        XCTAssertNil(VideoTimestampParser.parseTimestampAsTimeInterval("05:60"))
    }
    
    // MARK: - Edge Cases
    
    func testParseEdgeCase_LeadingZeros() {
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("00:00"), 0)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("00:00:00"), 0)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("00:05:00"), 300)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("05:00"), 300)
    }
    
    func testParseEdgeCase_LargeMinutes() {
        // MM:SS format allows minutes > 59
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("60:00"), 3600)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("90:30"), 5430)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("120:00"), 7200)
    }
    
    func testParseEdgeCase_LargeHours() {
        // HH:MM:SS format allows hours > 23
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("24:00:00"), 86400)
        XCTAssertEqual(VideoTimestampParser.parseTimestamp("100:30:45"), 361845)
    }
    
    // MARK: - Regression Tests (Previously Crashing Cases)
    
    func testRegression_MMSSNoCrash() {
        // These should not crash even if implementation incorrectly indexes array
        XCTAssertNotNil(VideoTimestampParser.parseTimestamp("05:30"))
        XCTAssertNotNil(VideoTimestampParser.parseTimestamp("10:45"))
    }
    
    func testRegression_SingleComponentNoCrash() {
        // Should handle gracefully without array index errors
        XCTAssertNil(VideoTimestampParser.parseTimestamp("5"))
        XCTAssertNil(VideoTimestampParser.parseTimestamp("300"))
    }
    
    func testRegression_FourComponentsNoCrash() {
        // Should handle gracefully without array index errors
        XCTAssertNil(VideoTimestampParser.parseTimestamp("1:2:3:4"))
    }
}
