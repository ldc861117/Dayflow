//
//  DatabaseContext.swift
//  Dayflow
//

import Foundation
import GRDB
import Sentry

actor DatabaseContext {
    private let pool: DatabasePool
    private let config: StorageConfiguration
    
    init(configuration: StorageConfiguration) throws {
        self.config = configuration
        
        var dbConfig = Configuration()
        dbConfig.maximumReaderCount = 5
        dbConfig.prepareDatabase { db in
            if !db.configuration.readonly {
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
            }
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
        }
        
        do {
            self.pool = try DatabasePool(path: configuration.databaseURL.path, configuration: dbConfig)
        } catch {
            throw StorageError.databaseNotInitialized
        }
        
        #if DEBUG
        if configuration.enableSlowQueryLogging {
            try? pool.write { db in
                db.trace { event in
                    if case .profile(let statement, let duration) = event, duration > 0.1 {
                        print("📊 SLOW SQL (\(Int(duration * 1000))ms): \(statement)")
                    }
                }
            }
        }
        #endif
    }
    
    func read<T>(_ label: String = #function, _ block: (Database) throws -> T) async throws -> T {
        let callStart = CFAbsoluteTimeGetCurrent()
        var execStart: CFAbsoluteTime = 0
        var execEnd: CFAbsoluteTime = 0
        
        let readBreadcrumb = Breadcrumb(level: .debug, category: "database")
        readBreadcrumb.message = "DB read: \(label)"
        readBreadcrumb.type = "debug"
        SentryHelper.addBreadcrumb(readBreadcrumb)
        
        do {
            let result = try pool.read { db in
                execStart = CFAbsoluteTimeGetCurrent()
                defer { execEnd = CFAbsoluteTimeGetCurrent() }
                return try block(db)
            }
            
            let waitMs = max(0, (execStart - callStart) * 1000)
            let execMs = max(0, (execEnd - execStart) * 1000)
            
            if config.enableSlowQueryLogging && (execMs > config.slowQueryThresholdMs || waitMs > config.slowQueryThresholdMs) {
                print("⚠️ SLOW READ [\(label)]: wait=\(Int(waitMs))ms exec=\(Int(execMs))ms")
                
                let slowReadBreadcrumb = Breadcrumb(level: .warning, category: "database")
                slowReadBreadcrumb.message = "SLOW DB read: \(label)"
                slowReadBreadcrumb.data = [
                    "duration_ms": Int((waitMs + execMs).rounded()),
                    "wait_ms": Int(waitMs.rounded()),
                    "exec_ms": Int(execMs.rounded())
                ]
                slowReadBreadcrumb.type = "error"
                SentryHelper.addBreadcrumb(slowReadBreadcrumb)
            }
            
            return result
        } catch {
            if execStart == 0 {
                execStart = CFAbsoluteTimeGetCurrent()
            }
            if execEnd == 0 {
                execEnd = CFAbsoluteTimeGetCurrent()
            }
            let waitMs = max(0, (execStart - callStart) * 1000)
            let execMs = max(0, (execEnd - execStart) * 1000)
            
            let failedReadBreadcrumb = Breadcrumb(level: .error, category: "database")
            failedReadBreadcrumb.message = "FAILED DB read: \(label)"
            failedReadBreadcrumb.data = [
                "wait_ms": Int(waitMs.rounded()),
                "exec_ms": Int(execMs.rounded()),
                "error": "\(error)"
            ]
            failedReadBreadcrumb.type = "error"
            SentryHelper.addBreadcrumb(failedReadBreadcrumb)
            throw StorageError.readFailure(label, error)
        }
    }
    
    func write<T>(_ label: String = #function, _ block: (Database) throws -> T) async throws -> T {
        let callStart = CFAbsoluteTimeGetCurrent()
        var execStart: CFAbsoluteTime = 0
        var execEnd: CFAbsoluteTime = 0
        
        let writeBreadcrumb = Breadcrumb(level: .debug, category: "database")
        writeBreadcrumb.message = "DB write: \(label)"
        writeBreadcrumb.type = "debug"
        SentryHelper.addBreadcrumb(writeBreadcrumb)
        
        do {
            let result = try pool.write { db in
                execStart = CFAbsoluteTimeGetCurrent()
                defer { execEnd = CFAbsoluteTimeGetCurrent() }
                return try block(db)
            }
            
            let waitMs = max(0, (execStart - callStart) * 1000)
            let execMs = max(0, (execEnd - execStart) * 1000)
            
            if config.enableSlowQueryLogging && (execMs > config.slowQueryThresholdMs || waitMs > config.slowQueryThresholdMs) {
                print("⚠️ SLOW WRITE [\(label)]: wait=\(Int(waitMs))ms exec=\(Int(execMs))ms")
                
                let slowWriteBreadcrumb = Breadcrumb(level: .warning, category: "database")
                slowWriteBreadcrumb.message = "SLOW DB write: \(label)"
                slowWriteBreadcrumb.data = [
                    "duration_ms": Int((waitMs + execMs).rounded()),
                    "wait_ms": Int(waitMs.rounded()),
                    "exec_ms": Int(execMs.rounded())
                ]
                slowWriteBreadcrumb.type = "error"
                SentryHelper.addBreadcrumb(slowWriteBreadcrumb)
            }
            
            return result
        } catch {
            if execStart == 0 {
                execStart = CFAbsoluteTimeGetCurrent()
            }
            if execEnd == 0 {
                execEnd = CFAbsoluteTimeGetCurrent()
            }
            let waitMs = max(0, (execStart - callStart) * 1000)
            let execMs = max(0, (execEnd - execStart) * 1000)
            
            let failedWriteBreadcrumb = Breadcrumb(level: .error, category: "database")
            failedWriteBreadcrumb.message = "FAILED DB write: \(label)"
            failedWriteBreadcrumb.data = [
                "wait_ms": Int(waitMs.rounded()),
                "exec_ms": Int(execMs.rounded()),
                "error": "\(error)"
            ]
            failedWriteBreadcrumb.type = "error"
            SentryHelper.addBreadcrumb(failedWriteBreadcrumb)
            throw StorageError.writeFailure(label, error)
        }
    }
}
