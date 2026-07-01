import Foundation
import Testing
@testable import HostsKit

@Suite struct RefreshScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let grace: TimeInterval = 300

    @Test func offReturnsNil() {
        #expect(RefreshSchedule.nextDelay(isLaunch: true, lastRefresh: nil, now: now, intervalHours: nil, graceSeconds: grace) == nil)
        #expect(RefreshSchedule.nextDelay(isLaunch: true, lastRefresh: nil, now: now, intervalHours: 0, graceSeconds: grace) == nil)
        #expect(RefreshSchedule.nextDelay(isLaunch: false, lastRefresh: nil, now: now, intervalHours: -5, graceSeconds: grace) == nil)
    }

    @Test func nonLaunchUsesPlainInterval() {
        // Even if it would be "due", a reschedule fires a full interval out.
        #expect(RefreshSchedule.nextDelay(isLaunch: false, lastRefresh: nil, now: now, intervalHours: 24, graceSeconds: grace) == TimeInterval(24 * 3600))
    }

    @Test func launchDueNeverRefreshedReturnsGrace() {
        #expect(RefreshSchedule.nextDelay(isLaunch: true, lastRefresh: nil, now: now, intervalHours: 24, graceSeconds: grace) == grace)
    }

    @Test func launchDuePastIntervalReturnsGrace() {
        let last = now.addingTimeInterval(-48 * 3600)  // 48h ago on 24h interval => due
        #expect(RefreshSchedule.nextDelay(isLaunch: true, lastRefresh: last, now: now, intervalHours: 24, graceSeconds: grace) == grace)
    }

    @Test func launchNotDueReturnsRemainingUntilDue() {
        let last = now.addingTimeInterval(-1 * 3600)   // 1h ago on 24h interval => 23h remaining
        #expect(RefreshSchedule.nextDelay(isLaunch: true, lastRefresh: last, now: now, intervalHours: 24, graceSeconds: grace) == TimeInterval(23 * 3600))
    }

    @Test func launchNotDueButWithinGraceFloorsToGrace() {
        let last = now.addingTimeInterval(-(24 * 3600 - 60))  // due in 60s, below the 300s grace floor
        #expect(RefreshSchedule.nextDelay(isLaunch: true, lastRefresh: last, now: now, intervalHours: 24, graceSeconds: grace) == grace)
    }
}
