import Foundation

public enum DNSRcode: UInt8, Sendable {
    case noError = 0
    case formatError = 1
    case nxDomain = 3
    case notImplemented = 4
    case refused = 5
}

public struct DNSQuestion: Equatable, Sendable {
    public let name: String
    public let type: UInt16
    public let qclass: UInt16
    public let wire: Data
}

extension DNSQuestion {
    var hasHostnameLabels: Bool {
        var index = wire.startIndex
        while index < wire.endIndex {
            let length = Int(wire[index])
            if length == 0 { return true }
            let end = index + 1 + length
            guard length & 0xC0 == 0, end <= wire.endIndex,
                wire[(index + 1)..<end].allSatisfy(Self.isHostnameByte)
            else { return false }
            index = end
        }
        return false
    }

    private static func isHostnameByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
            UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"):
            return true
        default:
            return false
        }
    }
}

struct DNSAnswer {
    let type: UInt16
    let ttl: UInt32
    let rdata: Data
}

public enum DNSParseResult: Equatable, Sendable {
    case query(id: UInt16, recursionDesired: Bool, question: DNSQuestion)
    case formatError(id: UInt16, recursionDesired: Bool)
    case notImplemented(id: UInt16, recursionDesired: Bool)
    case drop
}

public enum DNSMessage {
    private static let headerLength = 12
    private static let maxNameLength = 255

    static func parse(_ data: Data) -> DNSParseResult {
        let base = data.startIndex
        guard data.count >= headerLength else { return .drop }
        func byte(_ offset: Int) -> UInt8 { data[base + offset] }
        func u16(_ offset: Int) -> UInt16 { UInt16(byte(offset)) << 8 | UInt16(byte(offset + 1)) }

        let id = u16(0)
        let flags = byte(2)
        guard flags & 0x80 == 0 else { return .drop }
        let recursionDesired = flags & 0x01 != 0
        guard (flags >> 3) & 0x0F == 0 else {
            return .notImplemented(id: id, recursionDesired: recursionDesired)
        }
        let formatError = DNSParseResult.formatError(id: id, recursionDesired: recursionDesired)
        guard u16(4) == 1 else { return formatError }

        var offset = headerLength
        var labels: [String] = []
        while true {
            guard offset < data.count else { return formatError }
            let length = Int(byte(offset))
            offset += 1
            if length == 0 { break }
            guard length & 0xC0 == 0, offset + length <= data.count else { return formatError }
            labels.append(String(decoding: data[(base + offset)..<(base + offset + length)], as: UTF8.self))
            offset += length
            guard offset - headerLength < maxNameLength else { return formatError }
        }
        guard offset + 4 <= data.count else { return formatError }
        let question = DNSQuestion(
            name: labels.joined(separator: "."),
            type: u16(offset),
            qclass: u16(offset + 2),
            wire: Data(data[(base + headerLength)..<(base + offset + 4)]))
        return .query(id: id, recursionDesired: recursionDesired, question: question)
    }

    static func response(
        id: UInt16, recursionDesired: Bool, rcode: DNSRcode, question: DNSQuestion?,
        answer: DNSAnswer?
    ) -> Data {
        var out = Data()
        func u16(_ value: UInt16) { out.append(UInt8(value >> 8)); out.append(UInt8(value & 0xFF)) }
        u16(id)
        out.append(0x80 | 0x04 | (recursionDesired ? 0x01 : 0x00))
        out.append(rcode.rawValue)
        u16(question == nil ? 0 : 1)
        u16(answer == nil ? 0 : 1)
        u16(0)
        u16(0)
        if let question { out.append(question.wire) }
        if let answer {
            u16(0xC00C)
            u16(answer.type)
            u16(1)
            u16(UInt16(answer.ttl >> 16))
            u16(UInt16(answer.ttl & 0xFFFF))
            u16(UInt16(clamping: answer.rdata.count))
            out.append(answer.rdata)
        }
        return out
    }
}

public enum WildcardDNSResponder {
    public static func response(
        to query: Data, matcher: WildcardMatcher, ttl: UInt32 = WildcardDNS.ttl
    ) -> Data? {
        switch DNSMessage.parse(query) {
        case .drop:
            return nil
        case let .formatError(id, recursionDesired):
            return DNSMessage.response(
                id: id, recursionDesired: recursionDesired, rcode: .formatError, question: nil,
                answer: nil)
        case let .notImplemented(id, recursionDesired):
            return DNSMessage.response(
                id: id, recursionDesired: recursionDesired, rcode: .notImplemented, question: nil,
                answer: nil)
        case let .query(id, recursionDesired, question):
            func reply(_ rcode: DNSRcode, rdata: Data? = nil) -> Data {
                DNSMessage.response(
                    id: id, recursionDesired: recursionDesired, rcode: rcode, question: question,
                    answer: rdata.map { DNSAnswer(type: question.type, ttl: ttl, rdata: $0) })
            }
            guard question.qclass == 1, question.hasHostnameLabels else { return reply(.refused) }
            switch matcher.resolve(name: question.name, type: question.type) {
            case let .address(rdata): return reply(.noError, rdata: rdata)
            case .noData: return reply(.noError)
            case .refused: return reply(.refused)
            }
        }
    }
}

public enum DNSFraming {
    public static func frame(_ message: Data) -> Data {
        let body = message.prefix(Int(UInt16.max))
        var out = Data([UInt8(body.count >> 8), UInt8(body.count & 0xFF)])
        out.append(body)
        return out
    }

    public static func split(_ buffer: inout Data) -> [Data] {
        var messages: [Data] = []
        var start = buffer.startIndex
        while buffer.endIndex - start >= 2 {
            let length = Int(buffer[start]) << 8 | Int(buffer[start + 1])
            let end = start + 2 + length
            guard end <= buffer.endIndex else { break }
            messages.append(Data(buffer[(start + 2)..<end]))
            start = end
        }
        if start != buffer.startIndex { buffer = Data(buffer[start...]) }
        return messages
    }
}
