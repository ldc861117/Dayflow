//
//  BatchStore.swift
//  Dayflow
//

import Foundation
import GRDB

actor BatchStore {
    private let dbContext: DatabaseContext
    
    init(dbContext: DatabaseContext) {
        self.dbContext = dbContext
    }
    
    func createBatch(startTs: Int, endTs: Int, chunkIds: [Int64]) async throws -> Int64 {
        guard !chunkIds.isEmpty else { throw StorageError.invalidData("Chunk IDs required") }
        
        return try await dbContext.write("saveBatch") { db in
            try db.execute(sql: "INSERT INTO analysis_batches(batch_start_ts, batch_end_ts) VALUES (?, ?)", arguments: [startTs, endTs])
            let batchID = db.lastInsertedRowID
            for id in chunkIds {
                try db.execute(sql: "INSERT INTO batch_chunks(batch_id, chunk_id) VALUES (?, ?)", arguments: [batchID, id])
            }
            return batchID
        }
    }
    
    func updateStatus(batchId: Int64, status: String) async throws {
        _ = try await dbContext.write("updateBatchStatus") { db in
            try db.execute(sql: "UPDATE analysis_batches SET status = ? WHERE id = ?", arguments: [status, batchId])
        }
    }
    
    func markFailed(batchId: Int64, reason: String) async throws {
        _ = try await dbContext.write("markBatchFailed") { db in
            try db.execute(sql: "UPDATE analysis_batches SET status = 'failed', reason = ? WHERE id = ?", arguments: [reason, batchId])
        }
    }
    
    func updateMetadata(batchId: Int64, calls: [LLMCall]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(calls)
        guard let json = String(data: data, encoding: .utf8) else {
            throw StorageError.encodingFailed("Unable to encode LLM call metadata")
        }
        _ = try await dbContext.write("updateBatchLLMMetadata") { db in
            try db.execute(sql: "UPDATE analysis_batches SET llm_metadata = ? WHERE id = ?", arguments: [json, batchId])
        }
    }
    
    func fetchMetadata(batchId: Int64) async throws -> [LLMCall] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try await dbContext.read("fetchBatchLLMMetadata") { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT llm_metadata FROM analysis_batches WHERE id = ?", arguments: [batchId]) else {
                return []
            }
            guard let json: String = row["llm_metadata"], let data = json.data(using: .utf8) else {
                return []
            }
            return try decoder.decode([LLMCall].self, from: data)
        }
    }
    
    func allBatches() async throws -> [(id: Int64, start: Int, end: Int, status: String)] {
        try await dbContext.read("allBatches") { db in
            try Row.fetchAll(db, sql: "SELECT id, batch_start_ts, batch_end_ts, status FROM analysis_batches ORDER BY id DESC")
                .map { row in
                    (
                        id: row["id"],
                        start: row["batch_start_ts"],
                        end: row["batch_end_ts"],
                        status: row["status"]
                    )
                }
        }
    }
    
    func fetchBatchStartTimestamp(batchId: Int64) async throws -> Int? {
        try await dbContext.read("getBatchStartTimestamp") { db in
            try Int.fetchOne(db, sql: "SELECT batch_start_ts FROM analysis_batches WHERE id = ?", arguments: [batchId])
        }
    }
    
    func fetchBatches(forDay day: String) async throws -> [(id: Int64, startTs: Int, endTs: Int, status: String)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let dayDate = formatter.date(from: day) else { return [] }
        
        let calendar = Calendar.current
        guard let startOfDay = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: dayDate) else { return [] }
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        let startTs = Int(startOfDay.timeIntervalSince1970)
        let endTs = Int(endOfDay.timeIntervalSince1970)
        
        return try await dbContext.read("fetchBatchesForDay") { db in
            try Row.fetchAll(db, sql: """
                SELECT id, batch_start_ts, batch_end_ts, status FROM analysis_batches
                WHERE batch_start_ts >= ? AND batch_end_ts <= ?
                ORDER BY batch_start_ts ASC
            """, arguments: [startTs, endTs])
            .map { row in
                (
                    id: row["id"],
                    startTs: row["batch_start_ts"],
                    endTs: row["batch_end_ts"],
                    status: row["status"]
                )
            }
        }
    }
    
    func resetStatuses(forDay day: String) async throws -> [Int64] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let dayDate = formatter.date(from: day) else { return [] }
        
        let calendar = Calendar.current
        guard let startOfDay = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: dayDate) else { return [] }
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        let startTs = Int(startOfDay.timeIntervalSince1970)
        let endTs = Int(endOfDay.timeIntervalSince1970)
        
        return try await dbContext.write("resetBatchStatusesForDay") { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id FROM analysis_batches
                WHERE batch_start_ts >= ? AND batch_end_ts <= ?
                  AND status IN ('completed', 'failed', 'processing', 'analyzed')
            """, arguments: [startTs, endTs])
            let ids = rows.compactMap { $0["id"] as? Int64 }
            guard !ids.isEmpty else { return [] }
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            try db.execute(sql: "UPDATE analysis_batches SET status = 'pending', reason = NULL, llm_metadata = NULL WHERE id IN (\(placeholders))", arguments: StatementArguments(ids))
            return ids
        }
    }
    
    func resetStatuses(forBatchIds batchIds: [Int64]) async throws -> [Int64] {
        guard !batchIds.isEmpty else { return [] }
        return try await dbContext.write("resetBatchStatusesForBatchIds") { db in
            let placeholders = Array(repeating: "?", count: batchIds.count).joined(separator: ",")
            let rows = try Row.fetchAll(db, sql: "SELECT id FROM analysis_batches WHERE id IN (\(placeholders))", arguments: StatementArguments(batchIds))
            let ids = rows.compactMap { $0["id"] as? Int64 }
            guard !ids.isEmpty else { return [] }
            let updatePlaceholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            try db.execute(sql: "UPDATE analysis_batches SET status = 'pending', reason = NULL, llm_metadata = NULL WHERE id IN (\(updatePlaceholders))", arguments: StatementArguments(ids))
            return ids
        }
    }
    
    func setStatus(batchId: Int64, status: String, reason: String? = nil) async throws {
        _ = try await dbContext.write("setBatchStatus") { db in
            try db.execute(sql: "UPDATE analysis_batches SET status = ?, reason = ? WHERE id = ?", arguments: [status, reason, batchId])
        }
    }
    
    func setMetadata(batchId: Int64, metadata: String) async throws {
        _ = try await dbContext.write("setBatchMetadata") { db in
            try db.execute(sql: "UPDATE analysis_batches SET llm_metadata = ? WHERE id = ?", arguments: [metadata, batchId])
        }
    }
    
    func fetchRecentDebug(limit: Int) async throws -> [AnalysisBatchDebugEntry] {
        guard limit > 0 else { return [] }
        return try await dbContext.read("fetchRecentAnalysisBatchesForDebug") { db in
            try Row.fetchAll(db, sql: """
                SELECT id, status, batch_start_ts, batch_end_ts, created_at, reason
                FROM analysis_batches
                ORDER BY id DESC
                LIMIT ?
            """, arguments: [limit])
            .map { row in
                AnalysisBatchDebugEntry(
                    id: row["id"],
                    status: row["status"] ?? "unknown",
                    startTs: row["batch_start_ts"] ?? 0,
                    endTs: row["batch_end_ts"] ?? 0,
                    createdAt: row["created_at"],
                    reason: row["reason"]
                )
            }
        }
    }
}
