import Testing
@testable import HostsKit

@Test func diff_reportsAddedAndRemovedLines() {
    let old = "127.0.0.1 localhost\n127.0.0.1 old.local"
    let new = "127.0.0.1 localhost\n10.0.0.5 staging.local"
    let d = LocalLayerDiff.diff(old: old, new: new)
    #expect(d.added == ["10.0.0.5 staging.local"])
    #expect(d.removed == ["127.0.0.1 old.local"])
}

@Test func diff_identical_isEmpty() {
    let d = LocalLayerDiff.diff(old: "a\nb", new: "a\nb")
    #expect(d.added.isEmpty)
    #expect(d.removed.isEmpty)
}
