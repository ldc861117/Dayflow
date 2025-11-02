//
//  SchemaMigrator.swift
//  Dayflow
//

import Foundation
import GRDB

struct SchemaMigrator {
    static func migrate(using dbContext: DatabaseContext) async throws {
        try await dbContext.write("migrate") { db in
            try db.execute(sql: """
                -- Chunks table: stores video recording segments
                CREATE TABLE IF NOT EXISTS chunks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    start_ts INTEGER NOT NULL,
                    end_ts INTEGER NOT NULL,
                    file_url TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'recording',
                    is_deleted INTEGER DEFAULT 0
                );
                CREATE INDEX IF NOT EXISTS idx_chunks_status ON chunks(status);
                CREATE INDEX IF NOT EXISTS idx_chunks_start_ts ON chunks(start_ts);
                
                -- Analysis batches: groups chunks for LLM processing
                CREATE TABLE IF NOT EXISTS analysis_batches (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    batch_start_ts INTEGER NOT NULL,
                    batch_end_ts INTEGER NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending',
                    reason TEXT,
                    llm_metadata TEXT,
                    detailed_transcription TEXT,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX IF NOT EXISTS idx_analysis_batches_status ON analysis_batches(status);
                
                -- Junction table linking batches to chunks
                CREATE TABLE IF NOT EXISTS batch_chunks (
                    batch_id INTEGER NOT NULL REFERENCES analysis_batches(id) ON DELETE CASCADE,
                    chunk_id INTEGER NOT NULL REFERENCES chunks(id) ON DELETE RESTRICT,
                    PRIMARY KEY (batch_id, chunk_id)
                );
                
                -- Timeline cards: stores activity summaries
                CREATE TABLE IF NOT EXISTS timeline_cards (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    batch_id INTEGER REFERENCES analysis_batches(id) ON DELETE CASCADE,
                    start TEXT NOT NULL,       -- Clock time (e.g., "2:30 PM")
                    end TEXT NOT NULL,         -- Clock time (e.g., "3:45 PM")
                    start_ts INTEGER,          -- Unix timestamp
                    end_ts INTEGER,            -- Unix timestamp
                    day DATE NOT NULL,
                    title TEXT NOT NULL,
                    summary TEXT,
                    category TEXT NOT NULL,
                    subcategory TEXT,
                    detailed_summary TEXT,
                    metadata TEXT,             -- For distractions JSON
                    video_summary_url TEXT,    -- Link to video summary on filesystem
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX IF NOT EXISTS idx_timeline_cards_day ON timeline_cards(day);
                CREATE INDEX IF NOT EXISTS idx_timeline_cards_start_ts ON timeline_cards(start_ts);
                CREATE INDEX IF NOT EXISTS idx_timeline_cards_time_range ON timeline_cards(start_ts, end_ts);
                
                -- Observations: stores LLM transcription outputs
                CREATE TABLE IF NOT EXISTS observations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    batch_id INTEGER NOT NULL REFERENCES analysis_batches(id) ON DELETE CASCADE,
                    start_ts INTEGER NOT NULL,
                    end_ts INTEGER NOT NULL,
                    observation TEXT NOT NULL,
                    metadata TEXT,
                    llm_model TEXT,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX IF NOT EXISTS idx_observations_batch_id ON observations(batch_id);
                CREATE INDEX IF NOT EXISTS idx_observations_start_ts ON observations(start_ts);
                CREATE INDEX IF NOT EXISTS idx_observations_time_range ON observations(start_ts, end_ts);
            """)
            
            // LLM calls logging table
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS llm_calls (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    batch_id INTEGER NULL,
                    call_group_id TEXT NULL,
                    attempt INTEGER NOT NULL DEFAULT 1,
                    provider TEXT NOT NULL,
                    model TEXT NULL,
                    operation TEXT NOT NULL,
                    status TEXT NOT NULL CHECK(status IN ('success','failure')),
                    latency_ms INTEGER NULL,
                    http_status INTEGER NULL,
                    request_method TEXT NULL,
                    request_url TEXT NULL,
                    request_headers TEXT NULL,
                    request_body TEXT NULL,
                    response_headers TEXT NULL,
                    response_body TEXT NULL,
                    error_domain TEXT NULL,
                    error_code INTEGER NULL,
                    error_message TEXT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_llm_calls_created ON llm_calls(created_at DESC);
                CREATE INDEX IF NOT EXISTS idx_llm_calls_group ON llm_calls(call_group_id, attempt);
                CREATE INDEX IF NOT EXISTS idx_llm_calls_batch ON llm_calls(batch_id);
            """)
            
            // Migration: Add soft delete column to timeline_cards if it doesn't exist
            let timelineCardsColumns = try db.columns(in: "timeline_cards").map { $0.name }
            if !timelineCardsColumns.contains("is_deleted") {
                try db.execute(sql: """
                    ALTER TABLE timeline_cards ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;
                """)
                
                // Create composite partial indexes for common query patterns
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_timeline_cards_active_start_ts
                    ON timeline_cards(start_ts)
                    WHERE is_deleted = 0;
                """)
                
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_timeline_cards_active_batch
                    ON timeline_cards(batch_id)
                    WHERE is_deleted = 0;
                """)
                
                print("✅ Added is_deleted column and composite indexes to timeline_cards")
            }
        }
    }
}
