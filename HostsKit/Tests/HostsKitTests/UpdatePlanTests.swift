import Foundation
import Testing
@testable import HostsKit

@Suite struct UpdatePlanTests {
    private func dmg(_ version: String, size: Int = 4096) -> GitHubRelease.Asset {
        GitHubRelease.Asset(
            name: "HostsSwitchr-\(version).dmg",
            browserDownloadURL: "https://github.com/owner/repo/releases/download/v\(version)/HostsSwitchr.dmg",
            contentType: "application/x-apple-diskimage", size: size)
    }

    private func release(_ tag: String, body: String = "", draft: Bool = false,
                         prerelease: Bool = false, assets: [GitHubRelease.Asset]? = nil) -> GitHubRelease {
        GitHubRelease(
            tagName: tag, htmlURL: "https://github.com/owner/repo/releases/tag/\(tag)",
            body: body, draft: draft, prerelease: prerelease,
            assets: assets ?? [dmg(tag.hasPrefix("v") ? String(tag.dropFirst()) : tag)])
    }

    private let current = AppVersion("1.0.0")!

    @Test func picksNewestNewerReleaseAsTheDownloadTarget() {
        let plan = UpdateAvailability.plan(
            current: current,
            releases: [release("v1.1.0"), release("v1.2.1", assets: [dmg("1.2.1", size: 9999)]), release("v0.9.0")])
        #expect(plan?.version == AppVersion("1.2.1")!)
        #expect(plan?.size == 9999)
    }

    @Test func aggregatesNotesForEveryReleaseNewerThanCurrentNewestFirst() {
        let plan = UpdateAvailability.plan(
            current: current,
            releases: [release("v1.1.0", body: "- Middle"),
                       release("v1.0.0", body: "- Already have this"),
                       release("v1.2.0", body: "- Newest"),
                       release("v0.9.0", body: "- Ancient")])
        #expect(plan?.notes.map(\.version) == ["1.2.0", "1.1.0"])
        #expect(plan?.notes.first?.blocks == [.bullet("Newest")])
        #expect(plan?.notes.last?.blocks == [.bullet("Middle")])
    }

    @Test func nilWhenNothingIsNewer() {
        #expect(UpdateAvailability.plan(current: current,
                                        releases: [release("v1.0.0"), release("v0.4.0")]) == nil)
    }

    @Test func nilForAnEmptyReleaseList() {
        #expect(UpdateAvailability.plan(current: current, releases: []) == nil)
    }

    @Test func excludesDraftsAndPrereleases() {
        let plan = UpdateAvailability.plan(
            current: current,
            releases: [release("v2.0.0", body: "- Draft", draft: true),
                       release("v1.9.0", body: "- Prerelease", prerelease: true),
                       release("v1.1.0", body: "- Real")])
        #expect(plan?.version == AppVersion("1.1.0")!)
        #expect(plan?.notes.map(\.version) == ["1.1.0"])
    }

    @Test func dropsUnparseableTagsFromNotesAndSelection() {
        let plan = UpdateAvailability.plan(
            current: current,
            releases: [release("nightly", body: "- Unparseable"), release("v1.1.0", body: "- Real")])
        #expect(plan?.version == AppVersion("1.1.0")!)
        #expect(plan?.notes.map(\.version) == ["1.1.0"])
    }

    // Fail closed: a newest release that isn't installable must not silently
    // offer an older one the user never saw at the top of the releases page.
    @Test func nilWhenNewestReleaseHasNoDMG() {
        let zip = GitHubRelease.Asset(
            name: "source.zip", browserDownloadURL: "https://github.com/owner/repo/x.zip",
            contentType: "application/zip", size: 10)
        #expect(UpdateAvailability.plan(
            current: current,
            releases: [release("v1.2.0", assets: [zip]), release("v1.1.0")]) == nil)
    }

    @Test func nilWhenNewestReleaseDMGIsNotHTTPS() {
        let insecure = GitHubRelease.Asset(
            name: "HostsSwitchr.dmg", browserDownloadURL: "http://github.com/owner/repo/x.dmg",
            contentType: "application/x-apple-diskimage", size: 10)
        #expect(UpdateAvailability.plan(
            current: current, releases: [release("v1.2.0", assets: [insecure])]) == nil)
    }

    @Test func stripsInstallNoiseFromAggregatedNotes() {
        let body = """
        ## What's new

        - A change.

        ## Install (unsigned app)

        Do the Gatekeeper dance.

        **Requires macOS 26 (Tahoe) or later · Apple Silicon**.
        """
        let plan = UpdateAvailability.plan(current: current, releases: [release("v1.1.0", body: body)])
        #expect(plan?.notes.first?.blocks == [
            .heading(level: 2, text: "What's new"), .bullet("A change."),
        ])
    }
}

@Suite struct UpdatePromptGateTests {
    private let latest = AppVersion("1.2.0")!

    @Test func interactiveAlwaysPromptsEvenWhenSkipped() {
        #expect(UpdatePromptGate.shouldPrompt(latest: latest, skipped: latest, interactive: true))
    }

    @Test func backgroundPromptsWhenNothingSkipped() {
        #expect(UpdatePromptGate.shouldPrompt(latest: latest, skipped: nil, interactive: false))
    }

    @Test func backgroundStaysSilentForTheSkippedVersion() {
        #expect(!UpdatePromptGate.shouldPrompt(latest: latest, skipped: latest, interactive: false))
    }

    @Test func backgroundStaysSilentForAVersionOlderThanSkipped() {
        #expect(!UpdatePromptGate.shouldPrompt(
            latest: AppVersion("1.1.0")!, skipped: latest, interactive: false))
    }

    @Test func backgroundPromptsAgainForAReleaseNewerThanSkipped() {
        #expect(UpdatePromptGate.shouldPrompt(
            latest: AppVersion("1.3.0")!, skipped: latest, interactive: false))
    }
}
