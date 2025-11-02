//
//  LLMCallStore.swift
//  Dayflow
//

import Foundation
import GRDB

actor LLMCallStore {
    private let dbContext: DatabaseContext
    
    init(dbContext: DatabaseContext) {
        self.dbContext = dbContext
    }
    
    func insert(_ record: LLMCallDBRecord) async throws {
        _ = try await dbContext.write("insertLLMCall") { db in
            try db.execute(sql: """
                INSERT INTO llm_calls (
                    batch_id, call_group_id, attempt, provider, model, operation,
                    status, latency_ms, http_status, request_method, request_url,
                    request_headers, request_body, response_headers, response_body,
                    error_domain, error_code, error_message
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                record.batchId,
                record.callGroupId,
                record.attempt,
                record.provider,
                record.model,
                record.operation,
                record.status,
                record.latencyMs,
                record.httpStatus,
                record.requestMethod,
                record.requestURL,
                record.requestHeadersJSON,
                record.requestBody,
                record.responseHeadersJSON,
                record.responseBody,
                record.errorDomain,
                record.errorCode,
                record.errorMessage
            ])
        }
    }
    
    func fetchRecent(limit: Int) async throws -> [LLMCallDebugEntry] {
        guard limit > 0 else { return [] }
        return try await dbContext.read("fetchRecentLLMCallsForDebug") { db in
            try Row.fetchAll(db, sql: """
                SELECT created_at, batch_id, call_group_id, attempt, provider, model, operation, status, latency_ms, http_status, request_method, request_url, request_body, response_body, error_message
                FROM llm_calls
                ORDER BY created_at DESC, id DESC
                LIMIT ?
            """, arguments: [limit])
            .map { row in
                LLMCallDebugEntry(
                    createdAt: row["created_at"],
                    batchId: row["batch_id"],
                    callGroupId: row["call_group_id"],
                    attempt: row["attempt"] ?? 0,
                    provider: row["provider"] ?? "",
                    model: row["model"],
                    operation: row["operation"] ?? "",
                    status: row["status"] ?? "",
                    latencyMs: row["latency_ms"],
                    httpStatus: row["http_status"],
                    requestMethod: row["request_method"],
                    requestURL: row["request_url"],
                    requestBody: row["request_body"],
                    responseBody: row["response_body"],
                    errorMessage: row["error_message"]
                )
            }
        }
    }
    
    func fetchForBatches(batchIds: [Int64], limit: Int) async throws -> [LLMCallDebugEntry] {
        guard !batchIds.isEmpty, limit > 0 else { return [] }
        let placeholders = Array(repeating: "?", count: batchIds.count).joined(separator: ",")
        var arguments = batchIds.map { $0 }
        arguments.append(Int64(limit))
        return try await dbContext.read("fetchLLMCallsForBatches") { db in
            try Row.fetchAll(db, sql: """
                SELECT created_at, batch_id, call_group_id, attempt, provider, model, operation, status, latency_ms, http_status, request_method, request_url, request_body, response_body, error_message
                FROM llm_calls
                WHERE batch_id IN (\(placeholders))
                ORDER BY created_at DESC, id DESC
                LIMIT ?
            """, arguments: StatementArguments(arguments))
            .map { row in
                LLMCallDebugEntry(
                    createdAt: row["created_at"],
                    batchId: row["batch_id"],
                    callGroupId: row["call_group_id"],
                    attempt: row["attempt"] ?? 0,
                    provider: row["provider"] ?? "",
                    model: row["model"],
                    operation: row["operation"] ?? "",
                    status: row["status"] ?? "",
                    latencyMs: row["latency_ms"],
                    httpStatus: row["http_status"],
                    requestMethod: row["request_method"],
                    requestURL: row["request_url"],
                    requestBody: row["request_body"],
                    responseBody: row["response_body"],
                    errorMessage: row["error_message"]
                )
            }
        }
    }
}
