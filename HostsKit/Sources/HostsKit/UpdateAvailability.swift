import Foundation

/// Pure policy that decides whether a fetched release is an installable update.
/// Fail-closed: an unparseable tag, missing `.dmg`, or non-https asset URL all mean `.upToDate`.
public enum UpdateAvailability {
    public enum Outcome: Equatable, Sendable {
        case upToDate
        case available(version: AppVersion, dmgURL: URL, size: Int)
    }

    public static func evaluate(current: AppVersion, release: GitHubRelease) -> Outcome {
        guard let version = AppVersion(release.tagName), version > current else { return .upToDate }
        guard let dmg = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
            return .upToDate
        }
        guard let url = URL(string: dmg.browserDownloadURL),
              url.scheme?.lowercased() == "https" else {
            return .upToDate
        }
        return .available(version: version, dmgURL: url, size: dmg.size)
    }
}
