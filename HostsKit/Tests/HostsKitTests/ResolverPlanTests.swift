import Foundation
import Testing
@testable import HostsKit

@Suite struct ResolverPlanTests {
    let ours = ResolverFile.contents(port: 53535)

    @Test func contentsAreFixed() {
        #expect(ours == "# Managed by Hosts Switchr. Removed when no wildcard needs it.\nnameserver 127.0.0.1\nport 53535\n")
        #expect(ResolverFile.isManaged(ours))
        #expect(!ResolverFile.isManaged("nameserver 127.0.0.1\nport 53\n"))
    }

    @Test func writesNewAndChanged_keepsUnchanged() {
        let plan = ResolverPlan.make(desired: ["test", "app.test"], port: 53535,
                                     existing: ["app.test": ours, "x.test": ResolverFile.contents(port: 53536)])
        #expect(plan.writes == ["test"])
        #expect(plan.unchanged == ["app.test"])
        #expect(plan.removals == ["x.test"])
        #expect(plan.foreign.isEmpty)
        #expect(ResolverPlan.make(desired: ["x.test"], port: 53535, existing: ["x.test": ResolverFile.contents(port: 53536)]).writes == ["x.test"])
    }

    @Test func foreignFilesAreNeverWrittenOrRemoved() {
        let valet = "nameserver 127.0.0.1\n"
        let plan = ResolverPlan.make(desired: ["test"], port: 53535, existing: ["test": valet, "dev": valet, "odd": ""])
        #expect(plan.foreign == ["test"])
        #expect(plan.writes.isEmpty && plan.removals.isEmpty)
    }

    @Test func caseVariantFilesAreForeign() {
        let valet = "nameserver 127.0.0.1\n"
        let plan = ResolverPlan.make(desired: ["test"], port: 53535, existing: ["Test": valet])
        #expect(plan.foreign == ["test"])
        #expect(plan.writes.isEmpty && plan.removals.isEmpty)
        let managedVariant = ResolverPlan.make(desired: ["test"], port: 53535, existing: ["Test": ours])
        #expect(managedVariant.foreign == ["test"])
        #expect(managedVariant.writes.isEmpty && managedVariant.removals.isEmpty)
    }

    @Test func managedFilesWithInvalidNamesAreLeftAlone() {
        #expect(ResolverPlan.make(desired: [], port: 53535, existing: ["Bad_Name": ours]).removals.isEmpty)
    }

    @Test func noWildcardsAndNoManagedFilesPlansNothing() {
        #expect(ResolverPlan.make(desired: [], port: 53535, existing: ["dev": "nameserver 1.1.1.1\n"])
            == ResolverPlan(writes: [], removals: [], unchanged: [], foreign: []))
    }

    @Test func readListsRegularFilesAndMarksOthersForeign() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("resolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try ours.write(to: dir.appendingPathComponent("test"), atomically: true, encoding: .utf8)
        try ours.write(to: dir.appendingPathComponent(".hsk-tmp.X"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link"),
                                                   withDestinationURL: dir.appendingPathComponent("test"))
        #expect(ResolverDirectory.read(dir) == ["test": ours, "sub": "", "link": ""])
        #expect(ResolverDirectory.read(dir.appendingPathComponent("missing")).isEmpty)
    }

    @Test func needsReapply_withoutRecordedDeploymentButCurrentRules_isTrue() {
        let current = WildcardSet(rules: [WildcardRule(suffix: "test", ipv4: "127.0.0.1", ipv6: nil)], shadowedNames: [])
        #expect(ResolverPlan.needsReapply(recorded: nil, current: current, existing: [:]))
        #expect(!ResolverPlan.needsReapply(recorded: nil, current: .empty, existing: [:]))
    }

    @Test func needsReapply_whenARecordedFileIsMissingChangedOrForeign() {
        let d = WildcardDeployment(served: .empty, resolverDomains: ["test"], port: 53535)
        #expect(!ResolverPlan.needsReapply(recorded: d, current: .empty, existing: ["test": ours]))
        #expect(ResolverPlan.needsReapply(recorded: d, current: .empty, existing: [:]))
        #expect(ResolverPlan.needsReapply(recorded: d, current: .empty, existing: ["test": "nameserver 127.0.0.1\n"]))
    }
}
