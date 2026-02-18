//
//  Gumroad.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-31.
//

import Foundation
import AppKit

// New: error type to distinguish network/server failures from invalid license results
enum LicenseCheckError: Error {
    case network(Error)           // Transport / connectivity issues (timeouts, offline, DNS, etc.)
    case server(String)           // Non-OK HTTP or malformed responses
}

class Gumroad {
    let appState = AppState.shared

    func checkLicenseKeyValidity(key: String, save: Bool, isNewRegistration: Bool) async throws -> Bool {

        // Select product id based on chosen plan
        let selectedPlan = UserDefaults.standard.licensePlanType
        let membershipProductID = "smrIThhDxoQI33gQm3wwxw=="
        let oneTimeProductID = "3HkBPf4ovp7KiVISJS6N5A=="
        let productID = (selectedPlan == .oneTime) ? oneTimeProductID : membershipProductID
        let url = URL(string: "https://api.gumroad.com/v2/licenses/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let bodyComponents: [String: String] = [
            "product_id": productID,
            "license_key": key,
            "increment_uses_count": isNewRegistration ? "true" : "false"
        ]

        request.httpBody = bodyComponents
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Transport / connectivity error
            throw LicenseCheckError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseCheckError.server("Invalid HTTP response")
        }

        // Treat 404 as an invalid license (not a network error)
        if httpResponse.statusCode == 404 {
            if save {
                AppState.shared.isPlus = false
                AppState.shared.licenseDetails = nil
            }
            return false
        }

        // Accept only 2xx here; other codes are server-ish problems
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LicenseCheckError.server("HTTP \(httpResponse.statusCode)")
        }

        // Parse JSON
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let success = json["success"] as? Bool,
            let purchase = json["purchase"] as? [String: Any]
        else {
            throw LicenseCheckError.server("Malformed JSON")
        }

        // If Gumroad says not success => invalid license
        guard success else {
            if save {
                AppState.shared.isPlus = false
                AppState.shared.licenseDetails = nil
            }
            return false
        }

        // Subscription-only fields — for one-time purchase these may be nil/empty.
        let cancelledAt = purchase["subscription_cancelled_at"] as? String
        let endedAt = purchase["subscription_ended_at"] as? String
        let failedAt = purchase["subscription_failed_at"] as? String

        // Membership plan must be active; otherwise invalid
        if selectedPlan == .membership {
            if [cancelledAt, endedAt, failedAt].contains(where: { dateStr in
                if let s = dateStr, !s.isEmpty { return true }
                return false
            }) {
                if save {
                    AppState.shared.isPlus = false
                    AppState.shared.licenseDetails = nil
                }
                return false
            }
        }

        // Device limit logic — if exceeded we treat as invalid
        let currentUsesCount = json["uses"] as? Int ?? 0
        let previousUsesCount = AppState.shared.licenseDetails?.usesCount ?? currentUsesCount
        if (currentUsesCount - previousUsesCount) > 3 {
            if save {
                AppState.shared.isPlus = false
                AppState.shared.licenseDetails = nil
            }
            return false
        }

        // Valid license
        if save {
            AppState.shared.isPlus = true
            let details = LicenseDetails(
                key: key,
                email: purchase["email"] as? String ?? "unknown",
                productName: purchase["product_name"] as? String ?? "unknown",
                orderNumber: purchase["order_number"] as? Int ?? 0,
                purchaserID: purchase["purchaser_id"] as? String ?? "",
                usesCount: json["uses"] as? Int ?? 0,
                price: purchase["price"] as? Int ?? 0,
                currency: purchase["currency"] as? String ?? "usd",
                saleTimestamp: purchase["sale_timestamp"] as? String ?? "",
                subscriptionCancelledAt: cancelledAt,
                subscriptionEndedAt: endedAt,
                subscriptionFailedAt: failedAt,
                refunded: purchase["refunded"] as? Bool ?? false,
                disputed: purchase["disputed"] as? Bool ?? false,
                chargebacked: purchase["chargebacked"] as? Bool ?? false
            )
            AppState.shared.licenseDetails = details
        }

        return true
    }

    func clearLicenseDetails() {
        AppState.shared.licenseDetails = nil
        UserDefaults.standard.removeObject(forKey: "licenseDetailsKey")
        UserDefaults.standard.consecutiveLicenseFailCount = 0
    }

    func incrementInvalidLicenseFailCount() {
        let failCount = UserDefaults.standard.consecutiveLicenseFailCount + 1
        UserDefaults.standard.consecutiveLicenseFailCount = failCount

        if failCount >= 3 {
            Gumroad().clearLicenseDetails()
            print("[gumroad] License check failed \(failCount) times — license removed")
        }
    }

    func performUnregisterWithAlert(reason: String) {
        // Clear local license and disable Plus
        appState.isPlus = false
        Gumroad().clearLicenseDetails()
        UserDefaults.standard.consecutiveNetworkFailureDays = 0
        UserDefaults.standard.set(nil, forKey: "lastNetworkFailureDay")

        // Inform user with a blocking popup
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.messageText = "AirSync+ Unregistered"
            alert.informativeText = reason
            alert.runModal()
        }
    }

    @MainActor
    func checkLicense() async {
        // Always record that we attempted today (used to prevent double-counting network failures in one day)
        let now = Date()
        let calendar = Calendar.current

        // If no stored key, behave as before
        guard let key = appState.licenseDetails?.key, !key.isEmpty else {
            if !TrialManager.shared.isTrialActive {
                appState.isPlus = false
            }
            Gumroad().incrementInvalidLicenseFailCount() // treat as invalid (no key)
            UserDefaults.standard.lastLicenseCheckDate = now
            return
        }

        do {
            let valid = try await Gumroad().checkLicenseKeyValidity(
                key: key,
                save: false,
                isNewRegistration: false
            )

            UserDefaults.standard.lastLicenseCheckDate = now

            if valid {
                // Successful validation today
                UserDefaults.standard.consecutiveNetworkFailureDays = 0
                UserDefaults.standard.consecutiveLicenseFailCount = 0
                UserDefaults.standard.lastLicenseSuccessfulCheckDate = now
                appState.isPlus = true
                print("[gumroad] License valid — daily success recorded.")
            } else {
                // Invalid/expired/cancelled/license-limit — disable immediately
                if !TrialManager.shared.isTrialActive {
                    appState.isPlus = false
                }
                Gumroad().incrementInvalidLicenseFailCount()
                // Reset network failure streak because this is not a network failure
                UserDefaults.standard.consecutiveNetworkFailureDays = 0
                print("[gumroad] License invalid or expired — disabled Plus (unless trial active).")
            }
        } catch let error as LicenseCheckError {
            // Network/server failure: do not disable Plus today
            UserDefaults.standard.lastLicenseCheckDate = now

            // Only increment once per calendar day
            var consecutiveDays = UserDefaults.standard.consecutiveNetworkFailureDays
            if UserDefaults.standard.lastLicenseSuccessfulCheckDate != nil {
                // last successful check date exists; if it's today we already validated; but we are here only if not successful today
                // we still want to count by day against previous attempt date
            }
            // Compare with the last attempt day (not last success) to avoid double-counting same day
            if UserDefaults.standard.lastLicenseCheckDate != nil {
                // We just set it to 'now'; we need the previous value to compare. To avoid this race,
                // check by reading previous date first before setting in future refactors.
                // For current code path, guard by storing previous date before the call if needed.
            }
            // Simpler: increment if last success date is not today OR there was no success date recently
            // Also ensure we don't increment more than once a day by comparing with a stored "last network failure day" if needed.
            // For simplicity, we’ll increment if not already incremented today:
            let lastNetworkDay = UserDefaults.standard.object(forKey: "lastNetworkFailureDay") as? Date
            if lastNetworkDay == nil || !calendar.isDate(lastNetworkDay!, inSameDayAs: now) {
                consecutiveDays += 1
                UserDefaults.standard.set(now, forKey: "lastNetworkFailureDay")
            }
            UserDefaults.standard.consecutiveNetworkFailureDays = consecutiveDays

            // User messaging
            appState.postNativeNotification(
                id: "license_network_issue",
                appName: "AirSync+",
                title: "License check skipped",
                body: "Network issue while validating your license. \(consecutiveDays)/3 consecutive days."
            )

            if consecutiveDays >= 3 {
                // Unregister on 3rd consecutive day
                Gumroad().performUnregisterWithAlert(reason: "Could not validate your license for 3 consecutive days due to network issues. Please re-enter your key when you’re online.")
            } else {
                print("[gumroad] Network/server error during license check: \(error)")
            }
        } catch {
            // Any other unexpected error — treat as server error category
            UserDefaults.standard.lastLicenseCheckDate = now

            let lastNetworkDay = UserDefaults.standard.object(forKey: "lastNetworkFailureDay") as? Date
            if lastNetworkDay == nil || !Calendar.current.isDate(lastNetworkDay!, inSameDayAs: now) {
                let newVal = UserDefaults.standard.consecutiveNetworkFailureDays + 1
                UserDefaults.standard.consecutiveNetworkFailureDays = newVal
                UserDefaults.standard.set(now, forKey: "lastNetworkFailureDay")
            }

            appState.postNativeNotification(
                id: "license_network_issue",
                appName: "AirSync+",
                title: "License check skipped",
                body: "A server error occurred while validating your license."
            )

            if UserDefaults.standard.consecutiveNetworkFailureDays >= 3 {
                Gumroad().performUnregisterWithAlert(reason: "Could not validate your license for 3 consecutive days due to server issues. Please re-enter your key when you’re online.")
            } else {
                print("[gumroad] Unexpected error during license check: \(error)")
            }
        }
    }


    func checkLicenseIfNeeded() async {
        // If we already had a successful check today, skip to enforce "max one successful check per day"
        if let lastSuccess = UserDefaults.standard.lastLicenseSuccessfulCheckDate,
           Calendar.current.isDateInToday(lastSuccess) {
            print("[gumroad] License already successfully validated today — skipping network call.")
            appState.isPlus = true
            return
        }

        await Gumroad().checkLicense()
    }

}
