//
//  TimelineUtilities.swift
//  Dayflow
//
//  Helper functions for timeline date navigation and formatting
//

import Foundation

func canNavigateForward(from date: Date, now: Date = Date()) -> Bool {
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
    let timelineToday = timelineDisplayDate(from: now, now: now)
    return calendar.compare(tomorrow, to: timelineToday, toGranularity: .day) != .orderedDescending
}

func normalizedTimelineDate(_ date: Date) -> Date {
    let calendar = Calendar.current
    if let normalized = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) {
        return normalized
    }
    let startOfDay = calendar.startOfDay(for: date)
    return calendar.date(byAdding: DateComponents(hour: 12), to: startOfDay) ?? date
}

func timelineDisplayDate(from date: Date, now: Date = Date()) -> Date {
    let calendar = Calendar.current
    var normalizedDate = normalizedTimelineDate(date)
    let normalizedNow = normalizedTimelineDate(now)
    let nowHour = calendar.component(.hour, from: now)

    if nowHour < 4 && calendar.isDate(normalizedDate, inSameDayAs: normalizedNow) {
        normalizedDate = calendar.date(byAdding: .day, value: -1, to: normalizedDate) ?? normalizedDate
    }

    return normalizedDate
}

func timelineIsToday(_ date: Date, now: Date = Date()) -> Bool {
    let calendar = Calendar.current
    let timelineDate = timelineDisplayDate(from: date, now: now)
    let timelineToday = timelineDisplayDate(from: now, now: now)
    return calendar.isDate(timelineDate, inSameDayAs: timelineToday)
}

func formatDateForDisplay(_ date: Date) -> String {
    let now = Date()
    let calendar = Calendar.current
    let formatter = DateFormatter()

    let displayDate = timelineDisplayDate(from: date, now: now)
    let timelineToday = timelineDisplayDate(from: now, now: now)

    if calendar.isDate(displayDate, inSameDayAs: timelineToday) {
        formatter.dateFormat = "'Today,' MMM d"
    } else {
        formatter.dateFormat = "E, MMM d"
    }

    return formatter.string(from: displayDate)
}

func dayString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
