import Foundation
import HostsKit

extension AppModel {
    func warnings(for id: UUID) -> [HostsWarning] {
        guard let p = profiles.first(where: { $0.id == id }) else { return [] }
        return HostsValidator.validate(HostsFile(parsing: p.content),
                                       inheritedWildcards: WildcardCollector.rules(in: fragmentFiles(of: p)))
    }

    func activeWildcardSet() -> WildcardSet {
        guard let id = activeProfileID, let p = profiles.first(where: { $0.id == id }) else { return .empty }
        return WildcardCollector.set(in: [HostsFile(parsing: p.content)] + fragmentFiles(of: p))
    }

    private func fragmentFiles(of profile: Profile) -> [HostsFile] {
        resolveFragments(for: profile).map { HostsFile(parsing: $0.content) }
    }
}
