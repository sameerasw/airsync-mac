//
//  CrashManager.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2026-06-20.
//

import Foundation
import Cocoa
import KSCrashInstallations
import UniformTypeIdentifiers

class CrashManager {
    static let shared = CrashManager()
    
    private init() {}
    
    func install() {
        let installation = CrashInstallationStandard.shared
        // No URL is configured, ensuring reports remain strictly local
        let config = KSCrashConfiguration()
        config.monitors = [.machException, .signal]
        do {
            try installation.install(with: config)
        } catch {
            print("Failed to install KSCrash: \(error)")
        }
    }
    
    func hasReports() -> Bool {
        guard let reportStore = KSCrash.shared.reportStore else { return false }
        return !reportStore.reportIDs.isEmpty
    }
    
    func lastReportText() -> String? {
        guard let reportStore = KSCrash.shared.reportStore else { return nil }
        let reportIDs = reportStore.reportIDs
        guard !reportIDs.isEmpty else { return nil }
        
        // Get the latest report ID
        let sortedIDs = reportIDs.map { $0.int64Value }.sorted()
        guard let latestID = sortedIDs.last else { return nil }
        
        guard let reportDictionary = reportStore.report(for: latestID) else {
            return nil
        }
        
        let report = reportDictionary.value as? [String: Any] ?? [:]
        
        // Build a concise human-readable crash report summary
        var summary = ""
        
        // 1. System Info
        if let system = report["system"] as? [String: Any] {
            let appName = system["CFBundleName"] as? String ?? system["CFBundleExecutable"] as? String ?? "AirSync"
            let appVersion = system["CFBundleShortVersionString"] as? String ?? "Unknown"
            let appBuild = system["CFBundleVersion"] as? String ?? "Unknown"
            let osName = system["system_name"] as? String ?? "macOS"
            let osVersion = system["system_version"] as? String ?? system["os_version"] as? String ?? ""
            let cpuArch = system["cpu_arch"] as? String ?? system["binary_arch"] as? String ?? "Unknown"
            let timeStr = report["report"] as? [String: Any] ?? [:]
            let crashTime = timeStr["timestamp"] as? String ?? system["app_start_time"] as? String ?? "Unknown"
            
            summary += "=== SYSTEM INFO ===\n"
            summary += "App Name: \(appName)\n"
            summary += "App Version: \(appVersion) (\(appBuild))\n"
            summary += "OS: \(osName) \(osVersion)\n"
            summary += "CPU: \(cpuArch)\n"
            summary += "Crash Time: \(crashTime)\n\n"
        }
        
        // 2. Crash Diagnostics / Exception Details
        if let crash = report["crash"] as? [String: Any] {
            summary += "=== CRASH DIAGNOSTICS ===\n"
            if let errorInfo = crash["error"] as? [String: Any] {
                let reason = errorInfo["reason"] as? String ?? "Unknown"
                let type = errorInfo["type"] as? String ?? "Unknown"
                summary += "Type: \(type)\n"
                summary += "Reason: \(reason)\n"
                
                if let machException = errorInfo["mach"] as? [String: Any] {
                    let machName = machException["exception_name"] as? String ?? ""
                    let machCode = machException["code_name"] as? String ?? ""
                    if !machName.isEmpty {
                        summary += "Mach Exception: \(machName) (\(machCode))\n"
                    }
                }
                
                if let signalInfo = errorInfo["signal"] as? [String: Any] {
                    let sigName = signalInfo["signal_name"] as? String ?? ""
                    let sigCode = signalInfo["code_name"] as? String ?? ""
                    if !sigName.isEmpty {
                        summary += "Signal: \(sigName) (\(sigCode))\n"
                    }
                }
                
                if let nsexception = errorInfo["nsexception"] as? [String: Any] {
                    summary += "NSException: \(nsexception["name"] ?? "") - \(nsexception["reason"] ?? "")\n"
                }
                
                if let cppException = errorInfo["cpp_exception"] as? [String: Any] {
                    summary += "C++ Exception: \(cppException["name"] ?? "Unknown")\n"
                }
                
                if let userReported = errorInfo["user_reported"] as? [String: Any] {
                    summary += "User Reported Exception: \(userReported["name"] ?? "") - \(userReported["reason"] ?? "")\n"
                }
            }
            summary += "\n"
            
            // 3. Thread Stack Traces (Focusing on the crashed thread)
            if let threads = crash["threads"] as? [[String: Any]] {
                summary += "=== THREADS ===\n"
                for thread in threads {
                    let isCrashed = thread["crashed"] as? Bool ?? false
                    let threadIndex = thread["index"] as? Int ?? 0
                    let threadName = thread["name"] as? String ?? ""
                    let dispatchQueue = thread["dispatch_queue"] as? String ?? ""
                    
                    if isCrashed {
                        var threadHeader = "Thread \(threadIndex) (CRASHED)"
                        if !dispatchQueue.isEmpty {
                            threadHeader += " [Queue: \(dispatchQueue)]"
                        } else if !threadName.isEmpty {
                            threadHeader += " [Name: \(threadName)]"
                        }
                        summary += "\(threadHeader):\n"
                        
                        if let backtrace = thread["backtrace"] as? [String: Any], let contents = backtrace["contents"] as? [[String: Any]] {
                            for (index, frame) in contents.enumerated() {
                                let objectName = frame["object_name"] as? String ?? "Unknown"
                                let symbolName = frame["symbol_name"] as? String ?? ""
                                let symbolAddr = frame["symbol_addr"] as? UInt64 ?? 0
                                let instructionAddr = frame["instruction_addr"] as? UInt64 ?? 0
                                let offset = instructionAddr - symbolAddr
                                
                                if !symbolName.isEmpty {
                                    summary += "  \(index)  \(objectName) \(symbolName) + \(offset)\n"
                                } else {
                                    summary += "  \(index)  \(objectName) 0x\(String(instructionAddr, radix: 16))\n"
                                }
                            }
                        }
                        summary += "\n"
                    }
                }
            }
        }
        
        return summary.isEmpty ? "No crash information found." : summary
    }
    
    func checkAndNotify(mode: CrashReportingMode) {
        guard mode == .notify else { return }
        
        guard let reportStore = KSCrash.shared.reportStore else { return }
        let reportIDs = reportStore.reportIDs
        if !reportIDs.isEmpty {
            // Check if we have already notified about the current set of reports to avoid alerting repeatedly
            let sortedIDs = reportIDs.map { $0.int64Value }.sorted()
            guard let latestID = sortedIDs.last else { return }
            
            let lastNotifiedID = UserDefaults.standard.integer(forKey: "lastNotifiedCrashID")
            if Int64(lastNotifiedID) == latestID {
                return
            }
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Application Crash Detected"
                alert.informativeText = "AirSync encountered a crash during its previous run. You can view or save the crash report from the Help menu."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                
                UserDefaults.standard.set(Int(latestID), forKey: "lastNotifiedCrashID")
            }
        }
    }
    
    func copyLastReport() {
        guard let reportText = lastReportText() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(reportText, forType: .string)
    }
    
    func saveLastReport() {
        guard let reportText = lastReportText() else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text]
        savePanel.nameFieldStringValue = "airsync_crash_report.txt"
        savePanel.title = "Save Crash Report"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try reportText.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Error Saving Report"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .critical
                        alert.runModal()
                    }
                }
            }
        }
    }
}
