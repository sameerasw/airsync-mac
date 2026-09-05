//
//  ADBPairingManager.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2026-05-27.
//

import Foundation
import Combine

class ADBPairingManager: NSObject, ObservableObject, NetServiceDelegate, NetServiceBrowserDelegate {
    static let shared = ADBPairingManager()

    @Published var serviceName: String = ""
    @Published var password: String = ""
    @Published var pairingString: String = ""
    
    @Published var status: String = "Idle"
    @Published var isPairing: Bool = false
    
    private var pairingBrowser: NetServiceBrowser?
    private var connectBrowser: NetServiceBrowser?
    
    private var discoveredPairingServices: [NetService] = []
    private var discoveredConnectServices: [NetService] = []
    
    private var targetIP: String?
    private var targetPairingPort: Int?
    private var discoveredConnectPorts: [String: Int] = [:]
    
    private var isPairingInProgress: Bool = false
    private var isPairedSuccessfully: Bool = false
    private var isConnectedSuccessfully: Bool = false
    
    func startPairing() {
        stopPairing()
        
        isPairing = true
        status = "Generating pairing credentials..."
        
        let suffix = (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
        serviceName = "adb-wireless-\(suffix)"
        password = (0..<8).map { _ in String(Int.random(in: 0...9)) }.joined()
        pairingString = "WIFI:T:ADB;S:\(serviceName);P:\(password);;"
        
        status = "Waiting for device to scan QR code..."
        
        pairingBrowser = NetServiceBrowser()
        pairingBrowser?.delegate = self
        pairingBrowser?.searchForServices(ofType: "_adb-tls-pairing._tcp.", inDomain: "")
        
        connectBrowser = NetServiceBrowser()
        connectBrowser?.delegate = self
        connectBrowser?.searchForServices(ofType: "_adb-tls-connect._tcp.", inDomain: "")
        
        print("[ADBPairingManager] Started browsing for pairing (\(serviceName)) and connect services...")
    }
    
    func stopPairing() {
        pairingBrowser?.stop()
        pairingBrowser = nil
        
        connectBrowser?.stop()
        connectBrowser = nil
        
        discoveredPairingServices.removeAll()
        discoveredConnectServices.removeAll()
        discoveredConnectPorts.removeAll()
        
        isPairing = false
        isPairingInProgress = false
        isPairedSuccessfully = false
        isConnectedSuccessfully = false
        status = "Idle"
        targetIP = nil
        targetPairingPort = nil
    }
    
    // MARK: - NetServiceBrowserDelegate
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("[ADBPairingManager] Found service: \(service.name) of type \(service.type)")
        
        if browser === pairingBrowser {
            if service.name.contains(serviceName) || serviceName.contains(service.name) {
                print("[ADBPairingManager] Found matching pairing service! Resolving...")
                service.delegate = self
                service.resolve(withTimeout: 10.0)
                discoveredPairingServices.append(service)
                DispatchQueue.main.async {
                    if !self.isPairingInProgress && !self.isPairedSuccessfully {
                        self.status = "Resolving device address..."
                    }
                }
            }
        } else if browser === connectBrowser {
            service.delegate = self
            service.resolve(withTimeout: 10.0)
            discoveredConnectServices.append(service)
        }
    }
    
    // MARK: - NetServiceDelegate
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses, !addresses.isEmpty else { return }
        
        var ipAddress: String?
        var port: Int?
        
        for address in addresses {
            address.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                guard let sockaddr = ptr.bindMemory(to: sockaddr.self).baseAddress else { return }
                if sockaddr.pointee.sa_family == AF_INET {
                    guard let sockaddr_in = ptr.bindMemory(to: sockaddr_in.self).baseAddress else { return }
                    var sin_addr = sockaddr_in.pointee.sin_addr
                    var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    if inet_ntop(AF_INET, &sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN)) != nil {
                        ipAddress = String(cString: ipBuf)
                        port = Int(sockaddr_in.pointee.sin_port.bigEndian)
                    }
                }
            }
            if ipAddress != nil { break }
        }
        
        guard let ip = ipAddress, let p = port, p > 0 else { return }
        print("[ADBPairingManager] Resolved service \(sender.name) (\(sender.type)) to \(ip):\(p)")
        
        if discoveredPairingServices.contains(sender) {
            targetIP = ip
            targetPairingPort = p
            
            DispatchQueue.main.async {
                if !self.isPairingInProgress && !self.isPairedSuccessfully {
                    self.status = "Pairing with device at \(ip):\(p)..."
                    self.executePairing(ip: ip, pairingPort: p)
                }
            }
        } else if discoveredConnectServices.contains(sender) {
            discoveredConnectPorts[ip] = p
            print("[ADBPairingManager] Saved debugging port \(p) for IP \(ip)")
            
            if isPairedSuccessfully && !isConnectedSuccessfully, ip == targetIP {
                executeConnect(ip: ip, debuggingPort: p)
            }
        }
    }
    
    private func isPortReachable(ip: String, port: Int) -> (reachable: Bool, errNo: Int32) {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return (false, errno) }
        defer { close(sock) }
        
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        inet_pton(AF_INET, ip, &addr.sin_addr)
        
        let res = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                connect(sock, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        return (res == 0, res == 0 ? 0 : errno)
    }

    private func executePairing(ip: String, pairingPort: Int, attempt: Int = 1) {
        guard !isPairingInProgress || attempt > 1 else { return }
        isPairingInProgress = true
        
        guard let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) else {
            DispatchQueue.main.async {
                self.status = "ADB not found. Please install platform-tools."
                self.isPairingInProgress = false
            }
            return
        }
        
        let fullPairingAddress = "\(ip):\(pairingPort)"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let (reachable, errCode) = self.isPortReachable(ip: ip, port: pairingPort)
            print("[ADBPairingManager] Socket check to \(ip):\(pairingPort) => reachable: \(reachable), errno: \(errCode)")
            
            if AppState.shared.alwaysKillAdbBeforeConnect || attempt > 1 {
                print("[ADBPairingManager] Resetting ADB server before attempt \(attempt)...")
                self.killADBServer(adbPath: adbPath)
                Thread.sleep(forTimeInterval: 0.3)
            }
            
            self.runCommand(executable: adbPath, arguments: ["pair", fullPairingAddress, self.password]) { [weak self] pairSuccess, pairOutput in
                guard let self = self else { return }
                print("[ADBPairingManager] adb pair (attempt \(attempt)) output: \(pairOutput)")
                
                let cleanOutput = pairOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                let isProtocolFault = cleanOutput.contains("protocol fault") || cleanOutput.contains("Undefined error")
                
                if !pairSuccess || isProtocolFault {
                    if attempt < 3 && (isProtocolFault || cleanOutput.contains("No route to host") || cleanOutput.contains("cannot connect to daemon")) {
                        print("[ADBPairingManager] Pairing hit protocol/daemon fault. Auto-restarting ADB daemon and retrying (attempt \(attempt + 1))...")
                        DispatchQueue.main.async {
                            self.status = "ADB server busy. Restarting daemon and retrying pairing (\(attempt + 1)/3)..."
                        }
                        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                            self.executePairing(ip: ip, pairingPort: pairingPort, attempt: attempt + 1)
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        self.isPairingInProgress = false
                        if errCode == 65 || cleanOutput.contains("No route to host") {
                            self.status = "macOS blocked connection to phone (No route to host). Check System Settings -> Privacy -> Local Network & Firewall."
                        } else if cleanOutput.contains("protocol fault") || cleanOutput.contains("Connection refused") {
                            self.status = "Could not reach device. Keep the QR code screen active on your phone & ensure both devices are on same Wi-Fi."
                        } else {
                            self.status = "Pairing failed: \(cleanOutput)"
                        }
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.isPairedSuccessfully = true
                    self.status = "Pairing successful! Connecting to device..."
                    
                    if let debuggingPort = self.discoveredConnectPorts[ip] {
                        self.executeConnect(ip: ip, debuggingPort: debuggingPort)
                    } else {
                        self.waitForConnectPort(ip: ip, attemptsLeft: 10)
                    }
                }
            }
        }
    }
    
    private func waitForConnectPort(ip: String, attemptsLeft: Int) {
        guard isPairedSuccessfully && !isConnectedSuccessfully else { return }
        
        if let debuggingPort = discoveredConnectPorts[ip] {
            executeConnect(ip: ip, debuggingPort: debuggingPort)
            return
        }
        
        if attemptsLeft <= 0 {
            status = "Paired, but wireless debugging port not found. Enable Wireless Debugging on device."
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.waitForConnectPort(ip: ip, attemptsLeft: attemptsLeft - 1)
        }
    }
    
    private func executeConnect(ip: String, debuggingPort: Int, attempt: Int = 1) {
        guard !isConnectedSuccessfully || attempt > 1 else { return }
        
        guard let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) else {
            DispatchQueue.main.async {
                self.status = "ADB not found."
            }
            return
        }
        
        let fullConnectAddress = "\(ip):\(debuggingPort)"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if attempt > 1 {
                print("[ADBPairingManager] Connection retry attempt \(attempt). Resetting ADB daemon...")
                self.killADBServer(adbPath: adbPath)
                Thread.sleep(forTimeInterval: 0.3)
            }
            
            self.runCommand(executable: adbPath, arguments: ["connect", fullConnectAddress]) { [weak self] connectSuccess, connectOutput in
                guard let self = self else { return }
                let cleanOutput = connectOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if connectSuccess && cleanOutput.lowercased().contains("connected") {
                    DispatchQueue.main.async {
                        self.status = "Device successfully connected!"
                        AppState.shared.adbConnected = true
                        AppState.shared.adbPort = UInt16(debuggingPort)
                        AppState.shared.adbConnectedIP = ip
                        AppState.shared.adbConnectionResult = "Connected to \(fullConnectAddress)"
                    }
                } else if attempt < 3 && (cleanOutput.contains("protocol fault") || cleanOutput.contains("failed to connect") || cleanOutput.contains("cannot connect to daemon")) {
                    print("[ADBPairingManager] Connection hit daemon fault. Auto-restarting ADB daemon and retrying (attempt \(attempt + 1))...")
                    DispatchQueue.main.async {
                        self.status = "Re-establishing ADB connection (\(attempt + 1)/3)..."
                    }
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                        self.executeConnect(ip: ip, debuggingPort: debuggingPort, attempt: attempt + 1)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isConnectedSuccessfully = false
                        self.status = "Connection failed: \(cleanOutput)"
                    }
                }
            }
        }
    }
    
    private func killADBServer(adbPath: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: adbPath)
        task.arguments = ["kill-server"]
        try? task.run()
        task.waitUntilExit()
    }
    
    private func runCommand(executable: String, arguments: [String], completion: @escaping (Bool, String) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            
            let output = String(data: data, encoding: .utf8) ?? ""
            completion(task.terminationStatus == 0, output)
        } catch {
            completion(false, error.localizedDescription)
        }
    }
}

