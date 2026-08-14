import Testing
@testable import HostsKit

@Suite struct UpdateRelaunchTests {
    @Test func embedsPidAndPath() {
        let script = UpdateRelaunch.shellScript(pid: 4242, appPath: "/Applications/Hosts Switchr.app")
        #expect(script.contains("4242"))
        #expect(script.contains("/Applications/Hosts Switchr.app"))
    }

    @Test func waitsForOldInstanceThenOpens() {
        let script = UpdateRelaunch.shellScript(pid: 7, appPath: "/Applications/Hosts Switchr.app")
        // Poll the dying PID before launching: a fixed sleep races teardown.
        #expect(script.contains("/bin/kill -0 7"))
        #expect(script.contains("/usr/bin/open"))
        // The open must come after the wait loop, not before.
        let killIndex = script.range(of: "/bin/kill -0 7")!.lowerBound
        let openIndex = script.range(of: "/usr/bin/open")!.lowerBound
        #expect(killIndex < openIndex)
    }

    @Test func waitIsBounded() {
        // A wedged old process must not stall the relaunch forever.
        let script = UpdateRelaunch.shellScript(pid: 1, appPath: "/Applications/Hosts Switchr.app")
        #expect(script.contains("-lt 150"))
    }

    @Test func pathIsQuoted() {
        let script = UpdateRelaunch.shellScript(pid: 1, appPath: "/Applications/Hosts Switchr.app")
        #expect(script.contains("\"/Applications/Hosts Switchr.app\""))
    }
}
