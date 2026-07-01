import Foundation

/// Seconds until the next automatic source refresh should fire, or nil when refresh is Off.
/// `isLaunch` applies the boot grace and the due-check so a not-yet-due launch is anchored to
/// lastRefresh + interval (never a full interval from process start); a post-refresh or
/// settings-change reschedule uses the plain interval.
public enum RefreshSchedule {
    public static func nextDelay(
        isLaunch: Bool,
        lastRefresh: Date?,
        now: Date,
        intervalHours: Int?,
        graceSeconds: TimeInterval
    ) -> TimeInterval? {
        guard let hours = intervalHours, hours > 0 else { return nil }
        let interval = TimeInterval(hours) * 3600
        guard isLaunch else { return interval }
        if RefreshDuePolicy.isDue(lastRefresh: lastRefresh, now: now, intervalHours: hours) {
            return graceSeconds
        }
        let remaining = (lastRefresh ?? now).addingTimeInterval(interval).timeIntervalSince(now)
        return max(remaining, graceSeconds)
    }
}
