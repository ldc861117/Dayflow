//
//  StorageContainer.swift
//  Dayflow
//

import Foundation
import GRDB

final class StorageContainer: @unchecked Sendable {
    let config: StorageConfiguration
    private(set) var dbContext: DatabaseContext!
    private(set) var chunkStore: ChunkStore!
    private(set) var batchStore: BatchStore!
    private(set) var timelineStore: TimelineStore!
    private(set) var observationStore: ObservationStore!
    private(set) var llmCallStore: LLMCallStore!
    private(set) var maintenance: StorageMaintenance!
    
    init(config: StorageConfiguration) throws {
        self.config = config
        
        try FileManager.default.createDirectory(at: config.baseDirectory, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: config.recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        
        StorageMaintenance.migrateDatabaseLocationIfNeeded(
            fileManager: .default,
            legacyRecordingsDir: config.recordingsDirectory,
            newDatabaseURL: config.databaseURL
        )
        
        do {
            self.dbContext = try DatabaseContext(configuration: config)
        } catch {
            print("❌ Failed to initialize database context: \(error)")
            throw error
        }
        
        self.batchStore = BatchStore(dbContext: dbContext)
        self.chunkStore = ChunkStore(dbContext: dbContext, recordingsRoot: config.recordingsDirectory)
        self.timelineStore = TimelineStore(dbContext: dbContext, batchStore: batchStore)
        self.observationStore = ObservationStore(dbContext: dbContext)
        self.llmCallStore = LLMCallStore(dbContext: dbContext)
        self.maintenance = StorageMaintenance(
            dbContext: dbContext,
            recordingsRoot: config.recordingsDirectory,
            baseDirectory: config.baseDirectory
        )
        
        Task {
            do {
                try await SchemaMigrator.migrate(using: dbContext)
            } catch {
                print("❌ Schema migration failed: \(error)")
            }
            await maintenance.performStartupMaintenance()
            await maintenance.start()
        }
    }
    
    static func makeDefault() throws -> StorageContainer {
        UserDefaultsMigrator.migrateIfNeeded()
        StoragePathMigrator.migrateIfNeeded()
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let baseDir = appSupport.appendingPathComponent("Dayflow", isDirectory: true)
        let recordingsDir = baseDir.appendingPathComponent("recordings", isDirectory: true)
        let dbURL = baseDir.appendingPathComponent("chunks.sqlite")
        
        let config = StorageConfiguration(
            baseDirectory: baseDir,
            recordingsDirectory: recordingsDir,
            databaseURL: dbURL,
            slowQueryThresholdMs: 100,
            enableSlowQueryLogging: true
        )
        
        return try StorageContainer(config: config)
    }
}
