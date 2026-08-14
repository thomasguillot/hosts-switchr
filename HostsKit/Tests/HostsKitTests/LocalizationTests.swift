import Foundation
import Testing
@testable import HostsKit

// SwiftPM copies .xcstrings into the resource bundle verbatim — only Xcode compiles it to
// .lproj/.strings — so under `swift test` every lookup falls back to its defaultValue. These
// tests cover the English copy and interpolation; scripts/check-localizations.sh is what
// guarantees the other languages are present.
@Suite struct LocalizationTests {
    @Test func composeError_namesTheOffendingSource() {
        let message = ComposeError.cacheHashMismatch("StevenBlack").errorDescription

        #expect(message?.contains("StevenBlack") == true)
        #expect(message?.contains("checksum") == true)
        #expect(message?.contains("error.cacheHashMismatch") == false)
    }

    @Test func composeError_catalogCarriesEveryShippedLanguage() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/HostsKit/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        let strings = json?["strings"] as? [String: Any] ?? [:]

        #expect(!strings.isEmpty)
        for (key, entry) in strings {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for language in ["en", "fr", "es"] {
                #expect(localizations[language] != nil, "\(key) has no \(language) translation")
            }
        }
    }
}
