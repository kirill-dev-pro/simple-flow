import SwiftUI

public struct FloatingHUDState: Equatable, Sendable {
    public var phase: DictationPhase
    public var isLimitWarning: Bool
    public var recordingStartDate: Date?

    public init(
        phase: DictationPhase = .idle,
        isLimitWarning: Bool = false,
        recordingStartDate: Date? = nil
    ) {
        self.phase = phase
        self.isLimitWarning = isLimitWarning
        self.recordingStartDate = recordingStartDate
    }
}

public struct FloatingHUDView: View {
    public let state: FloatingHUDState
    public var onDismiss: (() -> Void)?

    public init(state: FloatingHUDState, onDismiss: (() -> Void)? = nil) {
        self.state = state
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 10) {
            contentView
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
        }
        .padding(6)
        .onTapGesture {
            onDismiss?()
        }
        .animation(.easeInOut(duration: 0.2), value: state.phase)
        .animation(.easeInOut(duration: 0.2), value: state.isLimitWarning)
    }

    @ViewBuilder
    private var contentView: some View {
        switch state.phase {
        case .idle:
            EmptyView()

        case .recording:
            recordingView

        case .transcribing:
            transcribingView

        case .feedback(let kind):
            feedbackView(for: kind)
        }
    }

    @ViewBuilder
    private var recordingView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .shadow(color: Color.red.opacity(0.6), radius: 3)

            if let startDate = state.recordingStartDate {
                TimelineView(.periodic(from: startDate, by: 0.5)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(startDate))
                    Text(formatDuration(elapsed))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
            } else {
                Text("0:00")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }

            if state.isLimitWarning {
                Text("10s remaining")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            Text("Esc to cancel")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var transcribingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Transcribing…")
                .font(.system(size: 13, weight: .medium))
        }
    }

    @ViewBuilder
    private func feedbackView(for kind: FeedbackKind) -> some View {
        switch kind {
        case .inserted:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.small)
                Text("Inserted")
                    .font(.system(size: 13, weight: .medium))
            }

        case .savedToHistory:
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.blue)
                    .imageScale(.small)
                Text("Saved to History")
                    .font(.system(size: 13, weight: .medium))
            }

        case .cancelled:
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text("Cancelled")
                    .font(.system(size: 13, weight: .medium))
            }

        case .error(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .imageScale(.small)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
