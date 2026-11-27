import Foundation
import HostsKit
import Observation

struct PreparedResolver {
    let writes: [ResolverWrite]
    let removals: [String]
    let foreign: [String]
    let deployment: WildcardDeployment
    let stagedURL: URL?

    func discardStaging() {
        guard let stagedURL else { return }
        try? FileManager.default.removeItem(at: stagedURL)
    }
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

    func prepare(_ set: WildcardSet) throws -> PreparedResolver {
        let port = WildcardDNS.defaultPort
        let plan = ResolverPlan.make(desired: set.rules.map(\.suffix), port: port,
                                     existing: ResolverDirectory.read(resolverDirectory))
        var stagedURL: URL?
        if !plan.writes.isEmpty {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("hostsswitchr-resolver-\(UUID().uuidString)")
            try ResolverFile.contents(port: port).write(to: url, atomically: true, encoding: .utf8)
            stagedURL = url
        }
        let foreign = Set(plan.foreign)
        let servedSet = WildcardSet(rules: set.rules.filter { !foreign.contains($0.suffix) },
                                    shadowedNames: set.shadowedNames)
        let deployment = WildcardDeployment(served: servedSet, resolverDomains: (plan.writes + plan.unchanged).sorted(),
                                            port: port)
        let writes = stagedURL.map { url in plan.writes.map { ResolverWrite(domain: $0, stagedPath: url.path) } } ?? []
        return PreparedResolver(writes: writes, removals: plan.removals, foreign: plan.foreign,
                                deployment: deployment, stagedURL: stagedURL)
    }

    func didApply(_ prepared: PreparedResolver, resolverFailed: Bool) -> String? {
        let deployment = resolverFailed ? retained(over: prepared.deployment) : prepared.deployment
        served = deployment
        foreignDomains = prepared.foreign
        resolverDrift = resolverFailed
            || ResolverPlan.needsReapply(recorded: deployment, current: deployment.served,
                                         existing: ResolverDirectory.read(resolverDirectory))
        serve(deployment.served, port: deployment.port)
        if resolverFailed {
            return String(localized: "The hosts file was updated, but wildcard domains couldn't be set up. /etc/resolver must be a folder owned by root.")
        }
        guard foreignDomains != alertedForeign else { return nil }
        alertedForeign = foreignDomains
        return foreignDomains.isEmpty ? nil : foreignDomains.map(Self.foreignLine).joined(separator: "\n")
    }

    @discardableResult
    func restore(_ recorded: WildcardDeployment?, current: WildcardSet) -> Bool {
        let deployment = recorded ?? WildcardDeployment(served: current, resolverDomains: [], port: WildcardDNS.defaultPort)
        let existing = ResolverDirectory.read(resolverDirectory)
        served = deployment
        let suffixes = Set(deployment.served.rules.map(\.suffix)).union(current.rules.map(\.suffix))
        foreignDomains = ResolverPlan.make(desired: Array(suffixes), port: deployment.port, existing: existing).foreign
        alertedForeign = foreignDomains
        resolverDrift = ResolverPlan.needsReapply(recorded: recorded, current: current, existing: existing)
        serve(deployment.served, port: deployment.port)
        return resolverDrift
    }

    private func retained(over intended: WildcardDeployment) -> WildcardDeployment {
        guard let served else { return intended }
        return WildcardDeployment(served: served.served, resolverDomains: intended.resolverDomains, port: served.port)
    }

    private func serve(_ set: WildcardSet, port: UInt16) {
        service.serve(set, port: port) { [weak self] state in self?.serviceState = state }
    }

    private static func foreignLine(_ domain: String) -> String {
        String(localized: "/etc/resolver/\(domain) belongs to another tool; *.\(domain) wildcards are off.")
    }
}
