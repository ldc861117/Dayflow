//
//  MainViewModelTests.swift
//  DayflowTests
//
//  Tests for MainViewModel analytics and navigation logic
//

import XCTest
@testable import Dayflow

final class MainViewModelTests: XCTestCase {
    var mockAnalytics: MockAnalyticsTracking!
    var mockAppState: AppState!
    var viewModel: MainViewModel!
    
    @MainActor
    override func setUp() {
        super.setUp()
        mockAnalytics = MockAnalyticsTracking()
        mockAppState = AppState.shared
        viewModel = MainViewModel(
            appState: mockAppState,
            analytics: mockAnalytics,
            startObservers: false
        )
    }
    
    override func tearDown() {
        viewModel = nil
        mockAnalytics = nil
        mockAppState = nil
        super.tearDown()
    }
    
    @MainActor
    func testOnAppearTracksScreenView() {
        viewModel.onAppear()
        
        XCTAssertTrue(mockAnalytics.screenCalls.contains { $0.name == "timeline" })
        XCTAssertTrue(mockAnalytics.captureCalls.count > 0)
    }
    
    @MainActor
    func testNavigateNextTracksAnalytics() {
        viewModel.selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: viewModel.selectedDate) ?? viewModel.selectedDate
        mockAnalytics.captureCalls.removeAll()
        viewModel.navigateNext()
        
        XCTAssertTrue(mockAnalytics.captureCalls.contains { $0.name == "date_navigation" })
        if let call = mockAnalytics.captureCalls.first(where: { $0.name == "date_navigation" }) {
            XCTAssertEqual(call.props["method"] as? String, "next")
        }
    }
    
    @MainActor
    func testNavigatePreviousTracksAnalytics() {
        mockAnalytics.captureCalls.removeAll()
        viewModel.navigatePrevious()
        
        XCTAssertTrue(mockAnalytics.captureCalls.contains { $0.name == "date_navigation" })
        if let call = mockAnalytics.captureCalls.first(where: { $0.name == "date_navigation" }) {
            XCTAssertEqual(call.props["method"] as? String, "prev")
        }
    }
    
    @MainActor
    func testActivitySelectionTracksAnalytics() {
        let activity = TimelineActivity(
            batchId: 1,
            startTime: Date(),
            endTime: Date().addingTimeInterval(300),
            title: "Test Activity",
            summary: "Test",
            detailedSummary: "Test",
            category: "Work",
            subcategory: "Development",
            distractions: nil,
            videoSummaryURL: nil,
            screenshot: nil,
            appSites: nil
        )
        
        let viewModelWithObservers = MainViewModel(
            appState: mockAppState,
            analytics: mockAnalytics,
            startObservers: true
        )
        mockAnalytics.captureCalls.removeAll()
        viewModelWithObservers.selectedActivity = activity
        
        XCTAssertTrue(mockAnalytics.captureCalls.contains { $0.name == "activity_card_opened" })
    }
}


@MainActor
final class MockAnalyticsTracking: AnalyticsTracking {
    var captureCalls: [(name: String, props: [String: Any])] = []
    var screenCalls: [(name: String, props: [String: Any])] = []
    var samplingCalls: [(probability: Double, executed: Bool)] = []
    
    func capture(_ name: String, _ props: [String : Any]) {
        captureCalls.append((name, props))
    }
    
    func screen(_ name: String, _ props: [String : Any]) {
        screenCalls.append((name, props))
    }
    
    func withSampling(probability: Double, action: () -> Void) {
        samplingCalls.append((probability, true))
        action()
    }
    
    func secondsBucket(_ seconds: Double) -> String {
        switch seconds {
        case ..<15: return "0-15s"
        case ..<60: return "15-60s"
        case ..<300: return "1-5m"
        case ..<1200: return "5-20m"
        default: return ">20m"
        }
    }
}
