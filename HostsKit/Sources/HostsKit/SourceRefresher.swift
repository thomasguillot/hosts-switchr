import Foundation

public struct RefreshOutcome: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case updated
        case notModified
        case failed(String)
    }
    public let sourceID: UUID
    public let kind: Kind
    public let changed: Bool
    public init(sourceID: UUID, kind: Kind, changed: Bool) {
        self.sourceID = sourceID; self.kind = kind; self.changed = changed
    }
}

public struct SourceRefresher {
    private let fetcher: SourceFetching
    private let now: @Sendable () -> Date
    private nonisolated(unsafe) let fileManager: FileManager

    public init(
        fetcher: SourceFetching,
        now: @escaping @Sendable () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.fetcher = fetcher
        self.now = now
        self.fileManager = fileManager
    }

    public func refresh(_ id: UUID, in catalog: SourceCatalog) async -> RefreshOutcome {
        guard var source = catalog.source(for: id) else {
            return RefreshOutcome(sourceID: id, kind: .failed("Source not found"), changed: false)
        }
        let cacheURL = catalog.cacheURL(for: id)
        let cacheWasMissing = !fileManager.fileExists(atPath: cacheURL.path)
        if cacheWasMissing {
            source.etag = nil
            source.lastModified = nil   // force a full GET: a 304 cannot repopulate a missing cache
        }
        do {
            let result = try await fetcher.fetch(source)
            switch result {
            case .notModified:
                source.lastFetchedAt = now()
                source.lastError = nil
                try? catalog.update(source)
                return RefreshOutcome(sourceID: id, kind: .notModified, changed: false)

            case let .updated(tempURL, etag, lastModified, domainCount):
                defer { try? fileManager.removeItem(at: tempURL) }
                let data = try Data(contentsOf: tempURL)
                let hash = SourceHash.hex(data)
                let changed = (hash != source.contentHash) || cacheWasMissing

                try data.write(to: cacheURL, options: .atomic)

                source.etag = etag
                source.lastModified = lastModified
                source.lastFetchedAt = now()
                source.contentHash = hash
                source.domainCount = domainCount
                source.lastError = nil
                try? catalog.update(source)
                return RefreshOutcome(sourceID: id, kind: .updated, changed: changed)
            }
        } catch {
            source.lastFetchedAt = now()
            source.lastError = (error as? SourceError).map { "\($0)" } ?? error.localizedDescription
            try? catalog.update(source)
            return RefreshOutcome(sourceID: id, kind: .failed(source.lastError ?? "error"), changed: false)
        }
    }

    public func refreshAll(in catalog: SourceCatalog) async -> [RefreshOutcome] {
        var outcomes: [RefreshOutcome] = []
        for source in catalog.sources {
            outcomes.append(await refresh(source.id, in: catalog))
        }
        return outcomes
    }
}
