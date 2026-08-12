import Foundation
import Testing
@testable import HostsKit

@Suite struct ReleaseNotesTests {
    @Test func parsesHeadingsBulletsAndParagraphs() {
        let blocks = ReleaseNotes.blocks(from: """
        ## What's new

        - **Profiles** — switch them.
        - Fragments.

        A closing paragraph.
        """)
        #expect(blocks == [
            .heading(level: 2, text: "What's new"),
            .bullet("**Profiles** — switch them."),
            .bullet("Fragments."),
            .paragraph("A closing paragraph."),
        ])
    }

    @Test func joinsWrappedParagraphLines() {
        let blocks = ReleaseNotes.blocks(from: "One line\nand its continuation.")
        #expect(blocks == [.paragraph("One line and its continuation.")])
    }

    @Test func joinsIndentedBulletContinuation() {
        let blocks = ReleaseNotes.blocks(from: "- A bullet that\n  wraps onto a second line.")
        #expect(blocks == [.bullet("A bullet that wraps onto a second line.")])
    }

    @Test func unindentedLineAfterBulletStartsAParagraph() {
        let blocks = ReleaseNotes.blocks(from: "- A bullet.\nNot a continuation.")
        #expect(blocks == [.bullet("A bullet."), .paragraph("Not a continuation.")])
    }

    @Test func handlesCRLF() {
        let blocks = ReleaseNotes.blocks(from: "## Title\r\n\r\n- One\r\n")
        #expect(blocks == [.heading(level: 2, text: "Title"), .bullet("One")])
    }

    @Test func treatsAsteriskBulletsLikeDashes() {
        #expect(ReleaseNotes.blocks(from: "* Starred") == [.bullet("Starred")])
    }

    @Test func hashWithoutSpaceIsNotAHeading() {
        #expect(ReleaseNotes.blocks(from: "#hashtag not a heading")
                == [.paragraph("#hashtag not a heading")])
    }

    // MARK: Updater noise — irrelevant to someone already running the app

    @Test func stripsInstallSectionUpToTheNextTopLevelHeading() {
        let blocks = ReleaseNotes.blocks(from: """
        ## What's new

        - A change.

        ## Install (unsigned app)

        1. Double-click the app.
        2. Open Anyway.

        ### A nested step

        More install detail.

        ## After install

        Kept.
        """)
        #expect(blocks == [
            .heading(level: 2, text: "What's new"),
            .bullet("A change."),
            .heading(level: 2, text: "After install"),
            .paragraph("Kept."),
        ])
    }

    @Test func stripsRequiresMacOSLine() {
        let blocks = ReleaseNotes.blocks(from: """
        Real content.

        **Requires macOS 26 (Tahoe) or later · Apple Silicon**.
        """)
        #expect(blocks == [.paragraph("Real content.")])
    }

    @Test func stripsChecksumLabelAndDigest() {
        let blocks = ReleaseNotes.blocks(from: """
        Real content.

        **DMG SHA-256**
        `22c32bf146a71783ce3623d6137bc4ed99d4afe5b8697627e14157cd0299a709`
        """)
        #expect(blocks == [.paragraph("Real content.")])
    }

    @Test func keepsOrdinaryInlineCode() {
        let blocks = ReleaseNotes.blocks(from: "Edit `/etc/hosts` directly.")
        #expect(blocks == [.paragraph("Edit `/etc/hosts` directly.")])
    }

    @Test func emptyBodyYieldsNoBlocks() {
        #expect(ReleaseNotes.blocks(from: "").isEmpty)
        #expect(ReleaseNotes.blocks(from: "\n\n  \n").isEmpty)
    }
}
