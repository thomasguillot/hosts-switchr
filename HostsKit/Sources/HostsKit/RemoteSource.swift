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
    ]
}
