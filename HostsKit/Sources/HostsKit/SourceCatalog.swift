import Foundation

public final class SourceCatalog: @unchecked Sendable {
    private let root: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var _sources: [RemoteSource] = []
    private var _loadedCorruptMetadata = false

    private(set) public var sources: [RemoteSource] {
        get { lock.withLock { _sources } }
        set { lock.withLock { _sources = newValue } }
    }

    public var loadedCorruptMetadata: Bool { lock.withLock { _loadedCorruptMetadata } }

    private var sourcesDir: URL { AppPaths.sourcesDir(root: root) }
    private var metadataURL: URL { AppPaths.sourcesMetadata(root: root) }

    public init(root: URL, fileManager: FileManager = .default) throws {
        self.root = root
        self.fileManager = fileManager
        try fileManager.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        // Take the lock once; helpers are non-locking to avoid NSLock re-entrancy.
        try lock.withLock {
            try loadLocked()
            try reconcileBuiltinsLocked()
        }
    }

    public func cacheURL(for id: UUID) -> URL {
        sourcesDir.appendingPathComponent("\(id.uuidString).hosts", isDirectory: false)
    }

    public func source(for id: UUID) -> RemoteSource? {
        lock.withLock { _sources.first { $0.id == id } }
    }

    public func cachedDomainCount(for id: UUID) -> Int? {
        lock.withLock { _sources.first { $0.id == id }?.domainCount }
    }

    // MARK: Non-locking helpers (callers must hold `lock`)

    private func loadLocked() throws {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            _sources = []
            return
        }
        let data = try Data(contentsOf: metadataURL)
        guard let decoded = try? JSONDecoder().decode([RemoteSource].self, from: data) else {
            // Corrupt: preserve to a unique path BEFORE any seed/save can overwrite it; fail closed if preservation fails.
            try fileManager.moveItem(at: metadataURL,
                                     to: AppPaths.uniqueCorruptURL(for: metadataURL, fileManager: fileManager))
            _loadedCorruptMetadata = true
            _sources = []
            return
        }
        _sources = decoded
    }

    private func reconcileBuiltinsLocked() throws {
        var changed = false
        let canonicalIDs = Set(BuiltinSources.all.map(\.id))
        let beforeCount = _sources.count
        _sources.removeAll { $0.kind == .builtin && !canonicalIDs.contains($0.id) }
        if _sources.count != beforeCount { changed = true }
        for builtin in BuiltinSources.all {
            guard let idx = _sources.firstIndex(where: { $0.id == builtin.id }) else {
                _sources.append(builtin)
                changed = true
                continue
            }
            var s = _sources[idx]
            let urlChanged = s.url != builtin.url
            if s.name != builtin.name || urlChanged || s.kind != builtin.kind {
                s.name = builtin.name; s.url = builtin.url; s.kind = builtin.kind
                if urlChanged {
                    // URL changed: drop stale cache + fetch state so old content can't be merged and the next refresh re-fetches.
                    s.etag = nil; s.lastModified = nil; s.contentHash = nil; s.domainCount = nil; s.lastError = nil
                    try? fileManager.removeItem(at: cacheURL(for: builtin.id))
                }
                _sources[idx] = s
                changed = true
            }
        }
        // Built-ins in canonical (BuiltinSources.all) order, custom sources after in their existing order.
        let ordered = BuiltinSources.all.compactMap { b in _sources.first { $0.id == b.id } }
            + _sources.filter { $0.kind == .custom }
        if ordered.map(\.id) != _sources.map(\.id) {
            _sources = ordered
            changed = true
        }
        if changed { try saveLocked() }
    }

    private func saveLocked() throws {
        let data = try JSONEncoder().encode(_sources)
        try data.write(to: metadataURL, options: .atomic)
    }

    // MARK: Mutating API (takes the lock once at the outermost entry)

    @discardableResult
    public func addCustom(name: String, urlString: String) throws -> RemoteSource {
        let url = try SourceURLPolicy.validated(urlString)   // https-only enforcement gate
        // Strip CR/LF from the name so it can't inject lines into the merged hosts header.
        let cleanName = name.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        let source = RemoteSource(id: UUID(), name: cleanName, url: url, kind: .custom)
        try lock.withLock {
            _sources.append(source)
            try saveLocked()
        }
        return source
    }

    public func add(_ source: RemoteSource) throws {
        _ = try SourceURLPolicy.validated(source.url.absoluteString)   // https-only enforcement gate
        let cleanName = source.name.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        var clean = source; clean.name = cleanName
        try lock.withLock {
            _sources.append(clean)
            try saveLocked()
        }
    }

    public func remove(_ id: UUID) throws {
        try lock.withLock {
            guard let source = _sources.first(where: { $0.id == id }) else { throw SourceError.notFound }
            if source.kind == .builtin { throw SourceError.builtinNotRemovable }
            try? fileManager.removeItem(at: cacheURL(for: id))
            _sources.removeAll { $0.id == id }
            try saveLocked()
        }
    }

    public func reorderCustoms(_ orderedIDs: [UUID]) throws {
        try lock.withLock {
            let customs = _sources.filter { $0.kind == .custom }
            let byID = Dictionary(uniqueKeysWithValues: customs.map { ($0.id, $0) })
            let ordered = orderedIDs.compactMap { byID[$0] }
            let leftovers = customs.filter { !orderedIDs.contains($0.id) }
            _sources = _sources.filter { $0.kind == .builtin } + ordered + leftovers
            try saveLocked()
        }
    }

    public func update(_ source: RemoteSource) throws {
        try lock.withLock {
            guard let idx = _sources.firstIndex(where: { $0.id == source.id }) else { throw SourceError.notFound }
            _sources[idx] = source
            try saveLocked()
        }
    }
}
