import Observation

enum SidebarSection: Hashable { case profiles, sources, fragments, settings }

@MainActor
@Observable
final class WindowRouter {
    var section: SidebarSection = .profiles
}
