import AppKit
import Foundation
import HostsKit
import Observation

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String, dmgURL: URL, size: Int)
    case downloading
    case failed(String)
}

@MainActor
@Observable
final class UpdateController {
    private(set) var state: UpdateState = .idle

    private let currentVersion: AppVersion?
    private let fetcher: ReleaseFetcher
    private let downloader: UpdateDownloader

    init(
        fetcher: ReleaseFetcher = ReleaseFetcher(),
        downloader: UpdateDownloader = UpdateDownloader(),
        bundleVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ) {
        self.fetcher = fetcher
        self.downloader = downloader
        self.currentVersion = bundleVersion.flatMap(AppVersion.init)
    }

    func checkNow(userInitiated: Bool) async {
        // Fail safe: an unparseable own version can't be compared, so never report a spurious update.
        guard let current = currentVersion else {
            state = .upToDate
            if userInitiated { showUpToDate() }
            return
        }

        state = .checking
        do {
            let release = try await fetcher.fetchLatest()
            switch UpdateAvailability.evaluate(current: current, release: release) {
            case .upToDate:
                state = .upToDate
                if userInitiated { showUpToDate() }
            case let .available(version, dmgURL, size):
                state = .available(version: Self.string(version), dmgURL: dmgURL, size: size)
                if userInitiated { promptAvailable() }
            }
        } catch {
            state = .failed(error.localizedDescription)
            if userInitiated {
                showFailure(error.localizedDescription)
            } else {
                print("Update check failed: \(error.localizedDescription)")
            }
        }
    }

    func downloadAndOpen() async {
        guard case let .available(version, dmgURL, size) = state else { return }
        state = .downloading
        do {
            _ = try await downloader.downloadAndOpen(
                dmgURL: dmgURL, suggestedName: "HostsSwitchr-\(version).dmg", expectedSize: size)
            showPostInstallHint()
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
            showFailure(error.localizedDescription)
        }
    }

    private static func string(_ version: AppVersion) -> String {
        "\(version.major).\(version.minor).\(version.patch)"
    }

    private func activate() { NSApplication.shared.activate(ignoringOtherApps: true) }

    private func showUpToDate() {
        activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "You're up to date"
        let version = currentVersion.map(Self.string) ?? ""
        alert.informativeText = "Hosts Switchr \(version) is the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func promptAvailable() {
        guard case let .available(version, _, _) = state else { return }
        activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update available"
        alert.informativeText = "Hosts Switchr \(version) is available. Download it and open the disk image to install?"
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await downloadAndOpen() }
        }
    }

    private func showFailure(_ message: String) {
        activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Update check failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showPostInstallHint() {
        activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update downloaded"
        alert.informativeText =
            "The disk image is open in Finder. To finish updating: quit Hosts Switchr first, "
            + "then drag it onto your Applications folder to replace this version, then reopen it."
            + "\n\nQuitting before you drag avoids a \u{201C}Hosts Switchr is in use\u{201D} error."
        alert.addButton(withTitle: "Quit Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            // applicationWillTerminate flushes any pending save before exit.
            NSApplication.shared.terminate(nil)
        }
    }
}
