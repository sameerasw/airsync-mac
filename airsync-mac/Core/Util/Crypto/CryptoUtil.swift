//
//  CryptoUtil.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-08.
//

import CryptoKit
import SwiftUI

func generateSymmetricKey() -> String {
    let key = SymmetricKey(size: .bits256)
    let keyData = key.withUnsafeBytes { Data($0) }
    return keyData.base64EncodedString()
}

func encryptMessage(_ message: String, using key: SymmetricKey) -> String? {
    let data = Data(message.utf8)
    do {
        let sealed = try AES.GCM.seal(data, using: key)
        let combined = sealed.combined! // nonce + ciphertext + tag
        return combined.base64EncodedString()
    } catch {
        print("[crypto-util] Encryption failed: \(error)")
        return nil
    }
}

func decryptMessage(_ base64: String, using key: SymmetricKey) -> String? {
    guard let combinedData = Data(base64Encoded: base64) else { return nil }
    do {
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let decrypted = try AES.GCM.open(sealedBox, using: key)
        return String(data: decrypted, encoding: .utf8)
    } catch {
        print("[crypto-util] Decryption failed: \(error)")
        return nil
    }
}

func sha256(_ input: String) -> String {
    let data = Data(input.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
