import Foundation

/// Single enforcement point for the https-only source-URL policy; all add/import paths must route through this.
public enum SourceURLPolicy {
    public static func validated(_ urlString: String) throws -> URL {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, url.host != nil else {
            throw SourceError.invalidURL
        }
        guard scheme.lowercased() == "https" else { throw SourceError.insecureURL }
        return url
    }
}
