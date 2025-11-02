//
//  StorageManaging.swift
//  Dayflow
//

import Foundation

protocol StorageManaging: Sendable {
    func nextFileURL() async -> URL
    func registerChunk(url: URL) async throws
    func markChunkCompleted(url: URL) async throws
    func markChunkFailed(url: URL) async throws
    
    func fetchUnprocessedChunks(olderThan oldestAllowed: Int) async throws -> [RecordingChunk]
    func fetchChunksInTimeRange(startTs: Int, endTs: Int) async throws -> [RecordingChunk]
    
    func saveBatch(startTs: Int, endTs: Int, chunkIds: [Int64]) async throws -> Int64
    func updateBatchStatus(batchId: Int64, status: String) async throws
    func markBatchFailed(batchId: Int64, reason: String) async throws
    
    func updateBatchLLMMetadata(batchId: Int64, calls: [LLMCall]) async throws
    func fetchBatchLLMMetadata(batchId: Int64) async throws -> [LLMCall]
    
    func saveTimelineCardShell(batchId: Int64, card: TimelineCardShell) async throws -> Int64
    func updateTimelineCardVideoURL(cardId: Int64, videoSummaryURL: String) async throws
    func fetchTimelineCards(forBatch batchId: Int64) async throws -> [TimelineCard]
    func fetchTimelineCard(byId id: Int64) async throws -> TimelineCardWithTimestamps?
    
    func fetchTimelineCards(forDay day: String) async throws -> [TimelineCard]
    func fetchTimelineCardsByTimeRange(from: Date, to: Date) async throws -> [TimelineCard]
    func replaceTimelineCardsInRange(from: Date, to: Date, with: [TimelineCardShell], batchId: Int64) async throws -> (insertedIds: [Int64], deletedVideoPaths: [String])
    func fetchRecentTimelineCardsForDebug(limit: Int) async throws -> [TimelineCardDebugEntry]
    
    func fetchRecentLLMCallsForDebug(limit: Int) async throws -> [LLMCallDebugEntry]
    func fetchRecentAnalysisBatchesForDebug(limit: Int) async throws -> [AnalysisBatchDebugEntry]
    func fetchLLMCallsForBatches(batchIds: [Int64], limit: Int) async throws -> [LLMCallDebugEntry]
    
    func saveObservations(batchId: Int64, observations: [Observation]) async throws
    func fetchObservations(batchId: Int64) async throws -> [Observation]
    func fetchObservations(startTs: Int, endTs: Int) async throws -> [Observation]
    func fetchObservationsByTimeRange(from: Date, to: Date) async throws -> [Observation]
    
    func getTimestampsForVideoFiles(paths: [String]) async throws -> [String: (startTs: Int, endTs: Int)]
    
    func deleteTimelineCards(forDay day: String) async throws -> [String]
    func deleteTimelineCards(forBatchIds batchIds: [Int64]) async throws -> [String]
    func deleteObservations(forBatchIds batchIds: [Int64]) async throws
    func resetBatchStatuses(forDay day: String) async throws -> [Int64]
    func resetBatchStatuses(forBatchIds batchIds: [Int64]) async throws -> [Int64]
    func fetchBatches(forDay day: String) async throws -> [(id: Int64, startTs: Int, endTs: Int, status: String)]
    
    func chunksForBatch(_ batchId: Int64) async throws -> [RecordingChunk]
    func allBatches() async throws -> [(id: Int64, start: Int, end: Int, status: String)]
    
    func getChunkFilesForBatch(batchId: Int64) async throws -> [String]
    func updateBatch(_ batchId: Int64, status: String, reason: String?) async throws
    func updateBatchMetadata(_ batchId: Int64, metadata: String) async throws
    func insertLLMCall(_ rec: LLMCallDBRecord) async throws
}

extension StorageContainer: StorageManaging {
    func nextFileURL() async -> URL {
        await chunkStore.nextFileURL()
    }
    
    func registerChunk(url: URL) async throws {
        try await chunkStore.register(url: url)
    }
    
    func markChunkCompleted(url: URL) async throws {
        try await chunkStore.markCompleted(url: url)
    }
    
    func markChunkFailed(url: URL) async throws {
        try await chunkStore.markFailed(url: url)
    }
    
    func fetchUnprocessedChunks(olderThan oldestAllowed: Int) async throws -> [RecordingChunk] {
        try await chunkStore.fetchUnprocessed(olderThan: oldestAllowed)
    }
    
    func fetchChunksInTimeRange(startTs: Int, endTs: Int) async throws -> [RecordingChunk] {
        try await chunkStore.fetchInTimeRange(startTs: startTs, endTs: endTs)
    }
    
    func saveBatch(startTs: Int, endTs: Int, chunkIds: [Int64]) async throws -> Int64 {
        try await batchStore.createBatch(startTs: startTs, endTs: endTs, chunkIds: chunkIds)
    }
    
    func updateBatchStatus(batchId: Int64, status: String) async throws {
        try await batchStore.updateStatus(batchId: batchId, status: status)
    }
    
    func markBatchFailed(batchId: Int64, reason: String) async throws {
        try await batchStore.markFailed(batchId: batchId, reason: reason)
    }
    
    func updateBatchLLMMetadata(batchId: Int64, calls: [LLMCall]) async throws {
        try await batchStore.updateMetadata(batchId: batchId, calls: calls)
    }
    
    func fetchBatchLLMMetadata(batchId: Int64) async throws -> [LLMCall] {
        try await batchStore.fetchMetadata(batchId: batchId)
    }
    
    func saveTimelineCardShell(batchId: Int64, card: TimelineCardShell) async throws -> Int64 {
        try await timelineStore.saveCardShell(batchId: batchId, card: card)
    }
    
    func updateTimelineCardVideoURL(cardId: Int64, videoSummaryURL: String) async throws {
        try await timelineStore.updateVideoURL(cardId: cardId, videoSummaryURL: videoSummaryURL)
    }
    
    func fetchTimelineCards(forBatch batchId: Int64) async throws -> [TimelineCard] {
        try await timelineStore.fetchForBatch(batchId)
    }
    
    func fetchTimelineCard(byId id: Int64) async throws -> TimelineCardWithTimestamps? {
        try await timelineStore.fetchCard(byId: id)
    }
    
    func fetchTimelineCards(forDay day: String) async throws -> [TimelineCard] {
        try await timelineStore.fetchForDay(day)
    }
    
    func fetchTimelineCardsByTimeRange(from: Date, to: Date) async throws -> [TimelineCard] {
        try await timelineStore.fetchByTimeRange(from: from, to: to)
    }
    
    func replaceTimelineCardsInRange(from: Date, to: Date, with cards: [TimelineCardShell], batchId: Int64) async throws -> (insertedIds: [Int64], deletedVideoPaths: [String]) {
        try await timelineStore.replaceInRange(from: from, to: to, cards: cards, batchId: batchId)
    }
    
    func fetchRecentTimelineCardsForDebug(limit: Int) async throws -> [TimelineCardDebugEntry] {
        try await timelineStore.fetchRecentDebug(limit: limit)
    }
    
    func fetchRecentLLMCallsForDebug(limit: Int) async throws -> [LLMCallDebugEntry] {
        try await llmCallStore.fetchRecent(limit: limit)
    }
    
    func fetchRecentAnalysisBatchesForDebug(limit: Int) async throws -> [AnalysisBatchDebugEntry] {
        try await batchStore.fetchRecentDebug(limit: limit)
    }
    
    func fetchLLMCallsForBatches(batchIds: [Int64], limit: Int) async throws -> [LLMCallDebugEntry] {
        try await llmCallStore.fetchForBatches(batchIds: batchIds, limit: limit)
    }
    
    func saveObservations(batchId: Int64, observations: [Observation]) async throws {
        try await observationStore.save(batchId: batchId, observations: observations)
    }
    
    func fetchObservations(batchId: Int64) async throws -> [Observation] {
        try await observationStore.fetch(batchId: batchId)
    }
    
    func fetchObservations(startTs: Int, endTs: Int) async throws -> [Observation] {
        try await observationStore.fetch(startTs: startTs, endTs: endTs)
    }
    
    func fetchObservationsByTimeRange(from: Date, to: Date) async throws -> [Observation] {
        try await observationStore.fetchByTimeRange(from: from, to: to)
    }
    
    func getTimestampsForVideoFiles(paths: [String]) async throws -> [String: (startTs: Int, endTs: Int)] {
        try await chunkStore.getTimestamps(forPaths: paths)
    }
    
    func deleteTimelineCards(forDay day: String) async throws -> [String] {
        try await timelineStore.deleteForDay(day)
    }
    
    func deleteTimelineCards(forBatchIds batchIds: [Int64]) async throws -> [String] {
        try await timelineStore.deleteForBatchIds(batchIds)
    }
    
    func deleteObservations(forBatchIds batchIds: [Int64]) async throws {
        try await observationStore.delete(forBatchIds: batchIds)
    }
    
    func resetBatchStatuses(forDay day: String) async throws -> [Int64] {
        try await batchStore.resetStatuses(forDay: day)
    }
    
    func resetBatchStatuses(forBatchIds batchIds: [Int64]) async throws -> [Int64] {
        try await batchStore.resetStatuses(forBatchIds: batchIds)
    }
    
    func fetchBatches(forDay day: String) async throws -> [(id: Int64, startTs: Int, endTs: Int, status: String)] {
        try await batchStore.fetchBatches(forDay: day)
    }
    
    func chunksForBatch(_ batchId: Int64) async throws -> [RecordingChunk] {
        try await chunkStore.fetchForBatch(batchId)
    }
    
    func allBatches() async throws -> [(id: Int64, start: Int, end: Int, status: String)] {
        try await batchStore.allBatches()
    }
    
    func getChunkFilesForBatch(batchId: Int64) async throws -> [String] {
        try await chunkStore.getFilePaths(forBatch: batchId)
    }
    
    func updateBatch(_ batchId: Int64, status: String, reason: String? = nil) async throws {
        try await batchStore.setStatus(batchId: batchId, status: status, reason: reason)
    }
    
    func updateBatchMetadata(_ batchId: Int64, metadata: String) async throws {
        try await batchStore.setMetadata(batchId: batchId, metadata: metadata)
    }
    
    func insertLLMCall(_ rec: LLMCallDBRecord) async throws {
        try await llmCallStore.insert(rec)
    }
}
