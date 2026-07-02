import Testing
import Foundation
@testable import HostsKit

private func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("hsk-cat-\(UUID().uuidString)", isDirectory: true)
}

@Test func builtins_includeStevenBlackAlternatesAllHttpsUniqueIds() {
    for s in BuiltinSources.all {
        #expect(s.url.scheme == "https")
        #expect(s.kind == .builtin)
    }
    let names = Set(BuiltinSources.all.map(\.name))
    #expect(names.isSuperset(of: ["StevenBlack (Fake News)", "StevenBlack (Gambling)",
                                  "StevenBlack (Porn)", "StevenBlack (Social)"]))
    #expect(Set(BuiltinSources.all.map(\.id)).count == BuiltinSources.all.count)
}

@Test func builtins_includeHaGeZiLadderInOrder() {
    let names = BuiltinSources.all.map(\.name)
    let hagezi = names.filter { $0.hasPrefix("HaGeZi") }
    #expect(hagezi == ["HaGeZi Light", "HaGeZi Normal", "HaGeZi Pro", "HaGeZi Pro++", "HaGeZi Ultimate"])
}

@Test func catalog_ordersBuiltinsCanonicallyThenCustoms() throws {
    let root = tempRoot()
    try FileManager.default.createDirectory(at: AppPaths.sourcesDir(root: root), withIntermediateDirectories: true)
    let custom = RemoteSource(id: UUID(), name: "Custom",
                              url: URL(string: "https://example.com/h.txt")!, kind: .custom)
    // Scrambled on-disk order: last builtin, a custom, then the first builtin.
    let pre = [BuiltinSources.all[BuiltinSources.all.count - 1], custom, BuiltinSources.all[0]]
    try JSONEncoder().encode(pre).write(to: AppPaths.sourcesMetadata(root: root))

    let c = try SourceCatalog(root: root)
    let builtinNames = c.sources.filter { $0.kind == .builtin }.map(\.name)
    #expect(builtinNames == BuiltinSources.all.map(\.name))   // canonical built-in order
    #expect(c.sources.last?.id == custom.id)                  // customs after builtins
}

@Test func catalog_seedsBuiltinsOnce() throws {
    let root = tempRoot()
    let c = try SourceCatalog(root: root)
    let builtinCount = c.sources.filter { $0.kind == .builtin }.count
    #expect(builtinCount == BuiltinSources.all.count)
    let reopened = try SourceCatalog(root: root)
    #expect(reopened.sources.filter { $0.kind == .builtin }.count == builtinCount) // no double seed
}

@Test func catalog_addAndRemoveCustom() throws {
    let root = tempRoot()
    let c = try SourceCatalog(root: root)
    let s = try c.addCustom(name: "My List", urlString: "https://example.com/hosts.txt")
    #expect(s.kind == .custom)
    #expect(c.sources.contains { $0.id == s.id })
    try c.remove(s.id)
    #expect(!c.sources.contains { $0.id == s.id })
}

@Test func catalog_removeBuiltin_throws() throws {
    let c = try SourceCatalog(root: tempRoot())
    let builtin = c.sources.first { $0.kind == .builtin }!
    #expect(throws: SourceError.self) { try c.remove(builtin.id) }
}

@Test func catalog_addCustom_invalidURL_throws() throws {
    let c = try SourceCatalog(root: tempRoot())
    #expect(throws: SourceError.self) { _ = try c.addCustom(name: "Bad", urlString: "not a url") }
}

@Test func catalog_addCustom_httpURL_throwsInsecure() throws {
    let c = try SourceCatalog(root: tempRoot())
    #expect(throws: SourceError.insecureURL) {
        _ = try c.addCustom(name: "Insecure", urlString: "http://example.com/hosts.txt")
    }
}

@Test func catalog_addCustom_httpsURL_succeeds() throws {
    let c = try SourceCatalog(root: tempRoot())
    let s = try c.addCustom(name: "Secure", urlString: "https://example.com/hosts.txt")
    #expect(s.kind == .custom)
    #expect(s.url.scheme == "https")
}

@Test func catalog_corruptMetadata_isPreservedNotOverwritten() throws {
    let root = tempRoot()
    try FileManager.default.createDirectory(at: AppPaths.sourcesDir(root: root), withIntermediateDirectories: true)
    let metaURL = AppPaths.sourcesMetadata(root: root)
    try "{ this is not valid json ".write(to: metaURL, atomically: true, encoding: .utf8)
    let c = try SourceCatalog(root: root)
    #expect(c.loadedCorruptMetadata == true)
    #expect(c.sources.filter { $0.kind == .builtin }.count == BuiltinSources.all.count)
    let corruptURL = metaURL.appendingPathExtension("corrupt")
    #expect(FileManager.default.fileExists(atPath: corruptURL.path))
    #expect(try String(contentsOf: corruptURL, encoding: .utf8).contains("not valid json"))
}

@Test func catalog_update_persistsFetchState() throws {
    let root = tempRoot()
    let c = try SourceCatalog(root: root)
    var s = c.sources.first { $0.kind == .builtin }!
    s.etag = "abc"; s.domainCount = 42; s.lastError = nil
    try c.update(s)
    let reopened = try SourceCatalog(root: root)
    let reloaded = reopened.source(for: s.id)
    #expect(reloaded?.etag == "abc")
    #expect(reloaded?.domainCount == 42)
}

@Test func catalog_dropsOrphanBuiltins() throws {
    let root = tempRoot()
    try FileManager.default.createDirectory(at: AppPaths.sourcesDir(root: root), withIntermediateDirectories: true)
    let adaway = UUID(uuidString: "00000000-0000-0000-0000-0000000000B8")!   // formerly AdAway, now removed
    let orphan = UUID(uuidString: "00000000-0000-0000-0000-0000000000B9")!
    // Pre-existing sources.json: an old AdAway built-in and an arbitrary orphan — both no longer canonical.
    let stale = [
        RemoteSource(id: adaway, name: "AdAway",
                     url: URL(string: "https://adaway.org/hosts.txt")!,
                     kind: .builtin, contentHash: "deadbeef", domainCount: 6541),
        RemoteSource(id: orphan, name: "Removed Builtin",
                     url: URL(string: "https://example.com/old.txt")!, kind: .builtin),
    ]
    try JSONEncoder().encode(stale).write(to: AppPaths.sourcesMetadata(root: root))

    let c = try SourceCatalog(root: root)
    #expect(c.source(for: adaway) == nil)         // AdAway removed from built-ins
    #expect(c.source(for: orphan) == nil)         // orphan built-in removed
    #expect(c.sources.filter { $0.kind == .builtin }.count == BuiltinSources.all.count)
}

@Test func sourceHash_isStableLowercaseHexSHA256() {
    // Known SHA-256 of "abc".
    let h = SourceHash.hex(Data("abc".utf8))
    #expect(h == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func urlPolicyAcceptsHTTPSRejectsHTTPAndJunk() {
    #expect((try? SourceURLPolicy.validated("https://example.com/h.txt")) != nil)
    #expect(throws: SourceError.insecureURL) { try SourceURLPolicy.validated("http://example.com/h.txt") }
    #expect(throws: SourceError.invalidURL) { try SourceURLPolicy.validated("not a url") }
}

@Test func catalogAddPreservesIDAndRejectsInsecure() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let catalog = try SourceCatalog(root: tmp)
    let id = UUID()
    try catalog.add(RemoteSource(id: id, name: "X", url: URL(string: "https://e.com/h")!, kind: .custom))
    #expect(catalog.source(for: id) != nil)
    #expect(throws: SourceError.insecureURL) {
        try catalog.add(RemoteSource(id: UUID(), name: "Y", url: URL(string: "http://e.com/h")!, kind: .custom))
    }
}

@Test func catalog_reorderCustoms_persistsAcrossReload() throws {
    let root = tempRoot()
    let c = try SourceCatalog(root: root)
    let s1 = try c.addCustom(name: "One", urlString: "https://example.com/1.txt")
    let s2 = try c.addCustom(name: "Two", urlString: "https://example.com/2.txt")

    try c.reorderCustoms([s2.id, s1.id])
    #expect(c.sources.filter { $0.kind == .custom }.map(\.id) == [s2.id, s1.id])
    #expect(c.sources.filter { $0.kind == .builtin }.map(\.id) == BuiltinSources.all.map(\.id))
    #expect(c.sources.prefix(BuiltinSources.all.count).allSatisfy { $0.kind == .builtin })

    let reopened = try SourceCatalog(root: root)
    #expect(reopened.sources.filter { $0.kind == .custom }.map(\.id) == [s2.id, s1.id])
}

@Test func catalog_reorderCustoms_ignoresBuiltinAndUnknownIDs() throws {
    let c = try SourceCatalog(root: tempRoot())
    let s1 = try c.addCustom(name: "One", urlString: "https://example.com/1.txt")
    let s2 = try c.addCustom(name: "Two", urlString: "https://example.com/2.txt")

    try c.reorderCustoms([BuiltinSources.all[0].id, UUID(), s2.id, s1.id])
    #expect(c.sources.filter { $0.kind == .builtin }.map(\.id) == BuiltinSources.all.map(\.id))
    #expect(c.sources.filter { $0.kind == .custom }.map(\.id) == [s2.id, s1.id])
    #expect(c.sources.prefix(BuiltinSources.all.count).allSatisfy { $0.kind == .builtin })
}

@Test func catalog_reorderCustoms_keepsOmittedCustomsInExistingOrder() throws {
    let c = try SourceCatalog(root: tempRoot())
    let s1 = try c.addCustom(name: "One", urlString: "https://example.com/1.txt")
    let s2 = try c.addCustom(name: "Two", urlString: "https://example.com/2.txt")
    let s3 = try c.addCustom(name: "Three", urlString: "https://example.com/3.txt")

    try c.reorderCustoms([s3.id])
    #expect(c.sources.filter { $0.kind == .custom }.map(\.id) == [s3.id, s1.id, s2.id])
}
