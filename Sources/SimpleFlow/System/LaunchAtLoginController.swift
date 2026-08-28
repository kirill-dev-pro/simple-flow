import Foundation
import ServiceManagement

public protocol LaunchAtLoginControlling: AnyObject, Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

public final class LaunchAtLoginController: LaunchAtLoginControlling {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
