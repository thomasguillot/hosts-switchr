/// Subset of `GET /repos/{owner}/{repo}/releases` used to detect, describe, and locate an update.
public struct GitHubRelease: Codable, Sendable, Equatable {
    public let tagName: String
    public let htmlURL: String
    public let body: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    public init(tagName: String, htmlURL: String, body: String = "",
                draft: Bool = false, prerelease: Bool = false, assets: [Asset]) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.body = body
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try c.decode(String.self, forKey: .tagName)
        htmlURL = try c.decode(String.self, forKey: .htmlURL)
        // Absent/null on releases published without notes — not a decode failure.
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        draft = try c.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try c.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        assets = try c.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    public struct Asset: Codable, Sendable, Equatable {
        public let name: String
        public let browserDownloadURL: String
        public let contentType: String
        public let size: Int

        public init(name: String, browserDownloadURL: String, contentType: String, size: Int) {
            self.name = name
            self.browserDownloadURL = browserDownloadURL
            self.contentType = contentType
            self.size = size
        }

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case contentType = "content_type"
            case size
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case draft
        case prerelease
        case assets
    }
}
