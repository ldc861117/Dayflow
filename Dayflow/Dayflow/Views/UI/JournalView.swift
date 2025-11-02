//
//  JournalView.swift
//  Dayflow
//
//  Daily journal view that generates narrative summaries from timeline data.
//  Supports local deterministic summaries and optional LLM enhancement.
//
//  Related to: Daily journal feature (GitHub issue reference to be added)
//

import SwiftUI

struct JournalView: View {
    @StateObject private var viewModel = JournalViewModel()
    @State private var showingSavePanel = false
    @State private var showCopiedNotification = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .center) {
                Text("Journal")
                    .font(.custom("InstrumentSerif-Regular", size: 42))
                    .foregroundColor(.black)
                
                Spacer()
                
                // Action buttons
                if viewModel.journalEntry != nil {
                    HStack(spacing: 8) {
                        Button(action: {
                            viewModel.copyToClipboard()
                            showCopiedNotification = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showCopiedNotification = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 12))
                                Text("Copy")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            Task {
                                try? await viewModel.saveAsFile()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 12))
                                Text("Save")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            viewModel.regenerateJournal()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                                .padding(6)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            
            // Content area
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.5))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if viewModel.isLoading {
                            // Loading state
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Generating your journal...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 100)
                        } else if let error = viewModel.errorMessage {
                            // Error state
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 32))
                                    .foregroundColor(.orange)
                                
                                Text("Unable to Generate Journal")
                                    .font(.system(size: 16, weight: .semibold))
                                
                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 400)
                                
                                Button("Try Again") {
                                    viewModel.generateJournal()
                                }
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 100)
                        } else if let entry = viewModel.journalEntry {
                            // Success state - show journal
                            journalContent(entry: entry)
                                .padding(24)
                        } else {
                            // Idle state - show generate button
                            VStack(spacing: 16) {
                                Image(systemName: "book.closed")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                
                                Text("Generate your daily journal")
                                    .font(.system(size: 16, weight: .medium))
                                
                                Text("Create a narrative summary of your day with highlights, focus blocks, and reflections.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 400)
                                
                                Button(action: {
                                    viewModel.generateJournal()
                                }) {
                                    Text("Generate Journal")
                                        .font(.system(size: 14, weight: .medium))
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 100)
                        }
                    }
                }
                
                // Copied notification
                if showCopiedNotification {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Copied to clipboard")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: showCopiedNotification)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            // Track screen view
            Task {
                await AnalyticsService.shared.screen("journal")
            }
        }
    }
    
    @ViewBuilder
    private func journalContent(entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            // Day header
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDayHeader(entry.day))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
                
                Text("Generated \(formatRelativeTime(entry.generatedAt))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            // Overview section
            sectionView(title: "Overview", icon: "chart.bar.fill") {
                Text(entry.overview)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .lineSpacing(4)
            }
            
            // Focus Blocks section
            if !entry.focusBlocks.isEmpty {
                sectionView(title: "Focus Blocks", icon: "target") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(entry.focusBlocks.prefix(5), id: \.title) { block in
                            focusBlockCard(block: block)
                        }
                    }
                }
            }
            
            // Distractions section
            if let distractionSummary = entry.distractionSummary {
                sectionView(title: "Distractions", icon: "bolt.fill") {
                    Text(distractionSummary)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineSpacing(4)
                }
            }
            
            // Reflections section
            if !entry.reflections.isEmpty {
                sectionView(title: "Reflections", icon: "lightbulb.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(entry.reflections, id: \.self) { reflection in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                
                                Text(reflection)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                    .lineSpacing(4)
                            }
                        }
                    }
                }
            }
            
            // Metadata footer
            HStack(spacing: 16) {
                metadataChip(
                    icon: "calendar",
                    text: "\(entry.metadata.totalActivities) activities"
                )
                
                if entry.metadata.totalDistractions > 0 {
                    metadataChip(
                        icon: "bolt",
                        text: "\(entry.metadata.totalDistractions) distractions"
                    )
                }
                
                metadataChip(
                    icon: "cpu",
                    text: entry.metadata.generationMode == "llm" ? "AI Enhanced" : "Local"
                )
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func sectionView<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
            }
            
            content()
        }
    }
    
    @ViewBuilder
    private func focusBlockCard(block: JournalEntry.FocusBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(block.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                
                Spacer()
                
                Text(formatDuration(block.duration))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor)
                    .cornerRadius(4)
            }
            
            Text("\(block.startTime) - \(block.endTime)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Text(block.summary)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineSpacing(3)
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func metadataChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(4)
    }
    
    // MARK: - Helper Methods
    
    private func formatDayHeader(_ day: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = formatter.date(from: day) else {
            return day
        }
        
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
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
}
