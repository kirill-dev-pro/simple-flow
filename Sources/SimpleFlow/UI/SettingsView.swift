import AppKit
import Carbon
import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var viewModel: SettingsViewModel
    @State private var isRecordingShortcut = false

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section("API Configuration") {
                TextField("Base URL", text: $viewModel.baseURL, prompt: Text("https://api.openai.com/v1"))
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if viewModel.isTokenRevealed {
                        TextField("API Token", text: $viewModel.token, prompt: Text("sk-..."))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Token", text: $viewModel.token, prompt: Text("sk-..."))
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        viewModel.isTokenRevealed.toggle()
                    } label: {
                        Image(systemName: viewModel.isTokenRevealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(viewModel.isTokenRevealed ? "Hide token" : "Show token")
                }

                TextField("Model", text: $viewModel.model, prompt: Text("gigaam"))
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Test Connection") {
                        Task {
                            await viewModel.testConnection()
                        }
                    }
                    .disabled(viewModel.isTestingConnection)

                    if viewModel.isTestingConnection {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 4)
                    }

                    if let result = viewModel.testConnectionResult {
                        ConnectionStatusBadge(result: result)
                    }
                }
                .padding(.top, 2)
            }

            Section("Audio") {
                Picker("Microphone", selection: $viewModel.microphoneDeviceUID) {
                    Text("System Default").tag(String?.none)
                    ForEach(viewModel.availableMicrophones.filter { $0.uid != nil }) { device in
                        Text(device.name).tag(device.uid as String?)
                    }
                }
            }

            Section("Push-to-Talk Shortcut") {
                HStack {
                    Text("Current Shortcut:")
                    Text(viewModel.hotkey.displayString)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    Button("Record Shortcut…") {
                        isRecordingShortcut = true
                    }

                    if !viewModel.hotkey.isFunctionKeyOnly {
                        Button("Reset to Fn") {
                            viewModel.hotkey = .functionKey
                        }
                    }
                }
            }

            Section("System Permissions") {
                HStack {
                    Label("Microphone", systemImage: "mic")
                    Spacer()
                    PermissionStatusBadge(status: viewModel.microphoneStatus)
                    if viewModel.microphoneStatus == .notDetermined {
                        Button("Grant Access") {
                            Task {
                                await viewModel.requestMicrophonePermission()
                            }
                        }
                    } else if viewModel.microphoneStatus == .denied {
                        Button("Open Settings") {
                            viewModel.openMicrophoneSettings()
                        }
                    }
                }

                HStack {
                    Label("Accessibility", systemImage: "accessibility")
                    Spacer()
                    PermissionStatusBadge(status: viewModel.accessibilityStatus)
                    if viewModel.accessibilityStatus == .granted {
                        // Already granted
                    } else {
                        Button("Grant Access / Settings") {
                            viewModel.requestAccessibilityPermission()
                            viewModel.openAccessibilitySettings()
                        }
                    }
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { val in
                        Task {
                            await viewModel.setLaunchAtLogin(val)
                        }
                    }
                ))
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Apply") {
                    Task {
                        await viewModel.apply()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 480)
        .sheet(isPresented: $isRecordingShortcut) {
            ShortcutRecorderSheet(currentHotkey: viewModel.hotkey) { newHotkey in
                viewModel.hotkey = newHotkey
                isRecordingShortcut = false
            } onCancel: {
                isRecordingShortcut = false
            }
        }
    }
}

private struct ConnectionStatusBadge: View {
    let result: ConnectionTestResult

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var label: String {
        switch result {
        case .reachable:
            return "Reachable"
        case .unauthorized:
            return "Unauthorized"
        case .modelsEndpointUnsupported:
            return "Models endpoint unsupported"
        case .server(let status):
            return "Server error (\(status))"
        case .transport(let code):
            return "Network error (\(code.rawValue))"
        case .invalidConfiguration(let reason):
            return "Invalid: \(reason)"
        }
    }

    private var color: Color {
        switch result {
        case .reachable:
            return .green
        case .modelsEndpointUnsupported:
            return .orange
        default:
            return .red
        }
    }
}

private struct PermissionStatusBadge: View {
    let status: PermissionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var label: String {
        switch status {
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Determined"
        }
    }

    private var color: Color {
        switch status {
        case .granted:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        }
    }
}

private struct ShortcutRecorderSheet: View {
    let currentHotkey: Hotkey
    let onSave: (Hotkey) -> Void
    let onCancel: () -> Void

    @State private var recordedHotkey: Hotkey?
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 20) {
            Text("Record Shortcut")
                .font(.headline)

            Text("Press any key combination or the Fn (Globe) key.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text((recordedHotkey ?? currentHotkey).displayString)
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.bold)
                .padding()
                .frame(minWidth: 200)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                Button("Use Fn Key") {
                    onSave(.functionKey)
                }

                Button("Cancel", role: .cancel) {
                    onCancel()
                }

                Button("Save") {
                    if let recorded = recordedHotkey {
                        onSave(recorded)
                    } else {
                        onSave(currentHotkey)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 220)
        .onAppear {
            recordedHotkey = currentHotkey
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                if event.modifierFlags.contains(.function) || (event.modifierFlags.rawValue & UInt(CGEventFlags.maskSecondaryFn.rawValue) != 0) {
                    self.recordedHotkey = .functionKey
                    return nil
                }
            } else if event.type == .keyDown {
                if event.keyCode == 53 { // Esc
                    self.onCancel()
                    return nil
                }

                let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
                self.recordedHotkey = Hotkey(
                    keyCode: event.keyCode,
                    modifiersRawValue: UInt64(modifiers.rawValue),
                    isFunctionKeyOnly: false
                )
                return nil
            }
            return event
        }
    }

    private func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
