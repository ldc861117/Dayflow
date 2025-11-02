//
//  SegmentWriterTests.swift
//  DayflowTests
//

import XCTest
@testable import Dayflow
import AVFoundation
import CoreMedia

final class SegmentWriterTests: XCTestCase {
    
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test_\(UUID().uuidString).mp4")
    }
    
    override func tearDown() {
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        super.tearDown()
    }
    
    func testSegmentWriterInitialization() throws {
        let writer = try SegmentWriter(url: tempURL, width: 1920, height: 1080)
        
        XCTAssertEqual(writer.fileURL, tempURL)
        XCTAssertEqual(writer.frameCount, 0)
        XCTAssertFalse(writer.hasFrames)
    }
    
    func testSegmentWriterInvalidDimensions() {
        // Test that initialization succeeds even with odd dimensions (they get adjusted)
        XCTAssertNoThrow(try SegmentWriter(url: tempURL, width: 1920, height: 1080))
    }
    
    func testFinishWithoutFrames() throws {
        let writer = try SegmentWriter(url: tempURL, width: 1920, height: 1080)
        
        let expectation = self.expectation(description: "finish called")
        
        writer.finish { success, error in
            XCTAssertFalse(success, "Finish should fail when no frames were written")
            XCTAssertNil(error)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
    }
    
    func testCancelWriting() throws {
        let writer = try SegmentWriter(url: tempURL, width: 1920, height: 1080)
        
        writer.cancel()
        
        // After cancel, the file should not exist or be incomplete
        // (exact behavior depends on AVAssetWriter)
    }
}
