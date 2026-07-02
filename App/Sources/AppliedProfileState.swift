import Foundation
import HostsKit

// The active profile as composed at the last successful apply — what's live in /etc/hosts.
// Staleness compares captured fragment contents and source hashes, not generation counters,
// so an edit that returns to the applied state reads as clean, and the snapshot survives relaunch.
struct AppliedProfileState: Codable {
    let profile: Profile
    let fragmentContents: [UUID: String]
    let sourceHashes: [UUID: String]

    static var defaultURL: URL {
        AppPaths.supportRoot().appendingPathComponent("appliedstate.json", isDirectory: false)
    }

    static func capture(_ profile: Profile, fragments: [LocalFragment],
                        sources: [RemoteSource]) -> AppliedProfileState {
        let frags = Dictionary(uniqueKeysWithValues: profile.fragmentIDs.compactMap { id in
            fragments.first { $0.id == id }.map { (id, $0.content) }
        })
        let hashes = Dictionary(uniqueKeysWithValues: profile.sourceIDs.compactMap { id in
            sources.first { $0.id == id }?.contentHash.map { (id, $0) }
        })
        return AppliedProfileState(profile: profile, fragmentContents: frags, sourceHashes: hashes)
    }

    func matches(_ current: Profile, fragments: [LocalFragment], sources: [RemoteSource]) -> Bool {
        current.content == profile.content && current.sourceIDs == profile.sourceIDs
            && current.fragmentIDs == profile.fragmentIDs
            && current.fragmentIDs.allSatisfy { id in
                fragments.first { $0.id == id }?.content == fragmentContents[id]
            }
            && current.sourceIDs.allSatisfy { id in
                sources.first { $0.id == id }?.contentHash == sourceHashes[id]
            }
    }

    // Advisory cache: unreadable/corrupt loads as nil, which falls back to latch-toward-stale.
    static func load(from url: URL) -> AppliedProfileState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppliedProfileState.self, from: data)
    }

    func save(to url: URL) {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url, options: .atomic) }
    }
}

extension AppModel {
    var canRevertActiveProfile: Bool { activeProfileID != nil && appliedState?.profile.id == activeProfileID }

    // Badge basis: the fragment as saved differs from what was live at the last apply.
    func fragmentNeedsApply(_ id: UUID) -> Bool {
        guard let a = appliedState, a.profile.id == activeProfileID, a.profile.fragmentIDs.contains(id),
              let cur = fragments.first(where: { $0.id == id }) else { return false }
        return a.fragmentContents[id] != cur.content
    }
}
