import Foundation
import Testing
@testable import HostsKit

@Suite struct GitHubReleaseTests {
    private let fixture = """
    {
      "tag_name": "v0.2.0",
      "html_url": "https://github.com/owner/repo/releases/tag/v0.2.0",
      "assets": [
        {
          "name": "HostsSwitchr-0.2.0.dmg",
          "browser_download_url": "https://github.com/owner/repo/releases/download/v0.2.0/HostsSwitchr-0.2.0.dmg",
          "content_type": "application/x-apple-diskimage",
          "size": 4194304
        },
        {
          "name": "source.zip",
          "browser_download_url": "https://github.com/owner/repo/releases/download/v0.2.0/source.zip",
          "content_type": "application/zip",
          "size": 1024
        }
      ]
    }
    """

    @Test func decodesTopLevelFields() throws {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(fixture.utf8))
        #expect(release.tagName == "v0.2.0")
        #expect(release.htmlURL == "https://github.com/owner/repo/releases/tag/v0.2.0")
        #expect(release.assets.count == 2)
    }

    @Test func decodesDMGAsset() throws {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(fixture.utf8))
        let dmg = try #require(release.assets.first)
        #expect(dmg.name == "HostsSwitchr-0.2.0.dmg")
        #expect(dmg.browserDownloadURL == "https://github.com/owner/repo/releases/download/v0.2.0/HostsSwitchr-0.2.0.dmg")
        #expect(dmg.browserDownloadURL.hasPrefix("https://"))
        #expect(dmg.contentType == "application/x-apple-diskimage")
        #expect(dmg.size == 4_194_304)
    }

    @Test func decodesNonDMGAsset() throws {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(fixture.utf8))
        let zip = release.assets[1]
        #expect(zip.name == "source.zip")
        #expect(zip.contentType == "application/zip")
        #expect(zip.size == 1024)
    }
}
