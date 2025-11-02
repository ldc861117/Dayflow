//
//  ScreenRecorderEngine.swift
//  Dayflow
//
//  Core actor managing screen recording state, lifecycle, and segment operations.
//

import Foundation
@preconcurrency import ScreenCaptureKit
@preconcurrency import AVFoundation
import CoreMedia
import Sentry

#if DEBUG
@inline(__always) func dbgEngine(_ msg: @autoclosure () -> String) { print("[RecorderEngine] \(msg())") }
#else
@inline(__always) func dbgEngine(_: @autoclosure () -> String) {}
#endif

private enum C {
    static let targetHeight = 1080               // Target ~1080p resolution
    static let chunkSeconds: TimeInterval = 15   // seconds per file
    static let fps: Int32 = 1                    // keep @ 1 fps
}

/// Explicit state machine for the recorder lifecycle
enum RecorderState: Equatable, Sendable {
    case idle           // Not recording, no active resources
    case starting       // Initiating stream creation (async operation in progress)
    case recording      // Active stream + writer
    case finishing      // Cleaning up current segment
    case paused         // System event pause (sleep/lock), will auto-resume

    var description: String {
        switch self {
        case .idle: return "idle"
        case .starting: return "starting"
        case .recording: return "recording"
        case .finishing: return "finishing"
        case .paused: return "paused"
        }
    }

    var canStart: Bool {
        switch self {
        case .idle, .paused: return true
        case .starting, .recording, .finishing: return false
        }
    }

    var canStop: Bool {
        switch self {
        case .starting, .recording, .finishing: return true
        case .idle, .paused: return false
        }
    }
}

private enum SCStreamErrorCode: Int {
    case noDisplayOrWindow = -3807          // Transient error, display disconnected
    case userStoppedViaSystemUI = -3808     // User clicked "Stop Sharing" in system UI
    case displayNotReady = -3815            // Failed to find displays/windows after wake/unlock
    case userDeclined = -3817               // Alternative code for user stop
    case connectionInvalid = -3805          // Stream connection became invalid
    case attemptToStopStreamState = -3802   // Stream already stopping
    case stoppedBySystem = -3821            // System stopped stream (usually disk space)
    
    var isUserInitiated: Bool {
        switch self {
        case .userStoppedViaSystemUI, .userDeclined:
            return true
        default:
            return false
        }
    }
    
    var shouldAutoRestart: Bool {
        switch self {
        case .noDisplayOrWindow, .displayNotReady, .stoppedBySystem:
            return true  // Transient errors, should retry
        case .userStoppedViaSystemUI, .userDeclined, .connectionInvalid, .attemptToStopStreamState:
            return false // User action or unrecoverable error
        }
    }
}

enum RecorderEngineError: Error {
    case noDisplay
}

/// Actor managing the core recording state machine and SCStream lifecycle
actor ScreenRecorderEngine {
    
    private var state: RecorderState = .idle
    private var stream: SCStream?
    private var segmentWriter: SegmentWriter?
    private var segmentTimer: Task<Void, Never>?
    private var currentWidth: Int = 1280
    private var currentHeight: Int = 800
    private let displaySelector: DisplaySelector
    private let storageManager: StorageManaging
    private let callbackQueue: DispatchQueue
    private weak var streamDelegate: SCStreamDelegate?
    private weak var streamOutput: SCStreamOutput?
    internal var testingBypassStreamStart = false
    
    init(displaySelector: DisplaySelector, storageManager: StorageManaging, callbackQueue: DispatchQueue) {
        self.displaySelector = displaySelector
        self.storageManager = storageManager
        self.callbackQueue = callbackQueue
    }
    
    func setStreamDelegate(_ delegate: SCStreamDelegate?) {
        self.streamDelegate = delegate
    }
    
    func setStreamOutput(_ output: SCStreamOutput?) {
        self.streamOutput = output
    }
    
    func setTestingBypassStreamStart(_ enabled: Bool) {
        testingBypassStreamStart = enabled
    }
    
    // MARK: - State Management
    
    func currentState() -> RecorderState {
        state
    }
    
    private func transition(to newState: RecorderState, context: String? = nil) {
        let oldState = state
        state = newState
        
        let message = context.map { "\(oldState.description) → \(newState.description) (\($0))" }
                      ?? "\(oldState.description) → \(newState.description)"
        dbgEngine("State: \(message)")
        
        let breadcrumb = Breadcrumb(level: .info, category: "recorder_state")
        breadcrumb.message = message
        breadcrumb.data = [
            "old_state": oldState.description,
            "new_state": newState.description
        ]
        if let ctx = context {
            breadcrumb.data?["context"] = ctx
        }
        SentryHelper.addBreadcrumb(breadcrumb)
    }
    
    // MARK: - Recording Control
    
    func startRecording(wantsRecording: Bool) async {
        guard wantsRecording else {
            dbgEngine("startRecording – suppressed (recording disabled)")
            return
        }
        
        guard state.canStart else {
            dbgEngine("startRecording – invalid state: \(state.description)")
            return
        }
        
        transition(to: .starting, context: "user/system start")
        
        if testingBypassStreamStart {
            currentWidth = 1920
            currentHeight = 1080
            transition(to: .recording, context: "test bypass stream start")
            return
        }
        
        await makeStream()
    }
    
    func stopRecording() async {
        await finishCurrentSegment(restart: false)
        await stopStream()
    }
    
    func pauseRecording(context: String) async {
        guard state == .recording || state == .starting else {
            dbgEngine("pauseRecording – invalid state: \(state.description)")
            return
        }
        
        transition(to: .paused, context: context)
        await finishCurrentSegment(restart: false)
        await stopStream()
    }
    
    // MARK: - Display Management
    
    func handleActiveDisplayChange(_ newID: CGDirectDisplayID) async {
        await displaySelector.requestDisplay(id: newID)
        
        // Only flip streams when one is currently running and we're in recording state
        guard let currentID = await displaySelector.currentDisplay(), state == .recording else {
            dbgEngine("Active display changed while not recording – will switch on next start")
            return
        }
        
        guard newID != currentID else { return }
        
        dbgEngine("Active display changed → switching stream: \(String(describing: currentID)) → \(newID)")
        
        // Finish the current segment and restart on the new display
        await finishCurrentSegment(restart: false)
        await stopStream()
    }
    
    // MARK: - Stream Management
    
    private func makeStream(attempt: Int = 1, maxAttempts: Int = 4) async {
        do {
            let display = try await displaySelector.selectDisplay()
            
            // Calculate dimensions to maintain aspect ratio at ~1080p
            let displayWidth = display.width
            let displayHeight = display.height
            let aspectRatio = Double(displayWidth) / Double(displayHeight)
            
            // Scale to target height while maintaining aspect ratio
            let targetHeight = C.targetHeight
            var targetWidth = Int(Double(targetHeight) * aspectRatio)
            // Ensure even dimensions for encoder safety
            if targetWidth % 2 != 0 { targetWidth += 1 }
            var evenTargetHeight = targetHeight
            if evenTargetHeight % 2 != 0 { evenTargetHeight += 1 }
            
            dbgEngine("Recording at \(targetWidth)×\(targetHeight) (display: \(displayWidth)×\(displayHeight), ratio: \(String(format: "%.2f", aspectRatio)):1)")
            
            // Create filter and configuration
            let filter = SCContentFilter(display: display,
                                         excludingApplications: [],
                                         exceptingWindows: [])
            
            let cfg = SCStreamConfiguration()
            cfg.width = targetWidth
            cfg.height = evenTargetHeight
            cfg.capturesAudio = false
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: C.fps)
            
            // Start the stream
            try await startStream(filter: filter, config: cfg, width: targetWidth, height: evenTargetHeight)
            
            // Successfully started - transition to recording
            guard state == .starting else {
                dbgEngine("makeStream completed but state changed to \(state.description), ignoring")
                return
            }
            
            transition(to: .recording, context: "stream started")
            
        } catch {
            dbgEngine("makeStream failed [attempt \(attempt)] – \(error.localizedDescription)")
            
            transition(to: .idle, context: "makeStream failed")
            
            // Extract error details for analytics
            let nsError = error as NSError
            let errorDomain = nsError.domain
            let errorCode = nsError.code
            let isNoDisplay = (error as? RecorderEngineError) == .noDisplay || (error as? DisplaySelectorError) == .noDisplay
            
            // Check if this is a user-initiated stop
            if isUserInitiatedStop(error) {
                dbgEngine("User stopped recording during startup - updating app state")
                
                await MainActor.run {
                    AnalyticsService.shared.capture("recording_startup_failed", [
                        "attempt": attempt,
                        "max_attempts": maxAttempts,
                        "error_domain": errorDomain,
                        "error_code": errorCode,
                        "error_type": "user_initiated",
                        "outcome": "user_cancelled"
                    ])
                }
                return
            }
            
            // Treat `noDisplay` like other transient issues
            let retryable = shouldRetry(error) || isNoDisplay
            
            if retryable, attempt < maxAttempts {
                let delay = Double(attempt)
                dbgEngine("retrying in \(delay)s")
                
                await MainActor.run {
                    AnalyticsService.shared.capture("recording_startup_failed", [
                        "attempt": attempt,
                        "max_attempts": maxAttempts,
                        "error_domain": errorDomain,
                        "error_code": errorCode,
                        "error_type": isNoDisplay ? "no_display" : "retryable",
                        "outcome": "will_retry",
                        "retry_delay_seconds": delay
                    ])
                }
                
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await makeStream(attempt: attempt + 1, maxAttempts: maxAttempts)
            } else {
                // Final failure
                let failureReason = !retryable ? "non_retryable" : "max_attempts_exceeded"
                
                await MainActor.run {
                    AnalyticsService.shared.capture("recording_startup_failed", [
                        "attempt": attempt,
                        "max_attempts": maxAttempts,
                        "error_domain": errorDomain,
                        "error_code": errorCode,
                        "error_type": isNoDisplay ? "no_display" : (retryable ? "retryable" : "non_retryable"),
                        "outcome": "gave_up",
                        "failure_reason": failureReason
                    ])
                }
            }
        }
    }
    
    @MainActor
    private func startStream(filter: SCContentFilter, config: SCStreamConfiguration, width: Int, height: Int) async throws {
        guard let output = streamOutput else {
            throw RecorderEngineError.noDisplay
        }
        let s = SCStream(filter: filter, configuration: config, delegate: streamDelegate)
        try s.addStreamOutput(output, type: .screen, sampleHandlerQueue: callbackQueue)
        try await s.startCapture()
        stream = s
        currentWidth = width
        currentHeight = height
        dbgEngine("stream started")
        AnalyticsService.shared.withSampling(probability: 0.01) {
            AnalyticsService.shared.capture("recording_started")
        }
    }
    
    private func stopStream() async {
        guard let s = stream else { return }
        
        if let output = streamOutput {
            try? s.removeStreamOutput(output, type: .screen)
        }
        
        do {
            try await s.stopCapture()
        } catch {
            dbgEngine("stopCapture failed – \(error)")
        }
        
        stream = nil
        
        // Only transition to .idle if not paused - preserve .paused state for auto-resume
        if state != .paused {
            transition(to: .idle, context: "stream stopped")
        }
        dbgEngine("stream stopped")
    }
    
    // MARK: - Segment Management
    
    func beginSegment() {
        guard segmentWriter == nil else { return }
        
        let width = currentWidth
        let height = currentHeight
        let url = storageManager.nextFileURL()
        storageManager.registerChunk(url: url)
        
        do {
            let writer = try SegmentWriter(url: url, width: width, height: height)
            segmentWriter = writer
            
            // Sampled chunk_created event
            Task { @MainActor in
                AnalyticsService.shared.withSampling(probability: 0.01) {
                    let gb = Double(width * height) / (1920.0 * 1080.0)
                    let resBucket: String = gb >= 1.0 ? "~1080p+" : "<1080p"
                    AnalyticsService.shared.capture("chunk_created", [
                        "duration_bucket": AnalyticsService.shared.secondsBucket(C.chunkSeconds),
                        "resolution_bucket": resBucket
                    ])
                }
            }
            
            // Auto-finish after C.chunkSeconds
            segmentTimer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(C.chunkSeconds * 1_000_000_000))
                await self?.finishCurrentSegment(restart: true)
            }
            
            transition(to: .recording, context: "segment started")
            
        } catch {
            dbgEngine("writer creation failed – \(error.localizedDescription)")
            storageManager.markChunkFailed(url: url)
        }
    }
    
    func appendFrame(_ sampleBuffer: CMSampleBuffer) {
        if segmentWriter == nil {
            beginSegment()
        }
        
        guard let writer = segmentWriter else { return }
        
        if !writer.appendFrame(sampleBuffer) {
            Task {
                await finishCurrentSegment(restart: true)
            }
        }
    }
    
    private func finishCurrentSegment(restart: Bool) async {
        // Guard against concurrent calls
        guard state != .finishing else { return }
        
        // Cancel timer
        segmentTimer?.cancel()
        segmentTimer = nil
        
        guard let writer = segmentWriter else {
            return
        }
        
        // Only transition to finishing if we're actually recording
        if state == .recording {
            transition(to: .finishing, context: "finishing segment (restart: \(restart))")
        }
        
        segmentWriter = nil
        let url = writer.fileURL
        
        await withCheckedContinuation { continuation in
            writer.finish { [weak self] success, error in
                Task {
                    guard let self = self else {
                        continuation.resume()
                        return
                    }
                    
                    await self.handleSegmentFinished(url: url, success: success, error: error, restart: restart)
                    continuation.resume()
                }
            }
        }
    }
    
    private func handleSegmentFinished(url: URL, success: Bool, error: Error?, restart: Bool) async {
        // Mark chunk completion status
        if success {
            storageManager.markChunkCompleted(url: url)
        } else {
            storageManager.markChunkFailed(url: url)
        }
        
        guard restart else {
            return
        }
        
        // Check if we should restart via MainActor
        let shouldRestart = await MainActor.run { AppState.shared.isRecording }
        guard shouldRestart else { return }
        
        // For the recording dimensions, we'll need to read them from the stream config
        // For now, use the same dimensions as before (this will be set when starting a new segment)
    }
    
    // MARK: - Error Handling
    
    func handleStreamError(_ error: Error?) async {
        let scError = error as NSError?
        
        guard let scError else {
            dbgEngine("stream stopped – nil error pointer, treating as transient")
            await stopStream()
            return
        }
        
        dbgEngine("stream stopped – domain: \(scError.domain), code: \(scError.code), description: \(scError.localizedDescription)")
        
        let userInfo = scError.userInfo
        if !userInfo.isEmpty {
            dbgEngine("Error userInfo: \(userInfo)")
        }
        
        await stopStream()
        
        if isUserInitiatedStop(scError) {
            dbgEngine("User stopped recording through system UI")
            await MainActor.run {
                AnalyticsService.shared.capture("recording_stopped", ["stop_reason": "user"])
            }
        } else if shouldRetry(scError) {
            dbgEngine("Retryable error - will restart if recording flag is set")
            await MainActor.run {
                AnalyticsService.shared.capture("recording_error", [
                    "code": scError.code,
                    "retryable": true
                ])
            }
        } else {
            dbgEngine("Non-retryable error - stopping recording")
            await MainActor.run {
                AnalyticsService.shared.capture("recording_error", [
                    "code": scError.code,
                    "retryable": false
                ])
                AnalyticsService.shared.capture("recording_auto_recovery", ["outcome": "gave_up"])
            }
        }
    }
    
    private func shouldRetry(_ err: Error) -> Bool {
        let nsError = err as NSError
        guard nsError.domain == SCStreamErrorDomain else { return false }
        
        if let errorCode = SCStreamErrorCode(rawValue: Int(nsError.code)) {
            dbgEngine("SCStream error code: \(nsError.code) (\(errorCode)) - shouldAutoRestart: \(errorCode.shouldAutoRestart)")
            return errorCode.shouldAutoRestart
        }
        
        dbgEngine("Unknown SCStream error code: \(nsError.code) - not retrying")
        return false
    }
    
    private func isUserInitiatedStop(_ err: Error) -> Bool {
        let nsError = err as NSError
        guard nsError.domain == SCStreamErrorDomain else { return false }
        
        if let errorCode = SCStreamErrorCode(rawValue: Int(nsError.code)) {
            return errorCode.isUserInitiated
        }
        
        let userInfo = nsError.userInfo
        if let reason = userInfo[NSLocalizedFailureReasonErrorKey] as? String {
            let userStopIndicators = ["user stopped", "stopped by user", "user cancelled", "stop sharing"]
            let lowercasedReason = reason.lowercased()
            if userStopIndicators.contains(where: { lowercasedReason.contains($0) }) {
                dbgEngine("Detected user stop from error reason: \(reason)")
                return true
            }
        }
        
        return false
    }
}
