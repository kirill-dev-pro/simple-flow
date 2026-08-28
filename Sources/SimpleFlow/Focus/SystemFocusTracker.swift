import AppKit
import ApplicationServices
import Foundation

public final class SystemFocusTracker: FocusTracking, @unchecked Sendable {
    public typealias FrontmostAppProvider = @Sendable () -> (pid: pid_t, name: String?)?
    public typealias FocusedElementProvider = @Sendable () -> AXUIElement?
    public typealias EditableValidator = @Sendable (AXUIElement) -> Bool

    private let frontmostAppProvider: FrontmostAppProvider
    private let systemWideElementProvider: FocusedElementProvider
    private let editableValidator: EditableValidator

    public init(
        frontmostAppProvider: @escaping FrontmostAppProvider = {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            return (app.processIdentifier, app.localizedName)
        },
        systemWideElementProvider: @escaping FocusedElementProvider = {
            let systemWide = AXUIElementCreateSystemWide()
            var focused: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
            guard result == .success, let focusedElement = focused, CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
                return nil
            }
            return (focusedElement as! AXUIElement)
        },
        editableValidator: @escaping EditableValidator = { element in
            SystemFocusTracker.isElementEditable(element)
        }
    ) {
        self.frontmostAppProvider = frontmostAppProvider
        self.systemWideElementProvider = systemWideElementProvider
        self.editableValidator = editableValidator
    }

    public static func isElementEditable(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if roleResult == .success, let role = roleValue as? String {
            if role == (kAXMenuBarRole as String) ||
               role == (kAXMenuRole as String) ||
               role == (kAXMenuItemRole as String) ||
               role == (kAXApplicationRole as String) {
                return false
            }
            return true
        }

        var isValueSettable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isValueSettable) == .success,
           isValueSettable.boolValue {
            return true
        }

        var isSelectedTextSettable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &isSelectedTextSettable) == .success,
           isSelectedTextSettable.boolValue {
            return true
        }

        return false
    }

    public func capture() -> FocusSnapshot? {
        guard let app = frontmostAppProvider() else {
            AppLogger.focus.debug("No frontmost application available")
            return nil
        }
        guard let element = systemWideElementProvider() else {
            AppLogger.focus.debug("No focused Accessibility element in application: \(app.name ?? "unknown", privacy: .public)")
            return nil
        }
        guard editableValidator(element) else {
            AppLogger.focus.debug("Focused element is not editable in application: \(app.name ?? "unknown", privacy: .public)")
            return nil
        }
        let snapshot = FocusSnapshot(applicationPID: app.pid, applicationName: app.name, element: element)
        AppLogger.focus.debug("Captured focus: app=\(app.name ?? "unknown", privacy: .public), pid=\(app.pid)")
        return snapshot
    }

    public func stillMatches(_ snapshot: FocusSnapshot) -> Bool {
        guard let current = capture() else {
            AppLogger.focus.info("Focus validation failed: no current editable focus found (targetApp: \(snapshot.applicationName ?? "unknown", privacy: .public))")
            return false
        }
        let matches = current.matches(snapshot)
        AppLogger.focus.info("Focus validation: stillMatches=\(matches), targetApp=\(snapshot.applicationName ?? "unknown", privacy: .public), currentApp=\(current.applicationName ?? "unknown", privacy: .public)")
        return matches
    }
}
