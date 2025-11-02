//
//  JournalComposerTests.swift
//  DayflowTests
//
//  Unit tests for JournalComposer service
//

import XCTest
@testable import Dayflow

final class JournalComposerTests: XCTestCase {
    
    func testGenerateJournal_WithSampleData_GeneratesEntry() async throws {
        // Given
        let mockStorage = MockStorageManager()
        mockStorage.mockTimelineCards = [
            createMockTimelineCard(
                title: "Working on code",
                category: "Work",
                startTime: "9:00 AM",
                endTime: "11:30 AM",
                summary: "Writing tests and fixing bugs"
            ),
            createMockTimelineCard(
                title: "Team meeting",
                category: "Work",
                startTime: "11:30 AM",
                endTime: "12:00 PM",
                summary: "Sprint planning discussion"
            ),
            createMockTimelineCard(
                title: "Lunch break",
                category: "Personal",
                startTime: "12:00 PM",
                endTime: "1:00 PM",
                summary: "Eating lunch"
            )
        ]
        
        let composer = JournalComposer(storage: mockStorage)
        
        // When
        let entry = try await composer.generateJournal(forDay: "2024-01-15", useLLM: false)
        
        // Then
        XCTAssertEqual(entry.day, "2024-01-15")
        XCTAssertFalse(entry.overview.isEmpty)
        XCTAssertEqual(entry.metadata.totalActivities, 3)
        XCTAssertEqual(entry.metadata.generationMode, "local")
        XCTAssertEqual(entry.focusBlocks.count, 3)
        XCTAssertTrue(entry.overview.contains("3 activities"))
    }
    
    func testGenerateJournal_WithNoData_ThrowsError() async {
        // Given
        let mockStorage = MockStorageManager()
        mockStorage.mockTimelineCards = []
        let composer = JournalComposer(storage: mockStorage)
        
        // When/Then
        do {
            _ = try await composer.generateJournal(forDay: "2024-01-15", useLLM: false)
            XCTFail("Should have thrown an error")
        } catch let error as JournalError {
            if case .noData = error {
                // Success
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testGenerateJournal_WithDistractions_IncludesDistractionSummary() async throws {
        // Given
        let mockStorage = MockStorageManager()
        let distraction = Distraction(
            startTime: "10:00 AM",
            endTime: "10:15 AM",
            title: "Social media",
            summary: "Browsing Twitter"
        )
        
        mockStorage.mockTimelineCards = [
            createMockTimelineCard(
                title: "Working",
                category: "Work",
                startTime: "9:00 AM",
                endTime: "11:00 AM",
                summary: "Deep work",
                distractions: [distraction]
            )
        ]
        
        let composer = JournalComposer(storage: mockStorage)
        
        // When
        let entry = try await composer.generateJournal(forDay: "2024-01-15", useLLM: false)
        
        // Then
        XCTAssertNotNil(entry.distractionSummary)
        XCTAssertTrue(entry.distractionSummary?.contains("1 distraction") ?? false)
        XCTAssertEqual(entry.metadata.totalDistractions, 1)
    }
    
    func testGenerateJournal_WithLongSessions_IncludesReflection() async throws {
        // Given
        let mockStorage = MockStorageManager()
        mockStorage.mockTimelineCards = [
            createMockTimelineCard(
                title: "Deep work session",
                category: "Work",
                startTime: "9:00 AM",
                endTime: "11:30 AM",
                summary: "Long focused coding session"
            )
        ]
        
        let composer = JournalComposer(storage: mockStorage)
        
        // When
        let entry = try await composer.generateJournal(forDay: "2024-01-15", useLLM: false)
        
        // Then
        XCTAssertFalse(entry.reflections.isEmpty)
        XCTAssertTrue(entry.reflections.contains { $0.contains("focused session") })
    }
    
    func testGenerateJournal_FiltersIdleActivities() async throws {
        // Given
        let mockStorage = MockStorageManager()
        mockStorage.mockTimelineCards = [
            createMockTimelineCard(
                title: "Working",
                category: "Work",
                startTime: "9:00 AM",
                endTime: "10:00 AM",
                summary: "Active work"
            ),
            createMockTimelineCard(
                title: "Idle",
                category: "Idle",
                startTime: "10:00 AM",
                endTime: "11:00 AM",
                summary: "No activity"
            )
        ]
        
        let composer = JournalComposer(storage: mockStorage)
        
        // When
        let entry = try await composer.generateJournal(forDay: "2024-01-15", useLLM: false)
        
        // Then
        XCTAssertEqual(entry.focusBlocks.count, 1)
        XCTAssertEqual(entry.focusBlocks[0].title, "Working")
    }
    
    func testGenerateJournal_FiltersShortActivities() async throws {
        // Given
        let mockStorage = MockStorageManager()
        mockStorage.mockTimelineCards = [
            createMockTimelineCard(
                title: "Quick task",
                category: "Work",
                startTime: "9:00 AM",
                endTime: "9:03 AM",
                summary: "Very short task"
            ),
            createMockTimelineCard(
                title: "Longer task",
                category: "Work",
                startTime: "9:03 AM",
                endTime: "10:00 AM",
                summary: "Substantial work"
            )
        ]
        
        let composer = JournalComposer(storage: mockStorage)
        
        // When
        let entry = try await composer.generateJournal(forDay: "2024-01-15", useLLM: false)
        
        // Then
        XCTAssertEqual(entry.focusBlocks.count, 1)
        XCTAssertEqual(entry.focusBlocks[0].title, "Longer task")
    }
    
    // MARK: - Helper Methods
    
    private func createMockTimelineCard(
        title: String,
        category: String,
        startTime: String,
        endTime: String,
        summary: String,
        distractions: [Distraction]? = nil
    ) -> TimelineCard {
        return TimelineCard(
            batchId: 1,
            startTimestamp: startTime,
            endTimestamp: endTime,
            category: category,
            subcategory: "",
            title: title,
            summary: summary,
            detailedSummary: summary,
            day: "2024-01-15",
            distractions: distractions,
            videoSummaryURL: nil,
            otherVideoSummaryURLs: nil,
            appSites: nil
        )
    }
}

// MARK: - Mock Storage Manager

class MockStorageManager: StorageManaging {
    var mockTimelineCards: [TimelineCard] = []
    
    func nextFileURL() -> URL {
        return URL(fileURLWithPath: "/tmp/test.mp4")
    }
    
    func registerChunk(url: URL) {}
    func markChunkCompleted(url: URL) {}
    func markChunkFailed(url: URL) {}
    
    func fetchUnprocessedChunks(olderThan oldestAllowed: Int) -> [RecordingChunk] {
        return []
    }
    
    func fetchChunksInTimeRange(startTs: Int, endTs: Int) -> [RecordingChunk] {
        return []
    }
    
    func saveBatch(startTs: Int, endTs: Int, chunkIds: [Int64]) -> Int64? {
        return 1
    }
    
    func updateBatchStatus(batchId: Int64, status: String) {}
    func markBatchFailed(batchId: Int64, reason: String) {}
    
    func updateBatchLLMMetadata(batchId: Int64, calls: [LLMCall]) {}
    func fetchBatchLLMMetadata(batchId: Int64) -> [LLMCall] {
        return []
    }
    
    func saveTimelineCardShell(batchId: Int64, card: TimelineCardShell) -> Int64? {
        return 1
    }
    
    func updateTimelineCardVideoURL(cardId: Int64, videoSummaryURL: String) {}
    
    func fetchTimelineCards(forBatch batchId: Int64) -> [TimelineCard] {
        return []
    }
    
    func fetchTimelineCard(byId id: Int64) -> TimelineCardWithTimestamps? {
        return nil
    }
    
    func fetchTimelineCards(forDay day: String) -> [TimelineCard] {
        return mockTimelineCards
    }
    
    func fetchTimelineCardsByTimeRange(from: Date, to: Date) -> [TimelineCard] {
        return []
    }
    
    func replaceTimelineCardsInRange(from: Date, to: Date, with: [TimelineCardShell], batchId: Int64) -> (insertedIds: [Int64], deletedVideoPaths: [String]) {
        return ([], [])
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
    
    func saveObservations(batchId: Int64, observations: [Observation]) {}
    
    func fetchObservations(batchId: Int64) -> [Observation] {
        return []
    }
    
    func fetchObservations(startTs: Int, endTs: Int) -> [Observation] {
        return []
    }
    
    func fetchObservationsByTimeRange(from: Date, to: Date) -> [Observation] {
        return []
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
    
    func deleteObservations(forBatchIds batchIds: [Int64]) {}
    
    func resetBatchStatuses(forDay day: String) -> [Int64] {
        return []
    }
    
    func resetBatchStatuses(forBatchIds batchIds: [Int64]) -> [Int64] {
        return []
    }
    
    func fetchBatches(forDay day: String) -> [(id: Int64, startTs: Int, endTs: Int, status: String)] {
        return []
    }
    
    func chunksForBatch(_ batchId: Int64) -> [RecordingChunk] {
        return []
    }
    
    func allBatches() -> [(id: Int64, start: Int, end: Int, status: String)] {
        return []
    }
}
