//
//  TimelineUpdater.swift
//  Dayflow
//

import Foundation

/// Handles timeline and storage operations for LLM processing results
actor TimelineUpdater {
    private let storage: any StorageManaging
    private let fileManager: FileManager
    
    init(storage: any StorageManaging) {
        self.storage = storage
        self.fileManager = FileManager.default
    }
    
    /// Updates batch status to processing
    func markBatchAsProcessing(_ batchId: Int64) async throws {
        storage.updateBatchStatus(batchId, status: "processing")
    }
    
    /// Updates batch status to analyzed
    func markBatchAsAnalyzed(_ batchId: Int64) async throws {
        storage.updateBatchStatus(batchId, status: "analyzed")
    }
    
    /// Updates batch status to failed with reason
    func markBatchAsFailed(_ batchId: Int64, reason: String) async throws {
        storage.markBatchFailed(batchId, reason: reason)
    }
    
    /// Saves observations for a batch
    func saveObservations(_ observations: [Observation], for batchId: Int64) async throws {
        storage.saveObservations(batchId: batchId, observations: observations)
    }
    
    /// Replaces timeline cards in a time range with new cards
    /// - Parameters:
    ///   - cards: New activity cards to save
    ///   - batchId: ID of the batch being processed
    ///   - timeRange: Time range to replace cards in
    /// - Returns: Tuple containing inserted card IDs and deleted video paths
    func replaceTimelineCards(
        with cards: [ActivityCardData],
        batchId: Int64,
        in timeRange: Range<Date>
    ) async throws -> (insertedIds: [Int64], deletedVideoPaths: [String]) {
        let timelineCards = cards.map { card in
            TimelineCardShell(
                startTimestamp: card.startTime,
                endTimestamp: card.endTime,
                category: card.category,
                subcategory: card.subcategory,
                title: card.title,
                summary: card.summary,
                detailedSummary: card.detailedSummary,
                distractions: card.distractions,
                appSites: card.appSites
            )
        }
        
        return storage.replaceTimelineCardsInRange(
            from: timeRange.lowerBound,
            to: timeRange.upperBound,
            with: timelineCards,
            batchId: batchId
        )
    }
    
    /// Creates an error card for a failed batch
    func createErrorCard(
        for batchId: Int64,
        batchStartTime: Date,
        batchEndTime: Date,
        error: Error
    ) -> TimelineCardShell {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        let startTimeStr = formatter.string(from: batchStartTime)
        let endTimeStr = formatter.string(from: batchEndTime)
        
        // Calculate duration in minutes
        let duration = Int(batchEndTime.timeIntervalSince(batchStartTime) / 60)
        
        // Get human-readable error message
        let humanError = getHumanReadableError(error)
        
        // Create the error card
        return TimelineCardShell(
            startTimestamp: startTimeStr,
            endTimestamp: endTimeStr,
            category: "System",
            subcategory: "Error",
            title: "Processing failed",
            summary: "Failed to process \(duration) minutes of recording from \(startTimeStr) to \(endTimeStr). \(humanError) Your recording is safe and can be reprocessed.",
            detailedSummary: "Error details: \(error.localizedDescription)\n\nThis recording batch (ID: \(batchId)) failed during AI processing. The original video files are preserved and can be reprocessed by retrying from Settings. Common causes include network issues, API rate limits, or temporary service outages.",
            distractions: nil,
            appSites: nil
        )
    }
    
    /// Fetches observations for a time range (sliding window approach)
    func fetchObservations(in timeRange: Range<Date>) async -> [Observation] {
        return storage.fetchObservationsByTimeRange(from: timeRange.lowerBound, to: timeRange.upperBound)
    }
    
    /// Fetches existing timeline cards for a time range
    func fetchTimelineCards(in timeRange: Range<Date>) async -> [TimelineCard] {
        return storage.fetchTimelineCardsByTimeRange(from: timeRange.lowerBound, to: timeRange.upperBound)
    }
    
    /// Gets chunk file paths for a batch
    func getChunkFiles(for batchId: Int64) -> [String] {
        return storage.getChunkFilesForBatch(batchId: batchId)
    }
    
    /// Gets batch information
    func getBatchInfo(for batchId: Int64) -> (id: Int64, startTs: Int, endTs: Int, status: String)? {
        let batches = storage.allBatches()
        return batches.first(where: { $0.0 == batchId })
    }
    
    /// Cleans up deleted video files
    func cleanupVideoFiles(at paths: [String]) async {
        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                try fileManager.removeItem(at: url)
                print("🗑️ Deleted timelapse: \(path)")
            } catch {
                print("❌ Failed to delete timelapse: \(path) - \(error)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func getHumanReadableError(_ error: Error) -> String {
        // First check if it's an NSError with a domain and code we recognize
        if let nsError = error as NSError? {
            // Check specific error domains and codes
            switch nsError.domain {
            case "LLMService":
                switch nsError.code {
                case 1: return "No AI provider is configured. Please set one up in Settings."
                case 2: return "The recording batch couldn't be found."
                case 3: return "No video recordings found in this time period."
                case 4: return "Failed to create the video for processing."
                case 5: return "Failed to combine video chunks."
                case 6: return "Failed to prepare video for processing."
                default: break
                }
                
            case "GeminiError", "GeminiProvider":
                switch nsError.code {
                case 1: return "Failed to upload the video to Gemini."
                case 2: return "Gemini took too long to process the video."
                case 3, 5: return "Failed to parse Gemini's response."
                case 4: return "Failed to start video upload to Gemini."
                case 6: return "Invalid video file."
                case 7, 9: return "Gemini returned an unexpected response format."
                case 8, 10: return "Failed to connect to Gemini after multiple attempts."
                case 100: return "The AI generated timestamps beyond the video duration."
                case 101: return "The AI couldn't identify any activities in the video."
                // HTTP status codes
                case 400: return "Invalid API key. Please check your Gemini API key in Settings."
                case 401: return "Unauthorized. Your Gemini API key may be invalid or expired."
                case 403: return "Access forbidden. Check your Gemini API permissions."
                case 429: return "Rate limited. Too many requests to Gemini. Please wait a few minutes."
                case 503: return "Google's Gemini servers returned a 503 error. Google's AI services may be temporarily down. If you see many of these in a row, please wait at least a few hours before retrying. Check the [Google AI Studio status](https://aistudio.google.com/status) page for updates."
                case 500...599: return "Gemini service error. The service may be temporarily down."
                default:
                    // For other HTTP errors, provide context
                    if nsError.code >= 400 && nsError.code < 600 {
                        return "Gemini returned HTTP error \(nsError.code). Check your API settings."
                    }
                    break
                }
                
            case "OllamaProvider":
                switch nsError.code {
                case 1: return "Invalid video duration."
                case 2: return "Failed to process video frame."
                case 4: return "Failed to connect to local AI model."
                case 8, 9, 10: return "The local AI returned an unexpected response."
                case 11: return "The local AI couldn't identify any activities."
                case 12: return "The local AI didn't analyze enough of the video."
                case 13: return "The local AI generated too many segments."
                default: break
                }
                
            default:
                break
            }
        }
        
        // Fallback to checking the error description for common patterns
        let errorDescription = error.localizedDescription.lowercased()
        
        switch true {
        case errorDescription.contains("rate limit") || errorDescription.contains("429"):
            return "The AI service is temporarily overwhelmed. This usually resolves itself in a few minutes."
            
        case errorDescription.contains("network") || errorDescription.contains("connection"):
            return "Couldn't connect to the AI service. Check your internet connection."
            
        case errorDescription.contains("api key") || errorDescription.contains("unauthorized") || errorDescription.contains("401"):
            return "There's an issue with your API key. Please check your settings."
            
        case errorDescription.contains("503"):
            return "Google's Gemini servers returned a 503 error. Google's AI services may be temporarily down. If you see many of these in a row, please wait at least a few hours before retrying. Check the [Google AI Studio status](https://aistudio.google.com/status) page for updates."
            
        case errorDescription.contains("timeout"):
            return "The AI took too long to respond. This might be due to a long recording or slow connection."
            
        case errorDescription.contains("no observations"):
            return "The AI couldn't understand what was happening in this recording."
            
        case errorDescription.contains("exceed") || errorDescription.contains("duration"):
            return "The AI got confused about the video timing."
            
        case errorDescription.contains("no llm provider") || errorDescription.contains("not configured"):
            return "No AI provider is configured. Please set one up in Settings."
            
        case errorDescription.contains("failed to upload"):
            return "Failed to upload the video for processing."
            
        case errorDescription.contains("invalid response") || errorDescription.contains("json"):
            return "The AI returned an unexpected response format."
            
        case errorDescription.contains("failed after") && errorDescription.contains("attempts"):
            return "Couldn't connect to the AI service after multiple attempts."
            
        default:
            // For unknown errors, keep it simple
            return "An unexpected error occurred."
        }
    }
}