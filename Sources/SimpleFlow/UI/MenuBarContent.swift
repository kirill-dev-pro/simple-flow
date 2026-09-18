import AppKit
import Carbon
import SwiftData
import SwiftUI

public struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \TranscriptRecord.createdAt, order: .reverse) private var records: [TranscriptRecord]
    @ObservedObject private var coordinator: AppCoordinator
    @State private var copiedRecently = false

    public init(coordinator: AppCoordinator? = nil) {
        if let coordinator = coordinator {
            self.coordinator = coordinator
        } else if let appDelegateCoordinator = AppDelegate.shared?.coordinator {
            self.coordinator = appDelegateCoordinator
        } else {
            // Fallback for previews
            self.coordinator = AppCoordinator(
                hotkeyMonitor: HotkeyMonitor(),
                audioRecorder: AudioRecorder(),
                focusTracker: SystemFocusTracker(),
                transcriptionClient: TranscriptionClient(),
                textInserter: TextInserter(),
                historyRepository: HistoryRepository(context: DatabaseContainerFactory.shared.mainContext),
                settingsStore: SettingsStore(),
                hudPresenter: FloatingHUDController()
            )
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Header with App Title, Hotkey hint & Live Status Pill
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Simple Flow")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Hold Fn to dictate")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                StatusPill(phase: coordinator.phase)
            }

            // 2. Secure Input warning
            if HotkeyMonitorDiagnostic.secureInputEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                    Text("Secure Input is active (may block Fn)")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            Divider()

            // 3. Action buttons
            VStack(spacing: 2) {
                MenuActionButton(
                    title: copiedRecently ? "Copied to clipboard!" : lastDictationTitle,
                    systemImage: copiedRecently ? "checkmark" : "doc.on.doc",
                    iconColor: copiedRecently ? .green : nil,
                    isDisabled: records.isEmpty
                ) {
                    if let latest = records.first {
                        copyText(latest.text)
                    }
                }

                MenuActionButton(
                    title: "History…",
                    systemImage: "clock.arrow.circlepath"
                ) {
                    if let delegate = AppDelegate.shared {
                        delegate.showHistoryWindow()
                    } else {
                        openWindow(id: "history")
                    }
                }

                MenuActionButton(
                    title: "Settings…",
                    systemImage: "gearshape"
                ) {
                    if let delegate = AppDelegate.shared {
                        delegate.showSettingsWindow()
                    } else {
                        openWindow(id: "settings")
                    }
                }
            }

            Divider()

            // 4. Quit
            MenuActionButton(
                title: "Quit Simple Flow",
                systemImage: "power",
                shortcut: "⌘Q",
                role: .destructive
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private var lastDictationTitle: String {
        guard let latest = records.first else {
            return "Copy last transcript"
        }
        let clean = latest.text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if clean.isEmpty {
            return "Copy last transcript"
        }
        if clean.count > 26 {
            let prefix = clean.prefix(25)
            return "Copy: \"\(prefix)…\""
        } else {
            return "Copy: \"\(clean)\""
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            copiedRecently = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.15)) {
                    copiedRecently = false
                }
            }
        }
    }
}

private struct StatusPill: View {
    let phase: DictationPhase

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusTitle: String {
        switch phase {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing"
        case .feedback(let kind):
            switch kind {
            case .inserted:
                return "Inserted"
            case .savedToHistory:
                return "Saved"
            case .cancelled:
                return "Cancelled"
            case .error:
                return "Error"
            }
        }
    }

    private var statusColor: Color {
        switch phase {
        case .idle:
            return .green
        case .recording:
            return .red
        case .transcribing:
            return .blue
        case .feedback(let kind):
            switch kind {
            case .inserted:
                return .green
            case .savedToHistory:
                return .blue
            case .cancelled:
                return .secondary
            case .error:
                return .yellow
            }
        }
    }
}

private struct MenuActionButton: View {
    let title: String
    let systemImage: String
    var shortcut: String? = nil
    var role: ButtonRole? = nil
    var iconColor: Color? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundStyle(iconColor ?? (role == .destructive ? Color.red : Color.primary))

                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(role == .destructive ? Color.red : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                !isDisabled && isHovered
                    ? (role == .destructive ? Color.red.opacity(0.1) : Color.primary.opacity(0.06))
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1.0)
        .onHover { hovering in
            if !isDisabled {
                isHovered = hovering
            }
        }
    }
}
