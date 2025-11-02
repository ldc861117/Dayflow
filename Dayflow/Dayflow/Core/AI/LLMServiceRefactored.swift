//
//  LLMServiceRefactored.swift
//  Dayflow
//

import Foundation
import AVFoundation

/// Refactored LLMService that orchestrates AI processing with proper separation of concerns
actor LLMService: LLMServicing {
    private let providerFactory: ProviderFactory
    private let batchAssembler: BatchAssembler
    private let timelineUpdater: TimelineUpdater
    private let analyticsService: AnalyticsService
    
    // Dependencies for testing
    init(
        providerFactory: ProviderFactory,
        batchAssembler: BatchAssembler,
        timelineUpdater: TimelineUpdater,
        analyticsService: AnalyticsService = .shared
    ) {
        self.providerFactory = providerFactory
        self.batchAssembler = batchAssembler
        self.timelineUpdater = timelineUpdater
        self.analyticsService = analyticsService
        
        // Start observing provider configuration changes
        Task {
            await providerFactory.startChangeObservation()
        }
    }
    
    deinit {
        // Stop observing configuration changes
        Task {
            await providerFactory.stopChangeObservation()
        }
    }
    
    /// Processes a batch asynchronously, returning structured results
    /// - Parameter batchId: ID of the batch to process
    /// - Returns: ProcessedBatchResult containing generated cards and their IDs
    func processBatchAsync(_ batchId: Int64) async throws -> ProcessedBatchResult {
        let processingStartTime = Date()
        
        // Get batch information
        guard let batchInfo = await timelineUpdater.getBatchInfo(for: batchId) else {
            throw LLMServiceError.batchNotFound(batchId)
        }
        
        let (_, batchStartTs, batchEndTs, _) = batchInfo
        let batchStartDate = Date(timeIntervalSince1970: TimeInterval(batchStartTs))
        let batchEndDate = Date(timeIntervalSince1970: TimeInterval(batchEndTs))
        
        print("\n📦 [LLMService] Processing batch \(batchId)")
        print("   Batch time: \(batchStartDate) to \(batchEndDate)")
        
        // Get current provider
        let provider = try await providerFactory.getProvider()
        let providerName = await getProviderName()
        
        // Track analysis batch started
        await analyticsService.capture("analysis_batch_started", [
            "batch_id": batchId,
            "total_duration_seconds": batchEndTs - batchStartTs,
            "llm_provider": providerName
        ])
        
        // Mark batch as processing
        try await timelineUpdater.markBatchAsProcessing(batchId)
        
        do {
            // Get chunk files for this batch
            let chunkFilePaths = await timelineUpdater.getChunkFiles(for: batchId)
            
            // Prepare combined video
            let (videoData, mimeType, totalDuration) = try await batchAssembler.prepareCombinedVideo(
                from: chunkFilePaths,
                batchId: batchId
            )
            
            // Transcribe video
            let (observations, transcribeLog) = try await provider.transcribeVideo(
                videoData: videoData,
                mimeType: mimeType,
                prompt: "Transcribe this video",
                batchStartTime: batchStartDate,
                videoDuration: totalDuration,
                batchId: batchId
            )
            
            // Save observations
            try await timelineUpdater.saveObservations(observations, for: batchId)
            
            // Handle empty observations
            guard !observations.isEmpty else {
                print("⚠️ [LLMService] Transcription returned 0 observations for batch \(batchId)")
                if let logOutput = transcribeLog.output, !logOutput.isEmpty {
                    print("   ↳ transcribeLog.output: \(logOutput)")
                }
                if let logInput = transcribeLog.input, !logInput.isEmpty {
                    print("   ↳ transcribeLog.input: \(logInput)")
                }
                
                await analyticsService.capture("transcription_returned_empty", [
                    "batch_id": batchId,
                    "provider": providerName,
                    "transcribe_latency_ms": Int((transcribeLog.latency ?? 0) * 1000)
                ])
                
                try await timelineUpdater.markBatchAsAnalyzed(batchId)
                return ProcessedBatchResult(cards: [], cardIds: [])
            }
            
            // Generate activity cards using sliding window approach
            let cards = try await generateActivityCards(
                for: batchId,
                batchEndTime: batchEndDate,
                currentObservations: observations,
                provider: provider
            )
            
            // Mark batch as complete
            try await timelineUpdater.markBatchAsAnalyzed(batchId)
            
            // Track analysis batch completed
            await analyticsService.capture("analysis_batch_completed", [
                "batch_id": batchId,
                "cards_generated": cards.count,
                "processing_duration_seconds": Int(Date().timeIntervalSince(processingStartTime)),
                "llm_provider": providerName
            ])
            
            return ProcessedBatchResult(cards: cards.cards, cardIds: cards.cardIds)
            
        } catch {
            return try await handleProcessingError(
                error,
                batchId: batchId,
                batchStartTime: batchStartDate,
                batchEndTime: batchEndDate,
                processingStartTime: processingStartTime,
                providerName: providerName
            )
        }
    }
    
    /// Legacy callback-based method for backward compatibility
    func processBatch(_ batchId: Int64, completion: @escaping (Result<ProcessedBatchResult, Error>) -> Void) {
        Task {
            do {
                let result = try await processBatchAsync(batchId)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func generateActivityCards(
        for batchId: Int64,
        batchEndTime: Date,
        currentObservations: [Observation],
        provider: LLMProvider
    ) async throws -> (cards: [ActivityCardData], cardIds: [Int64]) {
        
        // Calculate time window (1 hour before current batch end time)
        let oneHourAgo = batchEndTime.addingTimeInterval(-3600)
        let timeRange = oneHourAgo..<batchEndTime
        
        // Fetch all observations from the last hour (sliding window)
        let recentObservations = await timelineUpdater.fetchObservations(in: timeRange)
        
        print("[DEBUG] LLMService fetched \(recentObservations.count) observations")
        for (i, obs) in recentObservations.enumerated() {
            print("  [\(i)] observation type: \(type(of: obs.observation))")
            print("       observation: \(obs.observation)")
        }
        
        // Fetch existing timeline cards that overlap with the last hour
        let existingTimelineCards = await timelineUpdater.fetchTimelineCards(in: timeRange)
        
        // Convert TimelineCards to ActivityCardData for context
        let existingActivityCards = existingTimelineCards.map { card in
            ActivityCardData(
                startTime: card.startTimestamp,
                endTime: card.endTimestamp,
                category: card.category,
                subcategory: card.subcategory,
                title: card.title,
                summary: card.summary,
                detailedSummary: card.detailedSummary,
                distractions: card.distractions,
                appSites: card.appSites
            )
        }
        
        // Prepare context for activity generation
        let categories = CategoryStore.descriptorsForLLM()
        print("[DEBUG] LLMService loaded \(categories.count) categories")
        for (i, cat) in categories.enumerated() {
            print("  [\(i)] name type: \(type(of: cat.name)), value: \(cat.name)")
            print("       description type: \(type(of: cat.description)), value: \(cat.description ?? "nil")")
        }
        
        let context = ActivityGenerationContext(
            batchObservations: currentObservations,
            existingCards: existingActivityCards,
            currentTime: batchEndTime,
            categories: categories
        )
        
        // Generate activity cards using sliding window observations
        let (cards, _) = try await provider.generateActivityCards(
            observations: recentObservations,
            context: context,
            batchId: batchId
        )
        
        // Replace old cards with new ones in the time range
        let (insertedCardIds, deletedVideoPaths) = try await timelineUpdater.replaceTimelineCards(
            with: cards,
            batchId: batchId,
            in: timeRange
        )
        
        // Clean up deleted video files
        await timelineUpdater.cleanupVideoFiles(at: deletedVideoPaths)
        
        return (cards: cards, cardIds: insertedCardIds)
    }
    
    private func handleProcessingError(
        _ error: Error,
        batchId: Int64,
        batchStartTime: Date,
        batchEndTime: Date,
        processingStartTime: Date,
        providerName: String
    ) async throws -> ProcessedBatchResult {
        
        print("Error processing batch: \(error)")
        if let ns = error as NSError?, ns.domain == "GeminiError" {
            print("🔎 GEMINI DEBUG: NSError.userInfo=\(ns.userInfo)")
        }
        
        // Track analysis batch failed
        await analyticsService.capture("analysis_batch_failed", [
            "batch_id": batchId,
            "error_message": error.localizedDescription,
            "processing_duration_seconds": Int(Date().timeIntervalSince(processingStartTime)),
            "llm_provider": providerName
        ])
        
        // Mark batch as failed
        try await timelineUpdater.markBatchAsFailed(batchId, reason: error.localizedDescription)
        
        // Create an error card for the failed time period
        let errorCard = await timelineUpdater.createErrorCard(
            for: batchId,
            batchStartTime: batchStartTime,
            batchEndTime: batchEndTime,
            error: error
        )
        
        // Replace any existing cards in this time range with the error card
        let timeRange = batchStartTime..<batchEndTime
        let (insertedCardIds, deletedVideoPaths) = try await timelineUpdater.replaceTimelineCards(
            with: [ActivityCardData(
                startTime: errorCard.startTimestamp,
                endTime: errorCard.endTimestamp,
                category: errorCard.category,
                subcategory: errorCard.subcategory,
                title: errorCard.title,
                summary: errorCard.summary,
                detailedSummary: errorCard.detailedSummary,
                distractions: errorCard.distractions,
                appSites: errorCard.appSites
            )],
            batchId: batchId,
            in: timeRange
        )
        
        // Clean up any deleted video files
        await timelineUpdater.cleanupVideoFiles(at: deletedVideoPaths)
        
        if !insertedCardIds.isEmpty {
            print("✅ Created error card (ID: \(insertedCardIds.first ?? -1)) for failed batch \(batchId), replacing \(deletedVideoPaths.count) existing cards")
        }
        
        // Re-throw the error to maintain the failure semantics
        throw error
    }
    
    private func getProviderName() async -> String {
        let providerType = await providerFactory.getProviderType()
        switch providerType {
        case .geminiDirect: return "gemini"
        case .dayflowBackend: return "dayflow"
        case .ollamaLocal: return "ollama"
        case .chatGPTClaude: return "chat_cli"
        }
    }
}

// MARK: - Factory Method

extension LLMService {
    /// Creates a production-ready LLMService with default dependencies
    static func makeProductionService() -> LLMService {
        let providerFactory = ProviderFactory()
        let videoProcessingService = VideoProcessingService()
        let batchAssembler = BatchAssembler(videoProcessingService: videoProcessingService)
        let timelineUpdater = TimelineUpdater(storage: StorageManager.shared)
        
        return LLMService(
            providerFactory: providerFactory,
            batchAssembler: batchAssembler,
            timelineUpdater: timelineUpdater
        )
    }
}