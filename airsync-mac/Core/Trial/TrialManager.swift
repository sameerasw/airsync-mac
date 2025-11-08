import Foundation
import SwiftUI
internal import Combine

@MainActor
final class TrialManager: ObservableObject {
    static let shared = TrialManager()

    @Published private(set) var isTrialActive: Bool = false
    @Published private(set) var isPerformingRequest: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var countdownText: String = ""
    @Published private(set) var hasSecretConfigured: Bool = false

    private(set) var token: String?
    private(set) var deviceIdentifier: String

    private let endpoint = URL(string: "https://sameerasw.com/.netlify/functions/trial")!
    private var countdownTimer: Timer?
    private var lastSyncDate: Date?
    private let syncThrottle: TimeInterval = 60

    private init() {
        deviceIdentifier = TrialManager.loadOrCreateDeviceIdentifier()
        token = UserDefaults.standard.trialToken
        expiresAt = UserDefaults.standard.trialExpiryDate
        hasSecretConfigured = TrialSecretProvider.currentSecret() != nil
        lastSyncDate = UserDefaults.standard.trialLastSync

        evaluatePersistedState()
        observeLicenseChanges()
    }

    deinit {
        countdownTimer?.invalidate()
    }

    var hasExpired: Bool {
        guard let expiry = expiresAt else { return false }
        return expiry <= Date() && !isTrialActive
    }

    var expiryDisplayText: String? {
        guard let expiry = expiresAt else { return nil }
        return TrialManager.expiryFormatter.string(from: expiry)
    }

    func refreshStatus(force: Bool) async {
        guard let secret = TrialSecretProvider.currentSecret() else {
            hasSecretConfigured = false
            if force || isTrialActive {
                lastError = "Trial secret missing. Update Configs/Secrets.xcconfig or set TRIAL_SECRET."
            }
            return
        }

        hasSecretConfigured = true

        if let lastSyncDate, !force,
           Date().timeIntervalSince(lastSyncDate) < syncThrottle {
            return
        }

        await performRequest(secret: secret, treatAsActivation: false)
    }

    @discardableResult
    func activateTrial() async -> Bool {
        lastError = nil

        guard let secret = TrialSecretProvider.currentSecret() else {
            hasSecretConfigured = false
            lastError = "Trial secret missing. Update Configs/Secrets.xcconfig or set TRIAL_SECRET."
            return false
        }

        hasSecretConfigured = true

        await performRequest(secret: secret, treatAsActivation: true)
        return isTrialActive
    }

    func clearError() {
        lastError = nil
    }

    func clearTrial() {
        countdownTimer?.invalidate()
        countdownTimer = nil

        isTrialActive = false
        countdownText = ""
        expiresAt = nil
        token = nil
        lastSyncDate = nil
    lastError = nil

        UserDefaults.standard.trialToken = nil
        UserDefaults.standard.trialExpiryDate = nil
        UserDefaults.standard.trialLastSync = nil

        syncEntitlementWithAppState()
    }

    private func performRequest(secret: String, treatAsActivation: Bool) async {
        isPerformingRequest = true
        defer { isPerformingRequest = false }

        do {
            let result = try await callTrialEndpoint(secret: secret)
            lastSyncDate = Date()
            UserDefaults.standard.trialLastSync = lastSyncDate

            switch result {
            case .activated(let token, let expiry):
                lastError = nil
                handleActivation(token: token, expiry: expiry)
            case .expired(let message):
                lastError = message
                handleExpirationReached(expiryOverride: expiresAt)
            }
        } catch let error as TrialAPIError {
            lastError = error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handleActivation(token: String, expiry: Date) {
        self.token = token
        self.expiresAt = expiry
        UserDefaults.standard.trialToken = token
        UserDefaults.standard.trialExpiryDate = expiry

        if expiry > Date() {
            isTrialActive = true
            updateCountdownText()
            startCountdownTimer()
        } else {
            isTrialActive = false
            countdownText = ""
        }

        syncEntitlementWithAppState()
    }

    private func handleExpirationReached(expiryOverride: Date?) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        isTrialActive = false
        countdownText = ""

        lastSyncDate = nil
        UserDefaults.standard.trialLastSync = nil

        if let override = expiryOverride {
            expiresAt = override
            UserDefaults.standard.trialExpiryDate = override
        } else if let currentExpiry = expiresAt {
            UserDefaults.standard.trialExpiryDate = currentExpiry
        }

        token = nil
        UserDefaults.standard.trialToken = nil

        syncEntitlementWithAppState()
    }

    private func evaluatePersistedState() {
        guard let expiry = expiresAt else {
            isTrialActive = false
            countdownText = ""
            syncEntitlementWithAppState()
            return
        }

        if expiry > Date() {
            isTrialActive = true
            updateCountdownText()
            startCountdownTimer()
            syncEntitlementWithAppState()
        } else {
            handleExpirationReached(expiryOverride: expiry)
        }
    }

    private func startCountdownTimer() {
        countdownTimer?.invalidate()

        guard let expiry = expiresAt, expiry > Date() else {
            countdownText = ""
            return
        }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tickCountdown()
            }
        }
    }

    private func tickCountdown() {
        guard let expiry = expiresAt else {
            countdownTimer?.invalidate()
            countdownTimer = nil
            countdownText = ""
            return
        }

        if expiry <= Date() {
            countdownTimer?.invalidate()
            countdownTimer = nil
            countdownText = ""
            handleExpirationReached(expiryOverride: expiry)
            return
        }

        updateCountdownText()
    }

    private func updateCountdownText() {
        guard let expiry = expiresAt else {
            countdownText = ""
            return
        }

        let remaining = max(0, expiry.timeIntervalSinceNow)
        countdownText = TrialManager.countdownFormatter.string(from: remaining) ?? ""
    }

    private func syncEntitlementWithAppState() {
        #if SELF_COMPILED
        // In self-compiled builds, Plus is always enabled - don't override it
        return
        #endif
        let appState = AppState.shared
        if isTrialActive {
            if !appState.isPlus {
                appState.isPlus = true
            }
        } else if appState.licenseDetails == nil {
            if appState.isPlus {
                appState.isPlus = false
            }
        }
    }

    private func observeLicenseChanges() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LicenseStatusChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isTrialActive else { return }
                self.syncEntitlementWithAppState()
            }
        }
    }

    private func callTrialEndpoint(secret: String) async throws -> TrialServerResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = TrialRequestPayload(deviceId: deviceIdentifier, secret: secret)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TrialAPIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TrialAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if (200...299).contains(httpResponse.statusCode) {
            let payload = try decoder.decode(TrialResponsePayload.self, from: data)
            guard let token = payload.token,
                  let expires = payload.expiresAt else {
                throw TrialAPIError.invalidResponse
            }

            let expiryDate = Date(timeIntervalSince1970: expires / 1000)
            return .activated(token: token, expiry: expiryDate)
        }

        if httpResponse.statusCode == 403 {
            if let errorPayload = try? decoder.decode(TrialErrorPayload.self, from: data) {
                return .expired(message: errorPayload.error ?? "Trial expired or already used")
            }
            return .expired(message: "Trial expired or already used")
        }

        if let errorPayload = try? decoder.decode(TrialErrorPayload.self, from: data),
           let message = errorPayload.error {
            throw TrialAPIError.server(code: httpResponse.statusCode, message: message)
        }

        throw TrialAPIError.server(code: httpResponse.statusCode, message: "HTTP \(httpResponse.statusCode)")
    }

    private static func loadOrCreateDeviceIdentifier() -> String {
        let key = "trial-device-identifier"

        if let existing = KeychainStorage.string(for: key) {
            UserDefaults.standard.trialDeviceIdentifier = existing
            return existing
        }

        if let stored = UserDefaults.standard.trialDeviceIdentifier, !stored.isEmpty {
            KeychainStorage.set(stored, for: key)
            return stored
        }

        let newIdentifier = UUID().uuidString
        KeychainStorage.set(newIdentifier, for: key)
        UserDefaults.standard.trialDeviceIdentifier = newIdentifier
        return newIdentifier
    }

    private static let countdownFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.collapsesLargestUnit = false
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private enum TrialServerResult {
    case activated(token: String, expiry: Date)
    case expired(message: String)
}

private enum TrialAPIError: LocalizedError {
    case invalidResponse
    case network(Error)
    case server(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Server response was invalid."
        case .network(let underlying):
            return underlying.localizedDescription
        case .server(_, let message):
            return message
        }
    }
}

private struct TrialRequestPayload: Encodable {
    let deviceId: String
    let secret: String
}

private struct TrialResponsePayload: Decodable {
    let deviceId: String?
    let token: String?
    let expiresAt: TimeInterval?
}

private struct TrialErrorPayload: Decodable {
    let error: String?
}
