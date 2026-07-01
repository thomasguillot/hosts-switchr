import Foundation
import HostsKit
import Observation

@MainActor
final class RefreshScheduler {
    // Grace period after launch before the first refresh, so a re-apply (admin prompt) doesn't hit the user mid-boot.
    static let launchDelay: Duration = .seconds(300)

    private weak var model: AppModel?
    private var timer: Timer?
    private var launchTask: Task<Void, Never>?
    private let prefs = Preferences()

    init(model: AppModel) { self.model = model }

    func start() {
        if RefreshDuePolicy.isDue(lastRefresh: prefs.lastRefreshAt, now: Date(), intervalHours: prefs.refreshIntervalHours) {
            launchTask = Task { [weak model] in
                do { try await Task.sleep(for: Self.launchDelay) } catch { return }
                await model?.refreshAllSources()
            }
        }
        reschedule()
    }

    func reschedule() {
        timer?.invalidate(); timer = nil
        guard let hours = prefs.refreshIntervalHours else { return }
        let interval = TimeInterval(hours) * 3600
        let t = Timer(timeInterval: interval, repeats: true) { [weak model] _ in
            Task { @MainActor in await model?.refreshAllSources() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { launchTask?.cancel(); launchTask = nil; timer?.invalidate(); timer = nil }
}
