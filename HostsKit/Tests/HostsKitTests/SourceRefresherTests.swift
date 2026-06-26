import Testing
import Foundation
@testable import HostsKit

private func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("hsk-ref-\(UUID().uuidString)", isDirectory: true)
}

/// Programmable fetcher: returns queued results per call.
struct ScriptedFetcher: SourceFetching {
    let make: @Sendable (RemoteSource) async throws -> FetchResult
    func fetch(_ source: RemoteSource) async throws -> FetchResult { try await make(source) }
}

private func writeTemp(_ text: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString).hosts")
    try? text.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func refresh_updated_swapsCacheAndRecordsState_changed() async throws {
    let catalog = try SourceCatalog(root: tempRoot())
    let id = catalog.sources.first { $0.kind == .builtin }!.id
    let fetcher = ScriptedFetcher { _ in
        .updated(tempURL: writeTemp("0.0.0.0 a.example.com\n"), etag: "v1", lastModified: nil, domainCount: 1)
    }
    let outcome = await SourceRefresher(fetcher: fetcher).refresh(id, in: catalog)
    #expect(outcome.kind == .updated)
    #expect(outcome.changed == true)
    #expect(catalog.source(for: id)?.etag == "v1")
    #expect(catalog.source(for: id)?.domainCount == 1)
    #expect(FileManager.default.fileExists(atPath: catalog.cacheURL(for: id).path))
}

@Test func refresh_sameContentTwice_secondNotChanged() async throws {
    let catalog = try SourceCatalog(root: tempRoot())
    let id = catalog.sources.first { $0.kind == .builtin }!.id
    let fetcher = ScriptedFetcher { _ in
        .updated(tempURL: writeTemp("0.0.0.0 a.example.com\n"), etag: nil, lastModified: nil, domainCount: 1)
    }
    let refresher = SourceRefresher(fetcher: fetcher)
    _ = await refresher.refresh(id, in: catalog)
    let second = await refresher.refresh(id, in: catalog)
    #expect(second.kind == .updated)
    #expect(second.changed == false) // identical bytes -> contentHash unchanged
}

@Test func refresh_notModified_recordsTimeNoChange() async throws {
    let catalog = try SourceCatalog(root: tempRoot())
    let id = catalog.sources.first { $0.kind == .builtin }!.id
    let fetcher = ScriptedFetcher { _ in .notModified }
    let outcome = await SourceRefresher(fetcher: fetcher).refresh(id, in: catalog)
    #expect(outcome.kind == .notModified)
    #expect(outcome.changed == false)
    #expect(catalog.source(for: id)?.lastFetchedAt != nil)
}

@Test func refresh_failure_recordsLastError_doesNotThrow() async throws {
    let catalog = try SourceCatalog(root: tempRoot())
    let id = catalog.sources.first { $0.kind == .builtin }!.id
    let fetcher = ScriptedFetcher { _ in throw SourceError.notHostsFormat }
    let outcome = await SourceRefresher(fetcher: fetcher).refresh(id, in: catalog)
    if case .failed = outcome.kind {} else { Issue.record("expected .failed") }
    #expect(catalog.source(for: id)?.lastError != nil)
}

@Test func refresh_missingCache_forcesUnconditionalGET() async throws {
    let catalog = try SourceCatalog(root: tempRoot())
    let id = catalog.sources.first { $0.kind == .builtin }!.id

    // Seed a source so it has an etag stored.
    let seeder = ScriptedFetcher { _ in
        .updated(tempURL: writeTemp("0.0.0.0 a.example.com\n"), etag: "v1", lastModified: nil, domainCount: 1)
    }
    _ = await SourceRefresher(fetcher: seeder).refresh(id, in: catalog)
    #expect(catalog.source(for: id)?.etag == "v1")

    // Delete the cache file, then refresh: the fetch must be unconditional (etag == nil).
    try FileManager.default.removeItem(at: catalog.cacheURL(for: id))
    let box = EtagBox()
    let recorder = ScriptedFetcher { source in
        await box.set(source.etag)
        return .updated(tempURL: writeTemp("0.0.0.0 b.example.com\n"), etag: "v2", lastModified: nil, domainCount: 1)
    }
    _ = await SourceRefresher(fetcher: recorder).refresh(id, in: catalog)
    #expect(await box.value == nil) // missing cache -> forced full GET, not a conditional 304-able request
}

@Test func refresh_missingCacheSameBytes_reportsChanged() async throws {
    let catalog = try SourceCatalog(root: tempRoot())
    let id = catalog.sources.first { $0.kind == .builtin }!.id

    // First refresh caches bytes so contentHash is stored.
    let fetcher = ScriptedFetcher { _ in
        .updated(tempURL: writeTemp("0.0.0.0 a.example.com\n"), etag: nil, lastModified: nil, domainCount: 1)
    }
    let refresher = SourceRefresher(fetcher: fetcher)
    _ = await refresher.refresh(id, in: catalog)

    // Delete the cache file, then refresh with the SAME bytes (same contentHash).
    try FileManager.default.removeItem(at: catalog.cacheURL(for: id))
    let second = await refresher.refresh(id, in: catalog)

    #expect(second.kind == .updated)
    #expect(second.changed == true) // cache was missing -> must repopulate and report changed
    #expect(FileManager.default.fileExists(atPath: catalog.cacheURL(for: id).path))
}

private actor EtagBox {
    var value: String?
    func set(_ v: String?) { value = v }
}

@Test func refreshAll_oneFailureDoesNotAbortOthers() async throws {
    let catalog = try SourceCatalog(root: tempRoot())
    let ids = catalog.sources.map(\.id)
    let firstID = ids[0]
    let fetcher = ScriptedFetcher { source in
        if source.id == firstID { throw SourceError.notHostsFormat }
        return .updated(tempURL: writeTemp("0.0.0.0 a.example.com\n"), etag: nil, lastModified: nil, domainCount: 1)
    }
    let outcomes = await SourceRefresher(fetcher: fetcher).refreshAll(in: catalog)
    #expect(outcomes.count == ids.count)
    #expect(outcomes.contains { if case .failed = $0.kind { return true } else { return false } })
    #expect(outcomes.contains { $0.kind == .updated })
}
