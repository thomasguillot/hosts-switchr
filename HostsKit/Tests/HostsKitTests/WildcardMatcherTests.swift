import Foundation
import Testing
@testable import HostsKit

@Suite struct WildcardMatcherTests {
    let matcher = WildcardMatcher(WildcardSet(
        rules: [WildcardRule(suffix: "test", ipv4: "127.0.0.1", ipv6: nil),
                WildcardRule(suffix: "app.test", ipv4: "10.0.0.2", ipv6: "::2")],
        shadowedNames: ["api.test"]))
    let v6two = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2])

    @Test func matchesAnyDepthUnderSuffix() {
        #expect(matcher.resolve(name: "a.test", type: 1) == .address(Data([127, 0, 0, 1])))
        #expect(matcher.resolve(name: "a.b.test", type: 1) == .address(Data([127, 0, 0, 1])))
    }

    @Test func mostSpecificWins() {
        #expect(matcher.resolve(name: "x.app.test", type: 1) == .address(Data([10, 0, 0, 2])))
        #expect(matcher.resolve(name: "x.app.test", type: 28) == .address(v6two))
    }

    @Test func otherTypesGetNoData() {
        #expect(matcher.resolve(name: "a.test", type: 28) == .noData)
        #expect(matcher.resolve(name: "a.test", type: 65) == .noData)
        #expect(matcher.resolve(name: "a.test", type: 15) == .noData)
    }

    @Test func apexAndEmptyNonTerminalGetNoData() {
        #expect(matcher.resolve(name: "test", type: 1) == .noData)
        let deep = WildcardMatcher(WildcardSet(rules: [WildcardRule(suffix: "app.test", ipv4: "10.0.0.2", ipv6: nil)], shadowedNames: []))
        #expect(deep.resolve(name: "app.test", type: 1) == .noData)
        #expect(deep.resolve(name: "test", type: 1) == .noData)
    }

    @Test func explicitNamesGetNoDataForEveryType() {
        #expect(matcher.resolve(name: "api.test", type: 1) == .noData)
        #expect(matcher.resolve(name: "API.Test.", type: 28) == .noData)
    }

    @Test func caseAndTrailingDotAreIgnored() {
        #expect(matcher.resolve(name: "Site.TEST.", type: 1) == .address(Data([127, 0, 0, 1])))
    }

    @Test func namesOutsideEverySuffixAreRefused() {
        #expect(matcher.resolve(name: "example.com", type: 1) == .refused)
        #expect(matcher.resolve(name: "nottest", type: 1) == .refused)
    }
}
