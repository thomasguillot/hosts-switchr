import Testing
@testable import HostsKit

private final class MockLoginItem: LoginItemControlling {
    var enabled = false
    var enableError: Error?
    var disableError: Error?
    var isEnabled: Bool { enabled }
    func enable() throws { if let enableError { throw enableError }; enabled = true }
    func disable() throws { if let disableError { throw disableError }; enabled = false }
}

private struct Boom: Error {}

@Suite struct LaunchAtLoginTests {
    @Test func enableSuccessReportsEnabledNoError() {
        let mock = MockLoginItem()
        let result = LaunchAtLogin.apply(true, to: mock)
        #expect(result.isEnabled == true)
        #expect(result.error == nil)
    }

    @Test func disableSuccessReportsDisabledNoError() {
        let mock = MockLoginItem()
        mock.enabled = true
        let result = LaunchAtLogin.apply(false, to: mock)
        #expect(result.isEnabled == false)
        #expect(result.error == nil)
    }

    @Test func enableFailureRevertsToRealStatusWithError() {
        let mock = MockLoginItem()
        mock.enableError = Boom()
        let result = LaunchAtLogin.apply(true, to: mock)
        #expect(result.isEnabled == false)        // reverted to the real (still-off) status
        #expect(result.error != nil)
        #expect(result.error?.contains("enable") == true)
    }

    @Test func disableFailureRevertsToRealStatusWithError() {
        let mock = MockLoginItem()
        mock.enabled = true
        mock.disableError = Boom()
        let result = LaunchAtLogin.apply(false, to: mock)
        #expect(result.isEnabled == true)         // reverted to the real (still-on) status
        #expect(result.error != nil)
        #expect(result.error?.contains("disable") == true)
    }
}
