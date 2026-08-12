import Foundation

/// One release's notes as shown in the update window.
public struct ReleaseNote: Equatable, Sendable {
    public let version: String                 // display form, no leading "v"
    public let blocks: [ReleaseNotes.Block]

    public init(version: String, blocks: [ReleaseNotes.Block]) {
        self.version = version
        self.blocks = blocks
    }
}

/// What an update would install, plus the notes for everything the user missed.
public struct UpdatePlan: Equatable, Sendable {
    public let version: AppVersion
    public let dmgURL: URL
    public let size: Int
    public let notes: [ReleaseNote]            // newest first, spanning (current, latest]

    public init(version: AppVersion, dmgURL: URL, size: Int, notes: [ReleaseNote]) {
        self.version = version
        self.dmgURL = dmgURL
        self.size = size
        self.notes = notes
    }
}

extension UpdateAvailability {
    /// The newest installable release, with notes aggregated over every release
    /// newer than `current` — so someone who skipped versions sees all of them.
    ///
    /// Fail-closed throughout: drafts and prereleases are excluded, unparseable
    /// tags are dropped, and if the newest release isn't installable this returns
    /// `nil` rather than quietly offering an older one than the releases page shows.
    public static func plan(current: AppVersion, releases: [GitHubRelease]) -> UpdatePlan? {
        let newer = releases
            .filter { !$0.draft && !$0.prerelease }
            .compactMap { release -> (version: AppVersion, release: GitHubRelease)? in
                guard let version = AppVersion(release.tagName), version > current else { return nil }
                return (version, release)
            }
            .sorted { $0.version > $1.version }

        guard let latest = newer.first,
              case let .available(version, dmgURL, size) = evaluate(current: current, release: latest.release)
        else { return nil }

        return UpdatePlan(
            version: version, dmgURL: dmgURL, size: size,
            notes: newer.map {
                ReleaseNote(version: "\($0.version.major).\($0.version.minor).\($0.version.patch)",
                            blocks: ReleaseNotes.blocks(from: $0.release.body))
            })
    }
}

/// Whether an available release should open the update window.
///
/// "Skip This Version" silences BACKGROUND checks only, and only up to the
/// skipped version — a newer release prompts again, and a manual Check for
/// Updates always prompts.
public enum UpdatePromptGate {
    public static func shouldPrompt(latest: AppVersion, skipped: AppVersion?, interactive: Bool) -> Bool {
        if interactive { return true }
        guard let skipped else { return true }
        return latest > skipped
    }
}
