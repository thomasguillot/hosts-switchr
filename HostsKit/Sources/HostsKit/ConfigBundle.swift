import Foundation

public struct BundleProfile: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var content: String
    public var fragmentIDs: [UUID]
    public var sourceIDs: [UUID]
    public init(id: UUID, name: String, content: String, fragmentIDs: [UUID], sourceIDs: [UUID]) {
        self.id = id; self.name = name; self.content = content
        self.fragmentIDs = fragmentIDs; self.sourceIDs = sourceIDs
    }
}

public struct BundleFragment: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var content: String
    public init(id: UUID, name: String, content: String) { self.id = id; self.name = name; self.content = content }
}

public struct BundleSource: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var url: String
    public init(id: UUID, name: String, url: String) { self.id = id; self.name = name; self.url = url }
}

public struct ConfigBundle: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var exportedAt: Date
    public var profiles: [BundleProfile]
    public var fragments: [BundleFragment]
    public var customSources: [BundleSource]

    public init(schemaVersion: Int, exportedAt: Date, profiles: [BundleProfile],
                fragments: [BundleFragment], customSources: [BundleSource]) {
        self.schemaVersion = schemaVersion; self.exportedAt = exportedAt
        self.profiles = profiles; self.fragments = fragments; self.customSources = customSources
    }

    public enum ImportError: Error, Equatable {
        case malformed
        case unsupportedVersion(Int)
    }

    public enum ImportMode: Sendable { case merge, replace }

    public struct ImportPlan: Equatable, Sendable {
        public var profilesToAdd: [BundleProfile]
        public var fragmentsToAdd: [BundleFragment]
        public var sourcesToAdd: [BundleSource]
        public var profileIDsToDelete: [UUID]
        public var fragmentIDsToDelete: [UUID]
        public var customSourceIDsToDelete: [UUID]
        public var insecureSourceWarnings: [String]
    }

    // MARK: Export

    public static func export(profiles: [Profile], fragments: [LocalFragment],
                              sources: [RemoteSource], exportedAt: Date) -> ConfigBundle {
        ConfigBundle(
            schemaVersion: currentSchemaVersion,
            exportedAt: exportedAt,
            profiles: profiles.filter { !$0.isProtected }.map {
                BundleProfile(id: $0.id, name: $0.name, content: $0.content,
                              fragmentIDs: $0.fragmentIDs, sourceIDs: $0.sourceIDs)
            },
            fragments: fragments.map { BundleFragment(id: $0.id, name: $0.name, content: $0.content) },
            customSources: sources.filter { $0.kind == .custom }.map {
                BundleSource(id: $0.id, name: $0.name, url: $0.url.absoluteString)
            })
    }

    // MARK: Decode

    public static func decode(_ data: Data) throws -> ConfigBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(ConfigBundle.self, from: data) else {
            throw ImportError.malformed
        }
        guard bundle.schemaVersion == currentSchemaVersion else {
            throw ImportError.unsupportedVersion(bundle.schemaVersion)
        }
        return bundle
    }

    // MARK: Plan

    public static func plan(_ bundle: ConfigBundle, mode: ImportMode,
                            existingProfiles: [Profile], existingFragments: [LocalFragment],
                            existingSources: [RemoteSource]) -> ImportPlan {
        let profileIDsToDelete: [UUID]
        let fragmentIDsToDelete: [UUID]
        let customSourceIDsToDelete: [UUID]
        switch mode {
        case .merge:
            profileIDsToDelete = []; fragmentIDsToDelete = []; customSourceIDsToDelete = []
        case .replace:
            profileIDsToDelete = existingProfiles.filter { !$0.isProtected }.map(\.id)
            fragmentIDsToDelete = existingFragments.map(\.id)
            customSourceIDsToDelete = existingSources.filter { $0.kind == .custom }.map(\.id)
        }

        let deletedProfiles = Set(profileIDsToDelete)
        let deletedFragments = Set(fragmentIDsToDelete)
        let deletedSources = Set(customSourceIDsToDelete)
        let survivingProfileIDs = Set(existingProfiles.map(\.id)).subtracting(deletedProfiles)
        let survivingFragmentIDs = Set(existingFragments.map(\.id)).subtracting(deletedFragments)
        let survivingSourceIDs = Set(existingSources.map(\.id)).subtracting(deletedSources)

        var takenProfileIDs = survivingProfileIDs
        var profilesToAdd: [BundleProfile] = []
        for profile in bundle.profiles where !takenProfileIDs.contains(profile.id) {
            profilesToAdd.append(profile)
            takenProfileIDs.insert(profile.id)
        }

        var takenFragmentIDs = survivingFragmentIDs
        var fragmentsToAdd: [BundleFragment] = []
        for fragment in bundle.fragments where !takenFragmentIDs.contains(fragment.id) {
            fragmentsToAdd.append(fragment)
            takenFragmentIDs.insert(fragment.id)
        }

        var takenSourceIDs = survivingSourceIDs
        var sourcesToAdd: [BundleSource] = []
        var insecureWarnings: [String] = []
        for source in bundle.customSources {
            if (try? SourceURLPolicy.validated(source.url)) == nil {
                insecureWarnings.append(source.name)
            } else if !takenSourceIDs.contains(source.id) {
                sourcesToAdd.append(source)
                takenSourceIDs.insert(source.id)
            }
        }

        return ImportPlan(
            profilesToAdd: profilesToAdd, fragmentsToAdd: fragmentsToAdd, sourcesToAdd: sourcesToAdd,
            profileIDsToDelete: profileIDsToDelete, fragmentIDsToDelete: fragmentIDsToDelete,
            customSourceIDsToDelete: customSourceIDsToDelete, insecureSourceWarnings: insecureWarnings)
    }
}
