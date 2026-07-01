import Testing
@testable import HostsKit

@Suite struct AppVersionTests {
    @Test func stripsLeadingLowercaseV() {
        #expect(AppVersion("v0.2.0") == AppVersion("0.2.0"))
    }

    @Test func stripsLeadingUppercaseV() {
        #expect(AppVersion("V1.4.7") == AppVersion("1.4.7"))
    }

    @Test func majorMinorPatchStored() {
        let version = AppVersion("2.5.9")
        #expect(version?.major == 2)
        #expect(version?.minor == 5)
        #expect(version?.patch == 9)
    }

    @Test func patchOrdering() {
        #expect(AppVersion("0.2.0")! > AppVersion("0.1.2")!)
        #expect(AppVersion("1.0.1")! > AppVersion("1.0.0")!)
    }

    @Test func minorOrdering() {
        #expect(AppVersion("1.2.0")! > AppVersion("1.1.9")!)
    }

    @Test func majorOrdering() {
        #expect(AppVersion("2.0.0")! > AppVersion("1.99.99")!)
    }

    @Test func equalVersions() {
        #expect(AppVersion("1.2.3") == AppVersion("1.2.3"))
        #expect(!(AppVersion("1.2.3")! < AppVersion("1.2.3")!))
    }

    @Test func malformedProducesNil() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("abc") == nil)
        #expect(AppVersion("1.2") == nil)
        #expect(AppVersion("1.2.3.4") == nil)
        #expect(AppVersion("v") == nil)
        #expect(AppVersion("1.-2.0") == nil)
        #expect(AppVersion("1.2.x") == nil)
    }
}
