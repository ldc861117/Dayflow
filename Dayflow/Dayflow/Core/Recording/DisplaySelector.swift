//
//  DisplaySelector.swift
//  Dayflow
//
//  Handles selecting the appropriate display for screen capture.
//

import Foundation
import ScreenCaptureKit
import CoreGraphics

protocol DisplaySelecting: Sendable {
    func selectDisplay() async throws -> SCDisplay
    func requestDisplay(id: CGDirectDisplayID?)
}

enum DisplaySelectorError: Error {
    case noDisplay
    case displayUnavailable
}

actor DisplaySelector: DisplaySelecting {
    private var requestedDisplayID: CGDirectDisplayID?
    private var currentDisplayID: CGDirectDisplayID?
    private let tracker: ActiveDisplayTracker
    
    init(tracker: ActiveDisplayTracker) {
        self.tracker = tracker
    }
    
    func selectDisplay() async throws -> SCDisplay {
        let content = try await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard !content.displays.isEmpty else {
            throw DisplaySelectorError.noDisplay
        }
        
        let displaysByID: [CGDirectDisplayID: SCDisplay] = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) })
        
        // Read tracker's active display on the main actor to respect isolation
        let trackerID: CGDirectDisplayID? = await MainActor.run { [weak tracker] in tracker?.activeDisplayID }
        let preferredID = requestedDisplayID ?? trackerID
        
        let display: SCDisplay
        if let pid = preferredID, let scd = displaysByID[pid] {
            display = scd
        } else if let first = content.displays.first {
            display = first
        } else {
            throw DisplaySelectorError.noDisplay
        }
        
        currentDisplayID = display.displayID
        requestedDisplayID = nil
        
        return display
    }
    
    func requestDisplay(id: CGDirectDisplayID?) {
        requestedDisplayID = id
    }
    
    func currentDisplay() -> CGDirectDisplayID? {
        currentDisplayID
    }
}
