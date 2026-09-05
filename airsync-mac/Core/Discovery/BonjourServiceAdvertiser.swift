import Foundation
import Network

class BonjourServiceAdvertiser: NSObject, NetServiceDelegate {
    private var netService: NetService?
    private var pathMonitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.airsync.bonjour.advertiser")
    private var isAdvertising = false
    
    func start() {
        guard !isAdvertising else { return }
        isAdvertising = true
        
        setupPathMonitor()
        publishService()
    }
    
    func stop() {
        guard isAdvertising else { return }
        isAdvertising = false
        
        pathMonitor?.cancel()
        pathMonitor = nil
        netService?.stop()
        netService = nil
    }
    
    private func setupPathMonitor() {
        pathMonitor?.cancel()
        
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self, self.isAdvertising else { return }
            if path.status == .satisfied {
                print("[Bonjour] Network interface changed, re-publishing service")
                self.publishService()
            }
        }
        self.pathMonitor = monitor
        monitor.start(queue: queue)
    }
    
    private func publishService() {
        netService?.stop()
        
        let info = AppState.shared.myDevice
        let port = Int32(info?.port ?? Int(Defaults.serverPort))
        let name = info?.name ?? Host.current().localizedName ?? "Mac"
        let uuid = getStableUUID()
        
        let serviceName = "AirSync-\(name)"
        
        let service = NetService(domain: "", type: "_airsync._tcp", name: serviceName, port: port)
        service.delegate = self
        
        let txtDict = [
            "id": uuid,
            "name": name,
            "port": String(port),
            "ver": "1",
            "type": "mac"
        ]
        
        let txtRecordData = NetService.data(fromTXTRecord: txtDict.mapValues { $0.data(using: .utf8)! })
        service.setTXTRecord(txtRecordData)
        
        self.netService = service
        service.publish()
        print("[Bonjour] Publishing service: \(serviceName) on port \(port)")
    }
    
    // MARK: - NetServiceDelegate
    
    func netServiceDidPublish(_ sender: NetService) {
        print("[Bonjour] Successfully published service: sender name = \(sender.name)")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("[Bonjour] Failed to publish service: \(errorDict)")
    }
    
    private func getStableUUID() -> String {
        let defaults = UserDefaults.standard
        if let uuid = defaults.string(forKey: "device_stable_uuid") {
            return uuid
        }
        let uuid = UUID().uuidString
        defaults.set(uuid, forKey: "device_stable_uuid")
        return uuid
    }
}
