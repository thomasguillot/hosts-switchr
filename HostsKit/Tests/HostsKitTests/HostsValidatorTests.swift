import Testing
@testable import HostsKit

@Test func validate_flagsDuplicateHostname() {
    let file = HostsFile(parsing: "127.0.0.1 dup.local\n10.0.0.1 dup.local")
    let warnings = HostsValidator.validate(file)
    #expect(warnings.contains { $0.message.contains("dup.local") && $0.line == 2 })
}

@Test func validate_flagsMalformedIP() {
    let file = HostsFile(parsing: "999.999.1.1 bad.local")
    let warnings = HostsValidator.validate(file)
    #expect(warnings.contains { $0.message.contains("999.999.1.1") })
}

@Test func validate_cleanFile_hasNoWarnings() {
    let file = HostsFile(parsing: "127.0.0.1 localhost\n::1 localhost")
    #expect(HostsValidator.validate(file).isEmpty)
}

@Test func validate_identicalLoopbackLine_isStillFlagged() {
    // Same hostname on the SAME loopback IP twice is a real duplicate, not dual-stack.
    let file = HostsFile(parsing: "127.0.0.1 localhost\n127.0.0.1 localhost")
    let warnings = HostsValidator.validate(file)
    #expect(warnings.contains { $0.message.contains("localhost") && $0.line == 2 })
}

@Test func validate_nonLoopbackAfterLoopback_isFlagged() {
    let file = HostsFile(parsing: "127.0.0.1 web.local\n10.0.0.1 web.local")
    #expect(HostsValidator.validate(file).contains { $0.line == 2 })
}

@Test func validate_duplicateHostname_isCaseInsensitive() {
    // RFC 1123: host names are case-insensitive, so these two collide.
    let file = HostsFile(parsing: "127.0.0.1 Example.com\n10.0.0.1 example.com")
    let warnings = HostsValidator.validate(file)
    #expect(warnings.contains { $0.message.contains("example.com") && $0.line == 2 })
}

@Test func validate_caseOnlyDifference_stillCleanForLoopbackDualStack() {
    // Dual-stack loopback with differing case must still be exempt (no false positive).
    let file = HostsFile(parsing: "127.0.0.1 LocalHost\n::1 localhost")
    #expect(HostsValidator.validate(file).isEmpty)
}
