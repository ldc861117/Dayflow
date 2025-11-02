//
//  ActivityDetailPanel.swift
//  Dayflow
//
//  Right panel showing activity details, video, and summary
//

import SwiftUI

struct ActivityDetailPanel: View {
    let activity: TimelineActivity?
    var maxHeight: CGFloat? = nil
    var scrollSummary: Bool = false
    var hasAnyActivities: Bool = true
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var categoryStore: CategoryStore

    @State private var isRetrying = false
    @State private var retryProgress: String = ""
    @State private var retryError: String? = nil

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    var body: some View {
        if let activity = activity {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(activity.title)
                            .font(Font.custom("Nunito", size: 16).weight(.semibold))
                            .foregroundColor(.black)

                        Text("\(timeFormatter.string(from: activity.startTime)) to \(timeFormatter.string(from: activity.endTime))")
                            .font(Font.custom("Nunito", size: 12))
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                    }

                    Spacer()

                    if isFailedCard(activity) {
                        retryButtonInline(for: activity)
                    }
                }

                if isFailedCard(activity), let error = retryError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 12))

                        Text(error)
                            .font(.custom("Nunito", size: 11))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                            .lineLimit(2)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.05))
                    .cornerRadius(6)
                }

                if let videoURL = activity.videoSummaryURL {
                    VideoThumbnailView(
                        videoURL: videoURL,
                        title: activity.title,
                        startTime: activity.startTime,
                        endTime: activity.endTime
                    )
                    .id(videoURL)
                    .frame(height: 200)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 200)
                        .overlay(
                            VStack {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text("No video available")
                                    .font(.caption)
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                        )
                }
                
                Group {
                    if scrollSummary {
                        ScrollView(.vertical, showsIndicators: false) {
                            summaryContent(for: activity)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .id(activity.id)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        summaryContent(for: activity)
                    }
                }
            }
            .padding(16)
            .if(maxHeight != nil) { view in
                view.frame(maxHeight: maxHeight!)
            }
        } else {
            VStack(spacing: 10) {
                Spacer()
                if hasAnyActivities {
                    Text("Select an activity to view details")
                        .font(.custom("Nunito", size: 15))
                        .fontWeight(.regular)
                        .foregroundColor(.gray.opacity(0.5))
                } else {
                    if appState.isRecording {
                        VStack(spacing: 6) {
                            Text("No cards yet")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray.opacity(0.7))
                            Text("Cards are generated about every 15 minutes. If Dayflow is on and no cards show up within 30 minutes, please report a bug.")
                                .font(.custom("Nunito", size: 13))
                                .foregroundColor(.gray.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                    } else {
                        VStack(spacing: 6) {
                            Text("Recording is off")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray.opacity(0.7))
                            Text("Dayflow recording is currently turned off, so cards aren't being produced.")
                                .font(.custom("Nunito", size: 13))
                                .foregroundColor(.gray.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .if(maxHeight != nil) { view in
                view.frame(maxHeight: maxHeight!)
            }
        }
    }

    @ViewBuilder
    private func summaryContent(for activity: TimelineActivity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SUMMARY")
                    .font(Font.custom("Nunito", size: 12).weight(.semibold))
                    .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.55))

                renderMarkdownText(activity.summary)
                    .font(Font.custom("Nunito", size: 12))
                    .foregroundColor(.black)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !activity.detailedSummary.isEmpty && activity.detailedSummary != activity.summary {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DETAILED SUMMARY")
                        .font(Font.custom("Nunito", size: 12).weight(.semibold))
                        .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.55))

                    renderMarkdownText(activity.detailedSummary)
                        .font(Font.custom("Nunito", size: 12))
                        .foregroundColor(.black)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func renderMarkdownText(_ content: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let parsed = try? AttributedString(markdown: content, options: options) {
            return Text(parsed)
        }
        return Text(content)
    }

    private func isFailedCard(_ activity: TimelineActivity) -> Bool {
        return activity.title == "Processing failed"
    }

    @ViewBuilder
    private func retryButtonInline(for activity: TimelineActivity) -> some View {
        if isRetrying {
            HStack(alignment: .center, spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)

                Text("Processing")
                    .font(.custom("Nunito", size: 13))
                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.91, green: 0.85, blue: 0.8))
            .cornerRadius(200)
        } else {
            Button(action: { handleRetry(for: activity) }) {
                HStack(alignment: .center, spacing: 4) {
                    Text("Retry")
                        .font(.custom("Nunito", size: 13).weight(.medium))
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 1, green: 0.54, blue: 0.17))
                .cornerRadius(200)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func handleRetry(for activity: TimelineActivity) {
        guard let batchId = activity.batchId else {
            retryError = "Cannot retry: batch information missing"
            return
        }

        isRetrying = true
        retryProgress = "Preparing to retry..."
        retryError = nil

        AnalysisManager.shared.reprocessSpecificBatches(
            [batchId],
            progressHandler: { progress in
                DispatchQueue.main.async {
                    self.retryProgress = progress
                }
            },
            completion: { result in
                DispatchQueue.main.async {
                    self.isRetrying = false

                    switch result {
                    case .success:
                        self.retryProgress = ""
                        self.retryError = nil

                    case .failure(let error):
                        self.retryProgress = ""
                        self.retryError = "Retry failed: \(error.localizedDescription)"

                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                            self.retryError = nil
                        }
                    }
                }
            }
        )
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
