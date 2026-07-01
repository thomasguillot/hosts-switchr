import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
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

private struct AboutButton: View {
    var body: some View {
        Button("About Hosts Switchr") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.orderFrontStandardAboutPanel(options: Self.options)
        }
    }

    private static var options: [NSApplication.AboutPanelOptionKey: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let credits = NSAttributedString(
            string: "Manage your /etc/hosts file through switchable profiles, blocklist sources, and reusable fragments.\n\nUnsigned and open-source — no Apple Developer Program required. See the Help menu to learn how it works.",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: style
            ])
        return [.credits: credits]
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
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: Self.defaultWindowSize.width, height: Self.defaultWindowSize.height)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) { AboutButton() }
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
                .environment(appDelegate.updateController)
        } label: {
            MenuBarLabel().environment(appDelegate.model)
        }
        .menuBarExtraStyle(.menu)
        Settings {
            SettingsView().environment(appDelegate.model)
        }
    }
}
