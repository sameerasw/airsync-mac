import Foundation

class BonjourServiceBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var resolvingServices = Set<NetService>()
    private var serviceNameToId: [String: String] = [:]
    
    var onDeviceDiscovered: ((DiscoveredDevice) -> Void)?
    var onDeviceLost: ((String) -> Void)?
    
    func start() {
        resolvingServices.removeAll()
        serviceNameToId.removeAll()
        browser.delegate = self
        browser.searchForServices(ofType: "_airsync._tcp", inDomain: "")
    }
    
    func stop() {
        browser.stop()
        for service in resolvingServices {
            service.stop()
        }
        resolvingServices.removeAll()
        serviceNameToId.removeAll()
    }
    
    // MARK: - NetServiceBrowserDelegate
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("[Bonjour] Found service: \(service.name)")
        service.delegate = self
        resolvingServices.insert(service)
        service.resolve(withTimeout: 10.0)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        print("[Bonjour] Lost service: \(service.name)")
        if let id = serviceNameToId[service.name] {
            onDeviceLost?(id)
            serviceNameToId.removeValue(forKey: service.name)
        }
        resolvingServices.remove(service)
    }
    
    // MARK: - NetServiceDelegate
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        print("[Bonjour] Resolved service: \(sender.name)")
        resolvingServices.remove(sender)
        
        let ips = parseIPAddresses(from: sender)
        guard !ips.isEmpty else { return }
        
        let txtDict: [String: Data]
        if let recordData = sender.txtRecordData() {
            txtDict = NetService.dictionary(fromTXTRecord: recordData)
        } else {
            txtDict = [:]
        }
        
        let id = txtDict["id"].flatMap { String(data: $0, encoding: .utf8) } ?? sender.name
        let name = txtDict["name"].flatMap { String(data: $0, encoding: .utf8) } ?? sender.name
        let port = txtDict["port"].flatMap { String(data: $0, encoding: .utf8) }.flatMap { Int($0) } ?? sender.port
        let deviceType = txtDict["type"].flatMap { String(data: $0, encoding: .utf8) } ?? ""
        
        guard deviceType == "android" else {
            print("[Bonjour] Service \(sender.name) is of type '\(deviceType)', ignoring.")
            return
        }
        
        serviceNameToId[sender.name] = id
        
        let device = DiscoveredDevice(
            deviceId: id,
            name: name,
            ips: ips,
            port: port,
            type: "android",
            lastSeen: Date(),
            discoverySource: .mdns
        )
        onDeviceDiscovered?(device)
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("[Bonjour] Failed to resolve service \(sender.name): \(errorDict)")
        resolvingServices.remove(sender)
    }
    
    private func parseIPAddresses(from service: NetService) -> Set<String> {
        var ips: Set<String> = []
        guard let addresses = service.addresses else { return ips }
        
        for addressData in addresses {
            addressData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                guard let addr = ptr.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return }
                
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addressData.count), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ipStr = String(cString: hostname)
                    if ipStr.contains(".") {
                        ips.insert(ipStr)
                    }
                }
            }
        }
        return ips
    }
}
