//
//  SegmentWriter.swift
//  Dayflow
//
//  Manages AVAssetWriter lifecycle and segment file operations for screen recording.
//

import Foundation
import AVFoundation
import CoreMedia

/// Manages a single recording segment's writer lifecycle
final class SegmentWriter: @unchecked Sendable {
    
    private let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var firstPTS: CMTime?
    private(set) var frameCount: Int = 0
    
    enum SegmentWriterError: Error {
        case badInput
        case writerNotReady
        case failedToStart(Error?)
    }
    
    init(url: URL, width: Int, height: Int, bitrate: Int = 2_500_000) throws {
        self.url = url
        
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video,
                                       outputSettings: [
                                           AVVideoCodecKey  : AVVideoCodecType.h264,
                                           AVVideoWidthKey  : width,
                                           AVVideoHeightKey : height,
                                           AVVideoCompressionPropertiesKey: [
                                               AVVideoAverageBitRateKey: bitrate,
                                               AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
                                               AVVideoMaxKeyFrameIntervalKey: 30
                                           ]
                                       ])
        input.expectsMediaDataInRealTime = true
        
        guard writer.canAdd(input) else {
            throw SegmentWriterError.badInput
        }
        writer.add(input)
        
        guard writer.startWriting() else {
            throw SegmentWriterError.failedToStart(writer.error)
        }
        
        self.writer = writer
        self.input = input
    }
    
    /// Appends a sample buffer to the writer
    /// - Returns: true if successful, false if the segment should be finished
    func appendFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        if firstPTS == nil {
            firstPTS = sampleBuffer.presentationTimeStamp
            writer.startSession(atSourceTime: firstPTS!)
        }
        
        guard input.isReadyForMoreMediaData, writer.status == .writing else {
            return false
        }
        
        if input.append(sampleBuffer) {
            frameCount += 1
            return true
        } else {
            return false
        }
    }
    
    /// Finishes the segment asynchronously
    /// - Parameter completion: Called on a background queue with success status and error if any
    func finish(completion: @escaping @Sendable (Bool, Error?) -> Void) {
        guard frameCount > 0 else {
            writer.cancelWriting()
            completion(false, nil)
            return
        }
        
        guard writer.status == .writing else {
            writer.cancelWriting()
            completion(false, SegmentWriterError.writerNotReady)
            return
        }
        
        input.markAsFinished()
        writer.finishWriting {
            let success = self.writer.status == .completed
            completion(success, self.writer.error)
        }
    }
    
    /// Cancels writing without finishing
    func cancel() {
        writer.cancelWriting()
    }
    
    var hasFrames: Bool { frameCount > 0 }
    var fileURL: URL { url }
}
