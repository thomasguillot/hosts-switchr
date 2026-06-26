import Foundation
import Observation

@MainActor
final class RefreshScheduler {
    private weak var model: AppModel?
    private var timer: Timer?
    private let prefs = Preferences()

    init(model: AppModel) { self.model = model }

    func start() {
        Task { [weak model] in await model?.refreshAllSources() }
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

    func stop() { timer?.invalidate(); timer = nil }
}
