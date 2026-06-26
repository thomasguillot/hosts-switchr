import ServiceManagement
import HostsKit

// Unsigned-compatible: mainApp registers a Login Item, not a signed daemon/agent helper.
struct SMAppServiceLoginItem: LoginItemControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func enable() throws { try SMAppService.mainApp.register() }
    func disable() throws { try SMAppService.mainApp.unregister() }
}
