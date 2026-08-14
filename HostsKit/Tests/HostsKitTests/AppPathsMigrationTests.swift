import Foundation
import Testing
@testable import HostsKit

private func makeBase() throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("hsk-migration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

private func seedLegacy(_ base: URL, contents: String = "legacy") throws -> URL {
    let legacy = base.appendingPathComponent(AppPaths.legacySupportDirName, isDirectory: true)
    try FileManager.default.createDirectory(at: legacy.appendingPathComponent(AppPaths.profilesDirName),
                                            withIntermediateDirectories: true)
    try contents.write(to: legacy.appendingPathComponent(AppPaths.profilesMetadataName),
                       atomically: true, encoding: .utf8)
    return legacy
}

@Test func resolve_freshInstall_usesCurrentName() throws {
    let base = try makeBase()
    defer { try? FileManager.default.removeItem(at: base) }

    let root = AppPaths.resolveSupportRoot(base: base)

    #expect(root.lastPathComponent == "Hosts Switchr")
}

@Test func resolve_copiesLegacyStoreAcross() throws {
    let base = try makeBase()
    defer { try? FileManager.default.removeItem(at: base) }
    _ = try seedLegacy(base, contents: "the real profiles")

    let root = AppPaths.resolveSupportRoot(base: base)

    #expect(root.lastPathComponent == "Hosts Switchr")
    let copied = try String(contentsOf: AppPaths.profilesMetadata(root: root), encoding: .utf8)
    #expect(copied == "the real profiles")
    #expect(FileManager.default.fileExists(atPath: AppPaths.profilesDir(root: root).path))
}

@Test func resolve_leavesLegacyDirectoryInPlace() throws {
    let base = try makeBase()
    defer { try? FileManager.default.removeItem(at: base) }
    let legacy = try seedLegacy(base)

    _ = AppPaths.resolveSupportRoot(base: base)

    #expect(FileManager.default.fileExists(atPath: legacy.path))
    #expect(FileManager.default.fileExists(atPath: AppPaths.profilesMetadata(root: legacy).path))
}

@Test func resolve_doesNotRecopyOverAnExistingStore() throws {
    let base = try makeBase()
    defer { try? FileManager.default.removeItem(at: base) }
    _ = try seedLegacy(base, contents: "stale legacy")
    let current = base.appendingPathComponent(AppPaths.supportDirName, isDirectory: true)
    try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
    try "current".write(to: AppPaths.profilesMetadata(root: current), atomically: true, encoding: .utf8)

    let root = AppPaths.resolveSupportRoot(base: base)

    #expect(root == current)
    let kept = try String(contentsOf: AppPaths.profilesMetadata(root: root), encoding: .utf8)
    #expect(kept == "current")
}

@Test func resolve_fallsBackToLegacyWhenCopyFails() throws {
    let base = try makeBase()
    let legacy = try seedLegacy(base)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: base.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        try? FileManager.default.removeItem(at: base)
    }

    let root = AppPaths.resolveSupportRoot(base: base)

    #expect(root == legacy)
}

@Test func resolve_leavesNoPartialStoreWhenCopyFails() throws {
    let base = try makeBase()
    _ = try seedLegacy(base)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: base.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        try? FileManager.default.removeItem(at: base)
    }

    _ = AppPaths.resolveSupportRoot(base: base)

    let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
    #expect(names == [AppPaths.legacySupportDirName])
}
