//
//  ObservationStore.swift
//  Dayflow
//

import Foundation
import GRDB

actor ObservationStore {
    private let dbContext: DatabaseContext
    
    init(dbContext: DatabaseContext) {
        self.dbContext = dbContext
    }
    
    func save(batchId: Int64, observations: [Observation]) async throws {
        guard !observations.isEmpty else { return }
        _ = try await dbContext.write("saveObservations") { db in
            for obs in observations {
                try db.execute(sql: """
                    INSERT INTO observations(
                        batch_id, start_ts, end_ts, observation, metadata, llm_model
                    )
                    VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [
                    batchId, obs.startTs, obs.endTs, obs.observation,
                    obs.metadata, obs.llmModel
                ])
            }
        }
    }
    
    func fetch(batchId: Int64) async throws -> [Observation] {
        try await dbContext.read("fetchObservationsForBatch") { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM observations
                WHERE batch_id = ?
                ORDER BY start_ts ASC
            """, arguments: [batchId])
            .map { row in
                Observation(
                    id: row["id"],
                    batchId: row["batch_id"],
                    startTs: row["start_ts"],
                    endTs: row["end_ts"],
                    observation: row["observation"],
                    metadata: row["metadata"],
                    llmModel: row["llm_model"],
                    createdAt: row["created_at"]
                )
            }
        }
    }
    
    func fetch(startTs: Int, endTs: Int) async throws -> [Observation] {
        try await dbContext.read("fetchObservationsInTimeRange") { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM observations
                WHERE start_ts >= ? AND end_ts <= ?
                ORDER BY start_ts ASC
            """, arguments: [startTs, endTs])
            .map { row in
                Observation(
                    id: row["id"],
                    batchId: row["batch_id"],
                    startTs: row["start_ts"],
                    endTs: row["end_ts"],
                    observation: row["observation"],
                    metadata: row["metadata"],
                    llmModel: row["llm_model"],
                    createdAt: row["created_at"]
                )
            }
        }
    }
    
    func fetchByTimeRange(from: Date, to: Date) async throws -> [Observation] {
        let fromTs = Int(from.timeIntervalSince1970)
        let toTs = Int(to.timeIntervalSince1970)
        
        return try await dbContext.read("fetchObservationsByTimeRange") { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM observations
                WHERE (start_ts < ? AND end_ts > ?)
                   OR (start_ts >= ? AND start_ts < ?)
                ORDER BY start_ts ASC
            """, arguments: [toTs, fromTs, fromTs, toTs])
            .map { row in
                Observation(
                    id: row["id"],
                    batchId: row["batch_id"],
                    startTs: row["start_ts"],
                    endTs: row["end_ts"],
                    observation: row["observation"],
                    metadata: row["metadata"],
                    llmModel: row["llm_model"],
                    createdAt: row["created_at"]
                )
            }
        }
    }
    
    func delete(forBatchIds batchIds: [Int64]) async throws {
        guard !batchIds.isEmpty else { return }
        
        _ = try await dbContext.write("deleteObservationsForBatchIds") { db in
            let placeholders = Array(repeating: "?", count: batchIds.count).joined(separator: ",")
            try db.execute(sql: """
                DELETE FROM observations WHERE batch_id IN (\(placeholders))
            """, arguments: StatementArguments(batchIds))
        }
    }
}
