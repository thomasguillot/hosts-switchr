public protocol LoginItemControlling {
    var isEnabled: Bool { get }
    func enable() throws
    func disable() throws
}

public enum LaunchAtLogin {
    public static func apply(
        _ desired: Bool,
        to item: LoginItemControlling
    ) -> (isEnabled: Bool, error: String?) {
        do {
            if desired { try item.enable() } else { try item.disable() }
            return (item.isEnabled, nil)
        } catch {
            let verb = desired ? "enable" : "disable"
            return (item.isEnabled,
                    "Couldn't \(verb) launch at login: \(error.localizedDescription)")
        }
    }
}
