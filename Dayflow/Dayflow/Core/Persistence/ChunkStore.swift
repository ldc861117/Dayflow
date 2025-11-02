//
//  ChunkStore.swift
//  Dayflow
//

import Foundation
import GRDB

actor ChunkStore {
    private let dbContext: DatabaseContext
    private let fileManager: FileManager
    private let recordingsRoot: URL
    
    init(dbContext: DatabaseContext, recordingsRoot: URL, fileManager: FileManager = .default) {
        self.dbContext = dbContext
        self.recordingsRoot = recordingsRoot
        self.fileManager = fileManager
    }
    
    func nextFileURL() -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmssSSS"
        return recordingsRoot.appendingPathComponent("\(df.string(from: Date())).mp4")
    }
    
    func register(url: URL) async throws {
        let ts = Int(Date().timeIntervalSince1970)
        let path = url.path
        
        try await dbContext.write("registerChunk") { db in
            try db.execute(
                sql: "INSERT INTO chunks(start_ts, end_ts, file_url, status) VALUES (?, ?, ?, 'recording')",
                arguments: [ts, ts + 60, path]
            )
        }
    }
    
    func markCompleted(url: URL) async throws {
        let end = Int(Date().timeIntervalSince1970)
        let path = url.path
        
        try await dbContext.write("markChunkCompleted") { db in
            try db.execute(
                sql: "UPDATE chunks SET end_ts = ?, status = 'completed' WHERE file_url = ?",
                arguments: [end, path]
            )
        }
    }
    
    func markFailed(url: URL) async throws {
        let path = url.path
        
        try await dbContext.write("markChunkFailed") { db in
            try db.execute(sql: "DELETE FROM chunks WHERE file_url = ?", arguments: [path])
        }
        
        try? fileManager.removeItem(at: url)
    }
    
    func fetchUnprocessed(olderThan oldestAllowed: Int) async throws -> [RecordingChunk] {
        try await dbContext.read("fetchUnprocessedChunks") { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM chunks
                WHERE start_ts >= ?
                  AND status = 'completed'
                  AND (is_deleted = 0 OR is_deleted IS NULL)
                  AND id NOT IN (SELECT chunk_id FROM batch_chunks)
                ORDER BY start_ts ASC
            """, arguments: [oldestAllowed])
            .map { row in
                RecordingChunk(
                    id: row["id"],
                    startTs: row["start_ts"],
                    endTs: row["end_ts"],
                    fileUrl: row["file_url"],
                    status: row["status"]
                )
            }
        }
    }
    
    func fetchInTimeRange(startTs: Int, endTs: Int) async throws -> [RecordingChunk] {
        try await dbContext.read("fetchChunksInTimeRange") { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM chunks
                WHERE status = 'completed'
                  AND (is_deleted = 0 OR is_deleted IS NULL)
                  AND ((start_ts <= ? AND end_ts >= ?)
                       OR (start_ts >= ? AND start_ts <= ?)
                       OR (end_ts >= ? AND end_ts <= ?))
                ORDER BY start_ts ASC
            """, arguments: [endTs, startTs, startTs, endTs, startTs, endTs])
            .map { row in
                RecordingChunk(
                    id: row["id"],
                    startTs: row["start_ts"],
                    endTs: row["end_ts"],
                    fileUrl: row["file_url"],
                    status: row["status"]
                )
            }
        }
    }
    
    func fetchForBatch(_ batchId: Int64) async throws -> [RecordingChunk] {
        try await dbContext.read("chunksForBatch") { db in
            try Row.fetchAll(db, sql: """
                SELECT c.* FROM batch_chunks bc
                JOIN chunks c ON c.id = bc.chunk_id
                WHERE bc.batch_id = ?
                  AND (c.is_deleted = 0 OR c.is_deleted IS NULL)
                ORDER BY c.start_ts ASC
            """, arguments: [batchId])
            .map { row in
                RecordingChunk(
                    id: row["id"],
                    startTs: row["start_ts"],
                    endTs: row["end_ts"],
                    fileUrl: row["file_url"],
                    status: row["status"]
                )
            }
        }
    }
    
    func getTimestamps(forPaths paths: [String]) async throws -> [String: (startTs: Int, endTs: Int)] {
        guard !paths.isEmpty else { return [:] }
        
        let placeholders = Array(repeating: "?", count: paths.count).joined(separator: ",")
        let sql = "SELECT file_url, start_ts, end_ts FROM chunks WHERE file_url IN (\(placeholders)) AND (is_deleted = 0 OR is_deleted IS NULL)"
        
        return try await dbContext.read("getTimestampsForVideoFiles") { db in
            var result: [String: (Int, Int)] = [:]
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(paths))
            for row in rows {
                if let path: String = row["file_url"],
                   let start: Int = row["start_ts"],
                   let end: Int = row["end_ts"] {
                    result[path] = (start, end)
                }
            }
            return result
        }
    }
    
    func getFilePaths(forBatch batchId: Int64) async throws -> [String] {
        try await dbContext.read("getChunkFilesForBatch") { db in
            let sql = """
                SELECT c.file_url
                FROM chunks c
                JOIN batch_chunks bc ON c.id = bc.chunk_id
                WHERE bc.batch_id = ?
                  AND (c.is_deleted = 0 OR c.is_deleted IS NULL)
                ORDER BY c.start_ts
            """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [batchId])
            return rows.compactMap { $0["file_url"] as? String }
        }
    }
}
