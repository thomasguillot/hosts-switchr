import Foundation

public enum HostsScan {
    public static func mappingLineCount(_ text: String) -> Int {
        var count = 0
        text.enumerateLines { line, _ in
            if case let .mapping(ip, _) = HostsFile.parseLine(line).kind,
               HostsValidator.isValidIP(ip) { count += 1 }
        }
        return count
    }

    public static func looksLikeHostsFile(_ text: String) -> Bool {
        var mapping = 0
        var content = 0
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return }
            content += 1
            if case let .mapping(ip, _) = HostsFile.parseLine(line).kind,
               HostsValidator.isValidIP(ip) {
                mapping += 1
            }
        }
        return mapping >= 1 && mapping * 2 > content
    }
}
