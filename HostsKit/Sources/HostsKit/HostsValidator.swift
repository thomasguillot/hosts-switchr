import Foundation

public struct HostsWarning: Equatable, Hashable, Sendable {
    public let line: Int
    public let message: String
    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }
}

public enum HostsValidator {
    public static func validate(_ file: HostsFile, inheritedWildcards: [WildcardRule] = []) -> [HostsWarning] {
        var warnings: [HostsWarning] = []
        var seenHostnames: [String: (ip: String, line: Int)] = [:]

        for (index, entry) in file.lines.enumerated() {
            let lineNo = index + 1
            guard case let .mapping(ip, hostnames) = entry.kind else { continue }

            if !isValidIP(ip) {
                warnings.append(HostsWarning(line: lineNo, message: "Malformed IP address: \(ip)"))
            }
            if let warning = wildcardWarning(hostnames) {
                warnings.append(HostsWarning(line: lineNo, message: warning))
            }
            for host in hostnames {
                let key = host.lowercased()
                if let seen = seenHostnames[key] {
                    let isLoopback = isLoopbackIP(ip)
                    let wasLoopback = isLoopbackIP(seen.ip)
                    if !(isLoopback && wasLoopback && ip != seen.ip) {
                        warnings.append(HostsWarning(
                            line: lineNo,
                            message: "Duplicate hostname \(host) (also on line \(seen.line))"))
                    }
                } else {
                    seenHostnames[key] = (ip, lineNo)
                }
            }
        }
        let overrides = overrideWarnings(in: file, inherited: inheritedWildcards)
        guard !overrides.isEmpty else { return warnings }
        return (warnings + overrides).enumerated()
            .sorted { ($0.element.line, $0.offset) < ($1.element.line, $1.offset) }
            .map(\.element)
    }

    private static func wildcardWarning(_ hostnames: [String]) -> String? {
        guard WildcardCollector.isWildcardAttempt(hostnames) else { return nil }
        if hostnames.count > 1 {
            return String(localized: "validator.wildcardMixed",
                          defaultValue: "A wildcard must be the only name on its line", bundle: .hostsKit)
        }
        let host = hostnames[0]
        switch WildcardHostname.classify(host) {
        case .notAllowed:
            return String(localized: "validator.wildcardNotAllowed",
                          defaultValue: "Wildcards only work under .test and .internal: \(host)", bundle: .hostsKit)
        case .tooBroad:
            return String(localized: "validator.wildcardTooBroad",
                          defaultValue: "\(host) would catch every .internal name. Use a name below it, such as *.app.internal",
                          bundle: .hostsKit)
        case .invalid:
            return String(localized: "validator.wildcardInvalid",
                          defaultValue: "Invalid wildcard: \(host). Use the form *.name.test", bundle: .hostsKit)
        case .plain, .wildcard:
            return nil
        }
    }

    private static func overrideWarnings(in file: HostsFile, inherited: [WildcardRule]) -> [HostsWarning] {
        let rules = WildcardCollector.rules(in: [file]) + inherited
        guard !rules.isEmpty else { return [] }
        var warnings: [HostsWarning] = []
        for (index, entry) in file.lines.enumerated() {
            guard case let .mapping(ip, hostnames) = entry.kind, isValidIP(ip) else { continue }
            for host in hostnames where !host.contains("*") {
                let name = host.lowercased()
                let covering = rules
                    .filter { name.hasSuffix("." + $0.suffix) }
                    .max { $0.suffix.count < $1.suffix.count }
                guard let rule = covering else { continue }
                let ruleIP = ip.contains(":") ? rule.ipv6 : rule.ipv4
                guard let ruleIP, ruleIP != ip else { continue }
                let wildcard = "*." + rule.suffix
                warnings.append(HostsWarning(
                    line: index + 1,
                    message: String(localized: "validator.wildcardOverride",
                                    defaultValue: "\(host) overrides \(wildcard)", bundle: .hostsKit)))
            }
        }
        return warnings
    }

    static func isLoopbackIP(_ ip: String) -> Bool {
        if ip.hasPrefix("127.") { return true }
        if ip == "::1" { return true }
        return false
    }

    static func isValidIP(_ ip: String) -> Bool {
        var v4 = in_addr()
        if inet_pton(AF_INET, ip, &v4) == 1 { return true }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, ip, &v6) == 1 { return true }
        return false
    }
}
