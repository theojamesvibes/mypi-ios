import Foundation

/// Time-range options shown in Dashboard and Query Log filters.
/// Mirrors the options on the MyPi server's web dashboard.
enum TimeRange: String, CaseIterable, Identifiable, Hashable, Codable {
    case minutes15
    case hour1
    case today
    case hours24
    case hours48
    case days7
    case days30

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minutes15: return "15m"
        case .hour1:     return "1h"
        case .today:     return "Today"
        case .hours24:   return "24h"
        case .hours48:   return "48h"
        case .days7:     return "7d"
        case .days30:    return "30d"
        }
    }

    var longLabel: String {
        switch self {
        case .minutes15: return "Last 15 minutes"
        case .hour1:     return "Last 1 hour"
        case .today:     return "Today"
        case .hours24:   return "Last 24 hours"
        case .hours48:   return "Last 48 hours"
        case .days7:     return "Last 7 days"
        case .days30:    return "Last 30 days"
        }
    }

    /// Histogram bucket size that keeps the chart readable across ranges.
    var bucketMinutes: Int {
        switch self {
        case .minutes15: return 1
        case .hour1:     return 5
        case .today:     return 30
        case .hours24:   return 30
        case .hours48:   return 30
        case .days7:     return 60
        case .days30:    return 120
        }
    }

    /// Approximate hour-equivalent used for cache-key stability and fallbacks.
    var hoursEquivalent: Int {
        switch self {
        case .minutes15: return 1
        case .hour1:     return 1
        case .today:     return 24
        case .hours24:   return 24
        case .hours48:   return 48
        case .days7:     return 168
        case .days30:    return 720
        }
    }

    /// Fixed-hour ranges can use `?hours=`; "today" / "15m" / "1h" need `?since=` so the
    /// window lines up with wall-clock minutes / midnight rather than drifting.
    func queryString(now: Date = Date()) -> String {
        switch self {
        case .minutes15:
            let since = now.addingTimeInterval(-15 * 60)
            return "since=\(iso(since))"
        case .hour1:
            let since = now.addingTimeInterval(-60 * 60)
            return "since=\(iso(since))"
        case .today:
            let since = Calendar.current.startOfDay(for: now)
            return "since=\(iso(since))"
        case .hours24:  return "hours=24"
        case .hours48:  return "hours=48"
        case .days7:    return "hours=168"
        case .days30:   return "hours=720"
        }
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }

    /// Intended x-axis domain for charts rendering this range. Using this as
    /// `chartXScale(domain:)` keeps the axis full-width even when only a few
    /// buckets have data (e.g. just after midnight when "Today" is sparse).
    func xDomain(now: Date = Date()) -> ClosedRange<Date> {
        switch self {
        case .minutes15: return now.addingTimeInterval(-15 * 60)...now
        case .hour1:     return now.addingTimeInterval(-60 * 60)...now
        case .today:     return Calendar.current.startOfDay(for: now)...now
        case .hours24:   return now.addingTimeInterval(-24 * 3600)...now
        case .hours48:   return now.addingTimeInterval(-48 * 3600)...now
        case .days7:     return now.addingTimeInterval(-7 * 24 * 3600)...now
        case .days30:    return now.addingTimeInterval(-30 * 24 * 3600)...now
        }
    }
}
