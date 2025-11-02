//
//  LLMService.swift
//  Dayflow
//

import Foundation
import Combine
import AppKit
import AVFoundation
import SwiftUI
import GRDB

struct ProcessedBatchResult {
    let cards: [ActivityCardData]
    let cardIds: [Int64]
}

protocol LLMServicing {
    func processBatch(_ batchId: Int64, completion: @escaping (Result<ProcessedBatchResult, Error>) -> Void)
}

/// Legacy LLMService wrapper that delegates to the refactored actor-based implementation
final class LLMService: LLMServicing {
    static let shared: LLMServicing = LLMService()
    
    private let refactoredService: Dayflow.LLMService
    
    private init() {
        // Create the refactored service with production dependencies
        self.refactoredService = Dayflow.LLMService.makeProductionService()
    }
    
    /// Delegates to the refactored service implementation
    func processBatch(_ batchId: Int64, completion: @escaping (Result<ProcessedBatchResult, Error>) -> Void) {
        Task {
            do {
                let result = try await refactoredService.processBatchAsync(batchId)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }
}