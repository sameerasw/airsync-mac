//
//  AnyDecodable.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-29.
//

import Foundation

struct CodableValue: Codable {
    let value: Any

    init<T>(_ value: T) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try dictionary first (most common for our data messages)
        if let dict = try? container.decode([String: AnyCodable].self) {
            let converted = dict.mapValues { $0.value }
            self.value = converted
            print("[CodableValue] ✅ Decoded dictionary with \(converted.keys.count) keys: \(converted.keys.joined(separator: ", "))")
            return
        }
        
        // Try array
        if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
            print("[CodableValue] ✅ Decoded array with \(array.count) elements")
            return
        }
        
        // Try primitives
        if let string = try? container.decode(String.self) {
            self.value = string
            return
        }
        if let int = try? container.decode(Int.self) {
            self.value = int
            return
        }
        if let double = try? container.decode(Double.self) {
            self.value = double
            return
        }
        if let bool = try? container.decode(Bool.self) {
            self.value = bool
            return
        }
        
        // Fallback
        print("[CodableValue] ⚠️ Failed to decode, using empty dictionary")
        self.value = [String: Any]()
    }

    func encode(to encoder: Encoder) throws {
        // Not needed for your case now
    }
}

struct AnyCodable: Codable {
    let value: Any
    init<T>(_ value: T) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {}
}
