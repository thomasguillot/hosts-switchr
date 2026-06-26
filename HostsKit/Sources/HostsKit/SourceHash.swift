import Foundation
import CryptoKit

/// Single source of truth for the SHA-256 written at refresh and re-verified before merge; must not drift.
public enum SourceHash {
    public static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
