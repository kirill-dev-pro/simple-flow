import SwiftUI

public struct OnboardingView: View {
    @ObservedObject public var viewModel: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "mic.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .foregroundStyle(.tint)

                Text("Welcome to Simple Flow")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Fast push-to-talk dictation for macOS. Before getting started, Simple Flow needs two system permissions:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 16) {
                // Microphone Row
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Microphone")
                            .font(.headline)
                        Text("Required to capture your voice when push-to-talk is active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if viewModel.microphoneStatus == .granted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else if viewModel.microphoneStatus == .denied {
                        Button("Open Settings") {
                            viewModel.openMicrophoneSettings()
                        }
                    } else {
                        Button("Grant Access") {
                            Task {
                                await viewModel.requestMicrophoneAccess()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                // Accessibility Row
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "accessibility")
                        .font(.title2)
                        .foregroundStyle(.primary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility")
                            .font(.headline)
                        Text("Required to monitor the global shortcut and paste text into active apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if viewModel.accessibilityStatus == .granted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            viewModel.requestAccessibilityAccess()
                            viewModel.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 8)

            VStack(spacing: 8) {
                Button("Finish Setup") {
                    viewModel.finish()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canFinish)

                if !viewModel.canFinish {
                    Text("Both permissions are required before you can start dictating.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(28)
        .frame(minWidth: 460, maxWidth: 500, minHeight: 380)
        .onAppear {
            viewModel.refreshPermissions()
        }
        .onReceive(Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()) { _ in
            viewModel.refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshPermissions()
        }
    }
}
