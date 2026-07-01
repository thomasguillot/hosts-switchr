import Foundation
import HostsKit

struct ReleaseFetcher: Sendable {
    enum FetchError: Error { case insecureURL, badStatus(Int), tooLarge }

    private static let repoSlug = "thomasguillot/hosts-switchr"
    private static let maxBytes = 1024 * 1024

    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetchLatest() async throws -> GitHubRelease {
        let endpoint = "https://api.github.com/repos/\(Self.repoSlug)/releases/latest"
        guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https" else {
            throw FetchError.insecureURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw FetchError.badStatus(-1) }
        guard http.statusCode == 200 else { throw FetchError.badStatus(http.statusCode) }
        guard data.count <= Self.maxBytes else { throw FetchError.tooLarge }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}
