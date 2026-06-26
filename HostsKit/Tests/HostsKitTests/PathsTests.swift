import Testing
import Foundation
@testable import HostsKit

@Test func paths_rootBased_areNestedAndNamed() {
    let root = URL(fileURLWithPath: "/tmp/hsk-root", isDirectory: true)
    #expect(AppPaths.profilesDir(root: root).lastPathComponent == "profiles")
    #expect(AppPaths.profilesMetadata(root: root).lastPathComponent == "profiles.json")
    #expect(AppPaths.backupsDir(root: root).lastPathComponent == "backups")
    #expect(AppPaths.sourcesDir(root: root).lastPathComponent == "sources")
    #expect(AppPaths.sourcesMetadata(root: root).lastPathComponent == "sources.json")
    #expect(AppPaths.sourcesDir(root: root).path.hasPrefix(root.path))
}

@Test func paths_appOverloads_useSupportRoot() {
    #expect(AppPaths.sourcesDir().path.hasPrefix(AppPaths.supportRoot().path))
}
