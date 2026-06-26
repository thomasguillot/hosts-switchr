import Foundation

public enum MenuBarLabelText {
    public static func displayName(showName: Bool, activeName: String?, maxLength: Int = 24) -> String? {
        guard showName, let name = activeName else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxLength { return trimmed }
        return String(trimmed.prefix(maxLength - 1)) + "\u{2026}"
    }
}
