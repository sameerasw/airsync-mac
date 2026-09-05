import Foundation
import CoreBluetooth

struct BLEConstants {
    private static let uuidBase = "-7461-4694-8146-2162624a682c"

    // Services
    static let serviceSystem = CBUUID(string: "a1520001\(uuidBase)")
    static let serviceNotifications = CBUUID(string: "a1520002\(uuidBase)")
    static let serviceMedia = CBUUID(string: "a1520003\(uuidBase)")
    static let serviceClipboard = CBUUID(string: "a1520004\(uuidBase)")

    // System Characteristics
    static let charProtocolVersion = CBUUID(string: "a1520101\(uuidBase)")
    static let charAuthToken = CBUUID(string: "a1520102\(uuidBase)")
    static let charAuthResult = CBUUID(string: "a1520103\(uuidBase)")
    static let charBatteryLevel = CBUUID(string: "a1520104\(uuidBase)")
    static let charMacBattery = CBUUID(string: "a1520105\(uuidBase)")
    static let charSystemState = CBUUID(string: "a1520106\(uuidBase)")
    static let charMacControl = CBUUID(string: "a1520107\(uuidBase)")
    static let charDeviceName = CBUUID(string: "a1520108\(uuidBase)")

    // Notification Characteristics
    static let charNotificationData = CBUUID(string: "a1520201\(uuidBase)")
    static let charNotificationAction = CBUUID(string: "a1520202\(uuidBase)")
    static let charNotificationDismiss = CBUUID(string: "a1520203\(uuidBase)")
    static let charNotificationDismissNotify = CBUUID(string: "a1520204\(uuidBase)")

    // Media Characteristics
    static let charMediaState = CBUUID(string: "a1520301\(uuidBase)")
    static let charMediaControl = CBUUID(string: "a1520302\(uuidBase)")
    static let charMacMediaState = CBUUID(string: "a1520303\(uuidBase)")

    // Clipboard Characteristics
    static let charClipboardDataNotify = CBUUID(string: "a1520401\(uuidBase)")
    static let charClipboardDataWrite = CBUUID(string: "a1520402\(uuidBase)")

    // Protocol Constants
    static let protocolVersion: UInt8 = 1
    static let authSuccess: UInt8 = 0x01
    static let authFailed: UInt8 = 0x00

    // Chunking
    static let chunkHeaderSize = 4 // [index: UInt16][total: UInt16]
    
    // Delimiter
    static let delimiter = "\u{001F}"
}
