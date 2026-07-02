import Testing
import Foundation
@testable import HostsKit

@Test func profile_codableRoundTrips() throws {
    let p = Profile(name: "Dev", content: "127.0.0.1 dev.local", isProtected: false)
    let data = try JSONEncoder().encode(p)
    let decoded = try JSONDecoder().decode(Profile.self, from: data)
    #expect(decoded == p)
}

private func tempRoot() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hsk-\(UUID().uuidString)", isDirectory: true)
    return dir
}

@Test func store_createReadPersist() throws {
    let root = tempRoot()
    let store = try ProfileStore(root: root)
    let p = try store.create(name: "Dev", content: "127.0.0.1 dev.local")
    #expect(store.profiles.contains { $0.id == p.id })

    let reopened = try ProfileStore(root: root)
    #expect(reopened.profiles.contains { $0.name == "Dev" })
}

@Test func store_duplicate_copiesContentWithNewName() throws {
    let store = try ProfileStore(root: tempRoot())
    let original = try store.create(name: "Dev", content: "10.0.0.1 a.local")
    let copy = try store.duplicate(original.id)
    #expect(copy.id != original.id)
    #expect(copy.content == original.content)
    #expect(copy.name.contains("Dev"))
}

@Test func store_deleteProtected_throws() throws {
    let store = try ProfileStore(root: tempRoot())
    try store.seedSystemDefaultIfEmpty(currentHosts: "127.0.0.1 localhost")
    let def = store.profiles.first { $0.isProtected }!
    #expect(throws: ProfileError.self) { try store.delete(def.id) }
}

@Test func store_seedOnlyWhenEmpty() throws {
    let store = try ProfileStore(root: tempRoot())
    try store.seedSystemDefaultIfEmpty(currentHosts: "127.0.0.1 localhost")
    let count = store.profiles.count
    try store.seedSystemDefaultIfEmpty(currentHosts: "different")
    #expect(store.profiles.count == count)   // no second seed
}

@Test func store_setActive_persists() throws {
    let root = tempRoot()
    let store = try ProfileStore(root: root)
    let p = try store.create(name: "Dev", content: "x")
    store.setActive(p.id)
    try store.save()
    let reopened = try ProfileStore(root: root)
    #expect(reopened.activeProfileID == p.id)
}

@Test func store_update_persistsContent() throws {
    let root = tempRoot()
    let store = try ProfileStore(root: root)
    var p = try store.create(name: "Dev", content: "old")
    p.content = "new"
    try store.update(p)
    let reopened = try ProfileStore(root: root)
    #expect(reopened.profiles.first { $0.id == p.id }?.content == "new")
}

@Test func store_rename_persistsName() throws {
    let root = tempRoot()
    let store = try ProfileStore(root: root)
    let p = try store.create(name: "Dev", content: "x")
    try store.rename(p.id, to: "Renamed")
    let reopened = try ProfileStore(root: root)
    #expect(reopened.profiles.first { $0.id == p.id }?.name == "Renamed")
}

@Test func store_order_persists() throws {
    let root = tempRoot()
    let store = try ProfileStore(root: root)
    let a = try store.create(name: "A", content: "a")
    let b = try store.create(name: "B", content: "b")
    let reopened = try ProfileStore(root: root)
    #expect(reopened.profiles.map(\.id) == [a.id, b.id])
}

@Test func store_setActiveNil_clearsAndPersists() throws {
    let root = tempRoot()
    let store = try ProfileStore(root: root)
    let p = try store.create(name: "Dev", content: "x")
    store.setActive(p.id); try store.save()
    store.setActive(nil); try store.save()
    let reopened = try ProfileStore(root: root)
    #expect(reopened.activeProfileID == nil)
}

@Test func store_sourceIDs_persistAcrossReopen() throws {
    let root = tempRoot()
    let store = try ProfileStore(root: root)
    let p = try store.create(name: "Work", content: "127.0.0.1 dev.local")
    let s1 = UUID(); let s2 = UUID()
    try store.setSources(p.id, [s1, s2])
    let reopened = try ProfileStore(root: root)
    let reloaded = reopened.profiles.first { $0.id == p.id }
    #expect(reloaded?.sourceIDs == [s1, s2])
}

@Test func store_migratesOldMetadata_missingSourceIDs_toEmpty() throws {
    let root = tempRoot()
    try FileManager.default.createDirectory(
        at: AppPaths.profilesDir(root: root), withIntermediateDirectories: true)
    let id = UUID()
    try "127.0.0.1 localhost".write(
        to: AppPaths.profilesDir(root: root).appendingPathComponent("\(id.uuidString).hosts"),
        atomically: true, encoding: .utf8)
    // Old M1 profiles.json: ProfileMeta with NO sourceIDs key.
    let json = """
    {"order":["\(id.uuidString)"],"activeProfileID":null,"profiles":{"\(id.uuidString)":{"name":"Legacy","createdAt":0,"updatedAt":0,"isProtected":true}}}
    """
    try json.write(to: AppPaths.profilesMetadata(root: root), atomically: true, encoding: .utf8)
    let store = try ProfileStore(root: root)
    let loaded = store.profiles.first { $0.id == id }
    #expect(loaded?.name == "Legacy")
    #expect(loaded?.sourceIDs == [])
}

@Test func store_removeSourceFromAllProfiles_prunesAndPersists() throws {
    let root = tempRoot()
    let store = try ProfileStore(root: root)
    let shared = UUID()
    let other = UUID()
    let p1 = try store.create(name: "A", content: "x")
    let p2 = try store.create(name: "B", content: "y")
    try store.setSources(p1.id, [shared, other])
    try store.setSources(p2.id, [shared])
    try store.removeSourceFromAllProfiles(shared)
    #expect(!store.profiles.first { $0.id == p1.id }!.sourceIDs.contains(shared))
    #expect(!store.profiles.first { $0.id == p2.id }!.sourceIDs.contains(shared))
    #expect(store.profiles.first { $0.id == p1.id }!.sourceIDs.contains(other))
    let reopened = try ProfileStore(root: root)
    #expect(!reopened.profiles.first { $0.id == p1.id }!.sourceIDs.contains(shared))
    #expect(!reopened.profiles.first { $0.id == p2.id }!.sourceIDs.contains(shared))
    #expect(reopened.profiles.first { $0.id == p1.id }!.sourceIDs.contains(other))
}

@Test func store_duplicate_copiesSourceIDs() throws {
    let store = try ProfileStore(root: tempRoot())
    let p = try store.create(name: "Work", content: "x")
    let s = UUID()
    try store.setSources(p.id, [s])
    let copy = try store.duplicate(p.id)
    #expect(copy.sourceIDs == [s])
}

@Test func store_migratesRealM1ArrayShapedMetadata() throws {
    let root = tempRoot()
    try FileManager.default.createDirectory(at: AppPaths.profilesDir(root: root), withIntermediateDirectories: true)
    let id = UUID()
    try "127.0.0.1 localhost".write(
        to: AppPaths.profilesDir(root: root).appendingPathComponent("\(id.uuidString).hosts"),
        atomically: true, encoding: .utf8)
    // Reproduce M1's exact on-disk encoding: UUID-keyed dict (encodes as a JSON array), no sourceIDs.
    struct M1Meta: Encodable { var name: String; var createdAt: Date; var updatedAt: Date; var isProtected: Bool }
    struct M1Blob: Encodable { var order: [UUID]; var activeProfileID: UUID?; var profiles: [UUID: M1Meta] }
    let blob = M1Blob(order: [id], activeProfileID: id,
                      profiles: [id: M1Meta(name: "System Default", createdAt: Date(timeIntervalSince1970: 0),
                                            updatedAt: Date(timeIntervalSince1970: 0), isProtected: true)])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    try encoder.encode(blob).write(to: AppPaths.profilesMetadata(root: root))
    let store = try ProfileStore(root: root)
    let p = store.profiles.first { $0.id == id }
    #expect(p?.name == "System Default")
    #expect(p?.isProtected == true)
    #expect(p?.sourceIDs == [])
    #expect(store.activeProfileID == id)
}

@Test func store_delete_removesBackingFile() throws {
    let root = tempRoot()
    let store = try ProfileStore(root: root)
    let p = try store.create(name: "Dev", content: "127.0.0.1 dev.local")
    let backing = AppPaths.profilesDir(root: root).appendingPathComponent("\(p.id.uuidString).hosts")
    #expect(FileManager.default.fileExists(atPath: backing.path))

    try store.delete(p.id)
    #expect(!FileManager.default.fileExists(atPath: backing.path))   // file gone
    #expect(!store.profiles.contains { $0.id == p.id })              // profile gone

    // A reopened store must NOT resurrect a deleted profile from an orphan .hosts file.
    let reopened = try ProfileStore(root: root)
    #expect(!reopened.profiles.contains { $0.id == p.id })
}

@Test func store_corruptMetadata_isPreservedAndProfilesRecovered() throws {
    let root = tempRoot()
    try FileManager.default.createDirectory(at: AppPaths.profilesDir(root: root), withIntermediateDirectories: true)
    // A real .hosts file on disk, plus an unreadable profiles.json.
    let id = UUID()
    try "127.0.0.1 dev.local".write(
        to: AppPaths.profilesDir(root: root).appendingPathComponent("\(id.uuidString).hosts"),
        atomically: true, encoding: .utf8)
    let metaURL = AppPaths.profilesMetadata(root: root)
    try "{ not valid json ".write(to: metaURL, atomically: true, encoding: .utf8)

    let store = try ProfileStore(root: root)
    #expect(store.loadedCorruptMetadata == true)
    #expect(store.profiles.contains { $0.id == id })            // recovered from disk, not dropped
    // Original corrupt metadata preserved (not overwritten by the recovery save).
    let corruptURL = metaURL.appendingPathExtension("corrupt")
    #expect(FileManager.default.fileExists(atPath: corruptURL.path))
    #expect(try String(contentsOf: corruptURL, encoding: .utf8).contains("not valid json"))
}

@Test func appPaths_uniqueCorruptURL_doesNotClobberExistingRecoveryCopy() throws {
    let root = tempRoot()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let base = root.appendingPathComponent("profiles.json")
    let first = AppPaths.uniqueCorruptURL(for: base)
    #expect(first.lastPathComponent == "profiles.json.corrupt")
    try "older recovery copy".write(to: first, atomically: true, encoding: .utf8)
    let second = AppPaths.uniqueCorruptURL(for: base)
    #expect(second.lastPathComponent == "profiles.json.corrupt-1")   // avoids the existing copy
    #expect(try String(contentsOf: first, encoding: .utf8) == "older recovery copy")
}

@Test func store_partiallyCorruptMetadata_isPreservedNotSilentlyEmptied() throws {
    let root = tempRoot()
    try FileManager.default.createDirectory(at: AppPaths.profilesDir(root: root), withIntermediateDirectories: true)
    let id = UUID()
    try "127.0.0.1 dev.local".write(
        to: AppPaths.profilesDir(root: root).appendingPathComponent("\(id.uuidString).hosts"),
        atomically: true, encoding: .utf8)
    // Well-formed JSON, but one profile record is missing required fields (createdAt/updatedAt/...).
    // Under lenient decoding this would decode to empty and then be overwritten on save; the strict
    // decoder must treat it as corrupt and preserve it.
    let metaURL = AppPaths.profilesMetadata(root: root)
    let json = "{\"order\":[\"\(id.uuidString)\"],\"activeProfileID\":null,\"profiles\":{\"\(id.uuidString)\":{\"name\":\"X\"}}}"
    try json.write(to: metaURL, atomically: true, encoding: .utf8)

    let store = try ProfileStore(root: root)
    #expect(store.loadedCorruptMetadata == true)
    let corruptURL = metaURL.appendingPathExtension("corrupt")
    #expect(FileManager.default.fileExists(atPath: corruptURL.path))
    #expect(try String(contentsOf: corruptURL, encoding: .utf8).contains("\"name\":\"X\""))
    #expect(store.profiles.contains { $0.id == id })   // .hosts still recovered, not dropped
}

@Test func store_unreadableProfileFile_failsClosed_doesNotDrop() throws {
    let root = tempRoot()
    let dir = AppPaths.profilesDir(root: root)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let id = UUID()
    // A UUID-named .hosts whose bytes are not valid UTF-8 must abort init (fail closed), not be
    // silently skipped and then erased from metadata by the next save().
    let bad = dir.appendingPathComponent("\(id.uuidString).hosts")
    try Data([0xFF, 0xFE, 0xFF]).write(to: bad)
    #expect(throws: (any Error).self) { _ = try ProfileStore(root: root) }
}

@Test func profileFragmentIDsDefaultEmptyAndPersist() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try ProfileStore(root: tmp)
    let p = try store.create(name: "P", content: "x")
    #expect(p.fragmentIDs == [])
    let f1 = UUID(); let f2 = UUID()
    try store.setFragments(p.id, [f1, f2])
    // Reload from disk: fragmentIDs survive.
    let store2 = try ProfileStore(root: tmp)
    #expect(store2.profiles.first { $0.id == p.id }?.fragmentIDs == [f1, f2])
}

@Test func duplicateCopiesFragmentIDs() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try ProfileStore(root: tmp)
    let p = try store.create(name: "P", content: "x")
    let f = UUID()
    try store.setFragments(p.id, [f])
    let copy = try store.duplicate(p.id)
    #expect(copy.fragmentIDs == [f])
}

@Test func removeFragmentFromAllProfilesDropsIt() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try ProfileStore(root: tmp)
    let a = try store.create(name: "A", content: "")
    let b = try store.create(name: "B", content: "")
    let f = UUID()
    try store.setFragments(a.id, [f])
    try store.setFragments(b.id, [f])
    try store.removeFragmentFromAllProfiles(f)
    #expect(store.profiles.first { $0.id == a.id }?.fragmentIDs == [])
    #expect(store.profiles.first { $0.id == b.id }?.fragmentIDs == [])
}

@Test func storeAddPreservesIDRefsAndForcesUnprotected() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try ProfileStore(root: tmp)
    let id = UUID(); let sid = UUID(); let fid = UUID()
    try store.add(Profile(id: id, name: "Imported", content: "0.0.0.0 a", isProtected: true, sourceIDs: [sid], fragmentIDs: [fid]))
    let reloaded = try ProfileStore(root: tmp)
    let p = reloaded.profiles.first { $0.id == id }
    #expect(p?.sourceIDs == [sid])
    #expect(p?.fragmentIDs == [fid])
    #expect(p?.isProtected == false)   // add() never imports a protected profile
}

@Test func legacyProfileMetaWithoutFragmentIDsDecodesEmpty() throws {
    // A profiles.json written before this feature (no fragmentIDs key) must load with [].
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp.appendingPathComponent("profiles"), withIntermediateDirectories: true)
    let id = UUID()
    try "0.0.0.0 a".write(to: tmp.appendingPathComponent("profiles/\(id.uuidString).hosts"), atomically: true, encoding: .utf8)
    let legacy = """
    {"order":["\(id.uuidString)"],"activeProfileID":null,"profiles":{"\(id.uuidString)":{"name":"Old","createdAt":0,"updatedAt":0,"isProtected":false,"sourceIDs":[]}}}
    """
    try legacy.write(to: tmp.appendingPathComponent("profiles.json"), atomically: true, encoding: .utf8)
    let store = try ProfileStore(root: tmp)
    #expect(store.profiles.first { $0.id == id }?.fragmentIDs == [])
}

@Test func store_create_dedupesDuplicateNames() throws {
    let store = try ProfileStore(root: tempRoot())
    let a = try store.create(name: "untitled profile", content: "")
    let b = try store.create(name: "untitled profile", content: "")
    let c = try store.create(name: "untitled profile", content: "")
    #expect(a.name == "untitled profile")
    #expect(b.name == "untitled profile 2")
    #expect(c.name == "untitled profile 3")
}

@Test func store_rename_toExistingName_throwsDuplicate() throws {
    let store = try ProfileStore(root: tempRoot())
    _ = try store.create(name: "Dev", content: "")
    let other = try store.create(name: "Prod", content: "")
    #expect(throws: ProfileError.duplicateName) { try store.rename(other.id, to: "Dev") }
    #expect(throws: ProfileError.duplicateName) { try store.rename(other.id, to: "dev") }
}

@Test func store_rename_toOwnName_succeeds() throws {
    let store = try ProfileStore(root: tempRoot())
    let p = try store.create(name: "Dev", content: "")
    try store.rename(p.id, to: "Dev")
    #expect(store.profiles.first { $0.id == p.id }?.name == "Dev")
}

@Test func store_reorder_persistsAcrossReload() throws {
    let root = tempRoot()
    let store = try ProfileStore(root: root)
    try store.seedSystemDefaultIfEmpty(currentHosts: "127.0.0.1 localhost")
    let def = store.profiles.first { $0.isProtected }!
    let a = try store.create(name: "A", content: "")
    let b = try store.create(name: "B", content: "")

    try store.reorder([def.id, b.id, a.id])
    #expect(store.profiles.map(\.id) == [def.id, b.id, a.id])

    let reopened = try ProfileStore(root: root)
    #expect(reopened.profiles.map(\.id) == [def.id, b.id, a.id])
}

@Test func store_reorder_pinsProtectedFirst() throws {
    let root = tempRoot()
    let store = try ProfileStore(root: root)
    try store.seedSystemDefaultIfEmpty(currentHosts: "127.0.0.1 localhost")
    let def = store.profiles.first { $0.isProtected }!
    let a = try store.create(name: "A", content: "")
    let b = try store.create(name: "B", content: "")

    try store.reorder([a.id, b.id, def.id])
    #expect(store.profiles.map(\.id) == [def.id, a.id, b.id])

    let reopened = try ProfileStore(root: root)
    #expect(reopened.profiles.map(\.id) == [def.id, a.id, b.id])
}

@Test func store_reorder_ignoresUnknownAndAppendsOmittedByCreatedAt() throws {
    let store = try ProfileStore(root: tempRoot())
    let older = Profile(name: "Older", content: "", createdAt: Date(timeIntervalSince1970: 100))
    let newer = Profile(name: "Newer", content: "", createdAt: Date(timeIntervalSince1970: 200))
    try store.add(newer)
    try store.add(older)
    let kept = try store.create(name: "Kept", content: "")

    try store.reorder([UUID(), kept.id])
    #expect(store.profiles.map(\.id) == [kept.id, older.id, newer.id])
}
