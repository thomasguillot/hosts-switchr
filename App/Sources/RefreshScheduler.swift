import Foundation
import HostsKit
import Observation

@MainActor
final class RefreshScheduler {
    // Grace period after launch before the first refresh, so a re-apply (admin prompt) doesn't hit the user mid-boot.
    static let launchGrace: TimeInterval = 300

    private weak var model: AppModel?
    private var timer: Timer?
    private let prefs = Preferences()

    init(model: AppModel) { self.model = model }

    func start() { schedule(isLaunch: true) }

    func reschedule() { schedule(isLaunch: false) }

    func stop() { timer?.invalidate(); timer = nil }

    private func schedule(isLaunch: Bool) {
        timer?.invalidate(); timer = nil
        guard let delay = RefreshSchedule.nextDelay(
            isLaunch: isLaunch,
            lastRefresh: prefs.lastRefreshAt,
            now: Date(),
            intervalHours: prefs.refreshIntervalHours,
            graceSeconds: Self.launchGrace
        ) else { return }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.model?.refreshAllSources()
                self?.schedule(isLaunch: false)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
