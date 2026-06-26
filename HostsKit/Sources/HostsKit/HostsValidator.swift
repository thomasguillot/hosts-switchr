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
    public static func validate(_ file: HostsFile) -> [HostsWarning] {
        var warnings: [HostsWarning] = []
        var seenHostnames: [String: (ip: String, line: Int)] = [:]

        for (index, entry) in file.lines.enumerated() {
            let lineNo = index + 1
            guard case let .mapping(ip, hostnames) = entry.kind else { continue }

            if !isValidIP(ip) {
                warnings.append(HostsWarning(line: lineNo, message: "Malformed IP address: \(ip)"))
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
