import Foundation

public enum WildcardDNS {
    public static let defaultPort: UInt16 = 53535
    public static let ttl: UInt32 = 5
    public static let allowedParents: Set<String> = ["test", "internal"]
    public static let parentsNeedingSubdomain: Set<String> = ["internal"]
}

public enum WildcardHostname: Equatable, Sendable {
    case plain
    case wildcard(suffix: String)
    case notAllowed
    case tooBroad
    case invalid

    public static func classify(_ hostname: String) -> WildcardHostname {
        guard hostname.contains("*") else { return .plain }
        guard hostname.hasPrefix("*.") else { return .invalid }
        let suffix = String(hostname.dropFirst(2)).lowercased()
        let labels = suffix.split(separator: ".", omittingEmptySubsequences: false)
        guard !suffix.contains("*"), labels.allSatisfy(WildcardSuffixPolicy.isValidLabel) else {
            return .invalid
        }
        guard let parent = labels.last, WildcardDNS.allowedParents.contains(String(parent)) else {
            return .notAllowed
        }
        guard !WildcardSuffixPolicy.isWholeTLDNeedingSubdomain(labels) else { return .tooBroad }
        return .wildcard(suffix: suffix)
    }
}

public enum WildcardSuffixPolicy {
    static func isValidLabel(_ label: Substring) -> Bool {
        (1...63).contains(label.utf8.count)
            && label.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 }
    }

    static func isWholeTLDNeedingSubdomain(_ labels: [Substring]) -> Bool {
        labels.count == 1 && WildcardDNS.parentsNeedingSubdomain.contains(String(labels[0]))
    }

    public static func isValid(_ suffix: String) -> Bool {
        let labels = suffix.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy(isValidLabel), let parent = labels.last else { return false }
        return WildcardDNS.allowedParents.contains(String(parent)) && !isWholeTLDNeedingSubdomain(labels)
    }
}

public struct WildcardRule: Codable, Hashable, Sendable {
    public let suffix: String
    public var ipv4: String?
    public var ipv6: String?

    public init(suffix: String, ipv4: String?, ipv6: String?) {
        self.suffix = suffix
        self.ipv4 = ipv4
        self.ipv6 = ipv6
    }
}

public struct WildcardSet: Codable, Equatable, Sendable {
    public var rules: [WildcardRule]
    public var shadowedNames: Set<String>

    public static let empty = WildcardSet(rules: [], shadowedNames: [])

    public var isEmpty: Bool { rules.isEmpty }

    public init(rules: [WildcardRule], shadowedNames: Set<String>) {
        self.rules = rules
        self.shadowedNames = shadowedNames
    }
}

public enum WildcardCollector {
    public static func isWildcardAttempt(_ hostnames: [String]) -> Bool {
        hostnames.contains { $0.contains("*") }
    }

    public static func collectableSuffix(ip: String, hostnames: [String]) -> String? {
        guard hostnames.count == 1, HostsValidator.isValidIP(ip),
              case let .wildcard(suffix) = WildcardHostname.classify(hostnames[0]) else { return nil }
        return suffix
    }

    public static func rules(in files: [HostsFile]) -> [WildcardRule] {
        var order: [String] = []
        var bySuffixV4: [String: String] = [:]
        var bySuffixV6: [String: String] = [:]
        for file in files {
            for (ip, hostnames) in file.mappings {
                guard let suffix = collectableSuffix(ip: ip, hostnames: hostnames) else { continue }
                if !order.contains(suffix) { order.append(suffix) }
                if ip.contains(":") {
                    if bySuffixV6[suffix] == nil { bySuffixV6[suffix] = ip }
                } else if bySuffixV4[suffix] == nil {
                    bySuffixV4[suffix] = ip
                }
            }
        }
        return order.map { WildcardRule(suffix: $0, ipv4: bySuffixV4[$0], ipv6: bySuffixV6[$0]) }
    }

    public static func shadowedNames(in file: HostsFile, under rules: [WildcardRule]) -> Set<String> {
        var names: Set<String> = []
        for (ip, hostnames) in file.mappings where HostsValidator.isValidIP(ip) {
            for host in hostnames where !host.contains("*") {
                let name = host.lowercased()
                if rules.contains(where: { name == $0.suffix || name.hasSuffix("." + $0.suffix) }) {
                    names.insert(name)
                }
            }
        }
        return names
    }

    public static func set(in files: [HostsFile]) -> WildcardSet {
        let found = rules(in: files)
        let shadowed = files.reduce(into: Set<String>()) { $0.formUnion(shadowedNames(in: $1, under: found)) }
        return WildcardSet(rules: found, shadowedNames: shadowed)
    }
}
