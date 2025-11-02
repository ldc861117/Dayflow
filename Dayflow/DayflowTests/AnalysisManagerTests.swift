import XCTest
@testable import Dayflow

final class AnalysisManagerTests: XCTestCase {
    
    // MARK: - Mock Implementations
    
    class MockStorageManager: StorageManaging {
        var chunks: [RecordingChunk] = []
        var batches: [MockBatch] = []
        var batchChunks: [Int64: [RecordingChunk]] = [:]
        var timelineCards: [Int64: MockTimelineCard] = [:]
        var batchStatuses: [Int64: String] = [:]
        
        func nextFileURL() -> URL {
            URL(fileURLWithPath: "/tmp/test.mov")
        }
        
        func registerChunk(url: URL) {}
        func markChunkCompleted(url: URL) {}
        func markChunkFailed(url: URL) {}
        
        func fetchUnprocessedChunks(olderThan oldestAllowed: Int) -> [RecordingChunk] {
            return chunks.filter { $0.startTs >= oldestAllowed }
        }
        
        func fetchChunksInTimeRange(startTs: Int, endTs: Int) -> [RecordingChunk] {
            return chunks.filter { $0.startTs >= startTs && $0.endTs <= endTs }
        }
        
        func saveBatch(startTs: Int, endTs: Int, chunkIds: [Int64]) -> Int64? {
            let batchId = Int64(batches.count + 1)
            batches.append(MockBatch(id: batchId, startTs: startTs, endTs: endTs, status: "pending"))
            let batchChunksForId = chunks.filter { chunkIds.contains($0.id) }
            batchChunks[batchId] = batchChunksForId
            batchStatuses[batchId] = "pending"
            return batchId
        }
        
        func updateBatchStatus(batchId: Int64, status: String) {
            if let index = batches.firstIndex(where: { $0.id == batchId }) {
                batches[index].status = status
            }
            batchStatuses[batchId] = status
        }
        
        func markBatchFailed(batchId: Int64, reason: String) {
            updateBatchStatus(batchId: batchId, status: "failed")
        }
        
        func updateBatchLLMMetadata(batchId: Int64, calls: [LLMCall]) {}
        func fetchBatchLLMMetadata(batchId: Int64) -> [LLMCall] { [] }
        
        func saveTimelineCardShell(batchId: Int64, card: TimelineCardShell) -> Int64? {
            let cardId = Int64(timelineCards.count + 1)
            timelineCards[cardId] = MockTimelineCard(
                id: cardId,
                batchId: batchId,
                startTs: card.startTs,
                endTs: card.endTs,
                title: card.title
            )
            return cardId
        }
        
        func updateTimelineCardVideoURL(cardId: Int64, videoSummaryURL: String) {
            timelineCards[cardId]?.videoURL = videoSummaryURL
        }
        
        func fetchTimelineCards(forBatch batchId: Int64) -> [TimelineCard] { [] }
        func fetchTimelineCard(byId id: Int64) -> TimelineCardWithTimestamps? {
            guard let mock = timelineCards[id] else { return nil }
            return TimelineCardWithTimestamps(
                id: mock.id,
                startTs: mock.startTs,
                endTs: mock.endTs,
                title: mock.title,
                startTimestamp: Date(timeIntervalSince1970: TimeInterval(mock.startTs)),
                endTimestamp: Date(timeIntervalSince1970: TimeInterval(mock.endTs))
            )
        }
        
        func fetchTimelineCards(forDay day: String) -> [TimelineCard] { [] }
        func fetchTimelineCardsByTimeRange(from: Date, to: Date) -> [TimelineCard] { [] }
        func replaceTimelineCardsInRange(from: Date, to: Date, with: [TimelineCardShell], batchId: Int64) -> (insertedIds: [Int64], deletedVideoPaths: [String]) {
            ([], [])
        }
        func fetchRecentTimelineCardsForDebug(limit: Int) -> [TimelineCardDebugEntry] { [] }
        func fetchRecentLLMCallsForDebug(limit: Int) -> [LLMCallDebugEntry] { [] }
        func fetchRecentAnalysisBatchesForDebug(limit: Int) -> [AnalysisBatchDebugEntry] { [] }
        func fetchLLMCallsForBatches(batchIds: [Int64], limit: Int) -> [LLMCallDebugEntry] { [] }
        
        func saveObservations(batchId: Int64, observations: [Observation]) {}
        func fetchObservations(batchId: Int64) -> [Observation] { [] }
        func fetchObservations(startTs: Int, endTs: Int) -> [Observation] { [] }
        func fetchObservationsByTimeRange(from: Date, to: Date) -> [Observation] { [] }
        
        func getTimestampsForVideoFiles(paths: [String]) -> [String: (startTs: Int, endTs: Int)] { [:] }
        
        func deleteTimelineCards(forDay day: String) -> [String] { [] }
        func deleteTimelineCards(forBatchIds batchIds: [Int64]) -> [String] { [] }
        func deleteObservations(forBatchIds batchIds: [Int64]) {}
        
        func resetBatchStatuses(forDay day: String) -> [Int64] {
            let dayBatches = batches.filter { _ in true } // Simplified for testing
            return dayBatches.map { batch in
                updateBatchStatus(batchId: batch.id, status: "pending")
                return batch.id
            }
        }
        
        func resetBatchStatuses(forBatchIds batchIds: [Int64]) -> [Int64] {
            for batchId in batchIds {
                updateBatchStatus(batchId: batchId, status: "pending")
            }
            return batchIds
        }
        
        func chunksForBatch(_ batchId: Int64) -> [RecordingChunk] {
            return batchChunks[batchId] ?? []
        }
        
        func allBatches() -> [(id: Int64, start: Int, end: Int, status: String)] {
            return batches.map { (id: $0.id, start: $0.startTs, end: $0.endTs, status: $0.status) }
        }
        
        func fetchBatches(forDay day: String) -> [(id: Int64, startTs: Int, endTs: Int, status: String)] {
            return batches.map { (id: $0.id, startTs: $0.startTs, endTs: $0.endTs, status: $0.status) }
        }
    }
    
    struct MockBatch {
        let id: Int64
        let startTs: Int
        let endTs: Int
        var status: String
    }
    
    struct MockTimelineCard {
        let id: Int64
        let batchId: Int64
        let startTs: Int
        let endTs: Int
        let title: String
        var videoURL: String?
    }
    
    class MockLLMService: LLMServicing {
        var shouldSucceed = true
        var processBatchCalled = false
        var processedBatchIds: [Int64] = []
        
        func processBatch(_ batchId: Int64, completion: @escaping (Result<ProcessedBatchResult, Error>) -> Void) {
            processBatchCalled = true
            processedBatchIds.append(batchId)
            
            if shouldSucceed {
                let card = ActivityCardData(
                    startTime: "09:00 AM",
                    endTime: "09:15 AM",
                    title: "Test Activity",
                    category: "Work",
                    summary: "Test summary",
                    detailedSummary: "Test detailed summary"
                )
                
                // Simulate async processing
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    completion(.success(ProcessedBatchResult(cards: [card], cardIds: [1])))
                }
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    completion(.failure(NSError(domain: "MockLLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock failure"])))
                }
            }
        }
    }
    
    class MockVideoProcessingService: VideoProcessingService {
        // Inherits from VideoProcessingService, no mocking needed for basic tests
    }
    
    // MARK: - Tests
    
    func testHappyPathAnalysis() async throws {
        // Given: A storage manager with unprocessed chunks
        let mockStorage = MockStorageManager()
        let now = Int(Date().timeIntervalSince1970)
        
        // Create test chunks spanning 15 minutes
        for i in 0..<60 { // 60 chunks × 15s = 900s = 15 min
            let chunk = RecordingChunk(
                id: Int64(i),
                startTs: now + (i * 15),
                endTs: now + ((i + 1) * 15),
                fileUrl: "/tmp/chunk_\(i).mov",
                status: "completed"
            )
            mockStorage.chunks.append(chunk)
        }
        
        let mockLLM = MockLLMService()
        let mockVideo = MockVideoProcessingService()
        
        // When: Analysis manager processes recordings
        let manager = AnalysisManager(
            store: mockStorage,
            llmService: mockLLM,
            videoProcessingService: mockVideo
        )
        
        await manager.triggerAnalysisNow()
        
        // Wait a bit for async processing
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        // Then: Batch should be created and LLM should be called
        XCTAssertTrue(mockLLM.processBatchCalled, "LLM service should have been called")
        XCTAssertEqual(mockStorage.batches.count, 1, "One batch should be created")
        XCTAssertEqual(mockStorage.batches.first?.status, "completed", "Batch should be completed")
    }
    
    func testBatchingLogic() async throws {
        // Given: Multiple chunks with varying durations
        let mockStorage = MockStorageManager()
        let now = Int(Date().timeIntervalSince1970)
        
        // Create 30 minutes of chunks (should create 2 batches)
        for i in 0..<120 {
            let chunk = RecordingChunk(
                id: Int64(i),
                startTs: now + (i * 15),
                endTs: now + ((i + 1) * 15),
                fileUrl: "/tmp/chunk_\(i).mov",
                status: "completed"
            )
            mockStorage.chunks.append(chunk)
        }
        
        let mockLLM = MockLLMService()
        let mockVideo = MockVideoProcessingService()
        
        let manager = AnalysisManager(
            store: mockStorage,
            llmService: mockLLM,
            videoProcessingService: mockVideo
        )
        
        // When: Triggering analysis
        await manager.triggerAnalysisNow()
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Two batches should be created (first full 15min, second partial will be dropped)
        XCTAssertEqual(mockStorage.batches.count, 1, "Only complete batches should be created")
    }
    
    func testReprocessDay() async throws {
        // Given: A storage manager with an existing batch
        let mockStorage = MockStorageManager()
        let now = Int(Date().timeIntervalSince1970)
        
        // Add a batch that needs reprocessing
        let batchId = mockStorage.saveBatch(startTs: now, endTs: now + 900, chunkIds: [1, 2, 3])!
        
        // Add chunks for this batch
        for i in 1...3 {
            let chunk = RecordingChunk(
                id: Int64(i),
                startTs: now + ((i - 1) * 300),
                endTs: now + (i * 300),
                fileUrl: "/tmp/chunk_\(i).mov",
                status: "completed"
            )
            mockStorage.chunks.append(chunk)
        }
        mockStorage.batchChunks[batchId] = mockStorage.chunks
        
        let mockLLM = MockLLMService()
        let mockVideo = MockVideoProcessingService()
        
        let manager = AnalysisManager(
            store: mockStorage,
            llmService: mockLLM,
            videoProcessingService: mockVideo
        )
        
        // When: Reprocessing a day
        let expectation = XCTestExpectation(description: "Reprocess completes")
        var progressUpdates: [String] = []
        var completionResult: Result<Void, Error>?
        
        manager.reprocessDay(
            "2025-01-01",
            progressHandler: { progress in
                progressUpdates.append(progress)
            },
            completion: { result in
                completionResult = result
                expectation.fulfill()
            }
        )
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Then: Batch should be reset and reprocessed
        XCTAssertNotNil(completionResult, "Completion should be called")
        if case .success = completionResult {
            XCTAssertTrue(true, "Reprocessing succeeded")
        } else {
            XCTFail("Reprocessing should succeed")
        }
        XCTAssertTrue(progressUpdates.count > 0, "Progress updates should be sent")
    }
    
    func testReprocessSpecificBatches() async throws {
        // Given: Multiple batches
        let mockStorage = MockStorageManager()
        let now = Int(Date().timeIntervalSince1970)
        
        let batchId1 = mockStorage.saveBatch(startTs: now, endTs: now + 900, chunkIds: [1])!
        let batchId2 = mockStorage.saveBatch(startTs: now + 900, endTs: now + 1800, chunkIds: [2])!
        
        // Add chunks
        for i in 1...2 {
            let chunk = RecordingChunk(
                id: Int64(i),
                startTs: now + ((i - 1) * 900),
                endTs: now + (i * 900),
                fileUrl: "/tmp/chunk_\(i).mov",
                status: "completed"
            )
            mockStorage.chunks.append(chunk)
        }
        mockStorage.batchChunks[batchId1] = [mockStorage.chunks[0]]
        mockStorage.batchChunks[batchId2] = [mockStorage.chunks[1]]
        
        let mockLLM = MockLLMService()
        let mockVideo = MockVideoProcessingService()
        
        let manager = AnalysisManager(
            store: mockStorage,
            llmService: mockLLM,
            videoProcessingService: mockVideo
        )
        
        // When: Reprocessing specific batches
        let expectation = XCTestExpectation(description: "Reprocess specific batches completes")
        var completionResult: Result<Void, Error>?
        
        manager.reprocessSpecificBatches(
            [batchId1],
            progressHandler: { _ in },
            completion: { result in
                completionResult = result
                expectation.fulfill()
            }
        )
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Then: Only the specified batch should be reprocessed
        XCTAssertNotNil(completionResult, "Completion should be called")
        if case .success = completionResult {
            XCTAssertTrue(true, "Reprocessing succeeded")
        } else {
            XCTFail("Reprocessing should succeed")
        }
    }
    
    func testMinimumDurationCheck() async throws {
        // Given: Chunks totaling less than 5 minutes
        let mockStorage = MockStorageManager()
        let now = Int(Date().timeIntervalSince1970)
        
        // Only 3 minutes of chunks (12 × 15s = 180s)
        for i in 0..<12 {
            let chunk = RecordingChunk(
                id: Int64(i),
                startTs: now + (i * 15),
                endTs: now + ((i + 1) * 15),
                fileUrl: "/tmp/chunk_\(i).mov",
                status: "completed"
            )
            mockStorage.chunks.append(chunk)
        }
        
        let mockLLM = MockLLMService()
        let mockVideo = MockVideoProcessingService()
        
        let manager = AnalysisManager(
            store: mockStorage,
            llmService: mockLLM,
            videoProcessingService: mockVideo
        )
        
        // When: Processing recordings
        await manager.triggerAnalysisNow()
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Then: No batch should be created (under 15 min threshold)
        XCTAssertEqual(mockStorage.batches.count, 0, "Batches under 15 min should be dropped")
        XCTAssertFalse(mockLLM.processBatchCalled, "LLM should not be called for short batches")
    }
    
    func testFailedBatchHandling() async throws {
        // Given: LLM service that will fail
        let mockStorage = MockStorageManager()
        let now = Int(Date().timeIntervalSince1970)
        
        for i in 0..<60 {
            let chunk = RecordingChunk(
                id: Int64(i),
                startTs: now + (i * 15),
                endTs: now + ((i + 1) * 15),
                fileUrl: "/tmp/chunk_\(i).mov",
                status: "completed"
            )
            mockStorage.chunks.append(chunk)
        }
        
        let mockLLM = MockLLMService()
        mockLLM.shouldSucceed = false
        let mockVideo = MockVideoProcessingService()
        
        let manager = AnalysisManager(
            store: mockStorage,
            llmService: mockLLM,
            videoProcessingService: mockVideo
        )
        
        // When: Processing with failing LLM
        await manager.triggerAnalysisNow()
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Batch should be marked as failed
        XCTAssertTrue(mockLLM.processBatchCalled, "LLM should be attempted")
        XCTAssertEqual(mockStorage.batches.first?.status, "failed", "Batch should be marked as failed")
    }
}
