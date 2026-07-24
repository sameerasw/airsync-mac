//
//  BatteryInfo.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-18.
//

import Foundation
import IOKit.ps

struct BatteryStatus {
    let percentage: Int
    let isCharging: Bool
}

class BatteryInfo {
    static func fetchStatus() -> BatteryStatus? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            // Verify this is an internal battery power source
            if let type = description[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
                let maxCapacity = description[kIOPSMaxCapacityKey] as? Int ?? 100
                let percentage = maxCapacity > 0 ? Int((Double(currentCapacity) / Double(maxCapacity)) * 100.0) : currentCapacity

                let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
                let powerSourceState = description[kIOPSPowerSourceStateKey] as? String
                let isAC = (powerSourceState == kIOPSACPowerValue)

                return BatteryStatus(percentage: percentage, isCharging: isCharging || isAC)
            }
        }

        return nil
    }
}

