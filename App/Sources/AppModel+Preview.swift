import Foundation
import HostsKit

extension AppModel {
    func previewData(for id: UUID) async -> PreviewData {
        guard let p = profiles.first(where: { $0.id == id }), let catalog else {
            return PreviewData(profileID: id, profileName: "", addedLocal: [], removedLocal: [],
                               addedOverflow: 0, removedOverflow: 0,
                               stats: MergeStats(totalDomains: 0, perSource: []), missingSources: [])
        }
        let activeLocal = activeProfileID.flatMap { aid in profiles.first { $0.id == aid }?.content } ?? ""
        let d = LocalLayerDiff.diff(old: activeLocal, new: p.content)
        let cap = PreviewData.maxDiffRows
        let added = Array(d.added.prefix(cap))
        let removed = Array(d.removed.prefix(cap))
        var perSource: [SourceStat] = []
        var total = 0
        var missing: [String] = []
        for fid in p.fragmentIDs {
            guard let f = fragments.first(where: { $0.id == fid }) else { continue }
            let count = HostsScan.mappingLineCount(f.content)
            perSource.append(SourceStat(name: f.name, domains: count))
            total += count
        }
        for sid in p.sourceIDs {
            guard let s = catalog.source(for: sid) else {
                missing.append("Unknown source (\(sid.uuidString.prefix(8)))")
                continue
            }
            let count = catalog.cachedDomainCount(for: sid) ?? 0
            perSource.append(SourceStat(name: s.name, domains: count))
            total += count
            if !FileManager.default.fileExists(atPath: catalog.cacheURL(for: sid).path) { missing.append(s.name) }
        }
        return PreviewData(profileID: id, profileName: p.name, addedLocal: added, removedLocal: removed,
                           addedOverflow: d.added.count - added.count,
                           removedOverflow: d.removed.count - removed.count,
                           stats: MergeStats(totalDomains: total, perSource: perSource), missingSources: missing)
    }
}
