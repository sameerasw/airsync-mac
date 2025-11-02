import Foundation

enum TrialSecretProvider {
    /// Resolves the trial secret from the environment or the bundled Info.plist.
    static func currentSecret() -> String? {
        if let envSecret = ProcessInfo.processInfo.environment["TRIAL_SECRET"],
           let trimmed = sanitized(secret: envSecret) {
            return trimmed
        }

        if let infoValue = Bundle.main.object(forInfoDictionaryKey: "TrialSecret") as? String,
           let trimmed = sanitized(secret: infoValue) {
            return trimmed
        }

        return nil
    }

    private static func sanitized(secret: String) -> String? {
        let clean = secret
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        guard !clean.isEmpty, !clean.contains("$(TRIAL_SECRET)") else {
            return nil
        }
        return clean
    }
}
