import Foundation

/// Decides whether an automatic source refresh is due. A launch refresh must consult this so the
/// configured interval — not merely the repeating timer — governs how often the active profile can
/// be auto-re-applied (each re-apply prompts for the admin password).
public enum RefreshDuePolicy {
    public static func isDue(lastRefresh: Date?, now: Date, intervalHours: Int?) -> Bool {
        guard let hours = intervalHours, hours > 0 else { return false }
        guard let lastRefresh else { return true }
        return now >= lastRefresh.addingTimeInterval(TimeInterval(hours) * 3600)
    }
}
