import Foundation

public enum ComposeError: Error, Equatable, LocalizedError {
    case cacheHashMismatch(String)
    public var errorDescription: String? {
        switch self {
        case let .cacheHashMismatch(name):
            return String(localized: "error.cacheHashMismatch",
                          defaultValue: "Can't apply — the cached copy of \"\(name)\" doesn't match its verified checksum (it may be corrupted or was modified). Refresh that source and try again.",
                          bundle: .hostsKit)
        }
    }
}

/// expectedHash is nil when never refreshed → integrity check skipped.
public struct SourceLayer: Sendable, Equatable {
    public let name: String
    public let cacheURL: URL
    public let expectedHash: String?
    public let domainCount: Int?
    public init(name: String, cacheURL: URL, expectedHash: String?, domainCount: Int? = nil) {
        self.name = name; self.cacheURL = cacheURL; self.expectedHash = expectedHash
        self.domainCount = domainCount
    }
}

public struct NamedContent: Sendable, Equatable {
    public let name: String
    public let content: String
    public init(name: String, content: String) { self.name = name; self.content = content }
}

public struct SourceStat: Sendable, Equatable {
    public let name: String
    public let domains: Int
    public let wildcards: Int
    public init(name: String, domains: Int, wildcards: Int = 0) {
        self.name = name; self.domains = domains; self.wildcards = wildcards
    }
}

public struct MergeStats: Sendable, Equatable {
    public let totalDomains: Int
    public let perSource: [SourceStat]
    public let wildcards: WildcardSet
    public init(totalDomains: Int, perSource: [SourceStat], wildcards: WildcardSet = .empty) {
        self.totalDomains = totalDomains
        self.perSource = perSource
        self.wildcards = wildcards
    }
}

/// Merge order: local content → local fragments → remote sources, so first-match-wins gives local precedence.
public struct MergedHostsComposer: Sendable {
    public static let maxSourceShadowedNames = 10_000

    private nonisolated(unsafe) let fileManager: FileManager
    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    private static func commentingWildcards(_ text: String) -> String {
        guard text.contains("*") else { return text }
        return text.components(separatedBy: "\n").map { line in
            guard case let .mapping(ip, hostnames) = HostsFile.parseLine(line).kind,
                  WildcardCollector.collectableSuffix(ip: ip, hostnames: hostnames) != nil else { return line }
            return "# " + line.trimmingCharacters(in: .whitespacesAndNewlines) + "  (wildcard, served by Hosts Switchr)"
        }.joined(separator: "\n")
    }

    private static func shadowed(in texts: [String], under rules: [WildcardRule]) -> Set<String> {
        texts.reduce(into: Set<String>()) {
            $0.formUnion(WildcardCollector.shadowedNames(in: HostsFile(parsing: $1), under: rules))
        }
    }

    private static func lowercasedASCII(_ data: Data) -> Data {
        Data(data.map { (65...90).contains($0) ? $0 + 32 : $0 })
    }

    private static func sourceShadowed(in data: Data, under rules: [WildcardRule], limit: Int) -> Set<String> {
        guard limit > 0 else { return [] }
        let lowered = lowercasedASCII(data)
        let needles = rules.flatMap { rule in [".", " ", "\t"].map { $0 + rule.suffix } }
        guard needles.contains(where: { lowered.range(of: Data($0.utf8)) != nil }) else { return [] }
        var names: Set<String> = []
        for line in String(decoding: lowered, as: UTF8.self).split(separator: "\n")
        where needles.contains(where: { line.range(of: $0) != nil }) {
            for name in WildcardCollector.shadowedNames(in: HostsFile(parsing: String(line)), under: rules) {
                guard names.count < limit else { return names }
                names.insert(name)
            }
        }
        return names
    }

    public func compose(
        localContent: String,
        localFragments: [NamedContent],
        sources: [SourceLayer],
        to tempURL: URL
    ) throws -> MergeStats {
        let localRaw = [localContent] + localFragments.map(\.content)
        let localTexts = localRaw.map(Self.commentingWildcards)
        let rules = WildcardCollector.rules(in: localRaw.map { HostsFile(parsing: $0) })
        var shadowed: Set<String> = rules.isEmpty ? [] : Self.shadowed(in: localTexts, under: rules)

        var header = localTexts[0]
        if !header.isEmpty && !header.hasSuffix("\n") { header += "\n" }
        try header.data(using: .utf8)!.write(to: tempURL, options: .atomic)

        let handle = try FileHandle(forWritingTo: tempURL)
        defer { try? handle.close() }
        try handle.seekToEnd()

        var perSource: [SourceStat] = []
        var total = 0
        var fromSources: Set<String> = []

        for (index, fragment) in localFragments.enumerated() {
            let safeName = fragment.name.replacingOccurrences(of: "\r", with: " ")
                                        .replacingOccurrences(of: "\n", with: " ")
            try handle.write(contentsOf: Data("# \(safeName)\n".utf8))
            let data = Data(localTexts[index + 1].utf8)
            try handle.write(contentsOf: data)
            if let last = data.last, last != UInt8(ascii: "\n") {
                try handle.write(contentsOf: Data("\n".utf8))
            }
            let count = HostsScan.localDomainLineCount(fragment.content)
            perSource.append(SourceStat(name: fragment.name, domains: count,
                                        wildcards: HostsScan.wildcardLineCount(fragment.content)))
            total += count
        }

        for source in sources {
            // Fail closed: an unreadable cache aborts the merge rather than producing an incomplete hosts file.
            let data = try Data(contentsOf: source.cacheURL)
            // Integrity guard: a cache not matching its refresh-time checksum must not reach the privileged /etc/hosts write.
            if let expected = source.expectedHash, SourceHash.hex(data) != expected {
                throw ComposeError.cacheHashMismatch(source.name)
            }
            // Collapse CR/LF so the name can't break out of its `# ` comment line into a host mapping.
            let safeName = source.name.replacingOccurrences(of: "\r", with: " ")
                                      .replacingOccurrences(of: "\n", with: " ")
            try handle.write(contentsOf: Data("# \(safeName)\n".utf8))
            try handle.write(contentsOf: data)
            if let last = data.last, last != UInt8(ascii: "\n") {
                try handle.write(contentsOf: Data("\n".utf8))
            }
            if !rules.isEmpty {
                fromSources.formUnion(Self.sourceShadowed(
                    in: data, under: rules, limit: Self.maxSourceShadowedNames - fromSources.count))
            }
            let count = source.domainCount ?? HostsScan.mappingLineCount(String(decoding: data, as: UTF8.self))
            perSource.append(SourceStat(name: source.name, domains: count))
            total += count
        }
        shadowed.formUnion(fromSources)
        return MergeStats(totalDomains: total, perSource: perSource,
                          wildcards: WildcardSet(rules: rules, shadowedNames: shadowed))
    }
}
