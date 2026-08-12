import Foundation

/// GitHub release bodies → display blocks for the update window.
///
/// Block-level markdown only (headings, bullets, paragraphs); inline markdown is
/// left in the strings for the UI to render. Updater noise is dropped here — the
/// `## Install` section, the `**Requires macOS …**` line, and the DMG checksum —
/// all of which matter on the releases page but not to someone whose already-
/// running app is about to install the update for them.
public enum ReleaseNotes {
    public enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case bullet(String)
        case paragraph(String)
    }

    public static func blocks(from body: String) -> [Block] {
        var parser = Parser()
        for raw in body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            parser.consume(raw)
        }
        return parser.finish()
    }

    private struct Parser {
        private var blocks: [Block] = []
        private var paragraph: [String] = []
        private var skippingInstall = false
        private var bulletOpen = false   // true only directly after a bullet, for wrapped continuations

        mutating func consume(_ raw: String) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let (level, text) = heading(line) { consumeHeading(level: level, text: text); return }
            if skippingInstall { return }
            if line.isEmpty { flushParagraph(); bulletOpen = false; return }
            if isNoise(line) { return }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                bulletOpen = true
                return
            }
            if bulletOpen, raw.first?.isWhitespace == true, case .bullet(let text) = blocks.last {
                blocks[blocks.count - 1] = .bullet(text + " " + line)
                return
            }
            bulletOpen = false
            paragraph.append(line)
        }

        mutating func finish() -> [Block] {
            flushParagraph()
            return blocks
        }

        private mutating func consumeHeading(level: Int, text: String) {
            flushParagraph()
            bulletOpen = false
            if level <= 2, text.lowercased().hasPrefix("install") { skippingInstall = true; return }
            // Only a level ≤2 heading ends the skipped section; nested ones stay inside it.
            if skippingInstall {
                guard level <= 2 else { return }
                skippingInstall = false
            }
            if !text.isEmpty { blocks.append(.heading(level: level, text: text)) }
        }

        private mutating func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }
    }

    /// ATX heading: a run of `#` followed by a space or end of line.
    private static func heading(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }.count
        let rest = line.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        return (hashes, String(rest).trimmingCharacters(in: .whitespaces))
    }

    private static func isNoise(_ line: String) -> Bool {
        if line.hasPrefix("**Requires macOS") { return true }
        if line.lowercased().hasPrefix("**dmg sha-256**") { return true }
        return isChecksum(line)
    }

    /// A lone backticked hex digest — the checksum line under `**DMG SHA-256**`.
    private static func isChecksum(_ line: String) -> Bool {
        guard line.hasPrefix("`"), line.hasSuffix("`"), line.count >= 34 else { return false }
        let inner = line.dropFirst().dropLast()
        return inner.count >= 32 && inner.allSatisfy(\.isHexDigit)
    }
}
