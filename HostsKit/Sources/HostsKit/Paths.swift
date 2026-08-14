import Foundation

public enum AppPaths {
    public static let supportDirName = "Hosts Switchr"
    public static let legacySupportDirName = "HostsSwitchr"
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
        supportBase(fileManager: fileManager).appendingPathComponent(supportDirName, isDirectory: true)
    }

    public static func supportBase(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// The support root to use, copying a pre-rename `HostsSwitchr` store across on first run and
    /// leaving the original in place as a safety net. Staged then renamed so a copy that dies partway
    /// never leaves a half-store behind, and falls back to the legacy root when the copy fails at all:
    /// an empty store would reseed System Default from the live /etc/hosts and orphan the real profiles.
    public static func resolveSupportRoot(base: URL, fileManager: FileManager = .default) -> URL {
        let current = base.appendingPathComponent(supportDirName, isDirectory: true)
        let legacy = base.appendingPathComponent(legacySupportDirName, isDirectory: true)
        guard !fileManager.fileExists(atPath: current.path),
              fileManager.fileExists(atPath: legacy.path) else { return current }

        let staging = base.appendingPathComponent("\(supportDirName).migrating-\(UUID().uuidString)",
                                                  isDirectory: true)
        do {
            try fileManager.copyItem(at: legacy, to: staging)
            try fileManager.moveItem(at: staging, to: current)
            return current
        } catch {
            try? fileManager.removeItem(at: staging)
            return legacy
        }
    }

    public static func resolveSupportRoot(fileManager: FileManager = .default) -> URL {
        resolveSupportRoot(base: supportBase(fileManager: fileManager), fileManager: fileManager)
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
