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
    private let installer: UpdateInstaller

    init(
        fetcher: ReleaseFetcher = ReleaseFetcher(),
        downloader: UpdateDownloader = UpdateDownloader(),
        installer: UpdateInstaller = UpdateInstaller(),
        bundleVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ) {
        self.fetcher = fetcher
        self.downloader = downloader
        self.installer = installer
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

    func downloadAndInstall() async {
        guard case let .available(version, dmgURL, size) = state else { return }
        state = .downloading
        do {
            let dmg = try await downloader.downloadToTemp(dmgURL: dmgURL, expectedSize: size)
            let installedPath = try installer.install(dmgAt: dmg)
            confirmAndRelaunch(version: version, path: installedPath)
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
            Task { await downloadAndInstall() }
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

    private func confirmAndRelaunch(version: String, path: String) {
        activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update installed"
        alert.informativeText =
            "Hosts Switchr \(version) is installed in your Applications folder. "
            + "It will relaunch now to finish updating."
        alert.addButton(withTitle: "Relaunch")
        // relaunch() terminates this instance; applicationWillTerminate flushes
        // any pending save first, and the spawned script reopens the new copy.
        alert.runModal()
        installer.relaunch(path: path)
    }
}
