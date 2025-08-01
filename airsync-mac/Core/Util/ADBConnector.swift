//
//  ADBConnector.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-01.
//

import Foundation

struct ADBConnector {

    static func connectToADB(ip: String, port: UInt16) {
        guard let adbPath = Bundle.main.path(forResource: "adb", ofType: nil) else {
            AppState.shared.adbConnectionResult = "ADB binary not found in bundle."
            AppState.shared.adbConnected = false
            return
        }

        let fullAddress = "\(ip):\(port)"

        // Step 1: Kill any existing adb server
        runADBCommand(adbPath: adbPath, arguments: ["kill-server"]) { _ in
            // Step 2: Connect to device
            runADBCommand(adbPath: adbPath, arguments: ["connect", fullAddress]) { output in
                DispatchQueue.main.async {
                    let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    AppState.shared.adbConnectionResult = trimmedOutput

                    if trimmedOutput.lowercased().contains("connected to") {
                        AppState.shared.adbConnected = true
                    } else {
                        AppState.shared.adbConnected = false
                    }
                }
            }
        }
    }

    static func disconnectADB() {
        guard let adbPath = Bundle.main.path(forResource: "adb", ofType: nil) else {
            AppState.shared.adbConnectionResult = "ADB binary not found in bundle."
            AppState.shared.adbConnected = false
            return
        }

        // Step 1: Kill any existing adb server
        runADBCommand(adbPath: adbPath, arguments: ["kill-server"])
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
            completion?("Failed to run adb: \(error.localizedDescription)")
        }
    }

    static func startScrcpy(
        ip: String,
        port: UInt16,
        deviceName: String,
        desktop: Bool? = false,
        package: String? = nil
    ) {
        guard let scrcpyPath = Bundle.main.path(forResource: "scrcpy", ofType: nil) else {
            AppState.shared.adbConnectionResult = "scrcpy binary not found in bundle."
            return
        }

        let fullAddress = "\(ip):\(port)"
        let deviceNameFormatted = deviceName.removingApostrophesAndPossessives()

        // Arguments to scrcpy for wireless connection
        // scrcpy --tcpip=<ip>:<port>
        var args = [
            "--window-title=\(deviceNameFormatted)",
            "--tcpip=\(fullAddress)",
            "--video-bit-rate=3M",
            "--video-codec=h265",
            "--max-size=1200"
        ]

        if desktop ?? true {
            args.append("--new-display=2560x1440")
        }

        if package != nil {
            args.append(contentsOf: [
                "--new-display=500x800",
                "--start-app=\(package ?? "")",
                "--no-vd-system-decorations"
            ])
        }


        let task = Process()
        task.executableURL = URL(fileURLWithPath: scrcpyPath)
        task.arguments = args

        // Optionally, capture output if you want to show logs
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "No output"
            DispatchQueue.main.async {
                AppState.shared.adbConnectionResult = "scrcpy exited:\n" + output
            }
        }

        do {
            try task.run()
            DispatchQueue.main.async {
                AppState.shared.adbConnectionResult = "Started scrcpy on \(fullAddress)"
            }
        } catch {
            DispatchQueue.main.async {
                AppState.shared.adbConnectionResult = "Failed to start scrcpy: \(error.localizedDescription)"
            }
        }
    }
}
