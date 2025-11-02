//
//  StorageError.swift
//  Dayflow
//

import Foundation

enum StorageError: Error, LocalizedError {
    case databaseNotInitialized
    case invalidData(String)
    case recordNotFound(String)
    case writeFailure(String, Error)
    case readFailure(String, Error)
    case migrationFailure(String, Error)
    case fileOperationFailed(String, Error)
    case invalidPath(String)
    case encodingFailed(String)
    case decodingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .databaseNotInitialized:
            return "Database has not been initialized"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .recordNotFound(let identifier):
            return "Record not found: \(identifier)"
        case .writeFailure(let operation, let error):
            return "Write failure during \(operation): \(error.localizedDescription)"
        case .readFailure(let operation, let error):
            return "Read failure during \(operation): \(error.localizedDescription)"
        case .migrationFailure(let operation, let error):
            return "Migration failure during \(operation): \(error.localizedDescription)"
        case .fileOperationFailed(let operation, let error):
            return "File operation failed during \(operation): \(error.localizedDescription)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .encodingFailed(let reason):
            return "Encoding failed: \(reason)"
        case .decodingFailed(let reason):
            return "Decoding failed: \(reason)"
        }
    }
}
