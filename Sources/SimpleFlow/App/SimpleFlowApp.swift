import SwiftData
import SwiftUI

@main
struct SimpleFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Simple Flow", systemImage: "mic") {
            MenuBarContent()
        }
        Window("History", id: "history") {
            HistoryView()
        }
        .modelContainer(for: TranscriptRecord.self)
        Window("Settings", id: "settings") {
            Text("Settings")
        }
    }
}

