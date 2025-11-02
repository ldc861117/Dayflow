//
//  StorageMaintenance.swift
//  Dayflow
//

import Foundation
import GRDB

actor StorageMaintenance {
    private let dbContext: DatabaseContext
    private let recordingsRoot: URL
    private let baseDirectory: URL
    private let fileManager: FileManager
    private var purgeTimer: DispatchSourceTimer?
    private let purgeQueue = DispatchQueue(label: "com.dayflow.storage.purge", qos: .background)
    
    init(dbContext: DatabaseContext, recordingsRoot: URL, baseDirectory: URL, fileManager: FileManager = .default) {
        self.dbContext = dbContext
        self.recordingsRoot = recordingsRoot
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }
    
    func start() {
        schedulePurge()
    }
    
    func performStartupMaintenance() async {
        await migrateLegacyPathsIfNeeded()
        await purgeIfNeeded()
        TimelapseStorageManager.shared.purgeIfNeeded()
    }
    
    func stop() {
        purgeTimer?.cancel()
        purgeTimer = nil
    }
    
    private func schedulePurge() {
        let timer = DispatchSource.makeTimerSource(queue: purgeQueue)
        timer.schedule(deadline: .now() + 3600, repeating: 3600)
        timer.setEventHandler { [weak self] in
            Task { await self?.purgeIfNeeded() }
            TimelapseStorageManager.shared.purgeIfNeeded()
        }
        timer.resume()
        purgeTimer = timer
    }
    
    func purgeIfNeeded() async {
        await withCheckedContinuation { continuation in
            purgeQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                do {
                    let currentSize = try self.fileManager.allocatedSizeOfDirectory(at: self.recordingsRoot)
                    let limit = StoragePreferences.recordingsLimitBytes
                    if limit == Int64.max {
                        continuation.resume()
                        return
                    }
                    let cutoffDate = Date().addingTimeInterval(-3 * 24 * 60 * 60)
                    let cutoffTimestamp = Int(cutoffDate.timeIntervalSince1970)
                    if currentSize <= limit {
                        continuation.resume()
                        return
                    }
                    Task {
                        do {
                            try await self.dbContext.write("purgeIfNeeded") { db in
                                let oldChunks = try Row.fetchAll(db, sql: """
                                    SELECT id, file_url, start_ts
                                    FROM chunks
                                    WHERE start_ts < ?
                                    AND file_url IS NOT NULL
                                    AND file_url != ''
                                    AND (is_deleted = 0 OR is_deleted IS NULL)
                                    ORDER BY start_ts ASC
                                    LIMIT 500
                                """, arguments: [cutoffTimestamp])
                                var freedSpace: Int64 = 0
                                var remainingSize = currentSize
                                for chunk in oldChunks {
                                    guard let id: Int64 = chunk["id"], let path: String = chunk["file_url"] else { continue }
                                    var fileSize: Int64 = 0
                                    if self.fileManager.fileExists(atPath: path),
                                       let attrs = try? self.fileManager.attributesOfItem(atPath: path),
                                       let size = attrs[.size] as? NSNumber {
                                        fileSize = size.int64Value
                                    }
                                    try db.execute(sql: """
                                        UPDATE chunks
                                        SET is_deleted = 1
                                        WHERE id = ?
                                    """, arguments: [id])
                                    if self.fileManager.fileExists(atPath: path) {
                                        do {
                                            try self.fileManager.removeItem(atPath: path)
                                            freedSpace += fileSize
                                            remainingSize -= fileSize
                                        } catch {
                                            print("⚠️ Failed to delete chunk file at \(path): \(error)")
                                        }
                                    }
                                    if remainingSize < limit {
                                        break
                                    }
                                }
                            }
                        } catch {
                            print("❌ Purge error: \(error)")
                        }
                        continuation.resume()
                    }
                } catch {
                    print("❌ Purge error: \(error)")
                    continuation.resume()
                }
            }
        }
    }
    
    private func migrateLegacyPathsIfNeeded() async {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        
        let legacyBase = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Application Support/Dayflow", isDirectory: true)
        let newBase = appSupport.appendingPathComponent("Dayflow", isDirectory: true)
        
        if legacyBase.path == newBase.path { return }
        
        func normalized(_ path: String) -> String {
            path.hasSuffix("/") ? path : path + "/"
        }
        
        let legacyRecordings = normalized(legacyBase.appendingPathComponent("recordings", isDirectory: true).path)
        let newRecordings = normalized(recordingsRoot.path)
        let legacyTimelapses = normalized(legacyBase.appendingPathComponent("timelapses", isDirectory: true).path)
        let newTimelapses = normalized(newBase.appendingPathComponent("timelapses", isDirectory: true).path)
        
        let replacements: [(label: String, table: String, column: String, legacyPrefix: String, newPrefix: String)] = [
            ("chunk file paths", "chunks", "file_url", legacyRecordings, newRecordings),
            ("timelapse video paths", "timeline_cards", "video_summary_url", legacyTimelapses, newTimelapses)
        ]
        
        do {
            try await dbContext.write("migrateLegacyFileURLs") { db in
                for replacement in replacements {
                    guard replacement.legacyPrefix != replacement.newPrefix else { continue }
                    let pattern = replacement.legacyPrefix + "%"
                    let count = try Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM \(replacement.table) WHERE \(replacement.column) LIKE ?",
                        arguments: [pattern]
                    ) ?? 0
                    guard count > 0 else { continue }
                    try db.execute(
                        sql: """
                            UPDATE \(replacement.table)
                            SET \(replacement.column) = REPLACE(\(replacement.column), ?, ?)
                            WHERE \(replacement.column) LIKE ?
                        """,
                        arguments: [replacement.legacyPrefix, replacement.newPrefix, pattern]
                    )
                    let updated = db.changesCount
                    print("ℹ️ StorageMaintenance: migrated \(updated) \(replacement.label) to \(replacement.newPrefix)")
                }
            }
        } catch {
            print("⚠️ StorageMaintenance: failed to migrate legacy file URLs: \(error)")
        }
    }
    
    static func migrateDatabaseLocationIfNeeded(fileManager: FileManager, legacyRecordingsDir: URL, newDatabaseURL: URL) {
        let destinationDir = newDatabaseURL.deletingLastPathComponent()
        let filenames = ["chunks.sqlite", "chunks.sqlite-wal", "chunks.sqlite-shm"]
        guard filenames.contains(where: { fileManager.fileExists(atPath: legacyRecordingsDir.appendingPathComponent($0).path) }) else {
            return
        }
        if !fileManager.fileExists(atPath: destinationDir.path) {
            try? fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }
        for name in filenames {
            let legacyURL = legacyRecordingsDir.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: legacyURL.path) else { continue }
            let destinationURL = destinationDir.appendingPathComponent(name)
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: legacyURL, to: destinationURL)
                print("ℹ️ StorageMaintenance: migrated \(name) to \(destinationURL.path)")
            } catch {
                print("⚠️ StorageMaintenance: failed to migrate \(name): \(error)")
            }
        }
    }
}
