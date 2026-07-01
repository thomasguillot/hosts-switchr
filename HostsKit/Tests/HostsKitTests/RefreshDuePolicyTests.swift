import Foundation
import Testing
@testable import HostsKit

@Suite struct RefreshDuePolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func neverRefreshedIsDue() {
        #expect(RefreshDuePolicy.isDue(lastRefresh: nil, now: now, intervalHours: 24) == true)
    }

    @Test func offNeverRefreshesEvenIfNever() {
        #expect(RefreshDuePolicy.isDue(lastRefresh: nil, now: now, intervalHours: nil) == false)
    }

    @Test func withinIntervalIsNotDue() {
        let last = now.addingTimeInterval(-1 * 3600)   // 1h ago, interval 168h (weekly)
        #expect(RefreshDuePolicy.isDue(lastRefresh: last, now: now, intervalHours: 168) == false)
    }

    @Test func pastIntervalIsDue() {
        let last = now.addingTimeInterval(-169 * 3600)  // 169h ago, interval 168h
        #expect(RefreshDuePolicy.isDue(lastRefresh: last, now: now, intervalHours: 168) == true)
    }

    @Test func exactlyAtIntervalIsDue() {
        let last = now.addingTimeInterval(-24 * 3600)
        #expect(RefreshDuePolicy.isDue(lastRefresh: last, now: now, intervalHours: 24) == true)
    }

    @Test func nonPositiveIntervalIsNeverDue() {
        #expect(RefreshDuePolicy.isDue(lastRefresh: nil, now: now, intervalHours: 0) == false)
        #expect(RefreshDuePolicy.isDue(lastRefresh: nil, now: now, intervalHours: -5) == false)
    }
}
