import Foundation
import Testing
@testable import MyPi

struct TimeRangeTests {
    @Test func hasAllSevenCases() {
        #expect(TimeRange.allCases.count == 7)
    }

    @Test func fixedRangesUseHoursQuery() {
        // Fixed-width ranges hit the server with ?hours=N.
        #expect(TimeRange.hours24.queryString() == "hours=24")
        #expect(TimeRange.hours48.queryString() == "hours=48")
        #expect(TimeRange.days7.queryString() == "hours=168")
        #expect(TimeRange.days30.queryString() == "hours=720")
    }

    @Test func wallClockRangesUseSinceQuery() {
        // "today" / "1h" / "15m" must use ?since= so the window aligns to wall clock.
        #expect(TimeRange.today.queryString().hasPrefix("since="))
        #expect(TimeRange.hour1.queryString().hasPrefix("since="))
        #expect(TimeRange.minutes15.queryString().hasPrefix("since="))
    }

    @Test func bucketAndHourMappings() {
        #expect(TimeRange.minutes15.bucketMinutes == 1)
        #expect(TimeRange.hour1.bucketMinutes == 5)
        #expect(TimeRange.days30.bucketMinutes == 120)
        #expect(TimeRange.hours48.hoursEquivalent == 48)
        #expect(TimeRange.days7.hoursEquivalent == 168)
        #expect(TimeRange.days30.hoursEquivalent == 720)
    }

    @Test func xDomainIsOrderedAndEndsAtNow() {
        // 2025-06-15T14:13:20Z — clearly mid-day in any timezone, so even the
        // "today" lower bound (start of day) is strictly before now.
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        for range in TimeRange.allCases {
            let domain = range.xDomain(now: now)
            #expect(domain.lowerBound < domain.upperBound)
            #expect(domain.upperBound == now)
        }
    }

    @Test func rawValuesAreStableForPersistence() throws {
        // These are persisted in user prefs; drifting them silently breaks stored state.
        #expect(TimeRange.today.rawValue == "today")
        #expect(TimeRange(rawValue: "hours24") == .hours24)
        let data = try JSONEncoder().encode(TimeRange.days7)
        #expect(try JSONDecoder().decode(TimeRange.self, from: data) == .days7)
    }

    @Test func everyCaseHasLabels() {
        for range in TimeRange.allCases {
            #expect(!range.label.isEmpty)
            #expect(!range.longLabel.isEmpty)
        }
    }
}
