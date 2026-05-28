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
    
    private var pairingService: NetService?
    private var pairingBrowser: NetServiceBrowser?
    private var connectBrowser: NetServiceBrowser?
    
    private var discoveredPairingServices: [NetService] = []
    private var discoveredConnectServices: [NetService] = []
    
    private var targetIP: String?
    private var targetPairingPort: Int?
    
    func startPairing() {
        isPairing = true
        status = "Generating pairing credentials..."
        
        let suffix = (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
        serviceName = "adb-wireless-\(suffix)"
        password = (0..<8).map { _ in String(Int.random(in: 0...9)) }.joined()
        pairingString = "WIFI:T:ADB;S:\(serviceName);P:\(password);;"
        
        status = "Advertising pairing service..."
        
        // Start mDNS advertisement
        pairingService = NetService(domain: "", type: "_adb-tls-pairing._tcp.", name: serviceName, port: 0)
        pairingService?.delegate = self
        pairingService?.publish()
        
        // Start browsing for client pairing service
        pairingBrowser = NetServiceBrowser()
        pairingBrowser?.delegate = self
        pairingBrowser?.searchForServices(ofType: "_adb-tls-pairing._tcp.", inDomain: "")
        
        print("[ADBPairingManager] Started advertising \(serviceName) and browsing for client...")
    }
    
    func stopPairing() {
        pairingService?.stop()
        pairingService = nil
        
        pairingBrowser?.stop()
        pairingBrowser = nil
        
        connectBrowser?.stop()
        connectBrowser = nil
        
        discoveredPairingServices.removeAll()
        discoveredConnectServices.removeAll()
        
        isPairing = false
        status = "Idle"
        targetIP = nil
        targetPairingPort = nil
    }
    
    // MARK: - NetServiceDelegate (Advertising)
    func netServiceDidPublish(_ sender: NetService) {
        print("[ADBPairingManager] Successfully published pairing service: \(sender.name)")
        DispatchQueue.main.async {
            self.status = "Waiting for device to scan QR code..."
        }
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("[ADBPairingManager] Failed to publish pairing service: \(errorDict)")
        DispatchQueue.main.async {
            self.status = "Failed to start mDNS advertising."
        }
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
                    self.status = "Resolving device address..."
                }
            }
        } else if browser === connectBrowser {
            service.delegate = self
            service.resolve(withTimeout: 10.0)
            discoveredConnectServices.append(service)
        }
    }
    
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
        
        guard let ip = ipAddress, let p = port else { return }
        print("[ADBPairingManager] Resolved service \(sender.name) to \(ip):\(p)")
        
        if discoveredPairingServices.contains(sender) {
            targetIP = ip
            targetPairingPort = p
            
            DispatchQueue.main.async {
                self.status = "Found pairing port. Discovering connection port..."
                self.startConnectBrowser()
            }
        } else if discoveredConnectServices.contains(sender) {
            if ip == targetIP {
                print("[ADBPairingManager] Found debugging port \(p) for IP \(ip)")
                connectBrowser?.stop()
                connectBrowser = nil
                discoveredConnectServices.removeAll()
                
                let pairingPort = targetPairingPort ?? 0
                let debuggingPort = p
                
                DispatchQueue.main.async {
                    self.status = "Device found, pairing..."
                }
                
                executePairAndConnect(ip: ip, pairingPort: pairingPort, debuggingPort: debuggingPort)
            }
        }
    }
    
    private func startConnectBrowser() {
        connectBrowser?.stop()
        discoveredConnectServices.removeAll()
        
        connectBrowser = NetServiceBrowser()
        connectBrowser?.delegate = self
        connectBrowser?.searchForServices(ofType: "_adb-tls-connect._tcp.", inDomain: "")
    }
    
    private func executePairAndConnect(ip: String, pairingPort: Int, debuggingPort: Int) {
        guard let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) else {
            DispatchQueue.main.async {
                self.status = "ADB not found. Please install platform-tools."
            }
            return
        }
        
        let fullPairingAddress = "\(ip):\(pairingPort)"
        let fullConnectAddress = "\(ip):\(debuggingPort)"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 1. Run `adb pair <ip>:<pairingPort> <password>`
            self.runCommand(executable: adbPath, arguments: ["pair", fullPairingAddress, self.password]) { [weak self] pairSuccess, pairOutput in
                guard let self = self else { return }
                print("[ADBPairingManager] adb pair output: \(pairOutput)")
                
                if !pairSuccess {
                    DispatchQueue.main.async {
                        self.status = "Pairing failed: \(pairOutput)"
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.status = "Pairing successful! Connecting..."
                }
                
                // 2. Run `adb connect <ip>:<debuggingPort>`
                self.runCommand(executable: adbPath, arguments: ["connect", fullConnectAddress]) { connectSuccess, connectOutput in
                    DispatchQueue.main.async {
                        if connectSuccess {
                            self.status = "Device successfully connected!"
                            AppState.shared.adbConnected = true
                            AppState.shared.adbPort = UInt16(debuggingPort)
                            AppState.shared.adbConnectedIP = ip
                            AppState.shared.adbConnectionResult = "Connected to \(fullConnectAddress)"
                        } else {
                            self.status = "Connection failed: \(connectOutput)"
                        }
                    }
                }
            }
        }
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
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            completion(task.terminationStatus == 0, output)
        } catch {
            completion(false, error.localizedDescription)
        }
    }
}
