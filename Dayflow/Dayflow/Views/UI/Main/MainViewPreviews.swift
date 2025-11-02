//
//  MainViewPreviews.swift
//  Dayflow
//
//  Preview providers for Main view subcomponents
//

import SwiftUI

#if DEBUG
@available(macOS 13.0, *)
struct TimelineHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        let appState = AppState.shared
        let viewModel = MainViewModel(appState: appState, startObservers: false)
        
        TimelineHeaderView(viewModel: viewModel, appState: appState)
            .frame(width: 800, height: 80)
            .padding()
            .background(Color(hex: "FFF8F1"))
    }
}

@available(macOS 13.0, *)
struct TimelineSidebarView_Previews: PreviewProvider {
    static var previews: some View {
        let appState = AppState.shared
        let viewModel = MainViewModel(appState: appState, startObservers: false)
        
        TimelineSidebarView(viewModel: viewModel)
            .frame(width: 100, height: 600)
            .background(Color(hex: "FFF8F1"))
    }
}

@available(macOS 13.0, *)
struct ActivityDetailPanel_Previews: PreviewProvider {
    static var previews: some View {
        let appState = AppState.shared
        let categoryStore = CategoryStore()
        
        let mockActivity = TimelineActivity(
            batchId: 1,
            startTime: Date().addingTimeInterval(-3600),
            endTime: Date(),
            title: "Working on project",
            summary: "Focused work session on the main project. Made good progress on the timeline feature.",
            detailedSummary: "Worked on implementing the timeline view with proper scrolling and activity selection. Added support for time-based layouts and improved the overall user experience.",
            category: "Work",
            subcategory: "Development",
            distractions: nil,
            videoSummaryURL: nil,
            screenshot: nil,
            appSites: nil
        )
        
        ActivityDetailPanel(
            activity: mockActivity,
            maxHeight: 600,
            scrollSummary: true,
            hasAnyActivities: true
        )
        .frame(width: 300, height: 600)
        .environmentObject(appState)
        .environmentObject(categoryStore)
    }
}
#endif
