import Foundation
import Cocoa
import IOKit

enum HardwareInfo {
    static func hardwareUUID() -> String? {
        let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict)
        defer { IOObjectRelease(platformExpert) }

        guard platformExpert != 0 else { return nil }

        let uuidKey = "IOPlatformUUID" as CFString
        guard let uuidProperty = IORegistryEntryCreateCFProperty(platformExpert, uuidKey, kCFAllocatorDefault, 0) else {
            return nil
        }

        let uuid = uuidProperty.takeRetainedValue() as? String
        return uuid
    }

    static var deviceName: String {
        return Host.current().localizedName ?? "Mac"
    }

    static var modelName: String {
        return DeviceTypeUtil.deviceFullDescription()
    }

    static var osVersion: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
}
