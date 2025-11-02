//
//  JournalViewModel.swift
//  Dayflow
//
//  ViewModel for managing journal generation state and caching.
//

import Foundation
import Combine
import AppKit

@MainActor
class JournalViewModel: ObservableObject {
    enum LoadingState {
        case idle
        case loading
        case success(JournalEntry)
        case error(Error)
    }
    
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var selectedDay: String
    @Published var useLLMEnhancement: Bool
    
    private let composer: JournalComposing
    private let llmAvailable: Bool
    private var cache: [String: JournalEntry] = [:]
    
    init(
        selectedDay: String? = nil,
        composer: JournalComposing = JournalComposer()
    ) {
        self.selectedDay = selectedDay ?? JournalViewModel.defaultDayString()
        self.composer = composer
        self.llmAvailable = Self.hasLLMConfigured()
        self.useLLMEnhancement = llmAvailable
    }
    
    var isLoading: Bool {
        if case .loading = loadingState { return true }
        return false
    }
    
    var journalEntry: JournalEntry? {
        if case .success(let entry) = loadingState {
            return entry
        }
        return nil
    }
    
    var errorMessage: String? {
        if case .error(let error) = loadingState {
            return error.localizedDescription
        }
        return nil
    }
    
    var canUseLLMEnhancement: Bool {
        llmAvailable
    }
    
    func generateJournal(force: Bool = false) {
        if !force && isLoading { return }
        
        let day = selectedDay
        
        if !force, let cached = cache[day] {
            loadingState = .success(cached)
            return
        }
        
        loadingState = .loading
        
        let composer = self.composer
        let shouldUseLLM = useLLMEnhancement && llmAvailable
        
        Task(priority: .userInitiated) {
            do {
                let entry = try await composer.generateJournal(forDay: day, useLLM: shouldUseLLM)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.cache[day] = entry
                    if self.selectedDay == day {
                        self.loadingState = .success(entry)
                    }
                }
                
                AnalyticsService.shared.capture("journal_generated", [
                    "day": day,
                    "generation_mode": entry.metadata.generationMode,
                    "total_activities": entry.metadata.totalActivities,
                    "total_distractions": entry.metadata.totalDistractions,
                    "focus_blocks_count": entry.focusBlocks.count
                ])
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.selectedDay == day {
                        self.loadingState = .error(error)
                    }
                }
                
                AnalyticsService.shared.capture("journal_generation_failed", [
                    "day": day,
                    "error": error.localizedDescription
                ])
            }
        }
    }
    
    func regenerateJournal() {
        let day = selectedDay
        cache.removeValue(forKey: day)
        generateJournal(force: true)
        AnalyticsService.shared.capture("journal_regenerated", [
            "day": day,
            "llm_enabled": useLLMEnhancement && llmAvailable
        ])
    }
    
    func exportedMarkdown() -> String {
        guard let entry = journalEntry else { return "" }
        return formatAsMarkdown(entry)
    }
    
    func copyToClipboard() {
        let markdown = exportedMarkdown()
        guard markdown.isEmpty == false else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        
        AnalyticsService.shared.capture("journal_copied", [
            "day": selectedDay,
            "format": "markdown"
        ])
    }
    
    func saveAsFile() async throws {
        guard let entry = journalEntry else { return }
        
        let markdown = formatAsMarkdown(entry)
        let fileName = "Dayflow-Journal-\(selectedDay).md"
        
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.nameFieldStringValue = fileName
        savePanel.level = .modalPanel
        savePanel.message = "Save journal entry as Markdown"
        
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            let response = await savePanel.beginSheetModal(for: window)
            if response == .OK, let url = savePanel.url {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                AnalyticsService.shared.capture("journal_saved", [
                    "day": selectedDay,
                    "format": "markdown"
                ])
            }
        } else {
            let response = savePanel.runModal()
            if response == .OK, let url = savePanel.url {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                AnalyticsService.shared.capture("journal_saved", [
                    "day": selectedDay,
                    "format": "markdown"
                ])
            }
        }
    }
    
    func clearCache() {
        cache.removeAll()
    }
    
    // MARK: - Helpers
    
    private static func defaultDayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    private static func hasLLMConfigured() -> Bool {
        guard let savedData = UserDefaults.standard.data(forKey: "llmProviderType"),
              let providerType = try? JSONDecoder().decode(LLMProviderType.self, from: savedData) else {
            return false
        }
        
        switch providerType {
        case .geminiDirect:
            return KeychainManager.shared.retrieve(for: "gemini")?.isEmpty == false
        case .dayflowBackend:
            return KeychainManager.shared.retrieve(for: "dayflow")?.isEmpty == false
        case .ollamaLocal:
            return true
        case .chatGPTClaude:
            return false
        }
    }
    
    private func formatAsMarkdown(_ entry: JournalEntry) -> String {
        var markdown = "# Daily Journal - \(entry.day)\n\n"
        
        markdown += "## Overview\n\n"
        markdown += "\(entry.overview)\n\n"
        
        if !entry.focusBlocks.isEmpty {
            markdown += "## Focus Blocks\n\n"
            for block in entry.focusBlocks {
                markdown += "### \(block.title)\n"
                markdown += "**Time:** \(block.startTime) - \(block.endTime) (\(formatDuration(block.duration)))\n\n"
                markdown += "\(block.summary)\n\n"
            }
        }
        
        if let distractionSummary = entry.distractionSummary {
            markdown += "## Distractions\n\n"
            markdown += "\(distractionSummary)\n\n"
        }
        
        if !entry.reflections.isEmpty {
            markdown += "## Reflections\n\n"
            for reflection in entry.reflections {
                markdown += "- \(reflection)\n"
            }
            markdown += "\n"
        }
        
        markdown += "---\n\n"
        markdown += "*Generated on \(formatDate(entry.generatedAt)) using \(entry.metadata.generationMode) mode*"
        if let provider = entry.metadata.llmProvider {
            markdown += "\n*LLM Provider: \(provider)*"
        }
        markdown += "\n"
        
        return markdown
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
