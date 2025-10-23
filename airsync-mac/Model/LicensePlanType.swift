//
//  LicensePlanType.swift
//  AirSync
//
//  Created by Sameera on 2025-08-23.
//

import Foundation

/// Represents which paid plan the user selected before activating a license.
/// Stored in UserDefaults via the `licensePlanType` key so the verification
/// Choose the correct Gumroad product id.
enum LicensePlanType: String, CaseIterable, Codable, Identifiable {
    case membership
    case oneTime
    #if SELF_COMPILED
    case selfCompiled
    #endif

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .membership: return "Membership"
        case .oneTime: return "One-Time"
        #if SELF_COMPILED
        case .selfCompiled: return "Self-Compiled"
        #endif
        }
    }
}

extension UserDefaults {
    private static let licensePlanTypeKey = "licensePlanType"

    var licensePlanType: LicensePlanType {
        get { LicensePlanType(rawValue: string(forKey: Self.licensePlanTypeKey) ?? "") ?? .membership }
        set { set(newValue.rawValue, forKey: Self.licensePlanTypeKey) }
    }
}
