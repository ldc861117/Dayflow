//
//  StorageConfiguration.swift
//  Dayflow
//

import Foundation

struct StorageConfiguration {
    let baseDirectory: URL
    let recordingsDirectory: URL
    let databaseURL: URL
    let slowQueryThresholdMs: Double
    let enableSlowQueryLogging: Bool
    
    init(baseDirectory: URL, recordingsDirectory: URL, databaseURL: URL, slowQueryThresholdMs: Double = 100, enableSlowQueryLogging: Bool = true) {
        self.baseDirectory = baseDirectory
        self.recordingsDirectory = recordingsDirectory
        self.databaseURL = databaseURL
        self.slowQueryThresholdMs = slowQueryThresholdMs
        self.enableSlowQueryLogging = enableSlowQueryLogging
    }
}
