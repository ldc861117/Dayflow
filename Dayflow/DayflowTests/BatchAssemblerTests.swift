//
//  BatchAssemblerTests.swift
//  DayflowTests
//

import XCTest
import AVFoundation
@testable import Dayflow

final class BatchAssemblerTests: XCTestCase {
    private var mockVideoProcessingService: MockVideoProcessingService!
    private var batchAssembler: BatchAssembler!
    
    override func setUp() async throws {
        mockVideoProcessingService = MockVideoProcessingService()
        batchAssembler = BatchAssembler(videoProcessingService: mockVideoProcessingService)
    }
    
    func testPrepareCombinedVideo_EmptyChunkFiles() async throws {
        // Given: Empty chunk files array
        let chunkFilePaths: [String] = []
        
        // When & Then: Should throw error
        do {
            _ = try await batchAssembler.prepareCombinedVideo(from: chunkFilePaths, batchId: 123)
            XCTFail("Expected error to be thrown")
        } catch let error as LLMServiceError {
            XCTAssertEqual(error, .noRecordingsInBatch)
        }
    }
    
    func testPrepareCombinedVideo_Success() async throws {
        // Given: Valid chunk files
        let chunkFilePaths = ["/path/to/chunk1.mp4", "/path/to/chunk2.mp4"]
        let expectedVideoData = Data(repeating: 0x42, count: 1024)
        let expectedDuration: TimeInterval = 120.0
        
        mockVideoProcessingService.resultURL = URL(fileURLWithPath: "/tmp/combined.mp4")
        mockVideoProcessingService.videoData = expectedVideoData
        mockVideoProcessingService.duration = expectedDuration
        
        // When: Preparing combined video
        let result = try await batchAssembler.prepareCombinedVideo(from: chunkFilePaths, batchId: 123)
        
        // Then: Should return combined video data
        XCTAssertEqual(result.data, expectedVideoData)
        XCTAssertEqual(result.mimeType, "video/mp4")
        XCTAssertEqual(result.duration, expectedDuration)
        
        // And: Should call video processing service
        XCTAssertEqual(mockVideoProcessingService.prepareVideoForProcessingCallCount, 1)
        XCTAssertEqual(mockVideoProcessingService.cleanupTemporaryFileCallCount, 1)
    }
    
    func testPrepareCombinedVideo_InvalidFilePaths() async throws {
        // Given: Chunk files that don't exist (will result in empty URLs)
        let chunkFilePaths = [""] // Empty string won't create valid URL
        
        // When & Then: Should throw error
        do {
            _ = try await batchAssembler.prepareCombinedVideo(from: chunkFilePaths, batchId: 123)
            XCTFail("Expected error to be thrown")
        } catch let error as LLMServiceError {
            XCTAssertEqual(error, .noRecordingsInBatch)
        }
    }
    
    func testPrepareCombinedVideo_VideoProcessingError() async throws {
        // Given: Valid chunk files but video processing fails
        let chunkFilePaths = ["/path/to/chunk1.mp4"]
        mockVideoProcessingService.shouldThrowError = true
        mockVideoProcessingService.errorToThrow = VideoProcessingError.invalidInputURL
        
        // When & Then: Should throw wrapped error
        do {
            _ = try await batchAssembler.prepareCombinedVideo(from: chunkFilePaths, batchId: 123)
            XCTFail("Expected error to be thrown")
        } catch let error as LLMServiceError {
            if case .videoProcessingFailed(let videoError) = error {
                XCTAssertTrue(videoError is VideoProcessingError)
            } else {
                XCTFail("Expected videoProcessingFailed error")
            }
        }
    }
    
    func testExtractSegment_Success() async throws {
        // Given: Valid source video
        let sourceURL = URL(fileURLWithPath: "/path/to/source.mp4")
        let expectedSegmentURL = URL(fileURLWithPath: "/tmp/segment.mp4")
        let startTime: TimeInterval = 30.0
        let duration: TimeInterval = 60.0
        
        mockVideoProcessingService.resultURL = expectedSegmentURL
        
        // When: Extracting segment
        let result = try await batchAssembler.extractSegment(
            from: sourceURL,
            startTime: startTime,
            duration: duration
        )
        
        // Then: Should return segment URL
        XCTAssertEqual(result, expectedSegmentURL)
        
        // And: Should call video processing service with correct parameters
        XCTAssertEqual(mockVideoProcessingService.extractSegmentCallCount, 1)
        XCTAssertEqual(mockVideoProcessingService.lastExtractSegmentStartTime, startTime)
        XCTAssertEqual(mockVideoProcessingService.lastExtractSegmentDuration, duration)
    }
}

// MARK: - Mock VideoProcessingService

class MockVideoProcessingService: VideoProcessingService {
    // Mock properties
    var resultURL: URL?
    var videoData: Data?
    var duration: TimeInterval = 0.0
    var shouldThrowError = false
    var errorToThrow: Error?
    
    // Call tracking
    var prepareVideoForProcessingCallCount = 0
    var extractSegmentCallCount = 0
    var cleanupTemporaryFileCallCount = 0
    var lastExtractSegmentStartTime: TimeInterval?
    var lastExtractSegmentDuration: TimeInterval?
    
    override func prepareVideoForProcessing(urls: [URL]) async throws -> URL {
        prepareVideoForProcessingCallCount += 1
        
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        
        guard let resultURL = resultURL else {
            throw VideoProcessingError.invalidInputURL
        }
        
        return resultURL
    }
    
    override func extractSegment(from sourceVideoURL: URL, startTime: TimeInterval, duration: TimeInterval) async throws -> URL {
        extractSegmentCallCount += 1
        lastExtractSegmentStartTime = startTime
        lastExtractSegmentDuration = duration
        
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        
        guard let resultURL = resultURL else {
            throw VideoProcessingError.invalidInputURL
        }
        
        return resultURL
    }
    
    override func cleanupTemporaryFile(at url: URL) {
        cleanupTemporaryFileCallCount += 1
    }
}