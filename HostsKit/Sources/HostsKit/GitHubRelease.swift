/// Subset of `GET /repos/{owner}/{repo}/releases/latest` used to detect and locate an update.
public struct GitHubRelease: Codable, Sendable, Equatable {
    public let tagName: String
    public let htmlURL: String
    public let assets: [Asset]

    public init(tagName: String, htmlURL: String, assets: [Asset]) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.assets = assets
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
        case assets
    }
}
