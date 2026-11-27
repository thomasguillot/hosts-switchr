import Foundation

public enum ResolverFile {
    public static let directory = URL(fileURLWithPath: "/etc/resolver", isDirectory: true)
    public static let marker = "# Managed by Hosts Switchr. Removed when no wildcard needs it."

    public static func contents(port: UInt16) -> String {
        "\(marker)\nnameserver 127.0.0.1\nport \(String(port))\n"
    }

    public static func isManaged(_ contents: String) -> Bool {
        contents.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) == marker
    }
}

public enum ResolverDirectory {
    public static func read(_ dir: URL = ResolverFile.directory, fileManager: FileManager = .default) -> [String: String] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return [:] }
        var result: [String: String] = [:]
        for name in names where !name.hasPrefix(".") {
            let url = dir.appendingPathComponent(name)
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            if values?.isSymbolicLink != true, values?.isRegularFile == true,
                let text = try? String(contentsOf: url, encoding: .utf8)
            {
                result[name] = text
            } else {
                result[name] = ""
            }
        }
        return result
    }
}

public struct WildcardDeployment: Codable, Equatable, Sendable {
    public var served: WildcardSet
    public var resolverDomains: [String]
    public var port: UInt16

    public init(served: WildcardSet, resolverDomains: [String], port: UInt16) {
        self.served = served
        self.resolverDomains = resolverDomains
        self.port = port
    }
}

public struct ResolverPlan: Equatable, Sendable {
    public let writes: [String]
    public let removals: [String]
    public let unchanged: [String]
    public let foreign: [String]

    public init(writes: [String], removals: [String], unchanged: [String], foreign: [String]) {
        self.writes = writes
        self.removals = removals
        self.unchanged = unchanged
        self.foreign = foreign
    }

    public static func make(desired: [String], port: UInt16, existing: [String: String]) -> ResolverPlan {
        let wanted = Set(desired)
        let wantedLowercased = Set(desired.map { $0.lowercased() })
        let ours = ResolverFile.contents(port: port)
        var writes: [String] = []
        var unchanged: [String] = []
        var foreign: [String] = []
        for suffix in wanted {
            let hasCaseVariant = existing.keys.contains { $0 != suffix && $0.lowercased() == suffix.lowercased() }
            if hasCaseVariant {
                foreign.append(suffix)
            } else if let current = existing[suffix] {
                if !ResolverFile.isManaged(current) {
                    foreign.append(suffix)
                } else if current == ours {
                    unchanged.append(suffix)
                } else {
                    writes.append(suffix)
                }
            } else {
                writes.append(suffix)
            }
        }
        let removals = existing.filter { name, text in
            ResolverFile.isManaged(text) && !wantedLowercased.contains(name.lowercased())
                && WildcardSuffixPolicy.isValid(name)
        }.keys
        return ResolverPlan(
            writes: writes.sorted(), removals: removals.sorted(), unchanged: unchanged.sorted(),
            foreign: foreign.sorted())
    }

    public static func needsReapply(recorded: WildcardDeployment?, current: WildcardSet, existing: [String: String]) -> Bool {
        guard let recorded else { return !current.isEmpty }
        let expected = ResolverFile.contents(port: recorded.port)
        return recorded.resolverDomains.contains { existing[$0] != expected }
    }
}
