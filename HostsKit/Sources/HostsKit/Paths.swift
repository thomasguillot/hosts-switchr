import Foundation

public enum AppPaths {
    public static let profilesDirName = "profiles"
    public static let profilesMetadataName = "profiles.json"
    public static let backupsDirName = "backups"
    public static let sourcesDirName = "sources"
    public static let sourcesMetadataName = "sources.json"
    public static let fragmentsDirName = "fragments"
    public static let fragmentsMetadataName = "fragments.json"

    // MARK: Root-based (testable, injected root)

    public static func profilesDir(root: URL) -> URL {
        root.appendingPathComponent(profilesDirName, isDirectory: true)
    }
    public static func profilesMetadata(root: URL) -> URL {
        root.appendingPathComponent(profilesMetadataName, isDirectory: false)
    }
    public static func backupsDir(root: URL) -> URL {
        root.appendingPathComponent(backupsDirName, isDirectory: true)
    }
    public static func sourcesDir(root: URL) -> URL {
        root.appendingPathComponent(sourcesDirName, isDirectory: true)
    }
    public static func sourcesMetadata(root: URL) -> URL {
        root.appendingPathComponent(sourcesMetadataName, isDirectory: false)
    }
    public static func fragmentsDir(root: URL) -> URL {
        root.appendingPathComponent(fragmentsDirName, isDirectory: true)
    }
    public static func fragmentsMetadata(root: URL) -> URL {
        root.appendingPathComponent(fragmentsMetadataName, isDirectory: false)
    }

    // MARK: Live support root (used by the app)

    public static func supportRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HostsSwitchr", isDirectory: true)
    }
    public static func profilesDir(fileManager: FileManager = .default) -> URL {
        profilesDir(root: supportRoot(fileManager: fileManager))
    }
    public static func profilesMetadata(fileManager: FileManager = .default) -> URL {
        profilesMetadata(root: supportRoot(fileManager: fileManager))
    }
    public static func backupsDir(fileManager: FileManager = .default) -> URL {
        backupsDir(root: supportRoot(fileManager: fileManager))
    }
    public static func sourcesDir(fileManager: FileManager = .default) -> URL {
        sourcesDir(root: supportRoot(fileManager: fileManager))
    }
    public static func sourcesMetadata(fileManager: FileManager = .default) -> URL {
        sourcesMetadata(root: supportRoot(fileManager: fileManager))
    }
    public static func fragmentsDir(fileManager: FileManager = .default) -> URL {
        fragmentsDir(root: supportRoot(fileManager: fileManager))
    }
    public static func fragmentsMetadata(fileManager: FileManager = .default) -> URL {
        fragmentsMetadata(root: supportRoot(fileManager: fileManager))
    }

    // MARK: Corruption recovery

    /// A non-existing `.corrupt`/`.corrupt-N` sibling, so preserving a corrupt file never clobbers an earlier copy.
    public static func uniqueCorruptURL(for url: URL, fileManager: FileManager = .default) -> URL {
        var candidate = url.appendingPathExtension("corrupt")
        var n = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = url.appendingPathExtension("corrupt-\(n)")
            n += 1
        }
        return candidate
    }
}
