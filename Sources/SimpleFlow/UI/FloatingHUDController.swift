import AppKit
import SwiftUI

public protocol HUDPresenting: AnyObject, Sendable {
    @MainActor func show(_ phase: DictationPhase)
    @MainActor func showLimitWarning()
    @MainActor func hide()
}

extension HUDPresenting {
    public func showLimitWarning() {}
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
public final class FloatingHUDController: HUDPresenting {
    private var panel: NonActivatingPanel?
    private var hostingView: NSHostingView<FloatingHUDView>?
    private var currentState = FloatingHUDState()

    private var autoHideTask: Task<Void, Never>?

    public init() {}

    private func ensurePanel() -> NonActivatingPanel {
        if let panel = self.panel {
            return panel
        }

        let initialView = FloatingHUDView(state: currentState) { [weak self] in
            self?.hide()
        }
        let hostingView = NSHostingView(rootView: initialView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        self.hostingView = hostingView

        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 40),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView

        self.panel = panel
        return panel
    }

    public func show(_ phase: DictationPhase) {
        autoHideTask?.cancel()
        autoHideTask = nil

        if phase == .idle {
            hide()
            return
        }

        let isRecording = phase == .recording
        currentState.phase = phase
        currentState.isLimitWarning = isRecording ? currentState.isLimitWarning : false
        if isRecording && currentState.recordingStartDate == nil {
            currentState.recordingStartDate = Date()
        } else if !isRecording {
            currentState.recordingStartDate = nil
        }

        updateViewAndPosition()

        if case .feedback(let kind) = phase {
            let delay: TimeInterval
            switch kind {
            case .error:
                delay = 3.0
            default:
                delay = 1.5
            }
            autoHideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    public func showLimitWarning() {
        guard currentState.phase == .recording else { return }
        currentState.isLimitWarning = true
        updateViewAndPosition()
    }

    public func hide() {
        autoHideTask?.cancel()
        autoHideTask = nil
        currentState = FloatingHUDState()
        panel?.orderOut(nil)
    }

    private func updateViewAndPosition() {
        let panel = ensurePanel()
        hostingView?.rootView = FloatingHUDView(state: currentState) { [weak self] in
            self?.hide()
        }

        hostingView?.layoutSubtreeIfNeeded()
        let fittingSize = hostingView?.fittingSize ?? NSSize(width: 200, height: 40)
        panel.setContentSize(fittingSize)

        positionPanel(panel)
        panel.orderFront(nil)
    }

    private func positionPanel(_ panel: NSPanel) {
        let screen: NSScreen = {
            if let mouseLoc = CGEvent(source: nil)?.location {
                let screens = NSScreen.screens
                let flippedY = screens.first?.frame.height ?? 0
                let point = NSPoint(x: mouseLoc.x, y: flippedY - mouseLoc.y)
                if let matched = screens.first(where: { NSPointInRect(point, $0.frame) }) {
                    return matched
                }
            }
            return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        }()

        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let originX = visibleFrame.origin.x + (visibleFrame.width - panelSize.width) / 2.0
        let originY = visibleFrame.origin.y + 60.0

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}
