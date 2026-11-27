import Foundation

public struct HostsApplyResult: Equatable, Sendable {
    public let backupURL: URL?
    public let resolverFailed: Bool
    public let resolverMessage: String?
    public init(backupURL: URL?, resolverFailed: Bool, resolverMessage: String? = nil) {
        self.backupURL = backupURL
        self.resolverFailed = resolverFailed
        self.resolverMessage = resolverMessage
    }
}

public final class HostsApplier: @unchecked Sendable {
    private let runner: PrivilegedRunner
    private let backupsDir: URL
    private let fileManager: FileManager

    public init(
        runner: PrivilegedRunner,
        backupsDir: URL,
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.backupsDir = backupsDir
        self.fileManager = fileManager
    }

    /// `backupURL` is nil when the post-commit copy-out failed (apply succeeded, no rollback snapshot exists).
    @discardableResult
    public func apply(
        stagedURL: URL, resolverWrites: [ResolverWrite] = [], resolverRemovals: [String] = []
    ) throws -> HostsApplyResult {
        try fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        // Rethrows on privileged failure — /etc/hosts untouched, no backup created.
        let result = try runner.apply(ApplyRequest(
            stagedPath: stagedURL.path, resolverWrites: resolverWrites, resolverRemovals: resolverRemovals))
        // Per-apply UUID: unpredictable path so a local attacker can't pre-plant a symlink to redirect a write.
        let backupURL = backupsDir.appendingPathComponent("etc-hosts-\(UUID().uuidString).bak", isDirectory: false)
        do {
            try fileManager.copyItem(at: URL(fileURLWithPath: result.snapshotPath), to: backupURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        } catch {
            // Apply already committed, so copy-out failure must not throw. Remove any partial/mis-permissioned copy; return nil and skip pruning so existing real backups survive.
            try? fileManager.removeItem(at: backupURL)
            return HostsApplyResult(backupURL: nil, resolverFailed: result.resolverFailed, resolverMessage: result.message)
        }
        pruneBackups(keeping: backupURL)
        return HostsApplyResult(
            backupURL: backupURL, resolverFailed: result.resolverFailed, resolverMessage: result.message)
    }

    // `current` is excluded from deletion regardless of mtime so a future-dated older backup can't evict it. Skips symlinks (incl. the dir itself).
    private func pruneBackups(keeping current: URL) {
        guard !((try? backupsDir.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true) else {
            return
        }
        let contents = (try? fileManager.contentsOfDirectory(
            at: backupsDir, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey],
            options: .skipsHiddenFiles)) ?? []
        let baks = contents.filter {
            let name = $0.lastPathComponent
            return name.hasPrefix("etc-hosts-") && name.hasSuffix(".bak")
                && $0.standardizedFileURL != current.standardizedFileURL
                && !((try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true)
        }
        let sorted = baks.sorted {
            let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return d0 > d1
        }
        for old in sorted.dropFirst(2) {
            try? fileManager.removeItem(at: old)
        }
    }
}
