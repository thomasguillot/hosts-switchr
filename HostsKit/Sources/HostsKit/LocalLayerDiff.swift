import Foundation

public enum LocalLayerDiff {
    public static func diff(old: String, new: String) -> (added: [String], removed: [String]) {
        let oldLines = nonBlankLines(old)
        let newLines = nonBlankLines(new)
        let oldSet = Set(oldLines)
        let newSet = Set(newLines)
        let added = newLines.filter { !oldSet.contains($0) }
        let removed = oldLines.filter { !newSet.contains($0) }
        return (added, removed)
    }

    private static func nonBlankLines(_ text: String) -> [String] {
        var out: [String] = []
        text.enumerateLines { line, _ in
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { out.append(line) }
        }
        return out
    }
}
