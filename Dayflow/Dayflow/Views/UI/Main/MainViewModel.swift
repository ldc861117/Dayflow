//
//  MainViewModel.swift
//  Dayflow
//
//  View model for main timeline view, handling navigation, analytics, and inactivity reset
//

import SwiftUI
import Combine
import Sentry

protocol AnalyticsTracking {
    func capture(_ name: String, _ props: [String: Any])
    func screen(_ name: String, _ props: [String: Any])
    func withSampling(probability: Double, action: () -> Void)
    func secondsBucket(_ seconds: Double) -> String
}

extension AnalyticsService: AnalyticsTracking {}

@MainActor
final class MainViewModel: ObservableObject {
    // MARK: - Published State
    @Published var selectedIcon: SidebarIcon = .timeline
    @Published var selectedDate: Date
    @Published var showDatePicker = false
    @Published var selectedActivity: TimelineActivity? = nil
    @Published var scrollToNowTick: Int = 0
    @Published var hasAnyActivities: Bool = true
    @Published var showCategoryEditor = false
    
    // Animation states
    @Published var logoScale: CGFloat = 0.8
    @Published var logoOpacity: Double = 0
    @Published var timelineOffset: CGFloat = -20
    @Published var timelineOpacity: Double = 0
    @Published var sidebarOffset: CGFloat = -30
    @Published var sidebarOpacity: Double = 0
    @Published var contentOpacity: Double = 0
    
    // MARK: - Private State
    private var didInitialScroll = false
    private var previousDate: Date
    private var lastDateNavMethod: String? = nil
    private var dayChangeTimer: Timer? = nil
    private var lastObservedCivilDay: String
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Dependencies
    private let appState: AppState
    private let inactivityMonitor: InactivityMonitor
    private let analytics: AnalyticsTracking
    private let shouldSetupObservers: Bool
    
    // MARK: - Initialization
    init(appState: AppState, inactivityMonitor: InactivityMonitor = .shared, analytics: AnalyticsTracking = AnalyticsService.shared, startObservers: Bool = true) {
        let initialDate = timelineDisplayDate(from: Date())
        self.selectedDate = initialDate
        self.previousDate = initialDate
        self.appState = appState
        self.inactivityMonitor = inactivityMonitor
        self.analytics = analytics
        self.shouldSetupObservers = startObservers
        
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        self.lastObservedCivilDay = fmt.string(from: Date())
        
        if startObservers {
            setupObservers()
        }
    }
    
    // MARK: - Public Methods
    
    func onAppear() {
        trackScreenView()
        startEntranceAnimations()
        
        if !didInitialScroll {
            performInitialScrollIfNeeded()
        }
        
        startDayChangeTimer()
    }
    
    func onDisappear() {
        stopDayChangeTimer()
    }
    
    func navigateToDate(_ date: Date, method: String) {
        previousDate = selectedDate
        setSelectedDate(date)
        lastDateNavMethod = method
        
        trackDateNavigation(from: previousDate, to: date, method: method)
    }
    
    func navigatePrevious() {
        let from = selectedDate
        let to = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        navigateToDate(to, method: "prev")
    }
    
    func navigateNext() {
        guard canNavigateForward(from: selectedDate) else { return }
        let from = selectedDate
        let to = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        navigateToDate(to, method: "next")
    }
    
    func openDatePicker() {
        showDatePicker = true
        lastDateNavMethod = "picker"
    }
    
    func canNavigateForward() -> Bool {
        canNavigateForward(from: selectedDate)
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Watch for inactivity reset
        inactivityMonitor.$pendingReset
            .sink { [weak self] fired in
                guard let self = self else { return }
                if fired && self.selectedIcon != .settings {
                    self.performIdleResetAndScroll()
                    self.inactivityMonitor.markHandledIfPending()
                }
            }
            .store(in: &cancellables)
        
        // Watch for tab changes
        $selectedIcon
            .removeDuplicates()
            .sink { [weak self] newIcon in
                guard let self = self else { return }
                self.handleTabChange(newIcon)
            }
            .store(in: &cancellables)
        
        // Watch for date changes
        $selectedDate
            .removeDuplicates { Calendar.current.isDate($0, inSameDayAs: $1) }
            .sink { [weak self] newDate in
                guard let self = self else { return }
                // If changed via picker, emit navigation now
                if let method = self.lastDateNavMethod, method == "picker" {
                    self.trackDateNavigation(from: self.previousDate, to: newDate, method: method)
                }
                self.previousDate = newDate
                
                self.analytics.withSampling(probability: 0.01) {
                    self.analytics.capture("timeline_viewed", ["date_bucket": dayString(newDate)])
                }
            }
            .store(in: &cancellables)
        
        // Watch for activity selection
        $selectedActivity
            .compactMap { $0 }
            .removeDuplicates { $0.id == $1.id }
            .sink { [weak self] activity in
                guard let self = self else { return }
                let dur = activity.endTime.timeIntervalSince(activity.startTime)
                self.analytics.capture("activity_card_opened", [
                    "activity_type": activity.category,
                    "duration_bucket": self.analytics.secondsBucket(dur),
                    "has_video": activity.videoSummaryURL != nil
                ])
            }
            .store(in: &cancellables)
    }
    
    private func trackScreenView() {
        analytics.screen("timeline", [:])
        analytics.withSampling(probability: 0.01) {
            self.analytics.capture("timeline_viewed", ["date_bucket": dayString(self.selectedDate)])
        }
    }
    
    private func handleTabChange(_ newIcon: SidebarIcon) {
        let tabName: String
        switch newIcon {
        case .timeline: tabName = "timeline"
        case .dashboard: tabName = "dashboard"
        case .journal: tabName = "journal"
        case .bug: tabName = "bug_report"
        case .settings: tabName = "settings"
        }
        
        // Add Sentry context for app state tracking
        SentryHelper.configureScope { scope in
            scope.setContext(value: [
                "active_view": tabName,
                "selected_date": dayString(self.selectedDate),
                "is_recording": self.appState.isRecording
            ], key: "app_state")
        }
        
        // Add breadcrumb for view navigation
        let navBreadcrumb = Breadcrumb(level: .info, category: "navigation")
        navBreadcrumb.message = "Navigated to \(tabName)"
        navBreadcrumb.data = ["view": tabName]
        SentryHelper.addBreadcrumb(navBreadcrumb)
        
        analytics.capture("tab_selected", ["tab": tabName])
        analytics.screen(tabName, [:])
        
        if newIcon == .timeline {
            analytics.withSampling(probability: 0.01) {
                self.analytics.capture("timeline_viewed", ["date_bucket": dayString(self.selectedDate)])
            }
        }
        
        // Handle pending reset when returning from settings
        if newIcon != .settings && inactivityMonitor.pendingReset {
            performIdleResetAndScroll()
            inactivityMonitor.markHandledIfPending()
        }
    }
    
    private func trackDateNavigation(from: Date, to: Date, method: String) {
        analytics.capture("date_navigation", [
            "method": method,
            "from_day": dayString(from),
            "to_day": dayString(to)
        ])
    }
    
    private func startEntranceAnimations() {
        // Logo appears first with scale and fade
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0)) {
            logoScale = 1.0
            logoOpacity = 1
        }
        
        // Timeline text slides in from left
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0).delay(0.1)) {
            timelineOffset = 0
            timelineOpacity = 1
        }
        
        // Sidebar slides up
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0).delay(0.15)) {
            sidebarOffset = 0
            sidebarOpacity = 1
        }
        
        // Main content fades in last
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0).delay(0.2)) {
            contentOpacity = 1
        }
    }
    
    private func startDayChangeTimer() {
        stopDayChangeTimer()
        dayChangeTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.handleMinuteTickForDayChange()
        }
    }
    
    private func stopDayChangeTimer() {
        dayChangeTimer?.invalidate()
        dayChangeTimer = nil
    }
    
    private func handleMinuteTickForDayChange() {
        // Detect civil day rollover regardless of what day user is viewing
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let currentCivilDay = fmt.string(from: Date())
        if currentCivilDay != lastObservedCivilDay {
            lastObservedCivilDay = currentCivilDay
            
            // Jump to current civil day and re-scroll near now
            setSelectedDate(timelineDisplayDate(from: Date()))
            selectedActivity = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.scrollToNowTick &+= 1
                }
            }
        }
    }
    
    private func performIdleResetAndScroll() {
        // Switch to today
        setSelectedDate(timelineDisplayDate(from: Date()))
        // Clear selection
        selectedActivity = nil
        // Nudge timeline to scroll to now after it reloads
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            #if DEBUG
            print("[MainViewModel] performIdleResetAndScroll -> nudging scrollToNowTick")
            #endif
            withAnimation(.easeInOut(duration: 0.35)) {
                self.scrollToNowTick &+= 1
            }
        }
    }
    
    private func performInitialScrollIfNeeded() {
        // Check all conditions for initial scroll
        guard selectedIcon != .settings,
              !showDatePicker,
              timelineIsToday(selectedDate) else {
            return
        }
        
        // Mark that we've attempted initial scroll
        didInitialScroll = true
        
        // Wait for layout to settle after animations complete
        #if DEBUG
        print("[MainViewModel] performInitialScrollIfNeeded scheduled with 1.5s delay")
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            #if DEBUG
            print("[MainViewModel] performInitialScrollIfNeeded firing -> nudging scrollToNowTick")
            #endif
            withAnimation(.easeInOut(duration: 0.35)) {
                self.scrollToNowTick &+= 1
            }
        }
    }
    
    private func setSelectedDate(_ date: Date) {
        selectedDate = normalizedTimelineDate(date)
    }
}
