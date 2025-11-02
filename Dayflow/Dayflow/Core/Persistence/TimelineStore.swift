//
//  TimelineStore.swift
//  Dayflow
//

import Foundation
import GRDB

actor TimelineStore {
    private let dbContext: DatabaseContext
    private let batchStore: BatchStore
    
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    init(dbContext: DatabaseContext, batchStore: BatchStore) {
        self.dbContext = dbContext
        self.batchStore = batchStore
    }
    
    func saveCardShell(batchId: Int64, card: TimelineCardShell) async throws -> Int64 {
        guard let batchStartTs = try await batchStore.fetchBatchStartTimestamp(batchId: batchId) else {
            throw StorageError.recordNotFound("Batch \(batchId)")
        }
        let baseDate = Date(timeIntervalSince1970: TimeInterval(batchStartTs))
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let startTime = timeFormatter.date(from: card.startTimestamp),
              let endTime = timeFormatter.date(from: card.endTimestamp) else {
            throw StorageError.invalidData("Unable to parse card timestamps")
        }
        
        let calendar = Calendar.current
        
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        guard let startHour = startComponents.hour, let startMinute = startComponents.minute else {
            throw StorageError.invalidData("Missing start components")
        }
        
        var startDate = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: baseDate) ?? baseDate
        if startHour < 4 && startDate < baseDate {
            let nextDayStart = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
            let sameDayDistance = abs(startDate.timeIntervalSince(baseDate))
            let nextDayDistance = abs(nextDayStart.timeIntervalSince(baseDate))
            if nextDayDistance < sameDayDistance {
                startDate = nextDayStart
            }
        }
        let startTs = Int(startDate.timeIntervalSince1970)
        
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        guard let endHour = endComponents.hour, let endMinute = endComponents.minute else {
            throw StorageError.invalidData("Missing end components")
        }
        
        var endDate = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: baseDate) ?? baseDate
        if endHour < 4 && endDate < baseDate {
            let nextDayEnd = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
            let sameDayDistance = abs(endDate.timeIntervalSince(baseDate))
            let nextDayDistance = abs(nextDayEnd.timeIntervalSince(baseDate))
            if nextDayDistance < sameDayDistance {
                endDate = nextDayEnd
            }
        }
        if endDate < startDate {
            endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }
        let endTs = Int(endDate.timeIntervalSince1970)
        
        let encoder = JSONEncoder()
        let meta = TimelineMetadata(distractions: card.distractions, appSites: card.appSites)
        let metadataString: String?
        do {
            let data = try encoder.encode(meta)
            metadataString = String(data: data, encoding: .utf8)
        } catch {
            throw StorageError.encodingFailed("Timeline metadata")
        }
        
        let (dayString, _, _) = startDate.getDayInfoFor4AMBoundary()
        
        return try await dbContext.write("saveTimelineCardShell") { db in
            try db.execute(sql: """
                INSERT INTO timeline_cards(
                    batch_id, start, end, start_ts, end_ts, day, title,
                    summary, category, subcategory, detailed_summary, metadata
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                batchId, card.startTimestamp, card.endTimestamp, startTs, endTs, dayString, card.title,
                card.summary, card.category, card.subcategory, card.detailedSummary, metadataString
            ])
            return db.lastInsertedRowID
        }
    }
    
    func updateVideoURL(cardId: Int64, videoSummaryURL: String) async throws {
        _ = try await dbContext.write("updateTimelineCardVideoURL") { db in
            try db.execute(sql: """
                UPDATE timeline_cards
                SET video_summary_url = ?
                WHERE id = ?
            """, arguments: [videoSummaryURL, cardId])
        }
    }
    
    func fetchForBatch(_ batchId: Int64) async throws -> [TimelineCard] {
        let decoder = JSONDecoder()
        return try await dbContext.read("fetchTimelineCardsForBatch") { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM timeline_cards
                WHERE batch_id = ?
                  AND is_deleted = 0
                ORDER BY start ASC
            """, arguments: [batchId])
            .map { row in
                var distractions: [Distraction]? = nil
                var appSites: AppSites? = nil
                if let metadataString: String = row["metadata"],
                   let jsonData = metadataString.data(using: .utf8) {
                    if let meta = try? decoder.decode(TimelineMetadata.self, from: jsonData) {
                        distractions = meta.distractions
                        appSites = meta.appSites
                    } else if let legacy = try? decoder.decode([Distraction].self, from: jsonData) {
                        distractions = legacy
                    }
                }
                return TimelineCard(
                    batchId: batchId,
                    startTimestamp: row["start"] ?? "",
                    endTimestamp: row["end"] ?? "",
                    category: row["category"],
                    subcategory: row["subcategory"],
                    title: row["title"],
                    summary: row["summary"],
                    detailedSummary: row["detailed_summary"],
                    day: row["day"],
                    distractions: distractions,
                    videoSummaryURL: row["video_summary_url"],
                    otherVideoSummaryURLs: nil,
                    appSites: appSites
                )
            }
        }
    }
    
    func fetchCard(byId id: Int64) async throws -> TimelineCardWithTimestamps? {
        let decoder = JSONDecoder()
        return try await dbContext.read("fetchTimelineCardById") { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM timeline_cards
                WHERE id = ?
                  AND is_deleted = 0
            """, arguments: [id]) else { return nil }
            var distractions: [Distraction]? = nil
            if let metadataString: String = row["metadata"],
               let jsonData = metadataString.data(using: .utf8) {
                if let meta = try? decoder.decode(TimelineMetadata.self, from: jsonData) {
                    distractions = meta.distractions
                } else if let legacy = try? decoder.decode([Distraction].self, from: jsonData) {
                    distractions = legacy
                }
            }
            return TimelineCardWithTimestamps(
                id: id,
                startTimestamp: row["start"] ?? "",
                endTimestamp: row["end"] ?? "",
                startTs: row["start_ts"] ?? 0,
                endTs: row["end_ts"] ?? 0,
                category: row["category"],
                subcategory: row["subcategory"],
                title: row["title"],
                summary: row["summary"],
                detailedSummary: row["detailed_summary"],
                day: row["day"],
                distractions: distractions,
                videoSummaryURL: row["video_summary_url"]
            )
        }
    }
    
    func fetchForDay(_ day: String) async throws -> [TimelineCard] {
        let decoder = JSONDecoder()
        guard let dayDate = dateFormatter.date(from: day) else { return [] }
        
        let calendar = Calendar.current
        var startComponents = calendar.dateComponents([.year, .month, .day], from: dayDate)
        startComponents.hour = 4
        guard let dayStart = calendar.date(from: startComponents) else { return [] }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayDate) else { return [] }
        var endComponents = calendar.dateComponents([.year, .month, .day], from: nextDay)
        endComponents.hour = 4
        guard let dayEnd = calendar.date(from: endComponents) else { return [] }
        
        let startTs = Int(dayStart.timeIntervalSince1970)
        let endTs = Int(dayEnd.timeIntervalSince1970)
        
        return try await dbContext.read("fetchTimelineCardsForDay") { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM timeline_cards
                WHERE start_ts >= ? AND start_ts < ?
                  AND is_deleted = 0
                ORDER BY start_ts ASC, start ASC
            """, arguments: [startTs, endTs])
            .map { row in
                var distractions: [Distraction]? = nil
                var appSites: AppSites? = nil
                if let metadataString: String = row["metadata"],
                   let jsonData = metadataString.data(using: .utf8) {
                    if let meta = try? decoder.decode(TimelineMetadata.self, from: jsonData) {
                        distractions = meta.distractions
                        appSites = meta.appSites
                    } else if let legacy = try? decoder.decode([Distraction].self, from: jsonData) {
                        distractions = legacy
                    }
                }
                return TimelineCard(
                    batchId: row["batch_id"],
                    startTimestamp: row["start"] ?? "",
                    endTimestamp: row["end"] ?? "",
                    category: row["category"],
                    subcategory: row["subcategory"],
                    title: row["title"],
                    summary: row["summary"],
                    detailedSummary: row["detailed_summary"],
                    day: row["day"],
                    distractions: distractions,
                    videoSummaryURL: row["video_summary_url"],
                    otherVideoSummaryURLs: nil,
                    appSites: appSites
                )
            }
        }
    }
    
    func fetchByTimeRange(from: Date, to: Date) async throws -> [TimelineCard] {
        let decoder = JSONDecoder()
        let fromTs = Int(from.timeIntervalSince1970)
        let toTs = Int(to.timeIntervalSince1970)
        
        return try await dbContext.read("fetchTimelineCardsByTimeRange") { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM timeline_cards
                WHERE ((start_ts < ? AND end_ts > ?)
                   OR (start_ts >= ? AND start_ts < ?))
                  AND is_deleted = 0
                ORDER BY start_ts ASC
            """, arguments: [toTs, fromTs, fromTs, toTs])
            .map { row in
                var distractions: [Distraction]? = nil
                var appSites: AppSites? = nil
                if let metadataString: String = row["metadata"],
                   let jsonData = metadataString.data(using: .utf8) {
                    if let meta = try? decoder.decode(TimelineMetadata.self, from: jsonData) {
                        distractions = meta.distractions
                        appSites = meta.appSites
                    } else if let legacy = try? decoder.decode([Distraction].self, from: jsonData) {
                        distractions = legacy
                    }
                }
                return TimelineCard(
                    batchId: row["batch_id"],
                    startTimestamp: row["start"] ?? "",
                    endTimestamp: row["end"] ?? "",
                    category: row["category"],
                    subcategory: row["subcategory"],
                    title: row["title"],
                    summary: row["summary"],
                    detailedSummary: row["detailed_summary"],
                    day: row["day"],
                    distractions: distractions,
                    videoSummaryURL: row["video_summary_url"],
                    otherVideoSummaryURLs: nil,
                    appSites: appSites
                )
            }
        }
    }
    
    func replaceInRange(from: Date, to: Date, cards: [TimelineCardShell], batchId: Int64) async throws -> (insertedIds: [Int64], deletedVideoPaths: [String]) {
        let fromTs = Int(from.timeIntervalSince1970)
        let toTs = Int(to.timeIntervalSince1970)
        let encoder = JSONEncoder()
        var insertedIds: [Int64] = []
        var videoPaths: [String] = []
        
        try await dbContext.write("replaceTimelineCardsInRange") { db in
            let videoRows = try Row.fetchAll(db, sql: """
                SELECT video_summary_url FROM timeline_cards
                WHERE ((start_ts < ? AND end_ts > ?)
                   OR (start_ts >= ? AND start_ts < ?))
                   AND video_summary_url IS NOT NULL
                   AND is_deleted = 0
            """, arguments: [toTs, fromTs, fromTs, toTs])
            videoPaths = videoRows.compactMap { $0["video_summary_url"] as? String }
            
            try db.execute(sql: """
                UPDATE timeline_cards
                SET is_deleted = 1
                WHERE ((start_ts < ? AND end_ts > ?)
                   OR (start_ts >= ? AND start_ts < ?))
                   AND is_deleted = 0
            """, arguments: [toTs, fromTs, fromTs, toTs])
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            timeFormatter.locale = Locale(identifier: "en_US_POSIX")
            
            let calendar = Calendar.current
            let anchor = from.addingTimeInterval(to.timeIntervalSince(from) / 2.0)
            
            for card in cards {
                let meta = TimelineMetadata(distractions: card.distractions, appSites: card.appSites)
                let metadataString: String? = try {
                    let data = try encoder.encode(meta)
                    return String(data: data, encoding: .utf8)
                }()
                
                guard let startTime = timeFormatter.date(from: card.startTimestamp),
                      let endTime = timeFormatter.date(from: card.endTimestamp) else {
                    continue
                }
                let resolveClock: (Int, Int) -> Date = { hour, minute in
                    guard let sameDay = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: anchor) else {
                        return anchor
                    }
                    let previousDay = calendar.date(byAdding: .day, value: -1, to: sameDay) ?? sameDay
                    let nextDay = calendar.date(byAdding: .day, value: 1, to: sameDay) ?? sameDay
                    let candidates = [previousDay, sameDay, nextDay]
                    return candidates.min { lhs, rhs in
                        abs(lhs.timeIntervalSince(anchor)) < abs(rhs.timeIntervalSince(anchor))
                    } ?? sameDay
                }
                let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                guard let startHour = startComponents.hour, let startMinute = startComponents.minute else { continue }
                var startDate = resolveClock(startHour, startMinute)
                let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                guard let endHour = endComponents.hour, let endMinute = endComponents.minute else { continue }
                var endDate = resolveClock(endHour, endMinute)
                if endDate < startDate {
                    endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
                }
                let startTs = Int(startDate.timeIntervalSince1970)
                let endTs = Int(endDate.timeIntervalSince1970)
                let (dayString, _, _) = startDate.getDayInfoFor4AMBoundary()
                try db.execute(sql: """
                    INSERT INTO timeline_cards(
                        batch_id, start, end, start_ts, end_ts, day, title,
                        summary, category, subcategory, detailed_summary, metadata
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    batchId, card.startTimestamp, card.endTimestamp, startTs, endTs, dayString,
                    card.title, card.summary, card.category, card.subcategory, card.detailedSummary, metadataString
                ])
                insertedIds.append(db.lastInsertedRowID)
            }
        }
        return (insertedIds, videoPaths)
    }
    
    func fetchRecentDebug(limit: Int) async throws -> [TimelineCardDebugEntry] {
        guard limit > 0 else { return [] }
        return try await dbContext.read("fetchRecentTimelineCardsForDebug") { db in
            try Row.fetchAll(db, sql: """
                SELECT batch_id, day, start, end, category, subcategory, title, summary, detailed_summary, created_at
                FROM timeline_cards
                WHERE is_deleted = 0
                ORDER BY created_at DESC, id DESC
                LIMIT ?
            """, arguments: [limit])
            .map { row in
                TimelineCardDebugEntry(
                    createdAt: row["created_at"],
                    batchId: row["batch_id"],
                    day: row["day"] ?? "",
                    startTime: row["start"] ?? "",
                    endTime: row["end"] ?? "",
                    category: row["category"],
                    subcategory: row["subcategory"],
                    title: row["title"],
                    summary: row["summary"],
                    detailedSummary: row["detailed_summary"]
                )
            }
        }
    }
    
    func deleteForDay(_ day: String) async throws -> [String] {
        guard let dayDate = dateFormatter.date(from: day) else { return [] }
        
        let calendar = Calendar.current
        var startComponents = calendar.dateComponents([.year, .month, .day], from: dayDate)
        startComponents.hour = 4
        guard let dayStart = calendar.date(from: startComponents) else { return [] }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayDate) else { return [] }
        var endComponents = calendar.dateComponents([.year, .month, .day], from: nextDay)
        endComponents.hour = 4
        guard let dayEnd = calendar.date(from: endComponents) else { return [] }
        
        let startTs = Int(dayStart.timeIntervalSince1970)
        let endTs = Int(dayEnd.timeIntervalSince1970)
        
        var videoPaths: [String] = []
        
        try await dbContext.write("deleteTimelineCardsForDay") { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT video_summary_url FROM timeline_cards
                WHERE start_ts >= ? AND start_ts < ?
                  AND video_summary_url IS NOT NULL
                  AND is_deleted = 0
            """, arguments: [startTs, endTs])
            videoPaths = rows.compactMap { $0["video_summary_url"] as? String }
            try db.execute(sql: """
                UPDATE timeline_cards
                SET is_deleted = 1
                WHERE start_ts >= ? AND start_ts < ?
                  AND is_deleted = 0
            """, arguments: [startTs, endTs])
        }
        return videoPaths
    }
    
    func deleteForBatchIds(_ batchIds: [Int64]) async throws -> [String] {
        guard !batchIds.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: batchIds.count).joined(separator: ",")
        var videoPaths: [String] = []
        
        try await dbContext.write("deleteTimelineCardsForBatchIds") { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT video_summary_url
                FROM timeline_cards
                WHERE batch_id IN (\(placeholders))
                  AND video_summary_url IS NOT NULL
                  AND is_deleted = 0
            """, arguments: StatementArguments(batchIds))
            videoPaths = rows.compactMap { $0["video_summary_url"] as? String }
            try db.execute(sql: """
                UPDATE timeline_cards
                SET is_deleted = 1
                WHERE batch_id IN (\(placeholders))
                  AND is_deleted = 0
            """, arguments: StatementArguments(batchIds))
        }
        return videoPaths
    }
}
