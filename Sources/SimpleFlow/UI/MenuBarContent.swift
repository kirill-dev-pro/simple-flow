import SwiftUI

public struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        Button("History…") {
            openWindow(id: "history")
        }
        Button("Settings…") {
            openWindow(id: "settings")
        }
        Divider()
        Button("Quit Simple Flow") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
