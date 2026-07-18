import Foundation

/// Pure derivations over history buckets, kept out of the chart views so
/// they're unit-testable without SwiftUI.
enum HistoryMath {
    /// Permitted/blocked totals across a bucket series. Permitted is clamped
    /// at zero per bucket — the server counts `blocked <= queries`, but a
    /// malformed bucket must not produce a negative bar.
    static func totals(_ buckets: [HistoryBucket]) -> (permitted: Int, blocked: Int) {
        buckets.reduce((0, 0)) { acc, b in
            (acc.0 + max(0, b.queries - b.blocked), acc.1 + b.blocked)
        }
    }

    /// Blocked share per bucket, in percent (0–100). Buckets with no queries
    /// are skipped entirely — an idle bucket is "no data," not 0% blocked,
    /// and emitting fake zeros would drag the line down during quiet hours.
    static func blockedPercentSeries(_ buckets: [HistoryBucket]) -> [(date: Date, percent: Double)] {
        buckets.compactMap { b in
            guard b.queries > 0 else { return nil }
            let pct = Double(b.blocked) / Double(b.queries) * 100
            return (b.timestamp, min(100, max(0, pct)))
        }
    }

    /// Bucket whose timestamp is closest to `date` — the scrub-selection
    /// snap. Nil only for an empty series.
    static func nearestBucket(in buckets: [HistoryBucket], to date: Date) -> HistoryBucket? {
        buckets.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        })
    }
}
