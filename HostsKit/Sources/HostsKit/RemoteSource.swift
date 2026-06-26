import Foundation

public enum SourceKind: String, Codable, Sendable {
    case builtin
    case custom
}

public enum SourceError: Error, Equatable, Sendable {
    case notFound
    case builtinNotRemovable
    case notHostsFormat
    case invalidURL
    case insecureURL
    case insecureRedirect
    case tooLarge
}

public struct RemoteSource: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var kind: SourceKind
    public var etag: String?
    public var lastModified: String?
    public var lastFetchedAt: Date?
    public var contentHash: String?
    public var domainCount: Int?
    public var lastError: String?

    public init(
        id: UUID, name: String, url: URL, kind: SourceKind,
        etag: String? = nil, lastModified: String? = nil, lastFetchedAt: Date? = nil,
        contentHash: String? = nil, domainCount: Int? = nil, lastError: String? = nil
    ) {
        self.id = id; self.name = name; self.url = url; self.kind = kind
        self.etag = etag; self.lastModified = lastModified; self.lastFetchedAt = lastFetchedAt
        self.contentHash = contentHash; self.domainCount = domainCount; self.lastError = lastError
    }
}

public enum BuiltinSources {
    public static let all: [RemoteSource] = [
        RemoteSource(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
            name: "StevenBlack (Unified)",
            url: URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts")!,
            kind: .builtin),
        RemoteSource(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!,
            name: "StevenBlack (Fake News)",
            url: URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-only/hosts")!,
            kind: .builtin),
        RemoteSource(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B4")!,
            name: "StevenBlack (Gambling)",
            url: URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts")!,
            kind: .builtin),
        RemoteSource(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B5")!,
            name: "StevenBlack (Porn)",
            url: URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts")!,
            kind: .builtin),
        RemoteSource(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B6")!,
            name: "StevenBlack (Social)",
            url: URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/social-only/hosts")!,
            kind: .builtin),
        RemoteSource(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
            name: "HaGeZi Light",
            url: URL(string: "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/light.txt")!,
            kind: .builtin),
        RemoteSource(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!,
            name: "HaGeZi Normal",
            url: URL(string: "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/multi.txt")!,
            kind: .builtin),
        RemoteSource(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
            name: "HaGeZi Pro",
            url: URL(string: "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.txt")!,
            kind: .builtin),
        RemoteSource(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!,
            name: "HaGeZi Pro++",
            url: URL(string: "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.plus.txt")!,
            kind: .builtin),
        RemoteSource(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C4")!,
            name: "HaGeZi Ultimate",
            url: URL(string: "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/ultimate.txt")!,
            kind: .builtin),
    ]
}
