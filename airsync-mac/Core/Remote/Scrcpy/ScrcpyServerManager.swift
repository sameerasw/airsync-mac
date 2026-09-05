//
//  ScrcpyServerManager.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-04-01.
//

import Foundation

class ScrcpyServerManager: NSObject {
    static let shared = ScrcpyServerManager()
    
    private let serverLocalPath = Bundle.main.path(forResource: "scrcpy-server", ofType: nil) ?? "/Users/sameerasandakelum/GIT/airsync-mac/scrcpy-server"
    private let serverRemotePath = "/data/local/tmp/scrcpy-server"
    private let serverPort: Int = 1234
    
    private var adbProcess: Process?
    
    func startServer(serial: String, desktopMode: Bool = false, completion: @escaping (Bool) -> Void) {
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
                self.launchServer(serial: serial, desktopMode: desktopMode, completion: completion)
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
    
    func launchServer(serial: String, desktopMode: Bool = false, completion: @escaping (Bool) -> Void) {
        let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) ?? "/opt/homebrew/bin/adb"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        
        var serverArgs = [
            "tunnel_forward=true", "audio=false", "video=true", "control=true",
            "video_codec=h265", "video_bit_rate=8000000"
        ]
        
        if desktopMode {
            // Virtual display — new_display requires "WxH" or "WxH/DPI" format
            let dpi = UserDefaults.standard.scrcpyDesktopDpi
            if !dpi.isEmpty {
                serverArgs.append("new_display=1920x1080/\(dpi)")
            } else {
                serverArgs.append("new_display=1920x1080")
            }
            serverArgs.append("flex_display=true")
        } else {
            serverArgs.append("max_size=1440")
        }
        
        process.arguments = [
            "-s", serial,
            "shell",
            "CLASSPATH=\(serverRemotePath)",
            "app_process", "/", "com.genymobile.scrcpy.Server", "4.1"
        ] + serverArgs
        
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
                    
                    // Detect readiness: "[server] INFO: Video size: ..." or "[server] INFO: New display: ..."
                    if trimmed.contains("INFO: Video size:") || trimmed.contains("INFO: New display:") {
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
        if let process = adbProcess {
            if let pipe = process.standardOutput as? Pipe {
                pipe.fileHandleForReading.readabilityHandler = nil
            }
            if let pipe = process.standardError as? Pipe {
                pipe.fileHandleForReading.readabilityHandler = nil
            }
            process.terminate()
        }
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
    
    func startMirroringSession(appState: AppState, streamClient: ScrcpyStreamClient, desktopMode: Bool = false, completion: @escaping (Bool, String?) -> Void) {
        // Stop any current session first to prevent port/process clashes
        self.stopMirroringSession(streamClient: streamClient)
        
        let wiredAdbEnabled = appState.wiredAdbEnabled
        let wirelessAddress = "\(appState.adbConnectedIP):\(appState.adbPort)"
        let adbConnected = appState.adbConnected
        
        ADBConnector.getWiredDevices { devices in
            let mappedSerial = appState.selectedWiredSerial ?? (appState.device?.deviceId).flatMap { appState.deviceAdbSerials[$0] }
            let serialToUse: String?
            if let mapped = mappedSerial, devices.contains(where: { $0.serial == mapped }) {
                serialToUse = mapped
            } else {
                serialToUse = devices.first?.serial
            }
            
            let finalSerial: String?
            if wiredAdbEnabled, let serial = serialToUse {
                finalSerial = serial
            } else if adbConnected && !appState.adbConnectedIP.isEmpty {
                finalSerial = wirelessAddress
            } else {
                finalSerial = nil
            }
            
            guard let serial = finalSerial else {
                DispatchQueue.main.async {
                    completion(false, "No ADB device detected. Please connect your device via USB or Wi-Fi.")
                }
                return
            }
            
            self.startServer(serial: serial, desktopMode: desktopMode) { success in
                guard success else {
                    DispatchQueue.main.async {
                        completion(false, "Failed to start scrcpy server on device.")
                    }
                    return
                }
                DispatchQueue.main.async {
                    streamClient.onPacketReceived = { data, isConfig, isKeyframe, pts in
                        ScrcpyVideoDecoder.shared.decodePacket(data: data, isConfig: isConfig, pts: pts)
                    }
                    streamClient.connect()
                    ScrcpyControlClient.shared.connect()
                    completion(true, nil)
                }
            }
        }
    }
    
    func stopMirroringSession(streamClient: ScrcpyStreamClient) {
        streamClient.disconnect()
        ScrcpyControlClient.shared.disconnect()
        self.stopServer()
    }
}
