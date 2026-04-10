//
//  ScrcpyServerManager.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-04-01.
//

import Foundation

class ScrcpyServerManager: NSObject {
    static let shared = ScrcpyServerManager()
    
    private let serverLocalPath = Bundle.main.path(forResource: "scrcpy-server-v3.3.4", ofType: nil) ?? "/Users/sameerasandakelum/GIT/airsync-mac/scrcpy-server-v3.3.4"
    private let serverRemotePath = "/data/local/tmp/scrcpy-server"
    private let serverPort: Int = 1234
    
    private var adbProcess: Process?
    
    func startServer(serial: String, completion: @escaping (Bool) -> Void) {
        let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) ?? "/opt/homebrew/bin/adb"
        
        // Step 0: Cleanup previous instances and port forwards
        print("[ScrcpyServerManager] Cleaning up previous sessions...")
        
        // Remove port forward on Mac
        let cleanupPort = Process()
        cleanupPort.executableURL = URL(fileURLWithPath: adbPath)
        cleanupPort.arguments = ["-s", serial, "forward", "--remove", "tcp:\(serverPort)"]
        try? cleanupPort.run()
        cleanupPort.waitUntilExit()
        
        // Kill existing server process on device
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: adbPath)
        killProcess.arguments = ["-s", serial, "shell", "pkill -f com.genymobile.scrcpy.Server || true"]
        try? killProcess.run()
        killProcess.waitUntilExit()
        
        // Step 1: Push the server
        pushServer(serial: serial) { success in
            guard success else {
                completion(false)
                return
            }
            
            // Step 2: Forward port
            self.forwardPort(serial: serial) { success in
                guard success else {
                    completion(false)
                    return
                }
                
                // Step 3: Launch server
                self.launchServer(serial: serial, completion: completion)
            }
        }
    }
    
    private func pushServer(serial: String, completion: @escaping (Bool) -> Void) {
        let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) ?? "/opt/homebrew/bin/adb"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["-s", serial, "push", serverLocalPath, serverRemotePath]
        
        do {
            try process.run()
            process.waitUntilExit()
            completion(process.terminationStatus == 0)
        } catch {
            print("[ScrcpyServerManager] Push failed: \(error)")
            completion(false)
        }
    }
    
    private func forwardPort(serial: String, completion: @escaping (Bool) -> Void) {
        let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) ?? "/opt/homebrew/bin/adb"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["-s", serial, "forward", "tcp:\(serverPort)", "localabstract:scrcpy"]
        
        do {
            try process.run()
            process.waitUntilExit()
            completion(process.terminationStatus == 0)
        } catch {
            print("[ScrcpyServerManager] Port forward failed: \(error)")
            completion(false)
        }
    }
    
    private var launchCompletion: ((Bool) -> Void)?
    private var launchTimer: Timer?
    
    func launchServer(serial: String, completion: @escaping (Bool) -> Void) {
        let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) ?? "/opt/homebrew/bin/adb"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        
        // Explicitly include video=true and bit_rate/max_size
        process.arguments = [
            "-s", serial,
            "shell",
            "CLASSPATH=\(serverRemotePath)",
            "app_process", "/", "com.genymobile.scrcpy.Server", "3.3.4",
            "tunnel_forward=true", "audio=false", "video=true", "control=true",
            "video_codec=h265", "video_bit_rate=8000000", "max_size=1440"
        ]
        
        self.adbProcess = process
        self.launchCompletion = completion
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    print("[scrcpy-server] \(trimmed)")
                    
                    // Detect readiness: "[server] INFO: Video size: ..."
                    if trimmed.contains("INFO: Video size:") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self?.launchTimer?.invalidate()
                            self?.launchTimer = nil
                            self?.launchCompletion?(true)
                            self?.launchCompletion = nil
                        }
                    }
                    
                    // Detect failure
                    if trimmed.contains("ERROR:") || trimmed.contains("Exception") {
                        print("[ScrcpyServerManager] Server reported error: \(trimmed)")
                        // Trigger failure if it's a critical error
                        if trimmed.contains("Permission denied") || trimmed.contains("could not start") {
                            DispatchQueue.main.async {
                                self?.launchCompletion?(false)
                                self?.launchCompletion = nil
                            }
                        }
                    }
                }
            }
        }
        
        do {
            try process.run()
            
            // Watchdog timer: if we don't see the log in 5s, proceed anyway
            DispatchQueue.main.async {
                self.launchTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                    if let completion = self?.launchCompletion {
                        print("[ScrcpyServerManager] Readiness log timeout - proceeding anyway")
                        completion(true)
                        self?.launchCompletion = nil
                    }
                }
            }
        } catch {
            print("[ScrcpyServerManager] Launch failed: \(error)")
            completion(false)
        }
    }
    
    func stopServer() {
        adbProcess?.terminate()
        adbProcess = nil
        
        // Remove port forward
        let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) ?? "/opt/homebrew/bin/adb"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["forward", "--remove", "tcp:\(serverPort)"]
        
        do {
            try process.run()
            process.waitUntilExit()
            print("[ScrcpyServerManager] Port forward removed")
        } catch {
            print("[ScrcpyServerManager] Failed to remove port forward: \(error)")
        }
    }
}
