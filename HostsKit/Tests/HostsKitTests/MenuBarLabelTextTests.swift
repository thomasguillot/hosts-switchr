import Testing
@testable import HostsKit

@Suite struct MenuBarLabelTextTests {
    @Test func offReturnsNil() {
        #expect(MenuBarLabelText.displayName(showName: false, activeName: "Work") == nil)
    }
    @Test func nilOrEmptyActiveReturnsNil() {
        #expect(MenuBarLabelText.displayName(showName: true, activeName: nil) == nil)
        #expect(MenuBarLabelText.displayName(showName: true, activeName: "   ") == nil)
    }
    @Test func shortNameReturnedAsIs() {
        #expect(MenuBarLabelText.displayName(showName: true, activeName: "Work") == "Work")
    }
    @Test func longNameTruncatedWithEllipsis() {
        let name = String(repeating: "a", count: 40)
        let out = MenuBarLabelText.displayName(showName: true, activeName: name, maxLength: 24)
        #expect(out?.count == 24)
        #expect(out?.hasSuffix("\u{2026}") == true)
    }
}
