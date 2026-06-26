import Foundation
import HostsKit

struct PreviewData: Sendable {
    static let maxDiffRows = 100

    var profileID: UUID
    var profileName: String
    var addedLocal: [String]
    var removedLocal: [String]
    var addedOverflow: Int
    var removedOverflow: Int
    var stats: MergeStats
    var missingSources: [String]
}
