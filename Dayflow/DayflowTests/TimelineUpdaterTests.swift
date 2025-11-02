//
//  TimelineUpdaterTests.swift
//  DayflowTests
//

import XCTest
@testable import Dayflow

final class TimelineUpdaterTests: XCTestCase {
    private var mockStorage: MockStorageManaging!
    private var timelineUpdater: TimelineUpdater!
    
    override func setUp() async throws {
        mockStorage = MockStorageManaging()
        timelineUpdater = TimelineUpdater(storage: mockStorage)
    }
    
    func testMarkBatchAsProcessing() async throws {
        // Given: Batch ID
        let batchId: Int64 = 123
        
        // When: Marking as processing
        try await timelineUpdater.markBatchAsProcessing(batchId)
        
        // Then: Should update storage
        XCTAssertEqual(mockStorage.updateBatchStatusCallCount, 1)
        XCTAssertEqual(mockStorage.lastBatchId, batchId)
        XCTAssertEqual(mockStorage.lastStatus, "processing")
    }
    
    func testMarkBatchAsAnalyzed() async throws {
        // Given: Batch ID
        let batchId: Int64 = 123
        
        // When: Marking as analyzed
        try await timelineUpdater.markBatchAsAnalyzed(batchId)
        
        // Then: Should update storage
        XCTAssertEqual(mockStorage.updateBatchStatusCallCount, 1)
        XCTAssertEqual(mockStorage.lastBatchId, batchId)
        XCTAssertEqual(mockStorage.lastStatus, "analyzed")
    }
    
    func testMarkBatchAsFailed() async throws {
        // Given: Batch ID and reason
        let batchId: Int64 = 123
        let reason = "Test failure"
        
        // When: Marking as failed
        try await timelineUpdater.markBatchAsFailed(batchId, reason: reason)
        
        // Then: Should update storage
        XCTAssertEqual(mockStorage.markBatchFailedCallCount, 1)
        XCTAssertEqual(mockStorage.lastFailedBatchId, batchId)
        XCTAssertEqual(mockStorage.lastFailureReason, reason)
    }
    
    func testSaveObservations() async throws {
        // Given: Observations and batch ID
        let observations = [
            Observation(
                id: 1,
                batchId: 123,
                startTs: 1000,
                endTs: 1500,
                observation: "Test observation 1",
                metadata: nil,
                llmModel: nil,
                createdAt: Date()
            ),
            Observation(
                id: 2,
                batchId: 123,
                startTs: 1500,
                endTs: 2000,
                observation: "Test observation 2",
                metadata: nil,
                llmModel: nil,
                createdAt: Date()
            )
        ]
        let batchId: Int64 = 123
        
        // When: Saving observations
        try await timelineUpdater.saveObservations(observations, for: batchId)
        
        // Then: Should save to storage
        XCTAssertEqual(mockStorage.saveObservationsCallCount, 1)
        XCTAssertEqual(mockStorage.lastSavedBatchId, batchId)
        XCTAssertEqual(mockStorage.lastSavedObservations.count, 2)
    }
    
    func testReplaceTimelineCards() async throws {
        // Given: Cards and time range
        let cards = [
            ActivityCardData(
                startTime: "9:00 AM",
                endTime: "10:00 AM",
                category: "Work",
                subcategory: "Coding",
                title: "Development",
                summary: "Writing code",
                detailedSummary: "Working on new features",
                distractions: nil,
                appSites: nil
            )
        ]
        let batchId: Int64 = 123
        let timeRange = Date()..<Date().addingTimeInterval(3600)
        
        let expectedInsertedIds = [456, 789]
        let expectedDeletedPaths = ["/path/to/video1.mp4", "/path/to/video2.mp4"]
        mockStorage.insertedCardIds = expectedInsertedIds
        mockStorage.deletedVideoPaths = expectedDeletedPaths
        
        // When: Replacing timeline cards
        let result = try await timelineUpdater.replaceTimelineCards(
            with: cards,
            batchId: batchId,
            in: timeRange
        )
        
        // Then: Should call storage and return results
        XCTAssertEqual(mockStorage.replaceTimelineCardsInRangeCallCount, 1)
        XCTAssertEqual(result.insertedIds, expectedInsertedIds)
        XCTAssertEqual(result.deletedVideoPaths, expectedDeletedPaths)
    }
    
    func testCreateErrorCard() async {
        // Given: Batch info and error
        let batchId: Int64 = 123
        let batchStartTime = Date()
        let batchEndTime = batchStartTime.addingTimeInterval(1800) // 30 minutes
        let error = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        
        // When: Creating error card
        let errorCard = await timelineUpdater.createErrorCard(
            for: batchId,
            batchStartTime: batchStartTime,
            batchEndTime: batchEndTime,
            error: error
        )
        
        // Then: Should create appropriate error card
        XCTAssertEqual(errorCard.category, "System")
        XCTAssertEqual(errorCard.subcategory, "Error")
        XCTAssertEqual(errorCard.title, "Processing failed")
        XCTAssertTrue(errorCard.summary.contains("30 minutes"))
        XCTAssertTrue(errorCard.detailedSummary.contains("batch ID: \(batchId)"))
    }
    
    func testFetchObservations() async {
        // Given: Time range
        let timeRange = Date()..<Date().addingTimeInterval(3600)
        let expectedObservations = [
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
        mockStorage.observations = expectedObservations
        
        // When: Fetching observations
        let result = await timelineUpdater.fetchObservations(in: timeRange)
        
        // Then: Should return observations from storage
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.observation, "Test observation")
        XCTAssertEqual(mockStorage.fetchObservationsByTimeRangeCallCount, 1)
    }
    
    func testFetchTimelineCards() async {
        // Given: Time range
        let timeRange = Date()..<Date().addingTimeInterval(3600)
        let expectedCards = [
            TimelineCard(
                id: 1,
                startTimestamp: "9:00 AM",
                endTimestamp: "10:00 AM",
                category: "Work",
                subcategory: "Coding",
                title: "Development",
                summary: "Writing code",
                detailedSummary: "Working on features",
                distractions: nil,
                appSites: nil,
                batchId: 123
            )
        ]
        mockStorage.timelineCards = expectedCards
        
        // When: Fetching timeline cards
        let result = await timelineUpdater.fetchTimelineCards(in: timeRange)
        
        // Then: Should return cards from storage
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.category, "Work")
        XCTAssertEqual(mockStorage.fetchTimelineCardsByTimeRangeCallCount, 1)
    }
    
    func testGetChunkFiles() async {
        // Given: Batch ID
        let batchId: Int64 = 123
        let expectedChunkFiles = ["/path/to/chunk1.mp4", "/path/to/chunk2.mp4"]
        mockStorage.chunkFiles = expectedChunkFiles
        
        // When: Getting chunk files
        let result = await timelineUpdater.getChunkFiles(for: batchId)
        
        // Then: Should return chunk files from storage
        XCTAssertEqual(result, expectedChunkFiles)
    }
    
    func testGetBatchInfo() async {
        // Given: Batch ID
        let batchId: Int64 = 123
        let expectedBatchInfo = (batchId, 1000, 2000, "pending")
        mockStorage.batches = [expectedBatchInfo]
        
        // When: Getting batch info
        let result = await timelineUpdater.getBatchInfo(for: batchId)
        
        // Then: Should return batch info from storage
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, batchId)
        XCTAssertEqual(result?.startTs, 1000)
        XCTAssertEqual(result?.endTs, 2000)
        XCTAssertEqual(result?.status, "pending")
    }
}

// MARK: - Mock StorageManaging

class MockStorageManaging: StorageManaging {
    // Call tracking
    var updateBatchStatusCallCount = 0
    var markBatchFailedCallCount = 0
    var saveObservationsCallCount = 0
    var replaceTimelineCardsInRangeCallCount = 0
    var fetchObservationsByTimeRangeCallCount = 0
    var fetchTimelineCardsByTimeRangeCallCount = 0
    var allBatchesCallCount = 0
    var getChunkFilesForBatchCallCount = 0
    
    // Last call parameters
    var lastBatchId: Int64?
    var lastStatus: String?
    var lastFailedBatchId: Int64?
    var lastFailureReason: String?
    var lastSavedBatchId: Int64?
    var lastSavedObservations: [Observation] = []
    
    // Mock data
    var insertedCardIds: [Int64] = []
    var deletedVideoPaths: [String] = []
    var observations: [Observation] = []
    var timelineCards: [TimelineCard] = []
    var batches: [(Int64, Int, Int, String)] = []
    var chunkFiles: [String] = []
    
    // MARK: - StorageManaging Implementation
    
    func nextFileURL() -> URL {
        return URL(fileURLWithPath: "/tmp/test.mp4")
    }
    
    func registerChunk(url: URL) {
        // Mock implementation
    }
    
    func markChunkCompleted(url: URL) {
        // Mock implementation
    }
    
    func markChunkFailed(url: URL) {
        // Mock implementation
    }
    
    func fetchUnprocessedChunks(olderThan oldestAllowed: Int) -> [RecordingChunk] {
        return []
    }
    
    func fetchChunksInTimeRange(startTs: Int, endTs: Int) -> [RecordingChunk] {
        return []
    }
    
    func saveBatch(startTs: Int, endTs: Int, chunkIds: [Int64]) -> Int64? {
        return 123
    }
    
    func updateBatchStatus(_ batchId: Int64, status: String) {
        updateBatchStatusCallCount += 1
        lastBatchId = batchId
        lastStatus = status
    }
    
    func markBatchFailed(_ batchId: Int64, reason: String) {
        markBatchFailedCallCount += 1
        lastFailedBatchId = batchId
        lastFailureReason = reason
    }
    
    func updateBatchLLMMetadata(batchId: Int64, calls: [LLMCall]) {
        // Mock implementation
    }
    
    func fetchBatchLLMMetadata(batchId: Int64) -> [LLMCall] {
        return []
    }
    
    func saveTimelineCardShell(batchId: Int64, card: TimelineCardShell) -> Int64? {
        return 456
    }
    
    func updateTimelineCardVideoURL(cardId: Int64, videoSummaryURL: String) {
        // Mock implementation
    }
    
    func fetchTimelineCards(forBatch batchId: Int64) -> [TimelineCard] {
        return []
    }
    
    func fetchTimelineCard(byId id: Int64) -> TimelineCardWithTimestamps? {
        return nil
    }
    
    func fetchTimelineCards(forDay day: String) -> [TimelineCard] {
        return []
    }
    
    func fetchTimelineCardsByTimeRange(from: Date, to: Date) -> [TimelineCard] {
        fetchTimelineCardsByTimeRangeCallCount += 1
        return timelineCards
    }
    
    func replaceTimelineCardsInRange(from: Date, to: Date, with: [TimelineCardShell], batchId: Int64) -> (insertedIds: [Int64], deletedVideoPaths: [String]) {
        replaceTimelineCardsInRangeCallCount += 1
        return (insertedCardIds, deletedVideoPaths)
    }
    
    func fetchRecentTimelineCardsForDebug(limit: Int) -> [TimelineCardDebugEntry] {
        return []
    }
    
    func fetchRecentLLMCallsForDebug(limit: Int) -> [LLMCallDebugEntry] {
        return []
    }
    
    func fetchRecentAnalysisBatchesForDebug(limit: Int) -> [AnalysisBatchDebugEntry] {
        return []
    }
    
    func fetchLLMCallsForBatches(batchIds: [Int64], limit: Int) -> [LLMCallDebugEntry] {
        return []
    }
    
    func saveObservations(batchId: Int64, observations: [Observation]) {
        saveObservationsCallCount += 1
        lastSavedBatchId = batchId
        lastSavedObservations = observations
    }
    
    func fetchObservations(batchId: Int64) -> [Observation] {
        return []
    }
    
    func fetchObservations(startTs: Int, endTs: Int) -> [Observation] {
        return []
    }
    
    func fetchObservationsByTimeRange(from: Date, to: Date) -> [Observation] {
        fetchObservationsByTimeRangeCallCount += 1
        return observations
    }
    
    func getTimestampsForVideoFiles(paths: [String]) -> [String: (startTs: Int, endTs: Int)] {
        return [:]
    }
    
    func deleteTimelineCards(forDay day: String) -> [String] {
        return []
    }
    
    func deleteTimelineCards(forBatchIds batchIds: [Int64]) -> [String] {
        return []
    }
    
    func deleteObservations(forBatchIds batchIds: [Int64]) {
        // Mock implementation
    }
    
    func resetBatchStatuses(forDay day: String) -> [Int64] {
        return []
    }
    
    func resetBatchStatuses(forBatchIds batchIds: [Int64]) -> [Int64] {
        return []
    }
    
    func allBatches() -> [(Int64, Int, Int, String)] {
        allBatchesCallCount += 1
        return batches
    }
    
    func getChunkFilesForBatch(batchId: Int64) -> [String] {
        getChunkFilesForBatchCallCount += 1
        return chunkFiles
    }
}