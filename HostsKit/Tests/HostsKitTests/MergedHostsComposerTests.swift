import Testing
import Foundation
@testable import HostsKit

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("hsk-merge-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

@Test func compose_localFirst_thenSourceWithHeader() throws {
    let dir = tempDir()
    let cache = dir.appendingPathComponent("s1.hosts")
    try "0.0.0.0 ads.example.com\n0.0.0.0 t.example.net\n".write(to: cache, atomically: true, encoding: .utf8)
    let out = dir.appendingPathComponent("merged.hosts")
    let composer = MergedHostsComposer()
    let stats = try composer.compose(
        localContent: "127.0.0.1 dev.local",
        localFragments: [],
        sources: [SourceLayer(name: "My List", cacheURL: cache, expectedHash: nil)],
        to: out)

    let merged = try String(contentsOf: out, encoding: .utf8)
    #expect(merged == "127.0.0.1 dev.local\n# My List\n0.0.0.0 ads.example.com\n0.0.0.0 t.example.net\n")
    #expect(stats.totalDomains == 2)
    #expect(stats.perSource == [SourceStat(name: "My List", domains: 2)])
}

@Test func compose_noSources_writesLocalOnly() throws {
    let dir = tempDir()
    let out = dir.appendingPathComponent("merged.hosts")
    let stats = try MergedHostsComposer().compose(localContent: "127.0.0.1 localhost\n", localFragments: [], sources: [], to: out)
    #expect(try String(contentsOf: out, encoding: .utf8) == "127.0.0.1 localhost\n")
    #expect(stats.totalDomains == 0)
    #expect(stats.perSource.isEmpty)
}

@Test func compose_emptyLocal_startsWithFirstSource() throws {
    let dir = tempDir()
    let cache = dir.appendingPathComponent("s1.hosts")
    try "0.0.0.0 a.example.com\n".write(to: cache, atomically: true, encoding: .utf8)
    let out = dir.appendingPathComponent("merged.hosts")
    let stats = try MergedHostsComposer().compose(
        localContent: "", localFragments: [], sources: [SourceLayer(name: "L", cacheURL: cache, expectedHash: nil)], to: out)
    #expect(try String(contentsOf: out, encoding: .utf8) == "# L\n0.0.0.0 a.example.com\n")
    #expect(stats.totalDomains == 1)
}

@Test func compose_missingCacheFile_throws() throws {
    let dir = tempDir()
    let missing = dir.appendingPathComponent("nope.hosts")
    let out = dir.appendingPathComponent("merged.hosts")
    let composer = MergedHostsComposer()
    #expect(throws: (any Error).self) {
        try composer.compose(localContent: "127.0.0.1 localhost", localFragments: [], sources: [SourceLayer(name: "Gone", cacheURL: missing, expectedHash: nil)], to: out)
    }
}

@Test func composer_sanitizesNewlineInSourceName_noInjectedMapping() throws {
    let tmp = FileManager.default.temporaryDirectory
    let cache = tmp.appendingPathComponent("hsk-src-\(UUID().uuidString).hosts")
    try "0.0.0.0 ads.example\n".write(to: cache, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: cache) }
    let out = tmp.appendingPathComponent("hsk-merged-\(UUID().uuidString).hosts")
    defer { try? FileManager.default.removeItem(at: out) }

    let composer = MergedHostsComposer()
    // A malicious name with an embedded newline + host mapping must NOT break out of the comment line.
    _ = try composer.compose(localContent: "",
                             localFragments: [],
                             sources: [SourceLayer(name: "Evil\n0.0.0.0 bank.example", cacheURL: cache, expectedHash: nil)],
                             to: out)
    let merged = try String(contentsOf: out, encoding: .utf8)
    // The injected mapping must remain inside a single comment line, never as a live host entry.
    for line in merged.split(separator: "\n") where line.contains("bank.example") {
        #expect(line.hasPrefix("#"))   // stays commented, not an active 0.0.0.0 mapping
    }
}

@Test func compose_cacheHashMismatch_throwsAndMatchPasses() throws {
    let dir = tempDir()
    let cache = dir.appendingPathComponent("s.hosts")
    let bytes = "0.0.0.0 a.example\n"
    try bytes.write(to: cache, atomically: true, encoding: .utf8)
    let goodHash = SourceHash.hex(Data(bytes.utf8))
    let out = dir.appendingPathComponent("merged.hosts")
    let composer = MergedHostsComposer()

    // Matching checksum composes fine.
    _ = try composer.compose(localContent: "", localFragments: [], sources: [SourceLayer(name: "S", cacheURL: cache, expectedHash: goodHash)], to: out)
    #expect(try String(contentsOf: out, encoding: .utf8).contains("0.0.0.0 a.example"))

    // A wrong checksum (cache modified/corrupted since refresh) must fail closed before /etc/hosts.
    #expect(throws: ComposeError.cacheHashMismatch("S")) {
        try composer.compose(localContent: "", localFragments: [], sources: [SourceLayer(name: "S", cacheURL: cache, expectedHash: "deadbeef")], to: out)
    }
}

@Test func fragmentsWrittenBetweenLocalAndSources() throws {
    let composer = MergedHostsComposer()
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hosts")
    defer { try? FileManager.default.removeItem(at: temp) }

    // One cached source on disk.
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hosts")
    try "0.0.0.0 source.example\n".write(to: cache, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: cache) }

    let stats = try composer.compose(
        localContent: "127.0.0.1 local.example",
        localFragments: [NamedContent(name: "Frag A", content: "0.0.0.0 frag.example")],
        sources: [SourceLayer(name: "Src", cacheURL: cache, expectedHash: nil)],
        to: temp)

    let out = try String(contentsOf: temp, encoding: .utf8)
    let localIdx = out.range(of: "local.example")!.lowerBound
    let fragHdrIdx = out.range(of: "# Frag A")!.lowerBound
    let fragIdx = out.range(of: "frag.example")!.lowerBound
    let srcIdx = out.range(of: "source.example")!.lowerBound
    #expect(localIdx < fragHdrIdx)
    #expect(fragHdrIdx < fragIdx)
    #expect(fragIdx < srcIdx)
    // Fragment stats precede source stats.
    #expect(stats.perSource.map(\.name) == ["Frag A", "Src"])
    #expect(stats.perSource.first?.domains == 1)
}

@Test func fragmentNameCRLFSanitizedInHeader() throws {
    let composer = MergedHostsComposer()
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hosts")
    defer { try? FileManager.default.removeItem(at: temp) }
    _ = try composer.compose(
        localContent: "",
        localFragments: [NamedContent(name: "Evil\n0.0.0.0 injected", content: "0.0.0.0 ok.example")],
        sources: [],
        to: temp)
    let out = try String(contentsOf: temp, encoding: .utf8)
    // The newline in the name must not start a new line; it's collapsed to a space inside the comment.
    #expect(out.contains("# Evil 0.0.0.0 injected"))
    #expect(!out.contains("\n0.0.0.0 injected"))
}

@Test func emptyFragmentsBehaveLikeBefore() throws {
    let composer = MergedHostsComposer()
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hosts")
    defer { try? FileManager.default.removeItem(at: temp) }
    let stats = try composer.compose(localContent: "127.0.0.1 a", localFragments: [], sources: [], to: temp)
    let out = try String(contentsOf: temp, encoding: .utf8)
    #expect(out == "127.0.0.1 a\n")
    #expect(stats.perSource.isEmpty)
}
