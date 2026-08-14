import Foundation

// Counts that need real plural rules. Kept out of the call sites so the catalog holds one
// pluralized key per phrase instead of a "(s)" fudge that only reads correctly in English.
enum Localized {
    static func domains(_ count: Int) -> String {
        String(localized: "\(count) domains", comment: "Size of a blocklist source")
    }

    static func nullRoutedTotal(_ count: Int) -> String {
        String(localized: "Total: ~\(count) null-routed domains", comment: "Summary line in the apply preview")
    }

    static func profilesAdded(_ count: Int) -> String {
        String(localized: "\(count) profiles added", comment: "Import summary line")
    }

    static func fragmentsAdded(_ count: Int) -> String {
        String(localized: "\(count) fragments added", comment: "Import summary line")
    }

    static func sourcesAdded(_ count: Int) -> String {
        String(localized: "\(count) sources added", comment: "Import summary line")
    }

    static func alreadyPresent(_ count: Int) -> String {
        String(localized: "\(count) items were already present and were skipped", comment: "Import summary line")
    }
}
