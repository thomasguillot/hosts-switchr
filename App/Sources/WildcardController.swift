import Foundation
import HostsKit
import Observation

struct PreparedResolver {
    let writes: [ResolverWrite]
    let removals: [String]
    let foreign: [String]
    let deployment: WildcardDeployment
}

struct AppliedWildcards {
    let deployment: WildcardDeployment
    var failure: String?
    var notice: String?
}

@MainActor
@Observable
final class WildcardController {
    private(set) var serviceState: WildcardServiceState = .stopped
    private(set) var served: WildcardDeployment?
    private(set) var foreignDomains: [String] = []
    private(set) var resolverDrift = false
    private var alertedForeign: [String] = []

    private let service: WildcardDNSService
    private let resolverDirectory: URL

    init(service: WildcardDNSService = WildcardDNSService(), resolverDirectory: URL = ResolverFile.directory) {
        self.service = service
        self.resolverDirectory = resolverDirectory
    }

    func prepare(_ set: WildcardSet) -> PreparedResolver {
        let port = WildcardDNS.defaultPort
        let plan = ResolverPlan.make(desired: set.rules.map(\.suffix), port: port,
                                     existing: ResolverDirectory.read(resolverDirectory))
        let foreign = Set(plan.foreign)
        let servedSet = WildcardSet(rules: set.rules.filter { !foreign.contains($0.suffix) },
                                    shadowedNames: set.shadowedNames)
        let deployment = WildcardDeployment(served: servedSet, resolverDomains: (plan.writes + plan.unchanged).sorted(),
                                            port: port)
        return PreparedResolver(writes: plan.writes.map { ResolverWrite(domain: $0, port: port) },
                                removals: plan.removals, foreign: plan.foreign, deployment: deployment)
    }

    func didApply(_ prepared: PreparedResolver, resolverFailed: Bool) -> AppliedWildcards {
        let deployment = resolverFailed ? merged(over: prepared.deployment) : prepared.deployment
        served = deployment
        foreignDomains = prepared.foreign
        resolverDrift = resolverFailed
            || ResolverPlan.needsReapply(recorded: deployment, current: deployment.served,
                                         existing: ResolverDirectory.read(resolverDirectory))
        serve(deployment.served, port: deployment.port)
        if resolverFailed {
            return AppliedWildcards(deployment: deployment, failure: String(localized: "The hosts file was updated, but wildcard domains couldn't be updated. /etc/resolver may have changed or may not be safe to write to. Apply again to retry."))
        }
        guard foreignDomains != alertedForeign else { return AppliedWildcards(deployment: deployment) }
        alertedForeign = foreignDomains
        return AppliedWildcards(deployment: deployment,
                                notice: foreignDomains.isEmpty ? nil : foreignDomains.map(Self.foreignLine).joined(separator: "\n"))
    }

    @discardableResult
    func restore(_ loaded: WildcardDeployment?, current: WildcardSet) -> Bool {
        let deployment = Self.trusted(loaded)
            ?? WildcardDeployment(served: current, resolverDomains: [], port: WildcardDNS.defaultPort)
        served = deployment
        recheck(loaded, current: current)
        alertedForeign = foreignDomains
        serve(deployment.served, port: deployment.port)
        return resolverDrift
    }

    var servesAnything: Bool {
        guard let served else { return false }
        return !served.served.isEmpty || !served.resolverDomains.isEmpty
    }

    func recheck(_ loaded: WildcardDeployment?, current: WildcardSet) {
        guard let served else { return }
        let existing = ResolverDirectory.read(resolverDirectory)
        let suffixes = Set(served.served.rules.map(\.suffix)).union(current.rules.map(\.suffix))
        foreignDomains = ResolverPlan.make(desired: Array(suffixes), port: served.port, existing: existing).foreign
        resolverDrift = ResolverPlan.needsReapply(recorded: Self.trusted(loaded), current: current, existing: existing)
    }

    private static func trusted(_ loaded: WildcardDeployment?) -> WildcardDeployment? {
        loaded?.isWithinPolicy == true ? loaded : nil
    }

    private func merged(over intended: WildcardDeployment) -> WildcardDeployment {
        guard let served else { return intended }
        let suffixes = Set(intended.served.rules.map(\.suffix))
        let rules = intended.served.rules + served.served.rules.filter { !suffixes.contains($0.suffix) }
        let set = WildcardSet(rules: rules, shadowedNames: intended.served.shadowedNames.union(served.served.shadowedNames))
        return WildcardDeployment(served: set, resolverDomains: intended.resolverDomains, port: served.port)
    }

    private func serve(_ set: WildcardSet, port: UInt16) {
        service.serve(set, port: port) { [weak self] state in self?.serviceState = state }
    }

    var menuLines: [String] {
        var lines: [String] = []
        if let served, !served.served.isEmpty {
            let suffixes = served.served.rules.map { "*." + $0.suffix }.joined(separator: ", ")
            let port = String(served.port)
            switch serviceState {
            case .ready: lines.append(String(localized: "Wildcards active: \(suffixes)"))
            case .portInUse: lines.append(String(localized: "Wildcards stopped: port \(port) is in use"))
            case .failed(let message): lines.append(String(localized: "Wildcards stopped: \(message)"))
            case .stopped: lines.append(String(localized: "Wildcards stopped"))
            }
        }
        return lines + foreignDomains.map(Self.foreignLine)
    }

    private static func foreignLine(_ domain: String) -> String {
        String(localized: "/etc/resolver/\(domain) belongs to another tool; *.\(domain) wildcards are off.")
    }
}
