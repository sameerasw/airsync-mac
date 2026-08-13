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

    private var streamProcess: Process?
    private var streamPipe: Pipe?
    private var onUpdateHandler: ((NowPlayingInfo?) -> Void)?
    private var isStreamingActive = false
    private var retryCount = 0
    private let maxRetries = 10
    private var lineBuffer = Data()

    func startStreaming(onUpdate: @escaping (NowPlayingInfo?) -> Void) {
        self.onUpdateHandler = onUpdate
        self.isStreamingActive = true
        self.retryCount = 0
        launchStreamProcess()
    }

    func stopStreaming() {
        self.isStreamingActive = false
        self.retryCount = 0
        self.onUpdateHandler = nil
        terminateStreamProcess()
    }

    func resetRetryCount() {
        self.retryCount = 0
    }

    private func terminateStreamProcess() {
        if let process = streamProcess {
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
            }
        }
        streamPipe?.fileHandleForReading.readabilityHandler = nil
        streamProcess = nil
        streamPipe = nil
        lineBuffer.removeAll()
    }

    private func launchStreamProcess() {
        guard isStreamingActive else { return }

        guard let binPath = resolveBinaryPath() else {
            print("[now-playing] media-control binary not found. Cannot stream updates.")
            DispatchQueue.main.async { [weak self] in
                self?.onUpdateHandler?(nil)
            }
            return
        }

        terminateStreamProcess()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)
        process.arguments = ["stream", "--no-diff"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let readHandle = pipe.fileHandleForReading

        readHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleStreamData(data)
        }

        process.terminationHandler = { [weak self] proc in
            guard let self = self else { return }
            readHandle.readabilityHandler = nil

            DispatchQueue.main.async {
                guard self.isStreamingActive else { return }

                if self.retryCount < self.maxRetries {
                    self.retryCount += 1
                    print("[now-playing] media-control stream terminated unexpectedly. Retry \(self.retryCount)/\(self.maxRetries)")
                    let delay = min(Double(self.retryCount) * 0.5, 3.0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.launchStreamProcess()
                    }
                } else {
                    print("[now-playing] media-control stream reached max retries (\(self.maxRetries)). Stopping retry attempts until reset.")
                    self.onUpdateHandler?(nil)
                }
            }
        }

        self.streamProcess = process
        self.streamPipe = pipe

        do {
            try process.run()
            print("[now-playing] Successfully launched media-control stream --no-diff")
        } catch {
            print("[now-playing] Failed to launch media-control stream:", error)
            process.terminationHandler = nil
            if retryCount < maxRetries {
                retryCount += 1
                let delay = min(Double(retryCount) * 0.5, 3.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.launchStreamProcess()
                }
            }
        }
    }

    private func handleStreamData(_ data: Data) {
        lineBuffer.append(data)

        while let newlineIndex = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = lineBuffer.subdata(in: 0..<newlineIndex)
            lineBuffer.removeSubrange(0...newlineIndex)

            guard !lineData.isEmpty else { continue }
            parseStreamLine(lineData)
        }
    }

    private func parseStreamLine(_ lineData: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: lineData) else {
            if let lineStr = String(data: lineData, encoding: .utf8) {
                print("[now-playing] Raw line (non-JSON): \(lineStr)")
            }
            return
        }

        let dict: [String: Any]? = {
            if let root = obj as? [String: Any] {
                if let payload = root["payload"] as? [String: Any] {
                    return payload.isEmpty ? nil : payload
                }
                if root.keys.contains("type") && root.keys.contains("payload") {
                    return nil
                }
                return root.isEmpty ? nil : root
            }
            return nil
        }()

        let info: NowPlayingInfo? = {
            guard let payload = dict, !payload.isEmpty else { return nil }
            var item = NowPlayingInfo()
            item.updateFromPayload(payload)
            return item
        }()

        if let info = info {
            print("[now-playing] Parsed update: '\(info.title ?? "")' by '\(info.artist ?? "")' (playing: \(info.isPlaying ?? false))")
        } else {
            print("[now-playing] Parsed update: no media payload")
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isStreamingActive else { return }
            self.onUpdateHandler?(info)
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
