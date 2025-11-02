//
//  ScreenRecorder.swift
//  Dayflow
//
//  Refactored to use actor-based ScreenRecorderEngine with extracted helpers.
//

import Foundation
@preconcurrency import ScreenCaptureKit
@preconcurrency import AVFoundation
import Combine
import CoreGraphics
import AppKit
import Sentry

#if DEBUG
@inline(__always) func dbg(_ msg: @autoclosure () -> String) { print("[Recorder] \(msg())") }
#else
@inline(__always) func dbg(_: @autoclosure () -> String) {}
#endif

/// Main coordinator for screen recording, delegating to ScreenRecorderEngine actor
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    
    private let engine: ScreenRecorderEngine
    private let displaySelector: DisplaySelector
    private let tracker: ActiveDisplayTracker
    private let q: DispatchQueue
    private var sub: AnyCancellable?
    private var activeDisplaySub: AnyCancellable?
    private var wantsRecording = false
    
    @MainActor
    init(autoStart: Bool = true, storageManager: StorageManaging = StorageManager.shared) {
        self.q = DispatchQueue(label: "com.dayflow.recorder", qos: .userInitiated)
        self.tracker = ActiveDisplayTracker()
        self.displaySelector = DisplaySelector(tracker: tracker)
        self.engine = ScreenRecorderEngine(
            displaySelector: displaySelector,
            storageManager: storageManager,
            callbackQueue: q
        )
        
        super.init()
        
        // Register self as delegate and output
        Task {
            await engine.setStreamDelegate(self)
            await engine.setStreamOutput(self)
        }
        
        dbg("init – autoStart = \(autoStart)")
        
        wantsRecording = AppState.shared.isRecording
        
        // Observe the app-wide recording flag on the main actor
        sub = AppState.shared.$isRecording
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] rec in
                guard let self = self else { return }
                Task {
                    await self.handleRecordingStateChange(rec)
                }
            }
        
        // Active display tracking
        activeDisplaySub = tracker.$activeDisplayID
            .removeDuplicates()
            .sink { [weak self] newID in
                guard let self = self, let newID = newID else { return }
                Task {
                    await self.engine.handleActiveDisplayChange(newID)
                }
            }
        
        // Honor the current flag once (after subscriptions exist)
        if autoStart, AppState.shared.isRecording {
            Task {
                await self.handleRecordingStateChange(true)
            }
        }
        
        registerForSleepAndLock()
    }
    
    deinit {
        sub?.cancel()
        activeDisplaySub?.cancel()
        dbg("deinit")
    }
    
    private func handleRecordingStateChange(_ rec: Bool) async {
        wantsRecording = rec
        
        // Clear paused state when user disables recording
        if !rec {
            let state = await engine.currentState()
            if state == .paused {
                // Will transition to idle when stopRecording is called
            }
        }
        
        if rec {
            await engine.startRecording(wantsRecording: true)
        } else {
            await engine.stopRecording()
        }
    }
    
    func start() {
        Task {
            await engine.startRecording(wantsRecording: wantsRecording)
        }
    }
    
    func stop() {
        Task {
            await engine.stopRecording()
        }
    }
    
    // MARK: - SCStreamOutput
    
    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard CMSampleBufferDataIsReady(sb) else { return }
        guard isComplete(sb) else { return }
        
        Task {
            await engine.appendFrame(sb)
        }
    }
    
    // MARK: - SCStreamDelegate
    
    func stream(_ s: SCStream, didStopWithError error: Error?) {
        dbg("stream stopped with error: \(String(describing: error))")
        
        Task {
            await engine.handleStreamError(error)
            
            // Check if we should restart based on error type
            let shouldRestart = await shouldRestartAfterError(error)
            
            if shouldRestart {
                let isRecording = await MainActor.run { AppState.shared.isRecording }
                if isRecording {
                    await MainActor.run {
                        AnalyticsService.shared.capture("recording_auto_recovery", ["outcome": "restarted"])
                    }
                    await engine.startRecording(wantsRecording: true)
                }
            } else if isUserInitiatedStop(error) {
                await MainActor.run {
                    AppState.shared.isRecording = false
                }
            } else {
                await MainActor.run {
                    AppState.shared.isRecording = false
                }
            }
        }
    }
    
    private func shouldRestartAfterError(_ error: Error?) async -> Bool {
        guard let nsError = error as NSError? else { return true }
        guard nsError.domain == SCStreamErrorDomain else { return false }
        
        let code = Int(nsError.code)
        switch code {
        case -3807, -3815, -3821:  // noDisplayOrWindow, displayNotReady, stoppedBySystem
            return true
        case -3808, -3817, -3805, -3802:  // userStopped, userDeclined, connectionInvalid, attemptToStop
            return false
        default:
            return false
        }
    }
    
    private func isUserInitiatedStop(_ err: Error?) -> Bool {
        guard let nsError = err as NSError?, nsError.domain == SCStreamErrorDomain else { return false }
        let code = Int(nsError.code)
        
        // User-initiated stop codes
        if code == -3808 || code == -3817 {
            return true
        }
        
        // Check error reason text
        if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
            let userStopIndicators = ["user stopped", "stopped by user", "user cancelled", "stop sharing"]
            let lowercasedReason = reason.lowercased()
            if userStopIndicators.contains(where: { lowercasedReason.contains($0) }) {
                dbg("Detected user stop from error reason: \(reason)")
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Sleep/Lock Notifications
    
    private func registerForSleepAndLock() {
        let nc = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()
        
        // System will sleep
        nc.addObserver(forName: NSWorkspace.willSleepNotification,
                       object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            dbg("willSleep – pausing")
            
            Task {
                await self.handleSleepOrLock(context: "system sleep", reason: "system_sleep")
            }
        }
        
        // System did wake
        nc.addObserver(forName: NSWorkspace.didWakeNotification,
                       object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            dbg("didWake – checking flag")
            
            Task {
                await self.resumeRecordingIfPaused(after: 5, context: "didWake")
            }
        }
        
        // Screen locked
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"),
                        object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            dbg("screen locked – pausing")
            
            Task {
                await self.handleSleepOrLock(context: "screen locked", reason: "lock")
            }
        }
        
        // Screen unlocked
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"),
                        object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            dbg("screen unlocked – checking flag")
            
            Task {
                await self.resumeRecordingIfPaused(after: 0.5, context: "screen unlock")
            }
        }
        
        // Screensaver started
        dnc.addObserver(forName: .init("com.apple.screensaver.didstart"),
                        object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            dbg("screensaver started – pausing")
            
            Task {
                await self.handleSleepOrLock(context: "screensaver started", reason: "screensaver")
            }
        }
        
        // Screensaver stopped
        dnc.addObserver(forName: .init("com.apple.screensaver.didstop"),
                        object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            dbg("screensaver stopped – checking flag")
            
            Task {
                await self.resumeRecordingIfPaused(after: 0.5, context: "screensaver stop")
            }
        }
    }
    
    private func handleSleepOrLock(context: String, reason: String) async {
        let isRecording = await MainActor.run { AppState.shared.isRecording }
        
        if isRecording {
            await engine.pauseRecording(context: context)
        }
        
        await engine.stopRecording()
        
        await MainActor.run {
            AnalyticsService.shared.withSampling(probability: 0.01) {
                AnalyticsService.shared.capture("recording_stopped", ["stop_reason": reason])
            }
        }
    }
    
    private func resumeRecordingIfPaused(after delay: TimeInterval, context: String) async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        let state = await engine.currentState()
        guard state == .paused else { return }
        
        let isRecording = await MainActor.run { AppState.shared.isRecording }
        guard isRecording else {
            dbg("\(context) – skip auto-resume (recording disabled)")
            return
        }
        
        await engine.startRecording(wantsRecording: true)
    }
    
    // MARK: - Frame Validation
    
    private func isComplete(_ sb: CMSampleBuffer) -> Bool {
        guard let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo : Any]],
              let raw = arr.first?[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
