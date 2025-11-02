//
//  ScreenRecorderEngineTests.swift
//  DayflowTests
//

import XCTest
@testable import Dayflow
import ScreenCaptureKit
import AVFoundation

final class MockStorageManager: StorageManaging {
    var chunks: [(url: URL, status: String)] = []
    
    func nextFileURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test_\(UUID().uuidString).mp4")
    }
    
    func registerChunk(url: URL) {
        chunks.append((url, "pending"))
    }
    
    func markChunkCompleted(url: URL) {
        if let idx = chunks.firstIndex(where: { $0.url == url }) {
            chunks[idx].status = "completed"
        }
    }
    
    func markChunkFailed(url: URL) {
        if let idx = chunks.firstIndex(where: { $0.url == url }) {
            chunks[idx].status = "failed"
        }
    }
    
    func fetchUnprocessedChunks(olderThan oldestAllowed: Int) -> [RecordingChunk] { [] }
    func fetchChunksInTimeRange(startTs: Int, endTs: Int) -> [RecordingChunk] { [] }
    func saveBatch(startTs: Int, endTs: Int, chunkIds: [Int64]) -> Int64? { nil }
    func updateBatchStatus(batchId: Int64, status: String) {}
    func markBatchFailed(batchId: Int64, reason: String) {}
    func updateBatchLLMMetadata(batchId: Int64, calls: [LLMCall]) {}
    func fetchBatchLLMMetadata(batchId: Int64) -> [LLMCall] { [] }
    func saveTimelineCardShell(batchId: Int64, card: TimelineCardShell) -> Int64? { nil }
    func updateTimelineCardVideoURL(cardId: Int64, videoSummaryURL: String) {}
    func fetchTimelineCards(forBatch batchId: Int64) -> [TimelineCard] { [] }
    func fetchTimelineCard(byId id: Int64) -> TimelineCardWithTimestamps? { nil }
    func fetchTimelineCards(forDay day: String) -> [TimelineCard] { [] }
    func fetchTimelineCardsByTimeRange(from: Date, to: Date) -> [TimelineCard] { [] }
    func replaceTimelineCardsInRange(from: Date, to: Date, with: [TimelineCardShell], batchId: Int64) -> (insertedIds: [Int64], deletedVideoPaths: [String]) { ([], []) }
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
    func resetBatchStatuses(forDay day: String) -> [Int64] { [] }
    func resetBatchStatuses(forBatchIds batchIds: [Int64]) -> [Int64] { [] }
    func fetchBatches(forDay day: String) -> [(id: Int64, startTs: Int, endTs: Int, status: String)] { [] }
    func chunksForBatch(_ batchId: Int64) -> [RecordingChunk] { [] }
    func allBatches() -> [(id: Int64, start: Int, end: Int, status: String)] { [] }
}

@MainActor
final class ScreenRecorderEngineTests: XCTestCase {
    
    var engine: ScreenRecorderEngine!
    var mockStorage: MockStorageManager!
    var testQueue: DispatchQueue!
    
    override func setUp() async throws {
        try await super.setUp()
        mockStorage = MockStorageManager()
        testQueue = DispatchQueue(label: "test.queue")
        
        // Create a real ActiveDisplayTracker and DisplaySelector
        let tracker = ActiveDisplayTracker()
        let displaySelector = DisplaySelector(tracker: tracker)
        
        engine = ScreenRecorderEngine(
            displaySelector: displaySelector,
            storageManager: mockStorage,
            callbackQueue: testQueue
        )
    }
    
    func testInitialState() async {
        let state = await engine.currentState()
        XCTAssertEqual(state, .idle, "Engine should start in idle state")
    }
    
    func testStateTransitionIdleToStarting() async {
        await engine.startRecording(wantsRecording: true)
        
        // Give it a moment to attempt starting
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // It will fail due to no real display, but we can verify it tried
        let finalState = await engine.currentState()
        
        // Should be back to idle after failed attempt
        XCTAssertTrue(finalState == .idle || finalState == .starting,
                     "Engine should be idle after failed start attempt")
    }
    
    func testStateTransitionIdleToRecording() async {
        // Enable testing bypass to avoid needing real display
        await engine.setTestingBypassStreamStart(true)
        
        await engine.startRecording(wantsRecording: true)
        
        let state = await engine.currentState()
        XCTAssertEqual(state, .recording, "Engine should transition to recording with bypass enabled")
    }
    
    func testStateTransitionRecordingToPaused() async {
        // Enable testing bypass
        await engine.setTestingBypassStreamStart(true)
        
        // Start recording
        await engine.startRecording(wantsRecording: true)
        var state = await engine.currentState()
        XCTAssertEqual(state, .recording)
        
        // Pause
        await engine.pauseRecording(context: "test pause")
        
        state = await engine.currentState()
        XCTAssertEqual(state, .paused, "Engine should transition to paused state")
    }
    
    func testStateTransitionPausedToRecording() async {
        // Enable testing bypass
        await engine.setTestingBypassStreamStart(true)
        
        // Start recording
        await engine.startRecording(wantsRecording: true)
        XCTAssertEqual(await engine.currentState(), .recording)
        
        // Pause
        await engine.pauseRecording(context: "test pause")
        XCTAssertEqual(await engine.currentState(), .paused)
        
        // Resume
        await engine.startRecording(wantsRecording: true)
        
        let finalState = await engine.currentState()
        XCTAssertTrue(finalState == .starting || finalState == .recording,
                     "Engine should transition from paused to recording")
    }
    
    func testStopRecordingInIdleState() async {
        let initialState = await engine.currentState()
        XCTAssertEqual(initialState, .idle)
        
        await engine.stopRecording()
        
        let finalState = await engine.currentState()
        XCTAssertEqual(finalState, .idle, "Engine should remain idle after stop in idle state")
    }
    
    func testPauseRecordingInInvalidState() async {
        let initialState = await engine.currentState()
        XCTAssertEqual(initialState, .idle)
        
        await engine.pauseRecording(context: "test")
        
        let finalState = await engine.currentState()
        XCTAssertEqual(finalState, .idle, "Engine should remain idle after pause in idle state")
    }
    
    func testDisplayChangeRequest() async {
        let testDisplayID: CGDirectDisplayID = 12345
        
        await engine.handleActiveDisplayChange(testDisplayID)
        
        // The engine should have requested the display change
        // but not switched since we're not recording
        let state = await engine.currentState()
        XCTAssertEqual(state, .idle, "Engine should remain idle after display change")
    }
    
    func testStorageManagerChunkRegistration() async {
        // Enable testing bypass
        await engine.setTestingBypassStreamStart(true)
        
        // Start recording to trigger segment creation
        await engine.startRecording(wantsRecording: true)
        
        // Begin a segment manually
        await engine.beginSegment()
        
        // Give it time to create the segment
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Check that a chunk was registered
        XCTAssertFalse(mockStorage.chunks.isEmpty, "Storage manager should have registered a chunk")
    }
}
