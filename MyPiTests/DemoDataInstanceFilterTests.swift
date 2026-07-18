import Foundation
import Testing
@testable import MyPi

/// Demo mode must respect the Query Log's Device filter the same way the
/// server does: the two synthetic devices match their own traffic, any other
/// instance id matches nothing, and nil matches everything.
struct DemoDataInstanceFilterTests {
    @Test func demoInstanceListHasTwoDevices() {
        let instances = DemoData.instances()
        let ids = instances.map(\.id)
        let allActive = instances.allSatisfy(\.isActive)
        #expect(ids == [DemoData.primaryInstanceId, DemoData.secondaryInstanceId])
        #expect(allActive)
    }

    @Test func instanceStatsSumToTotals() {
        let instances = DemoData.instances(total: 1000, blocked: 200)
        let totalQueries = instances.map(\.dnsQueriesToday).reduce(0, +)
        let totalBlocked = instances.map(\.queriesBlocked).reduce(0, +)
        #expect(totalQueries == 1000)
        #expect(totalBlocked == 200)
    }

    @Test func eachDeviceMatchesOnlyItsOwnQueries() {
        for id in DemoData.validInstanceIds {
            let page = DemoData.queries(
                page: 1, pageSize: 50, range: .today, filter: .all,
                domain: nil, instanceId: id
            )
            let allMatch = page.items.allSatisfy { $0.instanceId == id }
            #expect(!page.items.isEmpty)
            #expect(allMatch)
        }
    }

    @Test func nilInstanceIdReturnsQueries() {
        let page = DemoData.queries(
            page: 1, pageSize: 50, range: .today, filter: .all,
            domain: nil, instanceId: nil
        )
        #expect(!page.items.isEmpty)
    }

    @Test func perDeviceQueryTotalsSumToUnfilteredTotal() {
        func total(_ id: String?) -> Int {
            DemoData.queries(
                page: 1, pageSize: 50, range: .today, filter: .all,
                domain: nil, instanceId: id
            ).total
        }
        #expect(total(DemoData.primaryInstanceId) + total(DemoData.secondaryInstanceId) == total(nil))
    }

    @Test func unknownInstanceIdReturnsNothing() {
        let page = DemoData.queries(
            page: 1, pageSize: 50, range: .today, filter: .all,
            domain: nil, instanceId: "not-a-device"
        )
        #expect(page.items.isEmpty)
        #expect(page.total == 0)
        #expect(DemoData.clients(range: .today, instanceId: "not-a-device").isEmpty)
        #expect(DemoData.history(range: .today, instanceId: "not-a-device").buckets.isEmpty)
    }

    /// The By Device chart stacks per-device series; they must sum
    /// bucket-for-bucket to the unfiltered total series or the stacked chart
    /// would silently disagree with the All mode.
    @Test func perDeviceHistoriesSumToTotal() {
        for range in TimeRange.allCases {
            let total = DemoData.history(range: range, instanceId: nil).buckets
            let primary = DemoData.history(range: range, instanceId: DemoData.primaryInstanceId).buckets
            let secondary = DemoData.history(range: range, instanceId: DemoData.secondaryInstanceId).buckets
            #expect(primary.count == total.count)
            #expect(secondary.count == total.count)
            for i in total.indices {
                #expect(primary[i].queries + secondary[i].queries == total[i].queries)
                #expect(primary[i].blocked + secondary[i].blocked == total[i].blocked)
                #expect(primary[i].blocked <= primary[i].queries)
                #expect(secondary[i].blocked <= secondary[i].queries)
            }
        }
    }
}
