//
//  StorageModels.swift
//  Dayflow
//

import Foundation

struct Observation: Codable, Sendable {
    let id: Int64?
    let batchId: Int64
    let startTs: Int
    let endTs: Int
    let observation: String
    let metadata: String?
    let llmModel: String?
    let createdAt: Date?
}

struct Distraction: Codable, Sendable, Identifiable {
    let id: UUID
    let startTime: String
    let endTime: String
    let title: String
    let summary: String
    let videoSummaryURL: String?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        self.startTime = try container.decode(String.self, forKey: .startTime)
        self.endTime = try container.decode(String.self, forKey: .endTime)
        self.title = try container.decode(String.self, forKey: .title)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.videoSummaryURL = try container.decodeIfPresent(String.self, forKey: .videoSummaryURL)
    }
    
    init(id: UUID = UUID(), startTime: String, endTime: String, title: String, summary: String, videoSummaryURL: String? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
        self.summary = summary
        self.videoSummaryURL = videoSummaryURL
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, title, summary, videoSummaryURL
    }
}

struct TimelineCard: Codable, Sendable, Identifiable {
    var id = UUID()
    let batchId: Int64?
    let startTimestamp: String
    let endTimestamp: String
    let category: String
    let subcategory: String
    let title: String
    let summary: String
    let detailedSummary: String
    let day: String
    let distractions: [Distraction]?
    let videoSummaryURL: String?
    let otherVideoSummaryURLs: [String]?
    let appSites: AppSites?
}

struct LLMCall: Codable, Sendable {
    let timestamp: Date?
    let latency: TimeInterval?
    let input: String?
    let output: String?
}

struct LLMCallDBRecord: Sendable {
    let batchId: Int64?
    let callGroupId: String?
    let attempt: Int
    let provider: String
    let model: String?
    let operation: String
    let status: String
    let latencyMs: Int?
    let httpStatus: Int?
    let requestMethod: String?
    let requestURL: String?
    let requestHeadersJSON: String?
    let requestBody: String?
    let responseHeadersJSON: String?
    let responseBody: String?
    let errorDomain: String?
    let errorCode: Int?
    let errorMessage: String?
}

struct TimelineCardDebugEntry: Sendable {
    let createdAt: Date?
    let batchId: Int64?
    let day: String
    let startTime: String
    let endTime: String
    let category: String
    let subcategory: String?
    let title: String
    let summary: String?
    let detailedSummary: String?
}

struct LLMCallDebugEntry: Sendable {
    let createdAt: Date?
    let batchId: Int64?
    let callGroupId: String?
    let attempt: Int
    let provider: String
    let model: String?
    let operation: String
    let status: String
    let latencyMs: Int?
    let httpStatus: Int?
    let requestMethod: String?
    let requestURL: String?
    let requestBody: String?
    let responseBody: String?
    let errorMessage: String?
}

struct TimelineCardShell: Sendable {
    let startTimestamp: String
    let endTimestamp: String
    let category: String
    let subcategory: String
    let title: String
    let summary: String
    let detailedSummary: String
    let distractions: [Distraction]?
    let appSites: AppSites?
}

struct TimelineMetadata: Codable {
    let distractions: [Distraction]?
    let appSites: AppSites?
}

struct AnalysisBatchDebugEntry: Sendable {
    let id: Int64
    let status: String
    let startTs: Int
    let endTs: Int
    let createdAt: Date?
    let reason: String?
}

struct TimelineCardWithTimestamps {
    let id: Int64
    let startTimestamp: String
    let endTimestamp: String
    let startTs: Int
    let endTs: Int
    let category: String
    let subcategory: String
    let title: String
    let summary: String
    let detailedSummary: String
    let day: String
    let distractions: [Distraction]?
    let videoSummaryURL: String?
}
