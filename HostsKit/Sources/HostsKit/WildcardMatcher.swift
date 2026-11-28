import Foundation

public enum DNSRecordType {
    public static let a: UInt16 = 1
    public static let aaaa: UInt16 = 28
}

public enum WildcardAnswer: Equatable, Sendable {
    case address(Data)
    case noData
    case refused
}

public struct WildcardMatcher: Sendable {
    private struct Entry: Sendable {
        let suffix: String
        let ipv4: Data?
        let ipv6: Data?
    }

    private let entries: [Entry]
    private let shadowed: Set<String>

    public init(_ set: WildcardSet) {
        entries = set.rules
            .map { Entry(suffix: $0.suffix.lowercased(), ipv4: Self.bytes($0.ipv4, family: AF_INET, length: 4), ipv6: Self.bytes($0.ipv6, family: AF_INET6, length: 16)) }
            .sorted { $0.suffix.count > $1.suffix.count }
        shadowed = Set(set.shadowedNames.map { $0.lowercased() })
    }

    public func resolve(name: String, type: UInt16) -> WildcardAnswer {
        var host = name.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        if shadowed.contains(host) { return .noData }
        if let entry = entries.first(where: { host.hasSuffix("." + $0.suffix) }) {
            let bytes: Data?
            switch type {
            case DNSRecordType.a: bytes = entry.ipv4
            case DNSRecordType.aaaa: bytes = entry.ipv6
            default: bytes = nil
            }
            return bytes.map(WildcardAnswer.address) ?? .noData
        }
        if entries.contains(where: { $0.suffix == host || $0.suffix.hasSuffix("." + host) }) {
            return .noData
        }
        return .refused
    }

    private static func bytes(_ text: String?, family: Int32, length: Int) -> Data? {
        guard let text else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        return inet_pton(family, text, &buffer) == 1 ? Data(buffer) : nil
    }
}
