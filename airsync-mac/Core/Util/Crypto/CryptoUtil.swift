//
//  CryptoUtil.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-08.
//

import CryptoKit
import SwiftUI

/// Thread-safe nonce replay cache to prevent replay attacks on AES-GCM messages.
/// Tracks recently-seen 12-byte nonces and rejects duplicates.
private class NonceReplayGuard {
    static let shared = NonceReplayGuard()

    private let lock = NSLock()
    private var seenNonces: Set<Data> = []
    private var nonceOrder: [Data] = []     // FIFO for eviction
    private let maxEntries = 10_000         // bounded memory (~120 KB)

    /// Returns `true` if the nonce has NOT been seen before (message is fresh).
    /// Returns `false` if the nonce is a duplicate (replay detected).
    func checkAndRecord(_ nonce: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if seenNonces.contains(nonce) {
            return false // replay
        }

        seenNonces.insert(nonce)
        nonceOrder.append(nonce)

        // Evict oldest entries when cache is full
        if nonceOrder.count > maxEntries {
            let evict = nonceOrder.removeFirst()
            seenNonces.remove(evict)
        }
        return true
    }

    /// Clears the replay cache (e.g. on key rotation or reconnect).
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        seenNonces.removeAll()
        nonceOrder.removeAll()
    }
}

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

        // Anti-replay: check that this nonce hasn't been used before
        let nonceData = Data(sealedBox.nonce)
        guard NonceReplayGuard.shared.checkAndRecord(nonceData) else {
            print("[crypto-util] Replay detected: duplicate nonce, dropping message")
            return nil
        }

        let decrypted = try AES.GCM.open(sealedBox, using: key)
        return String(data: decrypted, encoding: .utf8)
    } catch {
        print("[crypto-util] Decryption failed: \(error)")
        return nil
    }
}

/// Resets the replay nonce cache (call on key rotation or reconnect).
func resetReplayGuard() {
    NonceReplayGuard.shared.reset()
}

func sha256(_ input: String) -> String {
    let data = Data(input.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
