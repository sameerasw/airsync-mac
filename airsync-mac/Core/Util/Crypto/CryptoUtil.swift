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
    return encryptData(Data(message.utf8), using: key)
}

func encryptData(_ data: Data, using key: SymmetricKey) -> String? {
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
    guard let data = decryptMessageToData(base64, using: key) else { return nil }
    return String(data: data, encoding: .utf8)
}

func decryptMessageToData(_ base64: String, using key: SymmetricKey) -> Data? {
    guard let combinedData = Data(base64Encoded: base64) else { return nil }
    do {
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        return try AES.GCM.open(sealedBox, using: key)
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
