import Foundation

public final class FragmentStore {
    private let root: URL
    private let fileManager: FileManager
    private(set) public var fragments: [LocalFragment] = []
    private(set) public var loadedCorruptMetadata = false

    public init(root: URL, fileManager: FileManager = .default) throws {
        self.root = root
        self.fileManager = fileManager
        try fileManager.createDirectory(at: fragmentsDir, withIntermediateDirectories: true)
        try load()
    }

    private var fragmentsDir: URL { AppPaths.fragmentsDir(root: root) }
    private var metadataURL: URL { AppPaths.fragmentsMetadata(root: root) }
    private func fragmentURL(_ id: UUID) -> URL {
        fragmentsDir.appendingPathComponent("\(id.uuidString).hosts", isDirectory: false)
    }

    private struct FragmentMeta: Codable {
        var name: String
        var createdAt: Date
        var updatedAt: Date
    }

    private struct MetadataBlob: Codable {
        var order: [UUID]
        var fragments: [String: FragmentMeta]
    }

    private func load() throws {
        let blob: MetadataBlob
        if fileManager.fileExists(atPath: metadataURL.path) {
            let data = try Data(contentsOf: metadataURL)
            if let decoded = try? JSONDecoder().decode(MetadataBlob.self, from: data) {
                blob = decoded
            } else {
                // Corrupt: preserve to a unique path BEFORE any save can overwrite it; fail closed if preservation fails.
                try fileManager.moveItem(at: metadataURL,
                                         to: AppPaths.uniqueCorruptURL(for: metadataURL, fileManager: fileManager))
                loadedCorruptMetadata = true
                blob = MetadataBlob(order: [], fragments: [:])
            }
        } else {
            blob = MetadataBlob(order: [], fragments: [:])
        }

        let files = try fileManager.contentsOfDirectory(at: fragmentsDir, includingPropertiesForKeys: nil)
        var loaded: [UUID: LocalFragment] = [:]
        for url in files where url.pathExtension == "hosts" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            let sidecar = blob.fragments[id.uuidString]
            loaded[id] = LocalFragment(
                id: id,
                name: sidecar?.name ?? "Untitled",
                content: content,
                createdAt: sidecar?.createdAt ?? Date(),
                updatedAt: sidecar?.updatedAt ?? Date())
        }
        let ordered = blob.order.compactMap { loaded[$0] }
        let leftovers = loaded.values.filter { !blob.order.contains($0.id) }
        fragments = ordered + leftovers.sorted { $0.createdAt < $1.createdAt }
    }

    private func save() throws {
        let blob = MetadataBlob(
            order: fragments.map(\.id),
            fragments: Dictionary(uniqueKeysWithValues: fragments.map {
                ($0.id.uuidString, FragmentMeta(name: $0.name, createdAt: $0.createdAt, updatedAt: $0.updatedAt))
            }))
        let data = try JSONEncoder().encode(blob)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func writeContent(_ fragment: LocalFragment) throws {
        try fragment.content.write(to: fragmentURL(fragment.id), atomically: true, encoding: .utf8)
    }

    @discardableResult
    public func create(name: String, content: String) throws -> LocalFragment {
        let fragment = LocalFragment(name: uniqueName(name, taken: fragments.map(\.name)), content: content)
        fragments.append(fragment)
        try writeContent(fragment)
        try save()
        return fragment
    }

    public func add(_ fragment: LocalFragment) throws {
        fragments.append(fragment)
        try writeContent(fragment)
        try save()
    }

    public func update(_ fragment: LocalFragment) throws {
        guard let idx = fragments.firstIndex(where: { $0.id == fragment.id }) else { throw ProfileError.notFound }
        var updated = fragment
        updated.updatedAt = Date()
        fragments[idx] = updated
        try writeContent(updated)
        try save()
    }

    public func rename(_ id: UUID, to name: String) throws {
        guard let idx = fragments.firstIndex(where: { $0.id == id }) else { throw ProfileError.notFound }
        let lower = name.lowercased()
        if fragments.contains(where: { $0.id != id && $0.name.lowercased() == lower }) { throw ProfileError.duplicateName }
        fragments[idx].name = name
        fragments[idx].updatedAt = Date()
        try save()
    }

    public func reorder(_ orderedIDs: [UUID]) throws {
        let byID = Dictionary(uniqueKeysWithValues: fragments.map { ($0.id, $0) })
        let ordered = orderedIDs.compactMap { byID[$0] }
        let leftovers = fragments.filter { !orderedIDs.contains($0.id) }
        fragments = ordered + leftovers.sorted { $0.createdAt < $1.createdAt }
        try save()
    }

    public func delete(_ id: UUID) throws {
        guard fragments.contains(where: { $0.id == id }) else { throw ProfileError.notFound }
        // Remove the backing file first (fail closed) so a failed removal can't leave an orphan that load() re-imports.
        let url = fragmentURL(id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        fragments.removeAll { $0.id == id }
        try save()
    }
}
