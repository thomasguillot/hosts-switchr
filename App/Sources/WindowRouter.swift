import Observation

@MainActor
@Observable
final class WindowRouter {
    var section: SidebarSection = .profiles
}
