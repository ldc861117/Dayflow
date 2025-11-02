//
//  JournalComposer.swift
//  Dayflow
//
//  Service to generate daily journal entries from timeline cards and observations.
//  Supports both LLM-enhanced and local deterministic summaries.
//
//  Related to: Daily journal feature (issue reference to be added when identified)
//

import Foundation

/// Result of journal generation
struct JournalEntry: Codable, Sendable {
    let day: String
    let overview: String
    let focusBlocks: [FocusBlock]
    let distractionSummary: String?
    let reflections: [String]
    let metadata: JournalMetadata
    let generatedAt: Date
    
    struct FocusBlock: Codable, Sendable {
        let title: String
        let duration: TimeInterval
        let startTime: String
        let endTime: String
        let summary: String
    }
    
    struct JournalMetadata: Codable, Sendable {
        let totalActivities: Int
        let totalDistractions: Int
        let generationMode: String // "llm" or "local"
        let llmProvider: String?
    }
}

/// Protocol for journal composition
protocol JournalComposing: Sendable {
    func generateJournal(forDay day: String, useLLM: Bool) async throws -> JournalEntry
}

/// Service responsible for composing daily journal entries
final class JournalComposer: JournalComposing {
    private let storage: StorageManaging
    
    init(storage: StorageManaging = StorageManager.shared) {
        self.storage = storage
    }
    
    func generateJournal(forDay day: String, useLLM: Bool) async throws -> JournalEntry {
        // Fetch timeline cards for the day
        let cards = storage.fetchTimelineCards(forDay: day)
        
        guard !cards.isEmpty else {
            throw JournalError.noData("No activities found for \(day)")
        }
        
        // Generate journal sections
        let overview = generateOverview(from: cards)
        let focusBlocks = extractFocusBlocks(from: cards)
        let distractionSummary = generateDistractionSummary(from: cards)
        let reflections = generateReflections(from: cards, useLLM: useLLM)
        
        let metadata = JournalEntry.JournalMetadata(
            totalActivities: cards.count,
            totalDistractions: cards.flatMap { $0.distractions ?? [] }.count,
            generationMode: useLLM ? "llm" : "local",
            llmProvider: useLLM ? getCurrentProviderName() : nil
        )
        
        return JournalEntry(
            day: day,
            overview: overview,
            focusBlocks: focusBlocks,
            distractionSummary: distractionSummary,
            reflections: reflections,
            metadata: metadata,
            generatedAt: Date()
        )
    }
    
    // MARK: - Private Methods
    
    private func generateOverview(from cards: [TimelineCard]) -> String {
        let totalDuration = calculateTotalDuration(from: cards)
        let categories = Dictionary(grouping: cards, by: { $0.category })
        
        var overview = "Your day spanned \(formatDuration(totalDuration)) across \(cards.count) activities. "
        
        // Summarize by category
        let sortedCategories = categories.sorted { $0.value.count > $1.value.count }
        if !sortedCategories.isEmpty {
            let topCategories = sortedCategories.prefix(3).map { category, activities in
                let duration = calculateTotalDuration(from: activities)
                return "\(category) (\(formatDuration(duration)))"
            }
            overview += "You spent most of your time on: \(topCategories.joined(separator: ", ")). "
        }
        
        return overview
    }
    
    private func extractFocusBlocks(from cards: [TimelineCard]) -> [JournalEntry.FocusBlock] {
        // Filter out idle and short activities
        let significantCards = cards.filter { card in
            guard !card.category.lowercased().contains("idle") else { return false }
            let duration = parseDuration(start: card.startTimestamp, end: card.endTimestamp)
            return duration >= 300 // At least 5 minutes
        }
        
        // Group similar activities together
        var blocks: [JournalEntry.FocusBlock] = []
        
        for card in significantCards {
            let duration = parseDuration(start: card.startTimestamp, end: card.endTimestamp)
            
            let block = JournalEntry.FocusBlock(
                title: card.title,
                duration: duration,
                startTime: card.startTimestamp,
                endTime: card.endTimestamp,
                summary: card.summary
            )
            blocks.append(block)
        }
        
        // Sort by duration (longest first)
        return blocks.sorted { $0.duration > $1.duration }.prefix(10).map { $0 }
    }
    
    private func generateDistractionSummary(from cards: [TimelineCard]) -> String? {
        let allDistractions = cards.flatMap { $0.distractions ?? [] }
        
        guard !allDistractions.isEmpty else {
            return nil
        }
        
        let totalDistractionTime = allDistractions.reduce(0.0) { sum, distraction in
            sum + parseDuration(start: distraction.startTime, end: distraction.endTime)
        }
        
        if allDistractions.count == 1 {
            return "You had 1 distraction lasting \(formatDuration(totalDistractionTime)): \(allDistractions[0].title)."
        } else {
            let topDistraction = allDistractions.max(by: { d1, d2 in
                parseDuration(start: d1.startTime, end: d1.endTime) < parseDuration(start: d2.startTime, end: d2.endTime)
            })
            
            return "You had \(allDistractions.count) distractions totaling \(formatDuration(totalDistractionTime)). The longest was \(topDistraction?.title ?? "unknown")."
        }
    }
    
    private func generateReflections(from cards: [TimelineCard], useLLM: Bool) -> [String] {
        if useLLM {
            // For future LLM enhancement - for now return deterministic reflections
            return generateLocalReflections(from: cards)
        } else {
            return generateLocalReflections(from: cards)
        }
    }
    
    private func generateLocalReflections(from cards: [TimelineCard]) -> [String] {
        var reflections: [String] = []
        
        // Analyze work-life balance
        let categories = Dictionary(grouping: cards, by: { $0.category })
        let workCards = categories["Work"] ?? []
        let personalCards = categories["Personal"] ?? []
        
        if !workCards.isEmpty && !personalCards.isEmpty {
            let workTime = calculateTotalDuration(from: workCards)
            let personalTime = calculateTotalDuration(from: personalCards)
            let ratio = workTime / max(personalTime, 1)
            
            if ratio > 3 {
                reflections.append("You spent significantly more time on work than personal activities. Consider allocating time for personal activities tomorrow.")
            } else if ratio < 0.5 {
                reflections.append("You had a personal-focused day with minimal work time.")
            }
        }
        
        // Check for long focus sessions
        let longSessions = cards.filter { card in
            let duration = parseDuration(start: card.startTimestamp, end: card.endTimestamp)
            return duration >= 3600 // 1 hour or more
        }
        
        if !longSessions.isEmpty {
            reflections.append("You had \(longSessions.count) focused session(s) lasting over an hour. Great for deep work!")
        }
        
        // Check distraction patterns
        let totalDistractions = cards.flatMap { $0.distractions ?? [] }.count
        if totalDistractions > 10 {
            reflections.append("You had \(totalDistractions) distractions today. Consider time-blocking or notification management strategies.")
        } else if totalDistractions == 0 {
            reflections.append("You had zero distractions today. Excellent focus!")
        }
        
        return reflections
    }
    
    // MARK: - Helper Methods
    
    private func calculateTotalDuration(from cards: [TimelineCard]) -> TimeInterval {
        cards.reduce(0) { sum, card in
            sum + parseDuration(start: card.startTimestamp, end: card.endTimestamp)
        }
    }
    
    private func parseDuration(start: String, end: String) -> TimeInterval {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let startDate = formatter.date(from: start),
              let endDate = formatter.date(from: end) else {
            return 0
        }
        
        var duration = endDate.timeIntervalSince(startDate)
        
        // Handle midnight crossing (e.g., 11:00 PM to 1:00 AM)
        if duration < 0 {
            duration += 24 * 3600
        }
        
        return duration
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }
    
    private func getCurrentProviderName() -> String {
        guard let savedData = UserDefaults.standard.data(forKey: "llmProviderType"),
              let decoded = try? JSONDecoder().decode(LLMProviderType.self, from: savedData) else {
            return "unknown"
        }
        
        switch decoded {
        case .geminiDirect:
            return "Gemini"
        case .dayflowBackend:
            return "Dayflow Backend"
        case .ollamaLocal:
            return "Ollama"
        case .chatGPTClaude:
            return "ChatGPT/Claude"
        }
    }
}

// MARK: - Error Types

enum JournalError: LocalizedError {
    case noData(String)
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noData(let message):
            return message
        case .generationFailed(let message):
            return "Failed to generate journal: \(message)"
        }
    }
}
