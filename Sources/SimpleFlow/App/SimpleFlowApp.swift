import SwiftUI

@main
struct SimpleFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Simple Flow", systemImage: "mic") {
            MenuBarContent()
        }
        Window("History", id: "history") {
            Text("No transcripts yet")
        }
        Window("Settings", id: "settings") {
            Text("Settings")
        }
    }
}
