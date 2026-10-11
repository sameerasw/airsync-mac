//
//  OtpCodeExtractor.swift
//  airsync-mac
//
//  Detects one-time verification codes (OTP / 2FA) in notification text so the
//  Mac can offer them for paste without the user reaching for the phone.
//

import Foundation

struct OtpCodeExtractor {
    /// Keywords indicating the text carries a verification code. This gate keeps
    /// plain numbers (years, prices, counts) from triggering a clipboard copy.
    private static let keywords = [
        "code", "otp", "passcode", "verification", "verify",
        "authenticate", "authentication", "2fa", "two-factor", "two factor",
        "one-time", "one time", "onetime", "security", "login",
        "sign-in", "sign in", "confirm", "activation", "validate"
    ]

    /// Triple-grouped codes like "73 91 08" (separator must be consistent).
    private static let grouped3Pattern = #"(?<!\d)(\d{2,4})([ \u00A0\-])(\d{2,4})\2(\d{2,4})(?!\d)"#
    /// Grouped codes like "123 456" or "123-456".
    private static let grouped2Pattern = #"(?<!\d)(\d{2,4})[ \u00A0\-](\d{2,4})(?!\d)"#
    /// Plain codes like "123456".
    private static let plainPattern = #"(?<!\d)(\d{4,8})(?!\d)"#

    /// Returns the verification code found in the notification, or nil.
    /// Longer grouped formats are preferred; the first non-year-like match wins.
    static func extract(from title: String, body: String) -> String? {
        let text = "\(title)\n\(body)"
        let lowered = text.lowercased()
        guard keywords.contains(where: { lowered.contains($0) }) else { return nil }

        if let triple = matchGroups(pattern: grouped3Pattern, in: text, groups: [1, 3, 4]) {
            return triple
        }
        if let pair = matchGroups(pattern: grouped2Pattern, in: text, groups: [1, 2]) {
            return pair
        }
        return matchGroups(pattern: plainPattern, in: text, groups: [1])
    }

    private static func matchGroups(pattern: String, in text: String, groups: [Int]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            var digits = ""
            var complete = true
            for group in groups {
                let groupRange = match.range(at: group)
                guard groupRange.location != NSNotFound,
                      let swiftRange = Range(groupRange, in: text) else {
                    complete = false
                    break
                }
                digits += text[swiftRange]
            }
            guard complete, (4...8).contains(digits.count) else { continue }
            // Skip year-like 4-digit numbers (e.g. "2026") that slipped past the keyword gate.
            if digits.count == 4, let year = Int(digits), (1900...2099).contains(year) {
                continue
            }
            return digits
        }
        return nil
    }
}
