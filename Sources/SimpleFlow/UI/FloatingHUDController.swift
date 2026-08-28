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

    public init() {}

    private func ensurePanel() -> NonActivatingPanel {
        if let panel = self.panel {
            return panel
        }

        let initialView = FloatingHUDView(state: currentState)
        let hostingView = NSHostingView(rootView: initialView)
        self.hostingView = hostingView

        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 48),
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
    }

    public func showLimitWarning() {
        guard currentState.phase == .recording else { return }
        currentState.isLimitWarning = true
        updateViewAndPosition()
    }

    public func hide() {
        currentState = FloatingHUDState()
        panel?.orderOut(nil)
    }

    private func updateViewAndPosition() {
        let panel = ensurePanel()
        hostingView?.rootView = FloatingHUDView(state: currentState)

        hostingView?.layoutSubtreeIfNeeded()
        let fittingSize = hostingView?.fittingSize ?? NSSize(width: 260, height: 48)
        let size = NSSize(width: max(fittingSize.width, 180), height: max(fittingSize.height, 44))
        panel.setContentSize(size)

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
