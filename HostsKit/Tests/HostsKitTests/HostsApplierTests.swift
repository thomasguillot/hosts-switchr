import Testing
import Foundation
@testable import HostsKit

final class MockRunner: PrivilegedRunner, @unchecked Sendable {
    var received: ApplyRequest?
    /// When set, throw BEFORE creating/returning a snapshot — simulates a privileged apply failure
    /// (the real chain failed, /etc/hosts untouched, no snapshot produced).
    var shouldThrow: Error?
    /// Content the mock writes into the snapshot temp file it creates per apply.
    var snapshotContent = "simulated-snapshot"
    /// When true, return a path to a snapshot file that does NOT exist, so HostsApplier's copy-out
    /// throws — simulates a committed privileged apply whose post-commit copy-out fails.
    var returnMissingSnapshot = false
    /// Paths of snapshot temp files this mock created (so tests can inspect/clean them).
    private(set) var snapshotPaths: [String] = []

    func apply(_ request: ApplyRequest) throws -> String {
        received = request
        if let shouldThrow { throw shouldThrow }
        if returnMissingSnapshot {
            // A path the runner "committed" to but whose file was never created — copy-out will throw.
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("missing-snap-\(UUID().uuidString)").path
        }
        // The real runner snapshots /etc/hosts into a root-owned temp inside /etc and returns its
        // path; the mock emulates that with a real file in a test temp dir so copy-out can read it.
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-\(UUID().uuidString)").path
        try Data(snapshotContent.utf8).write(to: URL(fileURLWithPath: path))
        snapshotPaths.append(path)
        return path
    }
}

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("apply-\(UUID().uuidString)", isDirectory: true)
}

@Test func applier_buildsRequestWithStagedPathAndReturnsBackupURL() throws {
    let runner = MockRunner()
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let staged = dir.appendingPathComponent("staged.hosts")
    try "127.0.0.1 localhost".write(to: staged, atomically: true, encoding: .utf8)
    let applier = HostsApplier(runner: runner, backupsDir: dir)

    let backupURL = try #require(try applier.apply(stagedURL: staged))

    #expect(runner.received?.stagedPath == staged.path)
    #expect(backupURL.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
    #expect(backupURL.lastPathComponent.hasPrefix("etc-hosts-"))
    #expect(backupURL.pathExtension == "bak")
}

@Test func applier_backupContentsEqualSnapshot() throws {
    let runner = MockRunner()
    runner.snapshotContent = "snapshot-of-etc-hosts-at-commit-time"
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let staged = dir.appendingPathComponent("staged.hosts")
    try "127.0.0.1 localhost".write(to: staged, atomically: true, encoding: .utf8)
    let applier = HostsApplier(runner: runner, backupsDir: dir)

    let backupURL = try #require(try applier.apply(stagedURL: staged))

    let contents = try String(contentsOf: backupURL, encoding: .utf8)
    #expect(contents == "snapshot-of-etc-hosts-at-commit-time")
}

@Test func applier_backupFileIs0600() throws {
    let runner = MockRunner()
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let staged = dir.appendingPathComponent("staged.hosts")
    try "127.0.0.1 localhost".write(to: staged, atomically: true, encoding: .utf8)
    let applier = HostsApplier(runner: runner, backupsDir: dir)

    let backupURL = try #require(try applier.apply(stagedURL: staged))

    let perms = try FileManager.default.attributesOfItem(atPath: backupURL.path)[.posixPermissions] as? NSNumber
    #expect(perms?.intValue == 0o600)
}

@Test func applier_usesUniqueBackupPathPerApply() throws {
    let runner = MockRunner()
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let staged = dir.appendingPathComponent("staged.hosts")
    try "127.0.0.1 localhost".write(to: staged, atomically: true, encoding: .utf8)
    let applier = HostsApplier(runner: runner, backupsDir: dir)

    let b1 = try #require(try applier.apply(stagedURL: staged))
    let b2 = try #require(try applier.apply(stagedURL: staged))

    #expect(b1 != b2)
    #expect(b1.lastPathComponent.hasPrefix("etc-hosts-"))
    #expect(b1.pathExtension == "bak")
}

@Test func applier_pruneKeepsCurrentBackupEvenWhenOlderBackupsHaveFutureDates() throws {
    let runner = MockRunner()
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let staged = dir.appendingPathComponent("staged.hosts")
    try "127.0.0.1 localhost".write(to: staged, atomically: true, encoding: .utf8)

    // Plant 3 pre-existing .bak files with a future modification date so they sort ahead of the
    // new backup by mtime, filling the 3-keep slots before the new backup is considered.
    let future = Date().addingTimeInterval(86400 * 365)
    for i in 1...3 {
        let url = dir.appendingPathComponent("etc-hosts-OLD\(i).bak")
        try Data("old\(i)".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: url.path)
    }

    let applier = HostsApplier(runner: runner, backupsDir: dir)
    let backupURL = try #require(try applier.apply(stagedURL: staged))

    #expect(FileManager.default.fileExists(atPath: backupURL.path))
    let remaining = (try FileManager.default.contentsOfDirectory(atPath: dir.path))
        .filter { $0.hasPrefix("etc-hosts-") && $0.hasSuffix(".bak") }
    #expect(remaining.count == 3)
}

@Test func applier_propagatesRunnerErrorAndCreatesNoBackup() throws {
    let runner = MockRunner()
    runner.shouldThrow = ProfileError.notFound
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let staged = dir.appendingPathComponent("staged.hosts")
    try "x".write(to: staged, atomically: true, encoding: .utf8)
    let applier = HostsApplier(runner: runner, backupsDir: dir)

    #expect(throws: ProfileError.self) { _ = try applier.apply(stagedURL: staged) }

    let baks = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
        .filter { $0.hasPrefix("etc-hosts-") && $0.hasSuffix(".bak") } ?? []
    #expect(baks.isEmpty)
}

@Test func applier_returnsNilAndDoesNotPruneWhenCopyOutFails() throws {
    let runner = MockRunner()
    runner.returnMissingSnapshot = true   // committed apply, but the snapshot file is absent
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let staged = dir.appendingPathComponent("staged.hosts")
    try "127.0.0.1 localhost".write(to: staged, atomically: true, encoding: .utf8)

    // Pre-existing backups must survive: pruning happens only when a real new backup exists.
    for i in 1...4 {
        try Data("old\(i)".utf8).write(to: dir.appendingPathComponent("etc-hosts-OLD\(i).bak"))
    }
    let applier = HostsApplier(runner: runner, backupsDir: dir)

    let result = try applier.apply(stagedURL: staged)

    #expect(result == nil)
    let baks = (try FileManager.default.contentsOfDirectory(atPath: dir.path))
        .filter { $0.hasPrefix("etc-hosts-") && $0.hasSuffix(".bak") }
    #expect(baks.count == 4)
}
