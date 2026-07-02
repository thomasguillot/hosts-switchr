import Foundation

public enum ProfileError: Error, Equatable {
    case notFound
    case protectedProfile
    case duplicateName
}

public final class ProfileStore {
    private let root: URL
    private let fileManager: FileManager
    private(set) public var profiles: [Profile] = []
    private var metadata: ProfileMetadata

    private(set) public var loadedCorruptMetadata = false

    public var activeProfileID: UUID? { metadata.activeProfileID }

    public init(root: URL, fileManager: FileManager = .default) throws {
        self.root = root
        self.fileManager = fileManager
        self.metadata = ProfileMetadata()
        try createDirectories()
        try load()
    }

    private var profilesDir: URL { AppPaths.profilesDir(root: root) }
    private var metadataURL: URL { AppPaths.profilesMetadata(root: root) }
    private func profileURL(_ id: UUID) -> URL {
        profilesDir.appendingPathComponent("\(id.uuidString).hosts", isDirectory: false)
    }

    private func createDirectories() throws {
        try fileManager.createDirectory(at: profilesDir, withIntermediateDirectories: true)
    }

    private struct ProfileMeta: Codable {
        var name: String
        var createdAt: Date
        var updatedAt: Date
        var isProtected: Bool
        var sourceIDs: [UUID]
        var fragmentIDs: [UUID]

        init(name: String, createdAt: Date, updatedAt: Date, isProtected: Bool, sourceIDs: [UUID], fragmentIDs: [UUID]) {
            self.name = name; self.createdAt = createdAt; self.updatedAt = updatedAt
            self.isProtected = isProtected; self.sourceIDs = sourceIDs; self.fragmentIDs = fragmentIDs
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            createdAt = try c.decode(Date.self, forKey: .createdAt)
            updatedAt = try c.decode(Date.self, forKey: .updatedAt)
            isProtected = try c.decode(Bool.self, forKey: .isProtected)
            sourceIDs = try c.decodeIfPresent([UUID].self, forKey: .sourceIDs) ?? []
            fragmentIDs = try c.decodeIfPresent([UUID].self, forKey: .fragmentIDs) ?? []
        }
    }

    private struct MetadataBlob: Codable {
        var order: [UUID]
        var activeProfileID: UUID?
        var profiles: [String: ProfileMeta]

        init(order: [UUID], activeProfileID: UUID?, profiles: [String: ProfileMeta]) {
            self.order = order
            self.activeProfileID = activeProfileID
            self.profiles = profiles
        }

        private enum CodingKeys: String, CodingKey {
            case order, activeProfileID, profiles
        }

        // Decode strictly: unrecognised shapes throw rather than defaulting to empty, so load() preserves a corrupt file before any save overwrites it.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            order = try c.decode([UUID].self, forKey: .order)
            activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID)
            if let obj = try? c.decode([String: ProfileMeta].self, forKey: .profiles) {
                profiles = obj
            } else if let m1 = try? c.decode([UUID: ProfileMeta].self, forKey: .profiles) {
                profiles = Dictionary(uniqueKeysWithValues: m1.map { ($0.key.uuidString, $0.value) })
            } else {
                throw DecodingError.dataCorruptedError(forKey: .profiles, in: c,
                    debugDescription: "profiles is neither the M2 object nor the legacy M1 array shape")
            }
        }
    }

    private func load() throws {
        let blob: MetadataBlob
        if fileManager.fileExists(atPath: metadataURL.path) {
            let data = try Data(contentsOf: metadataURL)
            if let decoded = try? JSONDecoder().decode(MetadataBlob.self, from: data) {
                blob = decoded
            } else {
                // Corrupt: preserve to a unique path BEFORE any save() can overwrite it; fail closed if preservation fails.
                try fileManager.moveItem(at: metadataURL,
                                         to: AppPaths.uniqueCorruptURL(for: metadataURL, fileManager: fileManager))
                loadedCorruptMetadata = true
                blob = MetadataBlob(order: [], activeProfileID: nil, profiles: [:])
            }
        } else {
            blob = MetadataBlob(order: [], activeProfileID: nil, profiles: [:])
        }
        metadata = ProfileMetadata(order: blob.order, activeProfileID: blob.activeProfileID)

        let files = try fileManager.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil)
        var loaded: [UUID: Profile] = [:]
        for url in files where url.pathExtension == "hosts" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            let sidecar = blob.profiles[id.uuidString]
            loaded[id] = Profile(
                id: id,
                name: sidecar?.name ?? "Untitled",
                content: content,
                createdAt: sidecar?.createdAt ?? Date(),
                updatedAt: sidecar?.updatedAt ?? Date(),
                isProtected: sidecar?.isProtected ?? false,
                sourceIDs: sidecar?.sourceIDs ?? [],
                fragmentIDs: sidecar?.fragmentIDs ?? [])
        }
        let ordered = blob.order.compactMap { loaded[$0] }
        let leftovers = loaded.values.filter { !blob.order.contains($0.id) }
        profiles = ordered + leftovers.sorted { $0.createdAt < $1.createdAt }
    }

    public func save() throws {
        let blob = MetadataBlob(
            order: profiles.map(\.id),
            activeProfileID: metadata.activeProfileID,
            profiles: Dictionary(uniqueKeysWithValues: profiles.map {
                ($0.id.uuidString, ProfileMeta(name: $0.name, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                                    isProtected: $0.isProtected, sourceIDs: $0.sourceIDs, fragmentIDs: $0.fragmentIDs))
            }))
        let data = try JSONEncoder().encode(blob)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func writeContent(_ profile: Profile) throws {
        try profile.content.write(to: profileURL(profile.id), atomically: true, encoding: .utf8)
    }

    @discardableResult
    public func create(name: String, content: String) throws -> Profile {
        let profile = Profile(name: uniqueName(name, taken: profiles.map(\.name)), content: content)
        profiles.append(profile)
        try writeContent(profile)
        try save()
        return profile
    }

    public func add(_ profile: Profile) throws {
        var p = profile
        p.isProtected = false   // imported profiles are never protected — a bundle can't create an undeletable profile
        profiles.append(p)
        try writeContent(p)
        try save()
    }

    @discardableResult
    public func duplicate(_ id: UUID) throws -> Profile {
        guard let source = profiles.first(where: { $0.id == id }) else { throw ProfileError.notFound }
        let copy = try create(name: "\(source.name) copy", content: source.content)
        try setSources(copy.id, source.sourceIDs)
        try setFragments(copy.id, source.fragmentIDs)
        return profiles.first { $0.id == copy.id } ?? copy
    }

    public func update(_ profile: Profile) throws {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { throw ProfileError.notFound }
        var updated = profile
        updated.updatedAt = Date()
        profiles[idx] = updated
        try writeContent(updated)
        try save()
    }

    public func rename(_ id: UUID, to name: String) throws {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.notFound }
        let lower = name.lowercased()
        if profiles.contains(where: { $0.id != id && $0.name.lowercased() == lower }) { throw ProfileError.duplicateName }
        profiles[idx].name = name
        profiles[idx].updatedAt = Date()
        try save()
    }

    public func setSources(_ id: UUID, _ sourceIDs: [UUID]) throws {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.notFound }
        profiles[idx].sourceIDs = sourceIDs
        profiles[idx].updatedAt = Date()
        try save()
    }

    public func setFragments(_ id: UUID, _ fragmentIDs: [UUID]) throws {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.notFound }
        profiles[idx].fragmentIDs = fragmentIDs
        profiles[idx].updatedAt = Date()
        try save()
    }

    public func removeFragmentFromAllProfiles(_ fragmentID: UUID) throws {
        var changed = false
        for idx in profiles.indices where profiles[idx].fragmentIDs.contains(fragmentID) {
            profiles[idx].fragmentIDs.removeAll { $0 == fragmentID }
            profiles[idx].updatedAt = Date()
            changed = true
        }
        if changed { try save() }
    }

    public func reorder(_ orderedIDs: [UUID]) throws {
        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let ordered = orderedIDs.compactMap { byID[$0] }
        let leftovers = profiles.filter { !orderedIDs.contains($0.id) }
        let merged = ordered + leftovers.sorted { $0.createdAt < $1.createdAt }
        // Protected profiles stay pinned at the top regardless of the requested order.
        profiles = merged.filter(\.isProtected) + merged.filter { !$0.isProtected }
        try save()
    }

    public func delete(_ id: UUID) throws {
        guard let profile = profiles.first(where: { $0.id == id }) else { throw ProfileError.notFound }
        if profile.isProtected { throw ProfileError.protectedProfile }
        // Remove the backing file first (fail closed) so a failed removal can't leave an orphan that load() re-imports.
        let url = profileURL(id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        profiles.removeAll { $0.id == id }
        if metadata.activeProfileID == id { metadata.activeProfileID = nil }
        try save()
    }

    public func setActive(_ id: UUID?) {
        metadata.activeProfileID = id
    }

    public func removeSourceFromAllProfiles(_ sourceID: UUID) throws {
        var changed = false
        for idx in profiles.indices where profiles[idx].sourceIDs.contains(sourceID) {
            profiles[idx].sourceIDs.removeAll { $0 == sourceID }
            profiles[idx].updatedAt = Date()
            changed = true
        }
        if changed { try save() }
    }

    public func seedSystemDefaultIfEmpty(currentHosts: String) throws {
        guard profiles.isEmpty else { return }
        let profile = Profile(name: "System Default", content: currentHosts, isProtected: true)
        profiles.append(profile)
        try writeContent(profile)
        metadata.activeProfileID = profile.id
        try save()
    }
}
