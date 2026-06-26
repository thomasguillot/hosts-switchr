public struct HostsEntry: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case mapping(ip: String, hostnames: [String])
        case comment(String)
        case blank
    }

    public var kind: Kind
    public var raw: String

    public init(kind: Kind, raw: String) {
        self.kind = kind
        self.raw = raw
    }
}
