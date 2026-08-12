import Observation

enum SidebarSection: Hashable { case profiles, sources, fragments, about, settings }

@MainActor
@Observable
final class WindowRouter {
    var section: SidebarSection = .profiles
}
