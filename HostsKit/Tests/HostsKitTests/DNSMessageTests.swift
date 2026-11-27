import Foundation
import Testing
@testable import HostsKit

private func query(_ name: String, type: UInt16, id: UInt16 = 0xBEEF, flags: UInt16 = 0x0100,
                   qdcount: UInt16 = 1, arcount: UInt16 = 0, additional: Data = Data()) -> Data {
    var d = Data()
    func u16(_ v: UInt16) { d.append(UInt8(v >> 8)); d.append(UInt8(v & 0xFF)) }
    u16(id); u16(flags); u16(qdcount); u16(0); u16(0); u16(arcount)
    for label in name.split(separator: ".") { d.append(UInt8(label.utf8.count)); d.append(contentsOf: label.utf8) }
    d.append(0); u16(type); u16(1)
    return d + additional
}
private func byte(_ r: Data, _ i: Int) -> UInt8 { r[r.startIndex + i] }
private func rcode(_ r: Data) -> UInt8 { byte(r, 3) & 0x0F }
private func count(_ r: Data, at i: Int) -> Int { Int(byte(r, i)) << 8 | Int(byte(r, i + 1)) }

@Suite struct DNSMessageTests {
    let matcher = WildcardMatcher(WildcardSet(
        rules: [WildcardRule(suffix: "test", ipv4: "127.0.0.1", ipv6: nil),
                WildcardRule(suffix: "app.test", ipv4: nil, ipv6: "::2")],
        shadowedNames: ["api.test"]))

    @Test func responder_answersA_withVerbatimQuestionEcho() throws {
        let q = query("Site.Test", type: 1)
        let r = try #require(WildcardDNSResponder.response(to: q, matcher: matcher))
        #expect(byte(r, 0) == 0xBE && byte(r, 1) == 0xEF)
        #expect(byte(r, 2) & 0x80 != 0)
        #expect(byte(r, 2) & 0x04 != 0)
        #expect(byte(r, 2) & 0x01 != 0)
        #expect(rcode(r) == 0)
        #expect(count(r, at: 4) == 1 && count(r, at: 6) == 1 && count(r, at: 10) == 0)
        #expect(Data(r[12..<q.count]) == Data(q[12..<q.count]))
        #expect(Array(r.suffix(16)) == [0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 5, 0, 4, 127, 0, 0, 1])
    }

    @Test func responder_answersAAAA() throws {
        let r = try #require(WildcardDNSResponder.response(to: query("x.app.test", type: 28), matcher: matcher))
        #expect(count(r, at: 6) == 1)
        #expect(Array(r.suffix(18).prefix(2)) == [0, 16])
    }

    @Test func responder_noErrorEmptyForMissingFamilyHTTPSAndExplicitNames() throws {
        for (name, type) in [("a.test", UInt16(28)), ("a.test", 65), ("api.test", 1), ("test", 1)] {
            let r = try #require(WildcardDNSResponder.response(to: query(name, type: type), matcher: matcher))
            #expect(rcode(r) == 0 && count(r, at: 6) == 0 && count(r, at: 4) == 1, "\(name) \(type)")
        }
    }

    @Test func responder_refusesOutsideSuffixes() throws {
        let r = try #require(WildcardDNSResponder.response(to: query("example.com", type: 1), matcher: matcher))
        #expect(rcode(r) == 5)
    }

    @Test func responder_answersQueryCarryingEDNSOptRecord() throws {
        let opt = Data([0, 0, 41, 0x10, 0, 0, 0, 0, 0, 0, 0])
        let r = try #require(WildcardDNSResponder.response(to: query("a.test", type: 1, arcount: 1, additional: opt), matcher: matcher))
        #expect(rcode(r) == 0 && count(r, at: 6) == 1 && count(r, at: 10) == 0)
    }

    @Test func responder_formatErrorForMalformedQuestions() throws {
        let truncated = Data(query("a.test", type: 1).prefix(15))
        var pointer = Data(query("a.test", type: 1).prefix(12)); pointer.append(contentsOf: [0xC0, 0x0C, 0, 1, 0, 1])
        for bad in [truncated, pointer, query("a.test", type: 1, qdcount: 2), query("a.test", type: 1, qdcount: 0)] {
            let r = try #require(WildcardDNSResponder.response(to: bad, matcher: matcher))
            #expect(rcode(r) == 1 && byte(r, 0) == 0xBE)
        }
    }

    @Test func responder_dropsShortInputAndResponses() {
        #expect(WildcardDNSResponder.response(to: Data([0xBE, 0xEF, 0]), matcher: matcher) == nil)
        #expect(WildcardDNSResponder.response(to: query("a.test", type: 1, flags: 0x8100), matcher: matcher) == nil)
    }

    @Test func responder_notImplementedForOtherOpcodes() throws {
        let r = try #require(WildcardDNSResponder.response(to: query("a.test", type: 1, flags: 0x1000), matcher: matcher))
        #expect(rcode(r) == 4)
    }

    @Test func responder_handlesSlicedData() throws {
        let sliced = (Data([0xFF, 0xFF]) + query("a.test", type: 1))[2...]
        let r = try #require(WildcardDNSResponder.response(to: sliced, matcher: matcher))
        #expect(rcode(r) == 0 && count(r, at: 6) == 1)
    }

    @Test func builder_setsNXDomain() {
        let r = DNSMessage.response(id: 7, recursionDesired: false, rcode: .nxDomain, question: nil, answer: nil)
        #expect(r.count == 12 && rcode(r) == 3 && count(r, at: 4) == 0)
    }

    @Test func framing_prefixesLengthAndSplitsStream() {
        #expect(DNSFraming.frame(Data(count: 300)).prefix(2) == Data([0x01, 0x2C]))
        let q1 = query("a.test", type: 1), q2 = query("b.test", type: 28)
        var buffer = DNSFraming.frame(q1) + DNSFraming.frame(q2) + Data([0x00])
        let messages = DNSFraming.split(&buffer)
        #expect(messages == [q1, q2])
        #expect(buffer == Data([0x00]))
    }

    @Test func parse_formatErrorForReservedLabelBitsAndOversizedNames() {
        var reserved = Data(query("a.test", type: 1).prefix(12)); reserved.append(contentsOf: [0x41, 0x61, 0, 0, 1, 0, 1])
        let long = (0..<5).map { _ in String(repeating: "a", count: 60) }.joined(separator: ".")
        for bad in [reserved, query(long, type: 1), Data(query("a.test", type: 1).dropLast(1))] {
            #expect(DNSMessage.parse(bad) == .formatError(id: 0xBEEF, recursionDesired: true))
        }
    }

    @Test func parse_returnsQuestionWithNameTypeClassAndWire() {
        let q = query("Site.Test", type: 28, flags: 0)
        let expected = DNSQuestion(name: "Site.Test", type: 28, qclass: 1, wire: Data(q[12...]))
        #expect(DNSMessage.parse(q) == .query(id: 0xBEEF, recursionDesired: false, question: expected))
    }

    @Test func parse_acceptsMaximumLengthName() {
        let name = (0..<3).map { _ in String(repeating: "a", count: 63) }.joined(separator: ".")
            + "." + String(repeating: "b", count: 61)
        guard case .query(_, _, let question) = DNSMessage.parse(query(name, type: 1)) else {
            Issue.record("expected a query")
            return
        }
        #expect(question.wire.count == 255 + 4)
    }

    @Test func parse_dropsEmptyInput() {
        #expect(DNSMessage.parse(Data()) == .drop)
    }

    @Test func responder_refusesNonINClassWithQuestionEcho() throws {
        var q = query("a.test", type: 1)
        q[q.count - 1] = 3
        let r = try #require(WildcardDNSResponder.response(to: q, matcher: matcher))
        #expect(rcode(r) == 5 && count(r, at: 4) == 1 && count(r, at: 6) == 0)
    }

    @Test func responder_refusesLabelsWithEmbeddedDotsOrNonHostnameBytes() throws {
        func raw(_ labels: [[UInt8]]) -> Data {
            var q = Data(query("a", type: 1).prefix(12))
            for label in labels { q.append(UInt8(label.count)); q.append(contentsOf: label) }
            q.append(contentsOf: [0, 0, 1, 0, 1])
            return q
        }
        let dotted = raw([Array("a.test".utf8)])
        let nonHostname = [raw([Array("a b".utf8), Array("test".utf8)]),
                           raw([[0x61, 0x00], Array("test".utf8)]),
                           raw([Array("é".utf8), Array("test".utf8)])]
        for bad in [dotted] + nonHostname {
            let r = try #require(WildcardDNSResponder.response(to: bad, matcher: matcher))
            #expect(rcode(r) == 5 && count(r, at: 4) == 1 && count(r, at: 6) == 0)
        }
        for label in ["A-1", "_x", "my_app"] {
            let r = try #require(WildcardDNSResponder.response(to: raw([Array(label.utf8), Array("test".utf8)]), matcher: matcher))
            #expect(rcode(r) == 0 && count(r, at: 6) == 1, "\(label)")
        }
    }

    @Test func responder_survivesEveryTruncationAndSingleByteMutation() {
        let seed = [UInt8](query("a.b.test", type: 1))
        for cut in 0...seed.count {
            _ = WildcardDNSResponder.response(to: Data(seed.prefix(cut)), matcher: matcher)
        }
        for position in seed.indices {
            for value in UInt8.min...UInt8.max {
                var bytes = seed
                bytes[position] = value
                _ = WildcardDNSResponder.response(to: Data(bytes), matcher: matcher)
                _ = WildcardDNSResponder.response(to: Data(bytes.dropLast(4)), matcher: matcher)
            }
        }
    }

    @Test func framing_keepsPartialHeaderAndBodyAndHandlesSlicedBuffers() {
        var header = Data([0x00])
        #expect(DNSFraming.split(&header).isEmpty && header == Data([0x00]))
        var partial = Data([0x00, 0x05, 1, 2])
        #expect(DNSFraming.split(&partial).isEmpty && partial == Data([0x00, 0x05, 1, 2]))
        var sliced = (Data([0xFF]) + DNSFraming.frame(Data([9, 8])) + Data([0x00, 0x00, 0x00]))[1...]
        #expect(DNSFraming.split(&sliced) == [Data([9, 8]), Data()])
        #expect(sliced == Data([0x00]))
    }
}
