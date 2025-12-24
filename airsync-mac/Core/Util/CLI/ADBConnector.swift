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
    
    private static func clearConnectionFlag() {
        // Note: This function must ONLY be called while holding the connectionLock
        // Do NOT try to acquire the lock here
        isConnecting = false
    }

    static func connectToADB(ip: String) {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        
        // Prevent concurrent connection attempts
        if isConnecting {
            logBinaryDetection("ADB connection already in progress, ignoring duplicate request")
            return
        }
        
        isConnecting = true
        
        // Find adb
        guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
            AppState.shared.adbConnectionResult = "ADB not found. Please install via Homebrew: brew install android-platform-tools"
            AppState.shared.adbConnected = false
            DispatchQueue.main.async { AppState.shared.adbConnecting = false }
            clearConnectionFlag()
            return
        }

        DispatchQueue.main.async { AppState.shared.adbConnecting = true }

        // Get ADB ports from device info
        let devicePorts = AppState.shared.device?.adbPorts ?? []
        
        if devicePorts.isEmpty {
            if AppState.shared.fallbackToMdns {
                logBinaryDetection("Device reported no ADB ports, attempting mDNS discovery...")
                discoverADBPorts(adbPath: adbPath, ip: ip) { ports in
                    if ports.isEmpty {
                        logBinaryDetection("mDNS discovery found no ports for \(ip).")
                        DispatchQueue.main.async {
                            AppState.shared.adbConnected = false
                            AppState.shared.adbConnecting = false
                            AppState.shared.adbConnectionResult = "No ADB ports reported by device and mDNS discovery failed."
                        }
                        connectionLock.lock()
                        clearConnectionFlag()
                        connectionLock.unlock()
                    } else {
                        logBinaryDetection("mDNS discovery found ports: \(ports.map(String.init).joined(separator: ", "))")
                        self.proceedWithConnection(adbPath: adbPath, ip: ip, portsToTry: ports)
                    }
                }
            } else {
                logBinaryDetection("Device reported no ADB ports and mDNS fallback is disabled.")
                AppState.shared.adbConnected = false
                DispatchQueue.main.async { AppState.shared.adbConnecting = false }
                clearConnectionFlag()
            }
            return
        }
        
        logBinaryDetection("Using ADB ports from device: \(devicePorts.joined(separator: ", "))")
        let portsToTry = devicePorts.compactMap { UInt16($0) }
        
        guard !portsToTry.isEmpty else {
            AppState.shared.adbConnectionResult = "Device reported ADB ports but none could be parsed as valid port numbers."
            AppState.shared.adbConnected = false
            DispatchQueue.main.async { AppState.shared.adbConnecting = false }
            clearConnectionFlag()
            return
        }
        
        proceedWithConnection(adbPath: adbPath, ip: ip, portsToTry: portsToTry)
    }

    private static func discoverADBPorts(adbPath: String, ip: String, completion: @escaping ([UInt16]) -> Void) {
        runADBCommand(adbPath: adbPath, arguments: ["mdns", "services"]) { output in
            let lines = output.components(separatedBy: .newlines)
            var ports: [UInt16] = []
            
            for line in lines {
                // Typical line: _adb-tls-connect._tcp.   192.168.1.100:34567
                if line.contains(ip) {
                    let parts = line.split(separator: ":")
                    if parts.count >= 2 {
                        let portPart = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        // Extract only the numeric part if there's trailing junk
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
        }
    }

    private static func proceedWithConnection(adbPath: String, ip: String, portsToTry: [UInt16]) {
        // Kill adb server first
        logBinaryDetection("Killing adb server: \(adbPath) kill-server")
        runADBCommand(adbPath: adbPath, arguments: ["kill-server"]) { _ in
            // Give the adb daemon time to fully terminate
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
                // Explicitly start the server and wait for it
                logBinaryDetection("Starting adb server...")
                ADBConnector.runADBCommand(adbPath: adbPath, arguments: ["start-server"]) { _ in
                    // Give server time to fully initialize
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.5) {
                        // Try each port until one succeeds
                        attemptConnectionToNextPort(adbPath: adbPath, ip: ip, portsToTry: portsToTry, currentIndex: 0, reportedIP: ip)
                    }
                }
            }
        }
    }

    // Attempt connection using custom port directly without mDNS discovery
    private static func attemptDirectConnection(adbPath: String, fullAddress: String) {
        logBinaryDetection("Attempting direct connection to custom port: \(adbPath) connect \(fullAddress)")

        runADBCommand(adbPath: adbPath, arguments: ["connect", fullAddress]) { output in
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            DispatchQueue.main.async {
                UserDefaults.standard.lastADBCommand = "adb connect \(fullAddress)"

                if trimmedOutput.contains("connected to") {
                    // Success! Connection established
                    if let portStr = fullAddress.split(separator: ":").last,
                       let port = UInt16(portStr) {
                        AppState.shared.adbPort = port
                    }
                    AppState.shared.adbConnected = true
                    AppState.shared.adbConnectionResult = trimmedOutput
                    logBinaryDetection("(/^▽^)/ ADB connection successful to \(fullAddress)")
                    AppState.shared.adbConnecting = false
                    clearConnectionFlag()
                } else {
                    // Connection failed - show error popup only on final failure
                    AppState.shared.adbConnected = false
                    logBinaryDetection("(T＿T) Custom port connection failed: \(trimmedOutput)")
                    AppState.shared.adbConnectionResult = """
Failed to connect to custom ADB port.

Address: \(fullAddress)
Error: \(trimmedOutput)

Possible fixes:
- Verify the custom port is correct
- Ensure Wireless Debugging is enabled on the device
- Check that the device is reachable at the specified IP
- Disable custom port and use automatic discovery
"""
                    AppState.shared.adbConnecting = false
                    clearConnectionFlag()
                    
                    // Show alert popup for custom port failure (unless suppressed)
                    if !AppState.shared.suppressAdbFailureAlerts {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "Don't warn me again")
                        alert.addButton(withTitle: "OK")
                        alert.messageText = "Failed to connect to ADB on custom port."
                        alert.informativeText = """
Address: \(fullAddress)

Possible fixes:
- Verify the custom port is correct
- Ensure Wireless Debugging is enabled on the device
- Check that the device is reachable at the specified IP
- Disable custom port and use automatic discovery

Please see the ADB console for more details.
"""
                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            DispatchQueue.main.async {
                                AppState.shared.suppressAdbFailureAlerts = true
                            }
                        }
                    }
                }
            }
        }
    }

    // Recursive function to try each port until one succeeds
    private static func attemptConnectionToNextPort(adbPath: String, ip: String, portsToTry: [UInt16], currentIndex: Int, reportedIP: String? = nil) {
        // If we've tried all ports, fail
        if currentIndex >= portsToTry.count {
            // If we haven't tried the reported IP yet and it's different from the current IP, try it
            if let reportedIP = reportedIP, reportedIP != ip {
                logBinaryDetection("Failed to connect on discovered IP \(ip), attempting fallback to reported IP \(reportedIP)...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    attemptConnectionToNextPort(adbPath: adbPath, ip: reportedIP, portsToTry: portsToTry, currentIndex: 0, reportedIP: nil)
                }
                return
            }
            
            DispatchQueue.main.async {
                AppState.shared.adbConnected = false
                logBinaryDetection("(∩︵∩) ADB connection failed on all ports.")
                AppState.shared.adbConnectionResult = (AppState.shared.adbConnectionResult ?? "") + """

Failed to connect to device on any available port.

Tried ports: \(portsToTry.map(String.init).joined(separator: ", "))

Possible fixes:
- Ensure device is authorized for adb
- Disconnect and reconnect Wireless Debugging
- Run `adb disconnect` then retry
- It might be connected to another device.
  Try killing any external adb instances in mac terminal with 'adb kill-server' command.
"""
                AppState.shared.adbConnecting = false
                
                // Show alert popup only when all attempts have been exhausted (unless suppressed)
                if !AppState.shared.suppressAdbFailureAlerts {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Don't warn me again")
                    alert.addButton(withTitle: "OK")
                    alert.messageText = "Failed to connect to ADB."
                    alert.informativeText = """
Suggestions:
- Ensure your Android device is in Wireless debugging mode
- Try toggling Wireless Debugging off and on again
- Reconnect to the same Wi-Fi as your Mac
- Ensure device is authorized for adb
- Disconnect and reconnect Wireless Debugging

Please see the ADB console for more details.
"""
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        DispatchQueue.main.async {
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
        let portNumber = currentIndex + 1
        let totalPorts = portsToTry.count

        logBinaryDetection("Attempting connection to port \(currentPort) (attempt \(portNumber)/\(totalPorts)): \(adbPath) connect \(fullAddress)")

        runADBCommand(adbPath: adbPath, arguments: ["connect", fullAddress]) { output in
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            DispatchQueue.main.async {
                UserDefaults.standard.lastADBCommand = "adb connect \(fullAddress)"

                if trimmedOutput.contains("connected to") {
                    // Success! Connection established
                    AppState.shared.adbConnected = true
                    AppState.shared.adbPort = currentPort
                    AppState.shared.adbConnectedIP = ip  // Store the actual connected IP
                    AppState.shared.adbConnectionResult = trimmedOutput
                    logBinaryDetection("(/^▽^)/ ADB connection successful to \(fullAddress)")
                    AppState.shared.adbConnecting = false
                    clearConnectionFlag()
                }
                else if trimmedOutput.contains("protocol fault") || trimmedOutput.contains("connection reset by peer") {
                    // Connection exists elsewhere, show error and try next port
                    AppState.shared.adbConnected = false
                    logBinaryDetection("(T＿T) Port \(currentPort): ADB connection failed due to existing connection.")
                    AppState.shared.adbConnectionResult = (AppState.shared.adbConnectionResult ?? "") + """

Port \(currentPort) (attempt \(portNumber)/\(totalPorts)): Connection failed - another ADB instance already using the device.
"""
                    // Try next port after a short delay instead of giving up
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        attemptConnectionToNextPort(adbPath: adbPath, ip: ip, portsToTry: portsToTry, currentIndex: currentIndex + 1, reportedIP: reportedIP)
                    }
                }
                else {
                    // This port didn't work, try the next one
                    logBinaryDetection("Port \(currentPort) (attempt \(portNumber)/\(totalPorts)): Connection failed, trying next port...")
                    AppState.shared.adbConnectionResult = (AppState.shared.adbConnectionResult ?? "") + """

Attempt \(portNumber)/\(totalPorts) on port \(currentPort): Failed - \(trimmedOutput)
"""
                    // Try next port after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        attemptConnectionToNextPort(adbPath: adbPath, ip: ip, portsToTry: portsToTry, currentIndex: currentIndex + 1, reportedIP: reportedIP)
                    }
                }
            }
        }
    }

    static func disconnectADB() {
        guard let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) else {
            AppState.shared.adbConnectionResult = "ADB not found — cannot disconnect."
            AppState.shared.adbConnected = false
            return
        }

        logBinaryDetection("Killing adb server: \(adbPath) kill-server")
        runADBCommand(adbPath: adbPath, arguments: ["kill-server"])
        UserDefaults.standard.lastADBCommand = "adb kill-server"
        AppState.shared.adbConnected = false
        AppState.shared.adbConnecting = false
    }

    private static func runADBCommand(adbPath: String, arguments: [String], completion: ((String) -> Void)? = nil) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: adbPath)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "No output"
            completion?(output)
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
                AppState.shared.adbConnectionResult = "scrcpy not found. Please install via Homebrew: brew install scrcpy"

                presentScrcpyAlert(
                    title: "scrcpy Not Found",
                    informative: "AirSync couldn't find the scrcpy binary.\n\nFix suggestions:\n• Install via Homebrew: brew install scrcpy\n.\n\nAfter installing, try mirroring again. Might need the app to be restarted.")
            }
            return
        }

        let fullAddress = "\(ip):\(port)"
        let deviceNameFormatted = deviceName.removingApostrophesAndPossessives()
        let bitrate = AppState.shared.scrcpyBitrate
        let resolution = AppState.shared.scrcpyResolution
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
            "--tcpip=\(fullAddress)",
            "--video-bit-rate=\(bitrate)M",
            "--video-codec=h265",
            "--max-size=\(resolution)",
            "--no-power-on"
        ]

        if manualPosition {
            args.append("--window-x=\(manualPositionCoords[0])")
            args.append("--window-y=\(manualPositionCoords[1])")
        }

        if alwaysOnTop {
            args.append("--always-on-top")
        }

        if stayAwake {
            args.append("--stay-awake")
        }

        if turnScreenOff {
            args.append("--turn-screen-off")
        }

        if noAudio {
            args.append("--no-audio")
        }

        if directKeyInput {
            args.append("--keyboard=uhid")
        }

        if desktop ?? true {
            args.append("--new-display=\(desktopMode ?? "1600x1000")")
        }

        if let pkg = package {
            args.append(contentsOf: [
                "--new-display=\(appRes ?? "900x2100")",
                "--start-app=\(pkg)",
                "--no-vd-system-decorations"
            ])

            if continueApp {
                args.append("--no-vd-destroy-content")
            }
        }


        logBinaryDetection("Launching scrcpy: \(scrcpyPath) \(args.joined(separator: " "))")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)
        task.arguments = args

        //  Inject adb into scrcpy's environment
        if let adbPath = findExecutable(named: "adb", fallbackPaths: possibleADBPaths) {
            var env = ProcessInfo.processInfo.environment
            let adbDir = URL(fileURLWithPath: adbPath).deletingLastPathComponent().path
            env["PATH"] = "\(adbDir):" + (env["PATH"] ?? "")
            env["ADB"] = adbPath
            task.environment = env
        }

        UserDefaults.standard.lastADBCommand = "scrcpy \(args.joined(separator: " "))"


        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.terminationHandler = { process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "No output"
            DispatchQueue.main.async {
                AppState.shared.adbConnectionResult = "scrcpy exited:\n" + output

                let lowered = output.lowercased()
                let errorKeywords = ["error", "failed", "not found", "refused", "denied", "cannot", "unable", "protocol", "disconnected", "permission"]
                let hasErrorKeyword = errorKeywords.contains { lowered.contains($0) }
                let nonZero = process.terminationStatus != 0

                if nonZero || hasErrorKeyword {
                    var hint = "General troubleshooting:\n• Ensure only one mirroring/ADB tool is using the device\n• adb kill-server then retry\n• Re‑enable Wireless debugging\n• If using Desktop/App mode, ensure Android 15+ / vendor support\n• Try a lower resolution or bitrate.\n\nSee ADB Console in Settings for full output."

                    if lowered.contains("protocol fault") || lowered.contains("connection reset") {
                        hint = "Another active ADB/scrcpy session is likely holding the device.\n• Close any existing scrcpy or Android Studio emulator sessions\n• Run: adb kill-server\n• Retry mirroring."
                    } else if lowered.contains("permission denied") {
                        hint = "Permission denied starting scrcpy.\n• Verify scrcpy binary has execute permission (chmod +x)\n• Reinstall via Homebrew (brew reinstall scrcpy)."
                    } else if lowered.contains("could not"), lowered.contains("configure") || lowered.contains("video") {
                        hint = "Video initialization failed.\n• Lower bitrate or resolution in Settings\n• Toggle Desktop/App mode off\n• Reconnect ADB then retry."
                    }

                    presentScrcpyAlert(
                        title: "Mirroring Ended With Errors",
                        informative: hint
                    )
                }
            }
        }

        do {
            try task.run()
            DispatchQueue.main.async {
                AppState.shared.adbConnectionResult = "(ﾉ´ヮ´)ﾉ Started scrcpy on \(fullAddress)"
            }
        } catch {
            DispatchQueue.main.async {
                AppState.shared.adbConnectionResult = "┐('～`；)┌ Failed to start scrcpy: \(error.localizedDescription)"
                presentScrcpyAlert(
                    title: "Failed to Start Mirroring",
                    informative: "scrcpy couldn't launch.\nReason: \(error.localizedDescription)\n\nFix suggestions:\n• Ensure the device is still connected via ADB (reconnect if needed)\n• Close other scrcpy/ADB sessions\n• Reinstall scrcpy if the binary is corrupt\n• Lower bitrate/resolution then retry."
                )
            }
        }
    }
}

// MARK: - Alert Helper
private extension ADBConnector {
    static func presentScrcpyAlert(title: String, informative: String) {
        // Present immediately on main thread (caller ensures main queue)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = informative + "\n\nCheck the ADB Console in Settings for detailed logs."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
