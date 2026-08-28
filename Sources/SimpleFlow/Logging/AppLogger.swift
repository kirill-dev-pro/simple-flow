import Foundation
import os

public enum AppLogger {
    public static let lifecycle = Logger(subsystem: AppIdentity.bundleIdentifier, category: "lifecycle")
    public static let audio = Logger(subsystem: AppIdentity.bundleIdentifier, category: "audio")
    public static let network = Logger(subsystem: AppIdentity.bundleIdentifier, category: "network")
    public static let focus = Logger(subsystem: AppIdentity.bundleIdentifier, category: "focus")
    public static let insertion = Logger(subsystem: AppIdentity.bundleIdentifier, category: "insertion")
}
