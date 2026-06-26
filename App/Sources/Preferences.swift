import Foundation

struct Preferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Keys {
        static let refreshIntervalHours = "refreshIntervalHours"   // 0 = Off
        static let autoReapply = "autoReapply"
    }

    // nil = Off; defaults to 24h on first run.
    var refreshIntervalHours: Int? {
        get {
            if defaults.object(forKey: Keys.refreshIntervalHours) == nil { return 24 }
            let v = defaults.integer(forKey: Keys.refreshIntervalHours)
            return v == 0 ? nil : v
        }
        set { defaults.set(newValue ?? 0, forKey: Keys.refreshIntervalHours) }
    }

    var autoReapply: Bool {
        get {
            if defaults.object(forKey: Keys.autoReapply) == nil { return true }
            return defaults.bool(forKey: Keys.autoReapply)
        }
        set { defaults.set(newValue, forKey: Keys.autoReapply) }
    }
}
