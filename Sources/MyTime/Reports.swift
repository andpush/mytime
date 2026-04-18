import Foundation

struct ReportRow: Identifiable, Equatable {
    let id = UUID()
    var group: String
    var seconds: Int
    var percent: Double
}

enum ReportPeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case custom = "Custom"
    var id: String { rawValue }
}

enum ReportGrouping: String, CaseIterable, Identifiable {
    case client = "By Client"
    case label = "By Label"
    case dayOfWeek = "By Day of Week"
    case day = "By Day"
    case week = "By Week"
    case month = "By Month"
    case year = "By Year"
    var id: String { rawValue }
}

struct ReportResult {
    var rows: [ReportRow]
    var totalEntries: Int
    var totalSeconds: Int
    var discardedSeconds: Int
}

enum Reports {
    static func range(for period: ReportPeriod, now: Date = Date(),
                      customStart: Date? = nil, customEnd: Date? = nil) -> (Date, Date) {
        let cal = Calendar.current
        switch period {
        case .day:
            let start = cal.startOfDay(for: now)
            return (start, now)
        case .week:
            return (cal.date(byAdding: .day, value: -7, to: now) ?? now, now)
        case .month:
            return (cal.date(byAdding: .day, value: -30, to: now) ?? now, now)
        case .year:
            return (cal.date(byAdding: .day, value: -365, to: now) ?? now, now)
        case .custom:
            return (customStart ?? now, customEnd ?? now)
        }
    }

    static func compute(entries: [TimerEntry], period: ReportPeriod, grouping: ReportGrouping,
                        now: Date = Date(), customStart: Date? = nil, customEnd: Date? = nil) -> ReportResult {
        let (from, to) = range(for: period, now: now, customStart: customStart, customEnd: customEnd)
        var filtered: [TimerEntry] = []
        let discarded = 0
        for e in entries {
            if e.startTime < from || e.startTime > to { continue }
            filtered.append(e)
        }

        // Group entries. For calendar bucket groupings we keep a representative date
        // for each group so the rows can be sorted chronologically rather than by size.
        var groups: [String: Int] = [:]
        var sortDates: [String: Date] = [:]
        for e in filtered {
            let (key, sortDate) = Self.groupKey(for: e.startTime, grouping: grouping, client: e.client, activity: e.activity)
            groups[key, default: 0] += e.durationSeconds
            if let d = sortDate {
                // keep earliest date for stable chronological sort
                if let prev = sortDates[key] {
                    if d < prev { sortDates[key] = d }
                } else {
                    sortDates[key] = d
                }
            }
        }
        let total = groups.values.reduce(0, +)
        var rows: [ReportRow] = groups.map { (k, v) in
            ReportRow(group: k, seconds: v, percent: total > 0 ? Double(v) / Double(total) : 0)
        }
        if grouping.isChronological {
            rows.sort { (a, b) in (sortDates[a.group] ?? .distantPast) < (sortDates[b.group] ?? .distantPast) }
        } else {
            rows.sort { $0.seconds > $1.seconds }
        }
        return ReportResult(rows: rows, totalEntries: filtered.count, totalSeconds: total, discardedSeconds: discarded)
    }

    /// Returns the group label and — for calendar buckets — the representative
    /// date used to sort rows chronologically (nil for non-calendar groupings).
    private static func groupKey(for date: Date, grouping: ReportGrouping, client: String, activity: String) -> (String, Date?) {
        let cal = Calendar.current
        switch grouping {
        case .client:
            return (client.isEmpty ? "(none)" : client, nil)
        case .label:
            return (activity.isEmpty ? "(none)" : activity, nil)
        case .dayOfWeek:
            let fmt = DateFormatter()
            fmt.dateFormat = "EEEE"
            return (fmt.string(from: date), nil)
        case .day:
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd (EEE)"
            let bucket = cal.startOfDay(for: date)
            return (fmt.string(from: date), bucket)
        case .week:
            // ISO week + year, e.g. "2026-W16 (Apr 13–19)"
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let weekStart = cal.date(from: comps) ?? date
            let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let rangeFmt = DateFormatter()
            rangeFmt.dateFormat = "MMM d"
            let label = String(format: "%04d-W%02d (%@–%@)",
                               comps.yearForWeekOfYear ?? 0,
                               comps.weekOfYear ?? 0,
                               rangeFmt.string(from: weekStart),
                               rangeFmt.string(from: weekEnd))
            return (label, weekStart)
        case .month:
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM (MMMM)"
            let bucket = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
            return (fmt.string(from: date), bucket)
        case .year:
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy"
            let bucket = cal.date(from: cal.dateComponents([.year], from: date)) ?? date
            return (fmt.string(from: date), bucket)
        }
    }

}

extension ReportGrouping {
    var isChronological: Bool {
        switch self {
        case .day, .week, .month, .year: return true
        case .client, .label, .dayOfWeek: return false
        }
    }
}

extension Reports {
    static func formatHMS(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
