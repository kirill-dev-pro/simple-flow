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
            if role == (kAXTextFieldRole as String) ||
               role == (kAXTextAreaRole as String) ||
               role == (kAXComboBoxRole as String) {
                return true
            }
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
        guard let app = frontmostAppProvider() else { return nil }
        guard let element = systemWideElementProvider() else { return nil }
        guard editableValidator(element) else { return nil }
        return FocusSnapshot(applicationPID: app.pid, applicationName: app.name, element: element)
    }

    public func stillMatches(_ snapshot: FocusSnapshot) -> Bool {
        guard let current = capture() else { return false }
        return current.matches(snapshot)
    }
}
