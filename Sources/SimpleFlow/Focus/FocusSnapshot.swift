import ApplicationServices
import Foundation

public struct FocusSnapshot: Equatable, @unchecked Sendable {
    public let applicationPID: pid_t
    public let applicationName: String?
    public let element: AXUIElement

    public init(applicationPID: pid_t, applicationName: String?, element: AXUIElement) {
        self.applicationPID = applicationPID
        self.applicationName = applicationName
        self.element = element
    }

    public func matches(_ other: FocusSnapshot) -> Bool {
        applicationPID == other.applicationPID && CFEqual(element, other.element)
    }

    public static func == (lhs: FocusSnapshot, rhs: FocusSnapshot) -> Bool {
        lhs.matches(rhs)
    }
}

public protocol FocusTracking: Sendable {
    func capture() -> FocusSnapshot?
    func stillMatches(_ snapshot: FocusSnapshot) -> Bool
}
