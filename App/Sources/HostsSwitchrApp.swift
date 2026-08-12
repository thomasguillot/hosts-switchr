import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let router = WindowRouter()
    let updateController = UpdateController()
    lazy var updateScheduler = UpdateScheduler(controller: updateController)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The main window is suppressed, so bootstrap here to load/schedule on a quiet login-launch.
        model.bootstrap()
        updateScheduler.start()
    }

    func applicationDidResignActive(_ notification: Notification) {
        model.flushPendingSave()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.flushPendingSave()
    }
}

private struct DeleteCommand: View {
    @FocusedValue(\.deleteAction) private var deleteAction

    var body: some View {
        Button("Delete", role: .destructive) { deleteAction?() }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(deleteAction == nil)
    }
}

private struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    let router: WindowRouter

    var body: some View {
        Button("About Hosts Switchr") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            router.section = .about
            openWindow(id: "main")
        }
    }
}

private struct SettingsMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    let router: WindowRouter

    var body: some View {
        Button("Settings\u{2026}") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            router.section = .settings
            openWindow(id: "main")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

private struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Hosts Switchr Help") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "help")
        }
        .keyboardShortcut("?", modifiers: .command)
    }
}

@main
struct HostsSwitchrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private static var defaultWindowSize: CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: visible.width * 0.5, height: visible.height * 0.5)
    }

    var body: some Scene {
        Window("Hosts Switchr", id: "main") {
            MainWindowView()
                .frame(minWidth: 640, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
                .environment(appDelegate.model)
                .environment(appDelegate.router)
                .environment(appDelegate.updateController)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: Self.defaultWindowSize.width, height: Self.defaultWindowSize.height)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) { AboutMenuButton(router: appDelegate.router) }
            CommandGroup(replacing: .appSettings) { SettingsMenuButton(router: appDelegate.router) }
            CommandGroup(after: .pasteboard) { DeleteCommand() }
            CommandGroup(replacing: .help) { HelpMenuButton() }
        }
        Window("Hosts Switchr Help", id: "help") {
            DocumentationView()
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 560, height: 640)
        .windowResizability(.contentMinSize)
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.model)
                .environment(appDelegate.router)
                .environment(appDelegate.updateController)
        } label: {
            MenuBarLabel().environment(appDelegate.model)
        }
        .menuBarExtraStyle(.menu)
    }
}
