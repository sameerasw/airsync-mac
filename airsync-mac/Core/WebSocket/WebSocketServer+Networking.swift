//
//  WebSocketServer+Networking.swift
//  airsync-mac
//

import Foundation
import UniformTypeIdentifiers
#if canImport(MobileCoreServices)
import MobileCoreServices
#endif

extension WebSocketServer {
    
    // MARK: - Local IP handling

    /// Retrieves the local IP address based on configuration.
    /// Supports binding to a specific adapter or auto-discovery of all available non-loopback interfaces.
    func getLocalIPAddress(adapterName: String?) -> String? {
        let adapters = getAvailableNetworkAdapters()

        if let adapterName = adapterName {
            if let exact = adapters.first(where: { $0.name == adapterName }) {
                self.lock.lock()
                let lastLogged = lastLoggedSelectedAdapter
                self.lock.unlock()
                
                if lastLogged?.name != exact.name || lastLogged?.address != exact.address {
                    print("[websocket] Selected adapter match: \(exact.name) -> \(exact.address)")
                    self.lock.lock()
                    lastLoggedSelectedAdapter = (exact.name, exact.address)
                    self.lock.unlock()
                }
                return exact.address
            }
        }

        // Auto mode
        if adapterName == nil {
            let allAddresses = adapters.map { $0.address }
            if !allAddresses.isEmpty {
                let joined = allAddresses.joined(separator: ",")
                
                self.lock.lock()
                let lastLogged = lastLoggedSelectedAdapter
                self.lock.unlock()
                
                if lastLogged?.address != joined {
                    print("[websocket] Auto-mode addresses: \(joined)")
                    self.lock.lock()
                    lastLoggedSelectedAdapter = ("auto", joined)
                    self.lock.unlock()
                }
                return joined
            }
        }

        return nil
    }

    func getAvailableNetworkAdapters() -> [(name: String, address: String)] {
        var adapters: [(String, String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil

        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
                let interface = ptr.pointee
                let addrFamily = interface.ifa_addr.pointee.sa_family

                if addrFamily == UInt8(AF_INET),
                   let name = String(validatingUTF8: interface.ifa_name) {
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let result = getnameinfo(&addr,
                                             socklen_t(interface.ifa_addr.pointee.sa_len),
                                             &hostname,
                                             socklen_t(hostname.count),
                                             nil,
                                             socklen_t(0),
                                             NI_NUMERICHOST)
                    if result == 0 {
                        let address = String(cString: hostname)
                        if address != "127.0.0.1" {
                            adapters.append((name, address))
                        }
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return adapters
    }

    func ipIsPrivatePreferred(_ ip: String) -> Bool {
        if ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("10.") { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count > 1, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }

    // MARK: - Network Monitoring

    func startNetworkMonitoring() {
        DispatchQueue.main.async {
            self.lock.lock()
            self.networkMonitorTimer?.invalidate()
            let interval = self.networkCheckInterval
            self.lock.unlock()
            
            self.networkMonitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.checkNetworkChange()
            }
            self.networkMonitorTimer?.tolerance = 1.0
        }
    }

    func stopNetworkMonitoring() {
        DispatchQueue.main.async {
            self.lock.lock()
            self.networkMonitorTimer?.invalidate()
            self.networkMonitorTimer = nil
            self.lastKnownAdapters = []
            self.lock.unlock()
        }
    }

    /// Monitors network adapter state changes.
    /// Triggers a WebSocket server restart if the active IP address changes to maintain connectivity.
    func checkNetworkChange() {
        let adapters = getAvailableNetworkAdapters()
        let chosenIP = getLocalIPAddress(adapterName: AppState.shared.selectedNetworkAdapterName)

        self.lock.lock()
        let lastAddresses = lastKnownAdapters.map { $0.address }
        let currentAddresses = adapters.map { $0.address }
        let lastIP = lastKnownIP
        self.lock.unlock()

        if currentAddresses != lastAddresses {
            self.lock.lock()
            lastKnownAdapters = adapters
            self.lock.unlock()

            AppState.shared.revalidateNetworkAdapter()

            for adapter in adapters {
                let activeMark = (adapter.address == chosenIP) ? " [ACTIVE]" : ""
                print("[websocket] (network) \(adapter.name) -> \(adapter.address)\(activeMark)")
            }

            if let lastIP = lastIP, lastIP != chosenIP {
                print("[websocket] (network) IP changed from \(lastIP) to \(chosenIP ?? "N/A"), restarting WebSocket in 5 seconds")
                
                DispatchQueue.main.async {
                    self.lock.lock()
                    self.lastKnownIP = chosenIP
                    self.lock.unlock()
                    AppState.shared.shouldRefreshQR = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.stop()
                    self.start(port: Defaults.serverPort)
                }
            } else if lastIP == nil {
                DispatchQueue.main.async {
                    self.lock.lock()
                    self.lastKnownIP = chosenIP
                    self.lock.unlock()
                }
            }
        }
    }

    // MARK: - Utils

    func mimeType(for url: URL) -> String? {
        let ext = url.pathExtension
        if ext.isEmpty { return nil }

        if #available(macOS 11.0, *) {
            if let ut = UTType(filenameExtension: ext) {
                return ut.preferredMIMEType
            }
        } else {
#if canImport(MobileCoreServices)
            if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)?.takeRetainedValue() {
                if let mime = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() as String? {
                    return mime
                }
            }
#endif
        }
        return nil
    }
}
