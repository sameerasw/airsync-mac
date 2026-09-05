//
//  Gumroad.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-31.
//

import Foundation
import AppKit

// Enhanced error type to distinguish network/server failures from invalid license results with user-friendly descriptions
enum LicenseCheckError: Error, LocalizedError {
    case invalidKey(String)            // Invalid key / key not found for product
    case planMismatch(String)          // Plan tier mismatch (Membership vs One-Time)
    case subscriptionInactive(String)   // Cancelled, ended, or failed subscription
    case usesExceeded(String)          // Device activation limit
    case refunded(String)              // Refunded / disputed / chargebacked
    case network(Error)                // Transport / connectivity issues
    case server(String)                // HTTP non-200 / malformed response
    case unknown(String)               // Unknown errors

    var errorDescription: String? {
        switch self {
        case .invalidKey(let msg),
             .planMismatch(let msg),
             .subscriptionInactive(let msg),
             .usesExceeded(let msg),
             .refunded(let msg),
             .server(let msg),
             .unknown(let msg):
            return msg
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

class Gumroad {
    let appState = AppState.shared

    @discardableResult
    func checkLicenseKeyValidity(key: String, save: Bool, isNewRegistration: Bool) async throws -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            print("[gumroad] License check failed: Empty license key provided")
            throw LicenseCheckError.invalidKey("License key cannot be empty.")
        }

        // Select product id based on chosen plan
        let selectedPlan = UserDefaults.standard.licensePlanType
        let membershipProductID = "smrIThhDxoQI33gQm3wwxw=="
        let oneTimeProductID = "3HkBPf4ovp7KiVISJS6N5A=="
        let productID = (selectedPlan == .oneTime) ? oneTimeProductID : membershipProductID
        let url = URL(string: "https://api.gumroad.com/v2/licenses/verify")!

        let maskedKey = trimmedKey.count > 8 ? "\(trimmedKey.prefix(4))....\(trimmedKey.suffix(4))" : "****"
        print("[gumroad] Verifying license key '\(maskedKey)' | Plan: \(selectedPlan.displayName) | Product ID: \(productID) | Is New Registration: \(isNewRegistration)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let bodyComponents: [String: String] = [
            "product_id": productID,
            "license_key": trimmedKey,
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
            print("[gumroad] Network error during HTTP request: \(error.localizedDescription)")
            throw LicenseCheckError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[gumroad] Server error: Invalid HTTP response object")
            throw LicenseCheckError.server("Invalid HTTP response from server.")
        }

        print("[gumroad] Received HTTP \(httpResponse.statusCode) response from Gumroad API")

        // Treat 404 as an invalid license / plan mismatch
        if httpResponse.statusCode == 404 {
            let errorMsg = "License key not found for \(selectedPlan.displayName) plan. If you purchased a different tier, try changing the plan picker."
            print("[gumroad] License check failed (HTTP 404): Key '\(maskedKey)' not found for product ID '\(productID)'. \(errorMsg)")
            if save {
                AppState.shared.isPlus = false
                AppState.shared.licenseDetails = nil
                AppState.shared.lastLicenseCheckFailureReason = errorMsg
            }
            throw LicenseCheckError.planMismatch(errorMsg)
        }

        // Accept only 2xx here; other codes are server-ish problems
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = "Gumroad server error (HTTP \(httpResponse.statusCode)). Please try again later."
            print("[gumroad] License check failed: Server status code \(httpResponse.statusCode)")
            throw LicenseCheckError.server(errorMsg)
        }

        // Parse JSON
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("[gumroad] License check failed: Failed to parse JSON response")
            throw LicenseCheckError.server("Malformed JSON response from Gumroad.")
        }

        let success = json["success"] as? Bool ?? false
        let apiMessage = json["message"] as? String

        // If Gumroad says not success => invalid license
        guard success, let purchase = json["purchase"] as? [String: Any] else {
            let detailMessage = apiMessage ?? "Invalid license key or unverified purchase."
            let errorMsg = "Gumroad: \(detailMessage)"
            print("[gumroad] License check failed (success=false): \(detailMessage)")
            if save {
                AppState.shared.isPlus = false
                AppState.shared.licenseDetails = nil
                AppState.shared.lastLicenseCheckFailureReason = errorMsg
            }
            throw LicenseCheckError.invalidKey(errorMsg)
        }

        // Refunded, disputed, or chargebacked check
        let refunded = purchase["refunded"] as? Bool ?? false
        let disputed = purchase["disputed"] as? Bool ?? false
        let chargebacked = purchase["chargebacked"] as? Bool ?? false
        if refunded || disputed || chargebacked {
            let statusStr = refunded ? "refunded" : (disputed ? "disputed" : "chargebacked")
            let errorMsg = "This license key has been \(statusStr)."
            print("[gumroad] License check failed: Key '\(maskedKey)' was \(statusStr)")
            if save {
                AppState.shared.isPlus = false
                AppState.shared.licenseDetails = nil
                AppState.shared.lastLicenseCheckFailureReason = errorMsg
            }
            throw LicenseCheckError.refunded(errorMsg)
        }

        // Subscription-only fields — for one-time purchase these may be nil/empty.
        let cancelledAt = purchase["subscription_cancelled_at"] as? String
        let endedAt = purchase["subscription_ended_at"] as? String
        let failedAt = purchase["subscription_failed_at"] as? String

        // Membership plan must be active; otherwise invalid
        if selectedPlan == .membership {
            let isCancelled = cancelledAt != nil && !cancelledAt!.isEmpty
            let isEnded = endedAt != nil && !endedAt!.isEmpty
            let isFailed = failedAt != nil && !failedAt!.isEmpty

            if isCancelled || isEnded || isFailed {
                var reason = "Subscription inactive."
                if isEnded { reason = "Subscription ended on \(endedAt!)." }
                else if isFailed { reason = "Subscription payment failed on \(failedAt!)." }
                else if isCancelled { reason = "Subscription was cancelled on \(cancelledAt!)." }

                print("[gumroad] License check failed: Membership inactive — \(reason)")
                if save {
                    AppState.shared.isPlus = false
                    AppState.shared.licenseDetails = nil
                    AppState.shared.lastLicenseCheckFailureReason = reason
                }
                throw LicenseCheckError.subscriptionInactive(reason)
            }
        }

        // Device limit logic — if exceeded we treat as invalid
        let currentUsesCount = json["uses"] as? Int ?? 0
        let previousUsesCount = AppState.shared.licenseDetails?.usesCount ?? currentUsesCount
        if (currentUsesCount - previousUsesCount) > 3 {
            let errorMsg = "License usage limit reached (\(currentUsesCount) total activations)."
            print("[gumroad] License check failed: Usage limit exceeded (current uses: \(currentUsesCount), previous: \(previousUsesCount))")
            if save {
                AppState.shared.isPlus = false
                AppState.shared.licenseDetails = nil
                AppState.shared.lastLicenseCheckFailureReason = errorMsg
            }
            throw LicenseCheckError.usesExceeded(errorMsg)
        }

        // Valid license
        let email = purchase["email"] as? String ?? "unknown"
        let productName = purchase["product_name"] as? String ?? "unknown"
        let orderNumber = purchase["order_number"] as? Int ?? 0
        print("[gumroad] License verified successfully! Email: \(email), Product: \(productName), Order #: \(orderNumber), Uses: \(currentUsesCount)")

        if save {
            AppState.shared.isPlus = true
            AppState.shared.lastLicenseCheckFailureReason = nil
            let details = LicenseDetails(
                key: trimmedKey,
                email: email,
                productName: productName,
                orderNumber: orderNumber,
                purchaserID: purchase["purchaser_id"] as? String ?? "",
                usesCount: currentUsesCount,
                price: purchase["price"] as? Int ?? 0,
                currency: purchase["currency"] as? String ?? "usd",
                saleTimestamp: purchase["sale_timestamp"] as? String ?? "",
                subscriptionCancelledAt: cancelledAt,
                subscriptionEndedAt: endedAt,
                subscriptionFailedAt: failedAt,
                refunded: refunded,
                disputed: disputed,
                chargebacked: chargebacked
            )
            AppState.shared.licenseDetails = details
        }

        return true
    }

    func clearLicenseDetails() {
        print("[gumroad] Clearing saved license details")
        AppState.shared.licenseDetails = nil
        AppState.shared.lastLicenseCheckFailureReason = nil
        UserDefaults.standard.removeObject(forKey: "licenseDetailsKey")
        UserDefaults.standard.consecutiveLicenseFailCount = 0
        UserDefaults.standard.lastLicenseSuccessfulCheckDate = nil
    }

    func incrementInvalidLicenseFailCount() {
        let failCount = UserDefaults.standard.consecutiveLicenseFailCount + 1
        UserDefaults.standard.consecutiveLicenseFailCount = failCount

        print("[gumroad] License check fail count incremented to \(failCount)/3")
        if failCount >= 3 {
            Gumroad().clearLicenseDetails()
            print("[gumroad] License check failed \(failCount) times — license removed")
        }
    }

    func performUnregisterWithAlert(reason: String) {
        print("[gumroad] Unregistering license with alert: \(reason)")
        // Clear local license and disable Plus
        appState.isPlus = false
        AppState.shared.lastLicenseCheckFailureReason = reason
        Gumroad().clearLicenseDetails()
        UserDefaults.standard.consecutiveNetworkFailureDays = 0
        UserDefaults.standard.set(nil, forKey: "lastNetworkFailureDay")

        // Inform user without blocking main thread
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.messageText = "AirSync+ Unregistered"
            alert.informativeText = reason
            
            if let window = NSApp.windows.first(where: { $0.isKeyWindow && $0.isVisible }) ?? NSApp.windows.first(where: { $0.isVisible }) {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    @MainActor
    func checkLicense() async {
        let now = Date()
        let calendar = Calendar.current

        guard let key = appState.licenseDetails?.key, !key.isEmpty else {
            print("[gumroad] No saved license key found for scheduled check.")
            if !TrialManager.shared.isTrialActive {
                appState.isPlus = false
            }
            Gumroad().incrementInvalidLicenseFailCount()
            UserDefaults.standard.lastLicenseCheckDate = now
            return
        }

        print("[gumroad] Running routine license check...")
        do {
            let valid = try await Gumroad().checkLicenseKeyValidity(
                key: key,
                save: false,
                isNewRegistration: false
            )

            UserDefaults.standard.lastLicenseCheckDate = now

            if valid {
                UserDefaults.standard.consecutiveNetworkFailureDays = 0
                UserDefaults.standard.consecutiveLicenseFailCount = 0
                UserDefaults.standard.lastLicenseSuccessfulCheckDate = now
                appState.isPlus = true
                appState.lastLicenseCheckFailureReason = nil
                print("[gumroad] Routine license check passed — daily success recorded.")
            } else {
                if !TrialManager.shared.isTrialActive {
                    appState.isPlus = false
                }
                Gumroad().incrementInvalidLicenseFailCount()
                UserDefaults.standard.consecutiveNetworkFailureDays = 0
                print("[gumroad] Routine license check failed: Key invalid or expired — disabled Plus.")
            }
        } catch let error as LicenseCheckError {
            UserDefaults.standard.lastLicenseCheckDate = now

            switch error {
            case .network(let sysErr):
                print("[gumroad] Network error during routine check: \(sysErr.localizedDescription)")
                let lastNetworkDay = UserDefaults.standard.object(forKey: "lastNetworkFailureDay") as? Date
                var consecutiveDays = UserDefaults.standard.consecutiveNetworkFailureDays
                if lastNetworkDay == nil || !calendar.isDate(lastNetworkDay!, inSameDayAs: now) {
                    consecutiveDays += 1
                    UserDefaults.standard.set(now, forKey: "lastNetworkFailureDay")
                }
                UserDefaults.standard.consecutiveNetworkFailureDays = consecutiveDays

                appState.postNativeNotification(
                    id: "license_network_issue",
                    appName: "AirSync+",
                    title: "License check skipped",
                    body: "Network issue while validating your license. \(consecutiveDays)/3 consecutive days."
                )

                if consecutiveDays >= 3 {
                    Gumroad().performUnregisterWithAlert(reason: "Could not validate your license for 3 consecutive days due to network issues. Please re-enter your key when you’re online.")
                }
            default:
                // Non-network errors (invalid key, plan mismatch, subscription ended, etc.)
                let reason = error.localizedDescription
                print("[gumroad] License error during routine check: \(reason)")
                appState.lastLicenseCheckFailureReason = reason
                if !TrialManager.shared.isTrialActive {
                    appState.isPlus = false
                }
                Gumroad().incrementInvalidLicenseFailCount()
                UserDefaults.standard.consecutiveNetworkFailureDays = 0
            }
        } catch {
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
                print("[gumroad] Unexpected error during license check: \(error.localizedDescription)")
            }
        }
    }

    func checkLicenseIfNeeded() async {
        if appState.licenseDetails != nil,
           let lastSuccess = UserDefaults.standard.lastLicenseSuccessfulCheckDate,
           Calendar.current.isDateInToday(lastSuccess) {
            print("[gumroad] License already successfully validated today (\(lastSuccess.formatted())) — skipping network call.")
            appState.isPlus = true
            return
        }

        await Gumroad().checkLicense()
    }
}
