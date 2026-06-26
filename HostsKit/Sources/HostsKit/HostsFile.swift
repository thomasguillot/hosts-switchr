import Foundation

public struct HostsFile: Equatable, Sendable {
    public var lines: [HostsEntry]
    public var trailingNewline: Bool

    public init(lines: [HostsEntry], trailingNewline: Bool = false) {
        self.lines = lines
        self.trailingNewline = trailingNewline
    }

    public init(parsing text: String) {
        if text.isEmpty {
            self.lines = []
            self.trailingNewline = false
            return
        }
        var rawLines = text.components(separatedBy: "\n")
        let hasTrailingNewline = rawLines.last == ""
        if hasTrailingNewline { rawLines.removeLast() }
        self.lines = rawLines.map { HostsFile.parseLine($0) }
        self.trailingNewline = hasTrailingNewline
    }

    static func parseLine(_ raw: String) -> HostsEntry {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return HostsEntry(kind: .blank, raw: raw) }
        if trimmed.hasPrefix("#") { return HostsEntry(kind: .comment(trimmed), raw: raw) }

        let beforeComment = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let tokens = beforeComment.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let ip = tokens.first, tokens.count >= 2 else {
            return HostsEntry(kind: .comment(trimmed), raw: raw)
        }
        let hostnames = Array(tokens.dropFirst())
        return HostsEntry(kind: .mapping(ip: ip, hostnames: hostnames), raw: raw)
    }

    public func serialized() -> String {
        lines.map(\.raw).joined(separator: "\n") + (trailingNewline ? "\n" : "")
    }

    public var mappings: [(ip: String, hostnames: [String])] {
        lines.compactMap { entry in
            if case let .mapping(ip, hostnames) = entry.kind { return (ip, hostnames) }
            return nil
        }
    }
}
