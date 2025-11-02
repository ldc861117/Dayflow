//
//  BatchAssembler.swift
//  Dayflow
//

import Foundation
import AVFoundation

/// Handles video composition and batch preparation using VideoProcessingService
actor BatchAssembler {
    private let videoProcessingService: VideoProcessingService
    private let fileManager: FileManager
    
    init(videoProcessingService: VideoProcessingService) {
        self.videoProcessingService = videoProcessingService
        self.fileManager = FileManager.default
    }
    
    /// Prepares a combined video from chunk files for processing
    /// - Parameters:
    ///   - chunkFilePaths: Array of video file paths to combine
    ///   - batchId: ID for logging and tracking
    /// - Returns: Tuple containing the combined video data, MIME type, and duration
    func prepareCombinedVideo(from chunkFilePaths: [String], batchId: Int64) async throws -> (data: Data, mimeType: String, duration: TimeInterval) {
        guard !chunkFilePaths.isEmpty else {
            throw LLMServiceError.noRecordingsInBatch
        }
        
        print("📦 [BatchAssembler] Preparing combined video for batch \(batchId) from \(chunkFilePaths.count) chunks")
        
        // Convert file paths to URLs
        let chunkURLs = chunkFilePaths.compactMap { filePath in
            URL(fileURLWithPath: filePath)
        }
        
        guard !chunkURLs.isEmpty else {
            throw LLMServiceError.noRecordingsInBatch
        }
        
        // Use VideoProcessingService to prepare the video
        let combinedVideoURL = try await videoProcessingService.prepareVideoForProcessing(urls: chunkURLs)
        
        // Read the combined video data
        let videoData = try Data(contentsOf: combinedVideoURL)
        
        // Get the video duration
        let asset = AVAsset(url: combinedVideoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        print("✅ [BatchAssembler] Combined video prepared: \(videoData.count) bytes, duration: \(durationSeconds)s")
        
        // Schedule cleanup of the temporary file
        Task {
            await cleanupTemporaryFile(at: combinedVideoURL)
        }
        
        return (videoData, "video/mp4", durationSeconds)
    }
    
    /// Extracts a single segment from a video for processing
    /// - Parameters:
    ///   - sourceVideoURL: URL of the source video
    ///   - startTime: Start time in seconds
    ///   - duration: Duration in seconds
    /// - Returns: URL to the extracted segment
    func extractSegment(from sourceVideoURL: URL, startTime: TimeInterval, duration: TimeInterval) async throws -> URL {
        return try await videoProcessingService.extractSegment(
            from: sourceVideoURL,
            startTime: startTime,
            duration: duration
        )
    }
    
    // MARK: - Private Methods
    
    private func cleanupTemporaryFile(at url: URL) async {
        videoProcessingService.cleanupTemporaryFile(at: url)
    }
}