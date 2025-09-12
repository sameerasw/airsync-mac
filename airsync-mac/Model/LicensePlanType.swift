//
//  LicensePlanType.swift
//  AirSync
//
//  Created by Sameera on 2025-08-23.
//

import Foundation

// Deprecated: Licensing removed for App Store build. Placeholder to avoid references.
enum LicensePlanType: String, CaseIterable, Codable, Identifiable { case membership, oneTime; var id: String { rawValue }; var displayName: String { rawValue } }
extension UserDefaults { var licensePlanType: LicensePlanType { get { .membership } set { } } }
