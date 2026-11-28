import Testing
@testable import HostsKit

@Suite struct WildcardTests {
    @Test func classify_acceptsAllowedSuffixesAndLowercases() {
        #expect(WildcardHostname.classify("*.test") == .wildcard(suffix: "test"))
        #expect(WildcardHostname.classify("*.App.Test") == .wildcard(suffix: "app.test"))
        #expect(WildcardHostname.classify("*.svc.internal") == .wildcard(suffix: "svc.internal"))
        #expect(WildcardHostname.classify("www.test") == .plain)
    }

    @Test func classify_refusesOtherParents() {
        for host in ["*.local", "*.localhost", "*.home.arpa", "*.com", "*.test.com"] {
            #expect(WildcardHostname.classify(host) == .notAllowed, "\(host)")
        }
    }

    @Test func classify_refusesTheWholeInternalTLD() {
        #expect(WildcardHostname.classify("*.internal") == .tooBroad)
        #expect(WildcardHostname.classify("*.Internal") == .tooBroad)
        #expect(WildcardHostname.classify("*.app.internal") == .wildcard(suffix: "app.internal"))
        #expect(WildcardHostname.classify("*.test") == .wildcard(suffix: "test"))
    }

    @Test func classify_rejectsBadShapesAndLabels() {
        let long = String(repeating: "a", count: 64)
        for host in ["*test", "foo.*.test", "*.*.test", "*.", "*.bad_label.test", "*.\(long).test", "*..test"] {
            #expect(WildcardHostname.classify(host) == .invalid, "\(host)")
        }
    }

    @Test func rules_mergeFamiliesFirstWins() {
        let file = HostsFile(parsing: "127.0.0.1 *.test\n::1 *.test\n10.0.0.1 *.test")
        #expect(WildcardCollector.rules(in: [file]) == [WildcardRule(suffix: "test", ipv4: "127.0.0.1", ipv6: "::1")])
    }

    @Test func rules_ignoreMixedRefusedMalformedAndCommented() {
        let file = HostsFile(parsing: "127.0.0.1 *.test www.test\n127.0.0.1 *.local\n999.1.1.1 *.app.internal\n127.0.0.1 *.internal\n# 127.0.0.1 *.test")
        #expect(WildcardCollector.rules(in: [file]).isEmpty)
    }

    @Test func shadowedNames_areExplicitNamesAtOrUnderARuleSuffix() {
        let rules = [WildcardRule(suffix: "test", ipv4: "127.0.0.1", ipv6: nil)]
        let file = HostsFile(parsing: "127.0.0.1 Site.test\n127.0.0.1 example.com\n127.0.0.1 test\n127.0.0.1 nottest")
        #expect(WildcardCollector.shadowedNames(in: file, under: rules) == ["site.test", "test"])
    }

    @Test func set_collectsAcrossFiles() {
        let local = HostsFile(parsing: "10.0.0.5 api.test")
        let fragment = HostsFile(parsing: "127.0.0.1 *.test")
        let set = WildcardCollector.set(in: [local, fragment])
        #expect(set.rules.map(\.suffix) == ["test"])
        #expect(set.shadowedNames == ["api.test"])
        #expect(!set.isEmpty)
        #expect(WildcardSet.empty.isEmpty)
    }

    @Test func suffixPolicy_matchesClassify() {
        #expect(WildcardSuffixPolicy.isValid("app.test"))
        #expect(!WildcardSuffixPolicy.isValid("App.test"))
        #expect(!WildcardSuffixPolicy.isValid("../test"))
        #expect(!WildcardSuffixPolicy.isValid("evil'; rm -rf /"))
        #expect(!WildcardSuffixPolicy.isValid("example.com"))
        #expect(!WildcardSuffixPolicy.isValid("internal"))
        #expect(WildcardSuffixPolicy.isValid("svc.internal"))
        #expect(WildcardSuffixPolicy.isValid("test"))
    }

    @Test func collectableSuffix_requiresSingleValidWildcardAndIP() {
        #expect(WildcardCollector.collectableSuffix(ip: "127.0.0.1", hostnames: ["*.Test"]) == "test")
        #expect(WildcardCollector.collectableSuffix(ip: "127.0.0.1", hostnames: ["*.test", "a.test"]) == nil)
        #expect(WildcardCollector.collectableSuffix(ip: "nope", hostnames: ["*.test"]) == nil)
        #expect(WildcardCollector.collectableSuffix(ip: "127.0.0.1", hostnames: ["*.local"]) == nil)
        #expect(WildcardCollector.collectableSuffix(ip: "127.0.0.1", hostnames: ["www.test"]) == nil)
    }

    @Test func isWildcardAttempt_isAnyStar() {
        #expect(WildcardCollector.isWildcardAttempt(["a.test", "*.local"]))
        #expect(!WildcardCollector.isWildcardAttempt(["a.test"]))
    }
}
