//
//  LLMServiceIntegrationTests.swift
//  DayflowTests
//

import XCTest
@testable import Dayflow

final class LLMServiceIntegrationTests: XCTestCase {
    private var mockProviderFactory: MockProviderFactory!
    private var mockBatchAssembler: MockBatchAssembler!
    private var mockTimelineUpdater: MockTimelineUpdater!
    private var mockAnalyticsService: MockAnalyticsService!
    private var llmService: Dayflow.LLMService!
    
    override func setUp() async throws {
        mockProviderFactory = MockProviderFactory()
        mockBatchAssembler = MockBatchAssembler()
        mockTimelineUpdater = MockTimelineUpdater()
        mockAnalyticsService = MockAnalyticsService()
        
        llmService = Dayflow.LLMService(
            providerFactory: mockProviderFactory,
            batchAssembler: mockBatchAssembler,
            timelineUpdater: mockTimelineUpdater,
            analyticsService: mockAnalyticsService
        )
    }
    
    func testProcessBatchAsync_Success() async throws {
        // Given: Successful setup
        let batchId: Int64 = 123
        let batchInfo = (batchId, 1000, 2000, "pending")
        let chunkFiles = ["/path/to/chunk1.mp4"]
        let videoData = Data(repeating: 0x42, count: 1024)
        let observations = [
            Observation(
                id: 1,
                batchId: 123,
                startTs: 1000,
                endTs: 1500,
                observation: "Test observation",
                metadata: nil,
                llmModel: nil,
                createdAt: Date()
            )
        ]
        let cards = [
            ActivityCardData(
                startTime: "9:00 AM",
                endTime: "10:00 AM",
                category: "Work",
                subcategory: "Coding",
                title: "Development",
                summary: "Writing code",
                detailedSummary: "Working on features",
                distractions: nil,
                appSites: nil
            )
        ]
        
        mockTimelineUpdater.batchInfo = batchInfo
        mockTimelineUpdater.chunkFiles = chunkFiles
        mockProviderFactory.mockProvider = MockLLMProvider()
        mockBatchAssembler.videoData = videoData
        mockBatchAssembler.duration = 60.0
        mockProviderFactory.mockProvider?.observations = observations
        mockProviderFactory.mockProvider?.cards = cards
        mockTimelineUpdater.insertedCardIds = [456]
        mockTimelineUpdater.deletedVideoPaths = []
        
        // When: Processing batch
        let result = try await llmService.processBatchAsync(batchId)
        
        // Then: Should process successfully
        XCTAssertEqual(result.cards.count, 1)
        XCTAssertEqual(result.cardIds, [456])
        XCTAssertEqual(result.cards.first?.category, "Work")
        
        // And: Should call all components in order
        XCTAssertEqual(mockTimelineUpdater.getBatchInfoCallCount, 1)
        XCTAssertEqual(mockProviderFactory.getProviderCallCount, 1)
        XCTAssertEqual(mockAnalyticsService.captureCallCount, 2) // started + completed
        XCTAssertEqual(mockTimelineUpdater.markBatchAsProcessingCallCount, 1)
        XCTAssertEqual(mockTimelineUpdater.getChunkFilesCallCount, 1)
        XCTAssertEqual(mockBatchAssembler.prepareCombinedVideoCallCount, 1)
        XCTAssertEqual(mockProviderFactory.mockProvider?.transcribeVideoCallCount, 1)
        XCTAssertEqual(mockTimelineUpdater.saveObservationsCallCount, 1)
        XCTAssertEqual(mockTimelineUpdater.fetchObservationsCallCount, 1)
        XCTAssertEqual(mockTimelineUpdater.fetchTimelineCardsCallCount, 1)
        XCTAssertEqual(mockProviderFactory.mockProvider?.generateActivityCardsCallCount, 1)
        XCTAssertEqual(mockTimelineUpdater.replaceTimelineCardsCallCount, 1)
        XCTAssertEqual(mockTimelineUpdater.markBatchAsAnalyzedCallCount, 1)
    }
    
    func testProcessBatchAsync_EmptyObservations() async throws {
        // Given: Setup that returns empty observations
        let batchId: Int64 = 123
        let batchInfo = (batchId, 1000, 2000, "pending")
        let chunkFiles = ["/path/to/chunk1.mp4"]
        let videoData = Data(repeating: 0x42, count: 1024)
        let emptyObservations: [Observation] = []
        
        mockTimelineUpdater.batchInfo = batchInfo
        mockTimelineUpdater.chunkFiles = chunkFiles
        mockProviderFactory.mockProvider = MockLLMProvider()
        mockBatchAssembler.videoData = videoData
        mockBatchAssembler.duration = 60.0
        mockProviderFactory.mockProvider?.observations = emptyObservations
        
        // When: Processing batch
        let result = try await llmService.processBatchAsync(batchId)
        
        // Then: Should return empty result
        XCTAssertEqual(result.cards.count, 0)
        XCTAssertEqual(result.cardIds.count, 0)
        
        // And: Should mark batch as analyzed
        XCTAssertEqual(mockTimelineUpdater.markBatchAsAnalyzedCallCount, 1)
        
        // And: Should track empty observations
        let emptyObservationsEvents = mockAnalyticsService.capturedEvents.filter { $0.event == "transcription_returned_empty" }
        XCTAssertEqual(emptyObservationsEvents.count, 1)
    }
    
    func testProcessBatchAsync_BatchNotFound() async {
        // Given: No batch info found
        let batchId: Int64 = 123
        mockTimelineUpdater.batchInfo = nil
        
        // When & Then: Should throw error
        do {
            _ = try await llmService.processBatchAsync(batchId)
            XCTFail("Expected error to be thrown")
        } catch let error as LLMServiceError {
            XCTAssertEqual(error, .batchNotFound(batchId))
        }
    }
    
    func testProcessBatchAsync_NoProviderConfigured() async {
        // Given: Batch exists but no provider
        let batchId: Int64 = 123
        let batchInfo = (batchId, 1000, 2000, "pending")
        mockTimelineUpdater.batchInfo = batchInfo
        mockProviderFactory.shouldThrowError = true
        mockProviderFactory.errorToThrow = LLMServiceError.noProviderConfigured
        
        // When & Then: Should throw error
        do {
            _ = try await llmService.processBatchAsync(batchId)
            XCTFail("Expected error to be thrown")
        } catch let error as LLMServiceError {
            XCTAssertEqual(error, .noProviderConfigured)
        }
        
        // And: Should mark batch as failed
        XCTAssertEqual(mockTimelineUpdater.markBatchAsFailedCallCount, 1)
        
        // And: Should create error card
        XCTAssertEqual(mockTimelineUpdater.replaceTimelineCardsCallCount, 1)
    }
    
    func testProcessBatchAsync_VideoProcessingError() async {
        // Given: Video processing fails
        let batchId: Int64 = 123
        let batchInfo = (batchId, 1000, 2000, "pending")
        let chunkFiles = ["/path/to/chunk1.mp4"]
        
        mockTimelineUpdater.batchInfo = batchInfo
        mockTimelineUpdater.chunkFiles = chunkFiles
        mockProviderFactory.mockProvider = MockLLMProvider()
        mockBatchAssembler.shouldThrowError = true
        mockBatchAssembler.errorToThrow = VideoProcessingError.invalidInputURL
        
        // When & Then: Should throw error
        do {
            _ = try await llmService.processBatchAsync(batchId)
            XCTFail("Expected error to be thrown")
        } catch let error as LLMServiceError {
            if case .videoProcessingFailed(let videoError) = error {
                XCTAssertTrue(videoError is VideoProcessingError)
            } else {
                XCTFail("Expected videoProcessingFailed error")
            }
        }
        
        // And: Should mark batch as failed and create error card
        XCTAssertEqual(mockTimelineUpdater.markBatchAsFailedCallCount, 1)
        XCTAssertEqual(mockTimelineUpdater.replaceTimelineCardsCallCount, 1)
    }
    
    func testProcessBatchAsync_ProviderError() async {
        // Given: Provider throws error
        let batchId: Int64 = 123
        let batchInfo = (batchId, 1000, 2000, "pending")
        let chunkFiles = ["/path/to/chunk1.mp4"]
        let videoData = Data(repeating: 0x42, count: 1024)
        
        mockTimelineUpdater.batchInfo = batchInfo
        mockTimelineUpdater.chunkFiles = chunkFiles
        mockProviderFactory.mockProvider = MockLLMProvider()
        mockBatchAssembler.videoData = videoData
        mockBatchAssembler.duration = 60.0
        mockProviderFactory.mockProvider?.shouldThrowError = true
        mockProviderFactory.mockProvider?.errorToThrow = NSError(domain: "TestProvider", code: 500, userInfo: [NSLocalizedDescriptionKey: "Provider error"])
        
        // When & Then: Should throw error
        do {
            _ = try await llmService.processBatchAsync(batchId)
            XCTFail("Expected error to be thrown")
        } catch {
            // Should re-throw the provider error
            XCTAssertTrue(error.localizedDescription.contains("Provider error"))
        }
        
        // And: Should mark batch as failed and create error card
        XCTAssertEqual(mockTimelineUpdater.markBatchAsFailedCallCount, 1)
        XCTAssertEqual(mockTimelineUpdater.replaceTimelineCardsCallCount, 1)
    }
    
    func testProcessBatch_BackwardCompatibility() async throws {
        // Given: Setup for callback-based method
        let batchId: Int64 = 123
        let batchInfo = (batchId, 1000, 2000, "pending")
        let chunkFiles = ["/path/to/chunk1.mp4"]
        let videoData = Data(repeating: 0x42, count: 1024)
        let observations = [
            Observation(
                id: 1,
                batchId: 123,
                startTs: 1000,
                endTs: 1500,
                observation: "Test observation",
                metadata: nil,
                llmModel: nil,
                createdAt: Date()
            )
        ]
        let cards = [
            ActivityCardData(
                startTime: "9:00 AM",
                endTime: "10:00 AM",
                category: "Work",
                subcategory: "Coding",
                title: "Development",
                summary: "Writing code",
                detailedSummary: "Working on features",
                distractions: nil,
                appSites: nil
            )
        ]
        
        mockTimelineUpdater.batchInfo = batchInfo
        mockTimelineUpdater.chunkFiles = chunkFiles
        mockProviderFactory.mockProvider = MockLLMProvider()
        mockBatchAssembler.videoData = videoData
        mockBatchAssembler.duration = 60.0
        mockProviderFactory.mockProvider?.observations = observations
        mockProviderFactory.mockProvider?.cards = cards
        mockTimelineUpdater.insertedCardIds = [456]
        mockTimelineUpdater.deletedVideoPaths = []
        
        // When: Using callback-based method
        let expectation = XCTestExpectation(description: "Process batch completes")
        var result: Result<ProcessedBatchResult, Error>?
        
        llmService.processBatch(batchId) { completionResult in
            result = completionResult
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Then: Should return success
        switch result {
        case .success(let processedResult):
            XCTAssertEqual(processedResult.cards.count, 1)
            XCTAssertEqual(processedResult.cardIds, [456])
        case .failure(let error):
            XCTFail("Expected success but got error: \(error)")
        case .none:
            XCTFail("Expected result but got nil")
        }
    }
}

// MARK: - Mock Classes

class MockProviderFactory: ProviderFactory {
    var mockProvider: MockLLMProvider?
    var shouldThrowError = false
    var errorToThrow: Error?
    
    var getProviderCallCount = 0
    
    override func getProvider() async throws -> LLMProvider {
        getProviderCallCount += 1
        
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        
        guard let provider = mockProvider else {
            throw LLMServiceError.noProviderConfigured
        }
        
        return provider
    }
    
    override func getProviderName() async -> String {
        return "mock"
    }
}

class MockBatchAssembler: BatchAssembler {
    var videoData: Data?
    var duration: TimeInterval = 0.0
    var shouldThrowError = false
    var errorToThrow: Error?
    
    var prepareCombinedVideoCallCount = 0
    
    override func prepareCombinedVideo(from chunkFilePaths: [String], batchId: Int64) async throws -> (data: Data, mimeType: String, duration: TimeInterval) {
        prepareCombinedVideoCallCount += 1
        
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        
        guard let videoData = videoData else {
            throw LLMServiceError.noRecordingsInBatch
        }
        
        return (videoData, "video/mp4", duration)
    }
}

class MockTimelineUpdater: TimelineUpdater {
    // Mock data
    var batchInfo: (Int64, Int, Int, String)?
    var chunkFiles: [String] = []
    var insertedCardIds: [Int64] = []
    var deletedVideoPaths: [String] = []
    
    // Call tracking
    var getBatchInfoCallCount = 0
    var markBatchAsProcessingCallCount = 0
    var markBatchAsAnalyzedCallCount = 0
    var markBatchAsFailedCallCount = 0
    var getChunkFilesCallCount = 0
    var saveObservationsCallCount = 0
    var fetchObservationsCallCount = 0
    var fetchTimelineCardsCallCount = 0
    var replaceTimelineCardsCallCount = 0
    
    override func getBatchInfo(for batchId: Int64) -> (id: Int64, startTs: Int, endTs: Int, status: String)? {
        getBatchInfoCallCount += 1
        return batchInfo
    }
    
    override func markBatchAsProcessing(_ batchId: Int64) async throws {
        markBatchAsProcessingCallCount += 1
    }
    
    override func markBatchAsAnalyzed(_ batchId: Int64) async throws {
        markBatchAsAnalyzedCallCount += 1
    }
    
    override func markBatchAsFailed(_ batchId: Int64, reason: String) async throws {
        markBatchAsFailedCallCount += 1
    }
    
    override func getChunkFiles(for batchId: Int64) -> [String] {
        getChunkFilesCallCount += 1
        return chunkFiles
    }
    
    override func saveObservations(_ observations: [Observation], for batchId: Int64) async throws {
        saveObservationsCallCount += 1
    }
    
    override func fetchObservations(in timeRange: Range<Date>) async -> [Observation] {
        fetchObservationsCallCount += 1
        return []
    }
    
    override func fetchTimelineCards(in timeRange: Range<Date>) async -> [TimelineCard] {
        fetchTimelineCardsCallCount += 1
        return []
    }
    
    override func replaceTimelineCards(with cards: [ActivityCardData], batchId: Int64, in timeRange: Range<Date>) async throws -> (insertedIds: [Int64], deletedVideoPaths: [String]) {
        replaceTimelineCardsCallCount += 1
        return (insertedCardIds, deletedVideoPaths)
    }
}

class MockAnalyticsService: AnalyticsService {
    var capturedEvents: [(event: String, properties: [String: Any])] = []
    var captureCallCount = 0
    
    override func capture(_ event: String, properties: [String: Any]? = nil) async {
        captureCallCount += 1
        capturedEvents.append((event: event, properties: properties ?? [:]))
    }
}

class MockLLMProvider: LLMProvider {
    var observations: [Observation] = []
    var cards: [ActivityCardData] = []
    var shouldThrowError = false
    var errorToThrow: Error?
    
    var transcribeVideoCallCount = 0
    var generateActivityCardsCallCount = 0
    
    func transcribeVideo(videoData: Data, mimeType: String, prompt: String, batchStartTime: Date, videoDuration: TimeInterval, batchId: Int64?) async throws -> (observations: [Observation], log: LLMCall) {
        transcribeVideoCallCount += 1
        
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        
        let log = LLMCall(
            id: 1,
            batchId: batchId ?? 0,
            provider: "mock",
            callType: "transcribe",
            input: prompt,
            output: "Mock transcription",
            latency: 1.0,
            createdAt: Date(),
            tokensUsed: 100
        )
        
        return (observations, log)
    }
    
    func generateActivityCards(observations: [Observation], context: ActivityGenerationContext, batchId: Int64?) async throws -> (cards: [ActivityCardData], log: LLMCall) {
        generateActivityCardsCallCount += 1
        
        if shouldThrowError, let error = errorToThrow {
            throw error
        }
        
        let log = LLMCall(
            id: 2,
            batchId: batchId ?? 0,
            provider: "mock",
            callType: "generate_cards",
            input: "Mock card generation",
            output: "Mock cards",
            latency: 0.5,
            createdAt: Date(),
            tokensUsed: 50
        )
        
        return (cards, log)
    }
}