import Testing
import Foundation
@testable import HostsKit

@Suite struct ConfigBundleTests {
    private let epoch = Date(timeIntervalSince1970: 0)

    private func sampleStores() -> ([Profile], [LocalFragment], [RemoteSource]) {
        let sysId = UUID(); let workId = UUID(); let fragId = UUID()
        let customId = UUID(); let builtinId = BuiltinSources.all[0].id
        let profiles = [
            Profile(id: sysId, name: "System Default", content: "sys", isProtected: true),
            Profile(id: workId, name: "Work", content: "work", sourceIDs: [customId, builtinId], fragmentIDs: [fragId]),
        ]
        let fragments = [LocalFragment(id: fragId, name: "F", content: "0.0.0.0 a")]
        let sources = [
            RemoteSource(id: customId, name: "Custom", url: URL(string: "https://e.com/h")!, kind: .custom),
            BuiltinSources.all[0],
        ]
        return (profiles, fragments, sources)
    }

    @Test func exportExcludesProtectedAndBuiltins() {
        let (p, f, s) = sampleStores()
        let b = ConfigBundle.export(profiles: p, fragments: f, sources: s, exportedAt: epoch)
        #expect(b.schemaVersion == 1)
        #expect(b.profiles.map(\.name) == ["Work"])          // protected System Default excluded
        #expect(b.profiles[0].sourceIDs.count == 2)          // refs (incl. builtin id) preserved
        #expect(b.fragments.map(\.name) == ["F"])
        #expect(b.customSources.map(\.name) == ["Custom"])    // builtin source definition excluded
    }

    @Test func roundTripsThroughJSON() throws {
        let (p, f, s) = sampleStores()
        let b = ConfigBundle.export(profiles: p, fragments: f, sources: s, exportedAt: epoch)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(b)
        let decoded = try ConfigBundle.decode(data)
        #expect(decoded == b)
    }

    @Test func decodeRejectsMalformedAndBadVersion() throws {
        #expect(throws: ConfigBundle.ImportError.malformed) { try ConfigBundle.decode(Data("{".utf8)) }
        let v2 = #"{"schemaVersion":2,"exportedAt":"1970-01-01T00:00:00Z","profiles":[],"fragments":[],"customSources":[]}"#
        #expect(throws: ConfigBundle.ImportError.unsupportedVersion(2)) { try ConfigBundle.decode(Data(v2.utf8)) }
    }

    @Test func mergePlanSkipsExistingAddsNewAndWarnsInsecure() {
        let existingID = UUID()
        let bundle = ConfigBundle(
            schemaVersion: 1, exportedAt: epoch,
            profiles: [BundleProfile(id: existingID, name: "Dup", content: "x", fragmentIDs: [], sourceIDs: []),
                       BundleProfile(id: UUID(), name: "New", content: "y", fragmentIDs: [], sourceIDs: [])],
            fragments: [],
            customSources: [BundleSource(id: UUID(), name: "Bad", url: "http://e.com/h"),
                            BundleSource(id: UUID(), name: "Good", url: "https://e.com/h")])
        let existing = [Profile(id: existingID, name: "Dup", content: "x")]
        let plan = ConfigBundle.plan(bundle, mode: .merge, existingProfiles: existing, existingFragments: [], existingSources: [])
        #expect(plan.profilesToAdd.map(\.name) == ["New"])        // existing id skipped
        #expect(plan.sourcesToAdd.map(\.name) == ["Good"])         // http skipped
        #expect(plan.insecureSourceWarnings == ["Bad"])
        #expect(plan.profileIDsToDelete.isEmpty)                   // merge deletes nothing
    }

    @Test func planDedupesDuplicateIDsWithinBundle() {
        let dupID = UUID()
        let bundle = ConfigBundle(
            schemaVersion: 1, exportedAt: Date(timeIntervalSince1970: 0),
            profiles: [BundleProfile(id: dupID, name: "A", content: "x", fragmentIDs: [], sourceIDs: []),
                       BundleProfile(id: dupID, name: "B", content: "y", fragmentIDs: [], sourceIDs: [])],
            fragments: [], customSources: [])
        let plan = ConfigBundle.plan(bundle, mode: .merge, existingProfiles: [], existingFragments: [], existingSources: [])
        #expect(plan.profilesToAdd.count == 1)   // the same id is added only once
    }

    @Test func replacePlanDeletesNonProtectedAndAllFragmentsAndCustomSources() {
        let protectedID = UUID(); let normalID = UUID(); let fragID = UUID()
        let customID = UUID(); let builtinID = BuiltinSources.all[0].id
        let bundle = ConfigBundle(schemaVersion: 1, exportedAt: epoch, profiles: [], fragments: [], customSources: [])
        let existingProfiles = [Profile(id: protectedID, name: "System Default", content: "", isProtected: true),
                                Profile(id: normalID, name: "Work", content: "")]
        let existingFragments = [LocalFragment(id: fragID, name: "F", content: "")]
        let existingSources = [RemoteSource(id: customID, name: "C", url: URL(string: "https://e.com")!, kind: .custom),
                               RemoteSource(id: builtinID, name: "B", url: BuiltinSources.all[0].url, kind: .builtin)]
        let plan = ConfigBundle.plan(bundle, mode: .replace, existingProfiles: existingProfiles,
                                     existingFragments: existingFragments, existingSources: existingSources)
        #expect(plan.profileIDsToDelete == [normalID])            // protected kept
        #expect(plan.fragmentIDsToDelete == [fragID])
        #expect(plan.customSourceIDsToDelete == [customID])       // builtin kept
    }
}
