import Foundation
import Testing
@testable import MyPi

struct HistoryMathTests {
    private func bucket(_ offset: TimeInterval, queries: Int, blocked: Int) -> HistoryBucket {
        HistoryBucket(
            timestamp: Date(timeIntervalSinceReferenceDate: offset),
            queries: queries,
            blocked: blocked
        )
    }

    // MARK: - totals

    @Test func totalsSumPermittedAndBlocked() {
        let buckets = [
            bucket(0, queries: 100, blocked: 20),
            bucket(60, queries: 50, blocked: 10),
        ]
        let t = HistoryMath.totals(buckets)
        #expect(t.permitted == 120)
        #expect(t.blocked == 30)
    }

    @Test func totalsClampNegativePermitted() {
        // Malformed bucket where blocked > queries must not go negative.
        let t = HistoryMath.totals([bucket(0, queries: 5, blocked: 9)])
        #expect(t.permitted == 0)
        #expect(t.blocked == 9)
    }

    @Test func totalsOfEmptySeriesAreZero() {
        let t = HistoryMath.totals([])
        #expect(t.permitted == 0)
        #expect(t.blocked == 0)
    }

    // MARK: - blockedPercentSeries

    @Test func blockedPercentComputesShare() {
        let series = HistoryMath.blockedPercentSeries([
            bucket(0, queries: 200, blocked: 50),
            bucket(60, queries: 100, blocked: 100),
        ])
        #expect(series.count == 2)
        #expect(series[0].percent == 25)
        #expect(series[1].percent == 100)
    }

    @Test func blockedPercentSkipsEmptyBuckets() {
        // An idle bucket is "no data," not 0% blocked — it must be omitted,
        // not emitted as a fake zero that drags the line down.
        let series = HistoryMath.blockedPercentSeries([
            bucket(0, queries: 0, blocked: 0),
            bucket(60, queries: 100, blocked: 30),
            bucket(120, queries: 0, blocked: 0),
        ])
        #expect(series.count == 1)
        #expect(series[0].percent == 30)
    }

    @Test func blockedPercentClampsMalformedBuckets() {
        let series = HistoryMath.blockedPercentSeries([
            bucket(0, queries: 10, blocked: 25),   // > 100%
            bucket(60, queries: 10, blocked: -5),  // < 0%
        ])
        #expect(series[0].percent == 100)
        #expect(series[1].percent == 0)
    }

    // MARK: - nearestBucket

    @Test func nearestBucketSnapsToClosestTimestamp() {
        let buckets = [
            bucket(0, queries: 1, blocked: 0),
            bucket(600, queries: 2, blocked: 0),
            bucket(1200, queries: 3, blocked: 0),
        ]
        let hit = HistoryMath.nearestBucket(
            in: buckets,
            to: Date(timeIntervalSinceReferenceDate: 700)
        )
        #expect(hit?.queries == 2)
    }

    @Test func nearestBucketExactMatch() {
        let buckets = [
            bucket(0, queries: 1, blocked: 0),
            bucket(600, queries: 2, blocked: 0),
        ]
        let hit = HistoryMath.nearestBucket(
            in: buckets,
            to: Date(timeIntervalSinceReferenceDate: 600)
        )
        #expect(hit?.queries == 2)
    }

    @Test func nearestBucketOutOfDomainClampsToEdge() {
        let buckets = [
            bucket(0, queries: 1, blocked: 0),
            bucket(600, queries: 2, blocked: 0),
        ]
        let before = HistoryMath.nearestBucket(
            in: buckets,
            to: Date(timeIntervalSinceReferenceDate: -5000)
        )
        let after = HistoryMath.nearestBucket(
            in: buckets,
            to: Date(timeIntervalSinceReferenceDate: 9000)
        )
        #expect(before?.queries == 1)
        #expect(after?.queries == 2)
    }

    @Test func nearestBucketOfEmptySeriesIsNil() {
        #expect(HistoryMath.nearestBucket(in: [], to: Date(timeIntervalSinceReferenceDate: 0)) == nil)
    }
}
