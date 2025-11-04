//
//  VideoTimestampParser.swift
//  Dayflow
//
//  Helper for safely parsing video timestamps in MM:SS or HH:MM:SS format.
//

import Foundation

/// Parses video timestamps in formats "MM:SS" or "HH:MM:SS" into seconds.
/// Returns `nil` for malformed or invalid inputs.
struct VideoTimestampParser {
    
    /// Parse a video timestamp string into seconds.
    /// - Parameter timestamp: A string in format "MM:SS" or "HH:MM:SS"
    /// - Returns: The number of seconds as an Int, or nil if parsing fails
    static func parseTimestamp(_ timestamp: String) -> Int? {
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let components = trimmed.components(separatedBy: ":")
        
        // Handle HH:MM:SS format
        if components.count == 3 {
            guard let hours = Int(components[0]),
                  let minutes = Int(components[1]),
                  let seconds = Int(components[2]),
                  hours >= 0,
                  minutes >= 0, minutes < 60,
                  seconds >= 0, seconds < 60 else {
                return nil
            }
            return hours * 3600 + minutes * 60 + seconds
        }
        
        // Handle MM:SS format
        if components.count == 2 {
            guard let minutes = Int(components[0]),
                  let seconds = Int(components[1]),
                  minutes >= 0,
                  seconds >= 0, seconds < 60 else {
                return nil
            }
            return minutes * 60 + seconds
        }
        
        // Invalid format
        return nil
    }
    
    /// Parse a video timestamp string into TimeInterval (Double seconds).
    /// - Parameter timestamp: A string in format "MM:SS" or "HH:MM:SS"
    /// - Returns: The number of seconds as a TimeInterval, or nil if parsing fails
    static func parseTimestampAsTimeInterval(_ timestamp: String) -> TimeInterval? {
        guard let seconds = parseTimestamp(timestamp) else { return nil }
        return TimeInterval(seconds)
    }
}
