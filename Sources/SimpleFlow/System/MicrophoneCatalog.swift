import AVFoundation
import Foundation

public struct AudioInputDevice: Identifiable, Equatable, Hashable, Sendable {
    public let uid: String?
    public let name: String

    public var id: String {
        uid ?? "__system_default__"
    }

    public init(uid: String?, name: String) {
        self.uid = uid
        self.name = name
    }

    public static let systemDefault = AudioInputDevice(uid: nil, name: "System Default")
}

public protocol MicrophoneCataloging: Sendable {
    func availableDevices() -> [AudioInputDevice]
}

public final class MicrophoneCatalog: MicrophoneCataloging {
    public init() {}

    public func availableDevices() -> [AudioInputDevice] {
        var devices: [AudioInputDevice] = [.systemDefault]

        let deviceType: AVCaptureDevice.DeviceType
        if #available(macOS 14.0, *) {
            deviceType = .microphone
        } else {
            deviceType = .builtInMicrophone
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [deviceType, .external],
            mediaType: .audio,
            position: .unspecified
        )

        for device in discovery.devices {
            devices.append(AudioInputDevice(uid: device.uniqueID, name: device.localizedName))
        }

        return devices
    }
}
