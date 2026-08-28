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

    public init(state: FloatingHUDState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 12) {
            contentView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
                .overlay {
                    Capsule()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
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
                .frame(width: 10, height: 10)

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
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15), in: Capsule())
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
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.medium)
                Text("Inserted")
                    .font(.system(size: 13, weight: .medium))
            }

        case .savedToHistory:
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.blue)
                    .imageScale(.medium)
                Text("Saved to History")
                    .font(.system(size: 13, weight: .medium))
            }

        case .cancelled:
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.medium)
                Text("Cancelled")
                    .font(.system(size: 13, weight: .medium))
            }

        case .error(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .imageScale(.medium)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
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
