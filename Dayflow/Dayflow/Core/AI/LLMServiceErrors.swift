//
//  LLMServiceErrors.swift
//  Dayflow
//

import Foundation

enum LLMServiceError: LocalizedError {
    case noProviderConfigured
    case providerCreationFailed(String)
    case batchNotFound(Int64)
    case noRecordingsInBatch
    case videoProcessingFailed(VideoProcessingError)
    case providerError(Error)
    case emptyObservations
    case storageError(Error)
    case invalidConfiguration
    
    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "No AI provider is configured. Please set one up in Settings."
        case .providerCreationFailed(let reason):
            return "Failed to create AI provider: \(reason)"
        case .batchNotFound(let batchId):
            return "The recording batch \(batchId) couldn't be found."
        case .noRecordingsInBatch:
            return "No video recordings found in this time period."
        case .videoProcessingFailed(let error):
            return "Video processing failed: \(error.localizedDescription)"
        case .providerError(let error):
            return "AI provider error: \(error.localizedDescription)"
        case .emptyObservations:
            return "The AI couldn't understand what was happening in this recording."
        case .storageError(let error):
            return "Database error: \(error.localizedDescription)"
        case .invalidConfiguration:
            return "Invalid configuration detected."
        }
    }
    
    var failureReason: String? {
        return errorDescription
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .noProviderConfigured:
            return "Please configure an AI provider in the Settings."
        case .providerCreationFailed:
            return "Check your API keys and provider settings in Settings."
        case .batchNotFound:
            return "Try reprocessing the recordings from Settings."
        case .noRecordingsInBatch:
            return "Check if screen recording was active during this time period."
        case .videoProcessingFailed:
            return "Try reprocessing the recordings. If the issue persists, contact support."
        case .providerError:
            return "Check your internet connection and API settings. Rate limits may apply."
        case .emptyObservations:
            return "This is normal if there was no visible activity during the recording."
        case .storageError:
            return "Restart the application. If the issue persists, contact support."
        case .invalidConfiguration:
            return "Reset your provider settings in Settings and reconfigure."
        }
    }
}