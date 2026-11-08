import SwiftUI
import AppKit

@main
struct DroidBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("DroidBridge") {
            ContentView()
                .frame(minWidth: 820, minHeight: 500)
        }
        .commands {
            // Replaces the standard "About…" item in the app menu.
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppInfo.name)") {
                    openWindow(id: "about")
                }
            }
        }

        Window("About \(AppInfo.name)", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
