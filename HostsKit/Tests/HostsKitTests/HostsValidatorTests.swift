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

@Test func validate_wildcardOutsideAllowedParents_isFlagged() {
    let w = HostsValidator.validate(HostsFile(parsing: "127.0.0.1 *.local"))
    #expect(w.contains { $0.line == 1 && $0.message.contains("*.local") && $0.message.contains(".internal") })
}

@Test func validate_invalidWildcard_isFlagged() {
    let w = HostsValidator.validate(HostsFile(parsing: "127.0.0.1 *.bad_label.test"))
    #expect(w.contains { $0.line == 1 && $0.message.contains("Invalid wildcard") })
}

@Test func validate_mixedWildcardLine_isFlagged() {
    let w = HostsValidator.validate(HostsFile(parsing: "127.0.0.1 *.test www.test"))
    #expect(w.contains { $0.line == 1 && $0.message.contains("only name on its line") })
}

@Test func validate_explicitLineUnderWildcardWithOtherAddress_warns() {
    let w = HostsValidator.validate(HostsFile(parsing: "127.0.0.1 *.test\n10.0.0.5 api.test"))
    #expect(w == [HostsWarning(line: 2, message: "api.test overrides *.test")])
}

@Test func validate_explicitLineMatchingWildcardOrOtherFamily_isClean() {
    #expect(HostsValidator.validate(HostsFile(parsing: "127.0.0.1 *.test\n127.0.0.1 api.test")).isEmpty)
    #expect(HostsValidator.validate(HostsFile(parsing: "127.0.0.1 *.test\n::1 api.test")).isEmpty)
    #expect(HostsValidator.validate(HostsFile(parsing: "127.0.0.1 *.test\n::1 *.test")).isEmpty)
}

@Test func validate_overrideUsesMostSpecificWildcard() {
    let file = HostsFile(parsing: "127.0.0.1 *.test\n10.0.0.5 *.app.test\n10.0.0.5 x.app.test")
    #expect(HostsValidator.validate(file).isEmpty)
}

@Test func validate_inheritedWildcardOverride_warns() {
    let inherited = [WildcardRule(suffix: "test", ipv4: "127.0.0.1", ipv6: nil)]
    let w = HostsValidator.validate(HostsFile(parsing: "10.0.0.5 api.test"), inheritedWildcards: inherited)
    #expect(w == [HostsWarning(line: 1, message: "api.test overrides *.test")])
}

@Test func validate_apexIsNotCoveredByWildcard() {
    #expect(HostsValidator.validate(HostsFile(parsing: "127.0.0.1 *.test\n10.0.0.5 test")).isEmpty)
}

@Test func validate_apexOfNestedWildcardFallsToParentRule_clean() {
    let file = HostsFile(parsing: "127.0.0.1 *.test\n10.0.0.5 *.app.test\n127.0.0.1 app.test")
    #expect(HostsValidator.validate(file).isEmpty)
}

@Test func validate_apexOfNestedWildcardOverridesParentRule_warns() {
    let file = HostsFile(parsing: "127.0.0.1 *.test\n10.0.0.5 *.app.test\n10.0.0.5 app.test")
    #expect(HostsValidator.validate(file) == [HostsWarning(line: 3, message: "app.test overrides *.test")])
}
