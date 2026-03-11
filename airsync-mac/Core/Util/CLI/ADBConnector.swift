//
//  ADBConnector.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-01.
//

import Foundation
import AppKit

struct ADBConnector {

    // Potential fallback paths
    static let possibleADBPaths = [
        "/opt/homebrew/bin/adb",  // Apple Silicon Homebrew
        "/usr/local/bin/adb"      // Intel Homebrew
    ]
    static let possibleScrcpyPaths = [
        "/opt/scrcpy/scrcpy",
        "/opt/homebrew/bin/scrcpy",
        "/usr/local/bin/scrcpy"
    ]
    
    // Flag to prevent concurrent connection attempts
    private static var isConnecting = false
    private static let connectionLock = NSLock()

    // Try to locate a binary
    static func findExecutable(named name: String, fallbackPaths: [String]) -> String? {
        // Step 1: Try direct execution from PATH
        if isExecutableAvailable(name) {
            logBinaryDetection("\(name) found in system PATH — using direct command.")
            let path = getExecutablePath(name)
            return path
        }

        // Step 2: Try fallback paths
        for path in fallbackPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                logBinaryDetection("\(name) found at \(path) — using fallback path.")
                return path
            }
        }

        logBinaryDetection("\(name) not found in PATH or fallback locations.")
        return nil
    }

    private static func getExecutablePath(_ name: String) -> String {
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = [name]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output
    }
    // Check if binary is available in PATH
    static func isExecutableAvailable(_ name: String) -> Bool {
        let data = getExecutablePath(name)
        return !data.isEmpty
    }

    static func logBinaryDetection(_ message: String) {
        DispatchQueue.main.async {
            AppState.shared.adbConnectionResult = (AppState.shared.adbConnectionResult ?? "") + "\n[Binary Detection] \(message)"
        }
        print("[adb-connector] (Binary Detection) \(message)")
    }
    
    static func getWiredDeviceSerial(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
                completion(nil)
                return
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = ["devices", "-l"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let lines = output.components(separatedBy: .newlines)
                
                for line in lines {
                    if line.contains("device") && line.contains("usb:") {
                        let parts = line.split(separator: " ").filter { !$0.isEmpty }
                        if !parts.isEmpty {
                            let serial = String(parts[0])
                            logBinaryDetection("Detected wired ADB device: \(serial)")
                            completion(serial)
                            return
                        }
                    }
                }
            } catch {
                print("[adb-connector] Error getting wired devices: \(error)")
            }
            completion(nil)
        }
    }

    private static func clearConnectionFlag() {
        connectionLock.lock()
        isConnecting = false
        connectionLock.unlock()
    }

    static func connectToADB(ip: String) {
        connectionLock.lock()
        if isConnecting {
            connectionLock.unlock()
            logBinaryDetection("ADB connection already in progress, ignoring duplicate request")
            return
        }
        isConnecting = true
        connectionLock.unlock()
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
                DispatchQueue.main.async {
                    AppState.shared.adbConnectionResult = "ADB not found. Please install via Homebrew: brew install android-platform-tools"
                    AppState.shared.adbConnected = false
                    AppState.shared.adbConnecting = false
                }
                clearConnectionFlag()
                return
            }

            DispatchQueue.main.async { AppState.shared.adbConnecting = true }

            var devicePorts: [String] = []
            var fallbackToMdns = true
            
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                devicePorts = AppState.shared.device?.adbPorts ?? []
                fallbackToMdns = AppState.shared.fallbackToMdns
                semaphore.signal()
            }
            semaphore.wait()
            
            if devicePorts.isEmpty {
                if fallbackToMdns {
                    logBinaryDetection("Device reported no ADB ports, attempting mDNS discovery...")
                    discoverADBPorts(adbPath: adbPath, ip: ip) { ports in
                        if ports.isEmpty {
                            logBinaryDetection("mDNS discovery found no ports for \(ip).")
                            DispatchQueue.main.async {
                                AppState.shared.adbConnected = false
                                AppState.shared.adbConnecting = false
                                AppState.shared.adbConnectionResult = "No ADB ports reported by device and mDNS discovery failed."
                            }
                            clearConnectionFlag()
                        } else {
                            logBinaryDetection("mDNS discovery found ports: \(ports.map(String.init).joined(separator: ", "))")
                            self.proceedWithConnection(adbPath: adbPath, ip: ip, portsToTry: ports)
                        }
                    }
                } else {
                    logBinaryDetection("Device reported no ADB ports and mDNS fallback is disabled.")
                    DispatchQueue.main.async {
                        AppState.shared.adbConnected = false
                        AppState.shared.adbConnecting = false
                    }
                    clearConnectionFlag()
                }
                return
            }
            
            logBinaryDetection("Using ADB ports from device: \(devicePorts.joined(separator: ", "))")
            let portsToTry = devicePorts.compactMap { UInt16($0) }
            
            guard !portsToTry.isEmpty else {
                DispatchQueue.main.async {
                    AppState.shared.adbConnectionResult = "Device reported ADB ports but none could be parsed as valid port numbers."
                    AppState.shared.adbConnected = false
                    AppState.shared.adbConnecting = false
                }
                clearConnectionFlag()
                return
            }
            
            proceedWithConnection(adbPath: adbPath, ip: ip, portsToTry: portsToTry)
        }
    }

    private static func discoverADBPorts(adbPath: String, ip: String, completion: @escaping ([UInt16]) -> Void) {
        runADBCommand(adbPath: adbPath, arguments: ["mdns", "services"], completion: { output in
            let lines = output.components(separatedBy: .newlines)
            var ports: [UInt16] = []
            
            for line in lines {
                if line.contains(ip) {
                    let parts = line.split(separator: ":")
                    if parts.count >= 2 {
                        let portPart = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let numericPort = portPart.filter { "0123456789".contains($0) }
                        if let port = UInt16(numericPort) {
                            if !ports.contains(port) {
                                ports.append(port)
                            }
                        }
                    }
                }
            }
            completion(ports)
        })
    }

    private static func proceedWithConnection(adbPath: String, ip: String, portsToTry: [UInt16]) {
        logBinaryDetection("Proceeding with ADB connection attempts to \(ip)...")
        
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
            attemptConnectionToNextPort(adbPath: adbPath, ip: ip, portsToTry: portsToTry, currentIndex: 0, reportedIP: ip)
        }
    }

    private static func attemptConnectionToNextPort(adbPath: String, ip: String, portsToTry: [UInt16], currentIndex: Int, reportedIP: String? = nil) {
        if currentIndex >= portsToTry.count {
            if let reportedIP = reportedIP, reportedIP != ip {
                logBinaryDetection("Failed to connect on discovered IP \(ip), attempting fallback to reported IP \(reportedIP)...")
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                    attemptConnectionToNextPort(adbPath: adbPath, ip: reportedIP, portsToTry: portsToTry, currentIndex: 0, reportedIP: nil)
                }
                return
            }
            
            DispatchQueue.main.async {
                AppState.shared.adbConnected = false
                logBinaryDetection("(∩︵∩) ADB connection failed on all ports.")
                AppState.shared.adbConnectionResult = (AppState.shared.adbConnectionResult ?? "") + "\nFailed to connect to device on any available port."
                AppState.shared.adbConnecting = false
                
                if !AppState.shared.suppressAdbFailureAlerts {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Don't warn me again")
                    alert.addButton(withTitle: "OK")
                    alert.messageText = "Failed to connect to ADB."
                    alert.informativeText = "Suggestions:\n• Ensure your Android device is in Wireless debugging mode\n• Try toggling Wireless Debugging off and on again\n• Reconnect to the same Wi-Fi as your Mac"
                    
                    presentAlertAsynchronously(alert) { response in
                        if response == .alertFirstButtonReturn {
                            AppState.shared.suppressAdbFailureAlerts = true
                        }
                    }
                }
            }
            clearConnectionFlag()
            return
        }

        let currentPort = portsToTry[currentIndex]
        let fullAddress = "\(ip):\(currentPort)"
        logBinaryDetection("Attempting connection to port \(currentPort) (attempt \(currentIndex + 1)/\(portsToTry.count)): \(fullAddress)")

        runADBCommand(adbPath: adbPath, arguments: ["connect", fullAddress], completion: { output in
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            DispatchQueue.main.async {
                UserDefaults.standard.lastADBCommand = "adb connect \(fullAddress)"

                if trimmedOutput.contains("connected to") {
                    AppState.shared.adbConnected = true
                    AppState.shared.adbPort = currentPort
                    AppState.shared.adbConnectedIP = ip
                    AppState.shared.adbConnectionResult = trimmedOutput
                    logBinaryDetection("(/^▽^)/ ADB connection successful to \(fullAddress)")
                    AppState.shared.adbConnecting = false
                    clearConnectionFlag()
                } else {
                    logBinaryDetection("Port \(currentPort) failed, trying next...")
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                        attemptConnectionToNextPort(adbPath: adbPath, ip: ip, portsToTry: portsToTry, currentIndex: currentIndex + 1, reportedIP: reportedIP)
                    }
                }
            }
        })
    }

    static func disconnectADB() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
                DispatchQueue.main.async {
                    AppState.shared.adbConnected = false
                }
                return
            }

            var adbIP = ""
            var adbPort: UInt16 = 0
            
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                adbIP = AppState.shared.adbConnectedIP
                adbPort = AppState.shared.adbPort
                semaphore.signal()
            }
            semaphore.wait()

            if !adbIP.isEmpty {
                let fullAddress = "\(adbIP):\(adbPort)"
                runADBCommand(adbPath: adbPath, arguments: ["disconnect", fullAddress])
            }
            
            DispatchQueue.main.async {
                AppState.shared.adbConnected = false
                AppState.shared.adbConnecting = false
            }
        }
    }

    private static func runADBCommand(
        adbPath: String,
        arguments: [String],
        onOutput: ((String) -> Void)? = nil,
        completion: ((String) -> Void)? = nil
    ) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: adbPath)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        var fullOutput = ""
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let str = String(data: data, encoding: .utf8) {
                fullOutput += str
                onOutput?(str)
                
                if !arguments.contains("mdns") && !arguments.contains("kill-server") {
                    DispatchQueue.main.async {
                        AppState.shared.adbConnectionResult = (AppState.shared.adbConnectionResult ?? "") + str
                    }
                }
            }
        }

        task.terminationHandler = { _ in
            completion?(fullOutput)
        }

        do {
            try task.run()
        } catch {
            completion?("Failed to run \(adbPath): \(error.localizedDescription)")
        }
    }

    static func startScrcpy(
        ip: String,
        port: UInt16,
        deviceName: String,
        desktop: Bool? = false,
        package: String? = nil
    ) {
        guard let scrcpyPath = findExecutable(named: "scrcpy", fallbackPaths: possibleScrcpyPaths) else {
            DispatchQueue.main.async {
                AppState.shared.adbConnectionResult = "scrcpy not found."
                presentScrcpyAlert(title: "scrcpy Not Found", informative: "AirSync couldn't find the scrcpy binary.")
            }
            return
        }

        let fullAddress = "\(ip):\(port)"
        let deviceNameFormatted = deviceName.removingApostrophesAndPossessives()
        
        var bitrate = 4
        var resolution = 1200
        var wiredAdbEnabled = false
        
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            bitrate = AppState.shared.scrcpyBitrate
            resolution = AppState.shared.scrcpyResolution
            wiredAdbEnabled = AppState.shared.wiredAdbEnabled
            semaphore.signal()
        }
        semaphore.wait()

        let desktopMode = UserDefaults.standard.scrcpyDesktopMode
        let alwaysOnTop = UserDefaults.standard.scrcpyOnTop
        let stayAwake = UserDefaults.standard.stayAwake
        let turnScreenOff = UserDefaults.standard.turnScreenOff
        let appRes = UserDefaults.standard.scrcpyShareRes ? UserDefaults.standard.scrcpyDesktopMode : "900x2100"
        let noAudio = UserDefaults.standard.noAudio
        let manualPosition = UserDefaults.standard.manualPosition
        let manualPositionCoords = UserDefaults.standard.manualPositionCoords
        let continueApp = UserDefaults.standard.continueApp
        let directKeyInput = UserDefaults.standard.directKeyInput

        var args = [
            "--window-title=\(deviceNameFormatted)",
            "--video-bit-rate=\(bitrate)M",
            "--video-codec=h265",
            "--max-size=\(resolution)",
            "--no-power-on"
        ]

        getWiredDeviceSerial { serial in
            if wiredAdbEnabled, let serial = serial {
                args.append("--serial=\(serial)")
                DispatchQueue.main.async { AppState.shared.adbConnectionMode = .wired }
                logBinaryDetection("Wired ADB prioritized: using serial \(serial)")
            } else {
                args.append("--tcpip=\(fullAddress)")
                DispatchQueue.main.async { AppState.shared.adbConnectionMode = .wireless }
            }

            DispatchQueue.global(qos: .userInitiated).async {
                if manualPosition {
                    args.append("--window-x=\(manualPositionCoords[0])")
                    args.append("--window-y=\(manualPositionCoords[1])")
                }
                if alwaysOnTop { args.append("--always-on-top") }
                if stayAwake { args.append("--stay-awake") }
                if turnScreenOff { args.append("--turn-screen-off") }
                if noAudio { args.append("--no-audio") }
                if directKeyInput { args.append("--keyboard=uhid") }

                if desktop ?? true {
                    let res = desktopMode ?? "1600x1000"
                    let dpi = UserDefaults.standard.string(forKey: "scrcpyDesktopDpi") ?? ""
                    args.append("--new-display=\(res)" + (!dpi.isEmpty ? "/\(dpi)" : ""))
                }

                if let pkg = package {
                    args.append(contentsOf: ["--new-display=\(appRes ?? "900x2100")", "--start-app=\(pkg)", "--no-vd-system-decorations"])
                    if continueApp { args.append("--no-vd-destroy-content") }
                }

                logBinaryDetection("Launching scrcpy: \(scrcpyPath) \(args.joined(separator: " "))")
                let task = Process()
                task.executableURL = URL(fileURLWithPath: scrcpyPath)
                task.arguments = args

                if let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) {
                    var env = ProcessInfo.processInfo.environment
                    let adbDir = URL(fileURLWithPath: adbPath).deletingLastPathComponent().path
                    env["PATH"] = "\(adbDir):" + (env["PATH"] ?? "")
                    env["ADB"] = adbPath
                    task.environment = env
                }

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe

                task.terminationHandler = { process in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    DispatchQueue.main.async {
                        AppState.shared.adbConnectionResult = "scrcpy exited:\n" + output
                        if process.terminationStatus != 0 {
                            presentScrcpyAlert(title: "Mirroring Ended With Errors", informative: "See ADB Console for details.")
                        }
                    }
                }

                do {
                    try task.run()
                } catch {
                    DispatchQueue.main.async {
                        AppState.shared.adbConnectionResult = "Failed to start scrcpy: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    static func pull(remotePath: String, completion: ((Bool) -> Void)? = nil) {
        guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
            completion?(false)
            return
        }

        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.begin { response in
                if response == .OK, let destinationURL = panel.url {
                    let fileName = (remotePath as NSString).lastPathComponent
                    let destiny = destinationURL.appendingPathComponent(fileName).path
                    
                    var wiredAdbEnabled = false
                    var fullAddress = ""
                    let semaphore = DispatchSemaphore(value: 0)
                    DispatchQueue.main.async {
                        wiredAdbEnabled = AppState.shared.wiredAdbEnabled
                        fullAddress = "\(AppState.shared.adbConnectedIP):\(AppState.shared.adbPort)"
                        AppState.shared.isADBTransferring = true
                        AppState.shared.adbTransferringFilePath = remotePath
                        semaphore.signal()
                    }
                    semaphore.wait()

                    getWiredDeviceSerial { serial in
                        DispatchQueue.global(qos: .userInitiated).async {
                            var args = ["pull", remotePath, destiny]
                            if wiredAdbEnabled, let serial = serial {
                                args.insert(contentsOf: ["-s", serial], at: 0)
                            } else {
                                args.insert(contentsOf: ["-s", fullAddress], at: 0)
                            }
                            
                            runADBCommand(adbPath: adbPath, arguments: args) { output in
                                let success = !output.contains("error") && !output.contains("failed")
                                DispatchQueue.main.async {
                                    AppState.shared.isADBTransferring = false
                                    AppState.shared.adbTransferringFilePath = nil
                                    if success { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: destiny) }
                                    completion?(success)
                                }
                            }
                        }
                    }
                } else {
                    completion?(false)
                }
            }
        }
    }

    static func push(localPath: String, remotePath: String, completion: ((Bool) -> Void)? = nil) {
        guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
            completion?(false)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var wiredAdbEnabled = false
            var fullAddress = ""
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                wiredAdbEnabled = AppState.shared.wiredAdbEnabled
                fullAddress = "\(AppState.shared.adbConnectedIP):\(AppState.shared.adbPort)"
                AppState.shared.isADBTransferring = true
                AppState.shared.adbTransferringFilePath = remotePath
                semaphore.signal()
            }
            semaphore.wait()

            getWiredDeviceSerial { serial in
                DispatchQueue.global(qos: .userInitiated).async {
                    var args = ["push", localPath, remotePath]
                    if wiredAdbEnabled, let serial = serial {
                        args.insert(contentsOf: ["-s", serial], at: 0)
                    } else {
                        args.insert(contentsOf: ["-s", fullAddress], at: 0)
                    }
                    
                    runADBCommand(adbPath: adbPath, arguments: args) { output in
                        let success = !output.contains("error") && !output.contains("failed")
                        DispatchQueue.main.async {
                            AppState.shared.isADBTransferring = false
                            AppState.shared.adbTransferringFilePath = nil
                            completion?(success)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Alert Helper
private extension ADBConnector {
    static func presentAlertAsynchronously(_ alert: NSAlert, completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0.isKeyWindow && $0.isVisible }) ?? NSApp.windows.first(where: { $0.isVisible }) {
                alert.beginSheetModal(for: window) { response in
                    completion?(response)
                }
            } else {
                NSApp.activate(ignoringOtherApps: true)
                let response = alert.runModal()
                completion?(response)
            }
        }
    }

    static func presentScrcpyAlert(title: String, informative: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = informative + "\n\nCheck the ADB Console in Settings for detailed logs."
        alert.addButton(withTitle: "OK")
        presentAlertAsynchronously(alert)
    }
}
