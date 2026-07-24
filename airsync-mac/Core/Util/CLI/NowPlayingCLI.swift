//
//  NowPlayingAccessibility.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-17.
//

import Foundation

class NowPlayingCLI {
    static let shared = NowPlayingCLI()

    // Potential fallback paths for Apple Silicon and Intel Homebrew
    static let possibleMediaControlPaths = [
        "/opt/homebrew/bin/media-control", // Apple Silicon Homebrew
        "/usr/local/bin/media-control"     // Intel Homebrew
    ]

    // Cache resolved path to avoid repeated lookups
    private var cachedPath: String?

    private init() {}

    private func resolveBinaryPath() -> String? {
        if let cachedPath { return cachedPath }
        if let path = findExecutable(named: "media-control", fallbackPaths: NowPlayingCLI.possibleMediaControlPaths) {
            cachedPath = path
            return path
        }
        return nil
    }

    // MARK: - Local binary finder
    private func findExecutable(named name: String, fallbackPaths: [String]) -> String? {
        for path in fallbackPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
        let dirs = envPath.components(separatedBy: ":")
        for dir in dirs {
            let fullPath = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }

    func fetchNowPlaying(completion: @escaping (NowPlayingInfo?) -> Void) {
        guard let binPath = resolveBinaryPath() else {
            // media-control not available; gracefully return nil
            print("[now-playing] media-control binary not found. Install with: brew install media-control")
            completion(Optional<NowPlayingInfo>.none)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)
        process.arguments = ["get"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let handle = pipe.fileHandleForReading

        var buffer = Data()

        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)
        }

        process.terminationHandler = { _ in
            handle.readabilityHandler = nil
            guard !buffer.isEmpty else {
                DispatchQueue.main.async { completion(Optional<NowPlayingInfo>.none) }
                return
            }

            // Try decoding the full JSON at once
            if let rawString = String(data: buffer, encoding: .utf8) {
                let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
//                print("[now-playing] Full media-control output:", trimmed) // debug

                // If media-control returns literal "null", treat as no media
                if trimmed.isEmpty || trimmed.lowercased() == "null" {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                do {
                    let obj = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
                    if let dict = obj as? [String: Any] {
                        var info = NowPlayingInfo()
                        info.updateFromPayload(dict)
                        DispatchQueue.main.async { completion(info) }
                    } else {
                        // Not a dictionary (could be null/array) -> no media info
                        DispatchQueue.main.async { completion(nil) }
                    }
                } catch {
                    print("[now-playing] JSON parse error:", error)
                    DispatchQueue.main.async { completion(nil) }
                }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }

        do {
            try process.run()
        } catch {
            print("[now-playing] Failed to run media-control get:", error)
            completion(Optional<NowPlayingInfo>.none)
        }
    }




    func play() { runCommand("play") }
    func pause() { runCommand("pause") }
    func toggle() { runCommand("toggle-play-pause") }
    func next() { runCommand("next-track") }
    func previous() { runCommand("previous-track") }
    func stop() { runCommand("stop") }

    private func runCommand(_ cmd: String) {
        guard let binPath = resolveBinaryPath() else {
            print("[now-playing] media-control binary not found. Install with: brew install media-control")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)
        process.arguments = [cmd]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
    }
}
