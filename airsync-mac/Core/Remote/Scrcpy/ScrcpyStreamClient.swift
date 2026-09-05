//
//  ScrcpyStreamClient.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-04-01.
//

import Foundation
import Network
import Combine

class ScrcpyStreamClient: ObservableObject {
    static let shared = ScrcpyStreamClient()
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.sameerasw.airsync.scrcpy.stream", qos: .userInteractive)
    
    @Published var isConnected = false
    @Published var videoWidth: UInt32 = 0
    @Published var videoHeight: UInt32 = 0
    @Published var deviceName: String = "Device"
    
    private var retryCount = 0
    private let maxRetries = 5
    
    var onPacketReceived: ((Data, Bool, Bool, UInt64) -> Void)?
    
    func connect(host: String = "127.0.0.1", port: UInt16 = 1234) {
        // Reset retry count if it's a fresh manual connection
        if retryCount == 0 {
            print("[ScrcpyStreamClient] Connecting to \(host):\(port)...")
        }
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port))
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[ScrcpyStreamClient] Connected to server (Retry: \(self?.retryCount ?? 0))")
                DispatchQueue.main.async {
                    self?.isConnected = true
                    self?.retryCount = 0 // Reset on success
                }
                self?.readMetadata()
            case .failed(let error):
                print("[ScrcpyStreamClient] Connection failed: \(error)")
                self?.handleConnectionFailure()
            case .cancelled:
                print("[ScrcpyStreamClient] Connection cancelled")
                DispatchQueue.main.async {
                    self?.isConnected = false
                }
            default:
                break
            }
        }
        
        self.connection = connection
        connection.start(queue: queue)
    }
    
    private func handleConnectionFailure() {
        guard retryCount < maxRetries else {
            print("[ScrcpyStreamClient] Max retries reached. Giving up.")
            DispatchQueue.main.async {
                self.isConnected = false
                self.retryCount = 0
            }
            return
        }
        
        retryCount += 1
        let delay = Double(retryCount) * 0.5
        print("[ScrcpyStreamClient] Retrying connection in \(delay)s... (Attempt \(retryCount)/\(maxRetries))")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }
    
    func disconnect() {
        retryCount = 0
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
    
    private func readMetadata() {
        // Read 1-byte dummy character first
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1, completion: { [weak self] data, context, isComplete, error in
            if let error = error {
                print("[ScrcpyStreamClient] Dummy read failed: \(error) (isComplete: \(isComplete))")
                self?.handleConnectionFailure()
                return
            }
            
            // Read 64-byte device name header
            self?.connection?.receive(minimumIncompleteLength: 64, maximumLength: 64) { [weak self] data, context, isComplete, error in
                guard let data = data, data.count == 64, error == nil else {
                    print("[ScrcpyStreamClient] Failed to read device name. Error: \(String(describing: error)), isComplete: \(isComplete)")
                    return
                }
                
                let deviceName = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? "Unknown"
                print("[ScrcpyStreamClient] Device Name: \(deviceName)")
                
                DispatchQueue.main.async {
                    self?.deviceName = deviceName
                }
                
                // Read 4-byte metadata: [4: Codec]
                self?.connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, context, isComplete, error in
                    guard let data = data, data.count == 4, error == nil else {
                        print("[ScrcpyStreamClient] Failed to read codec")
                        return
                    }
                    
                    let codec = data.withUnsafeBytes { $0.load(as: UInt32.self).byteSwapped }
                    print("[ScrcpyStreamClient] Codec: 0x\(String(format: "%08X", codec))")
                    
                    self?.readFrameHeader()
                }
            }
        })
    }
    
    private func readFrameHeader() {
        // Read 12-byte packet header
        connection?.receive(minimumIncompleteLength: 12, maximumLength: 12) { [weak self] data, context, isComplete, error in
            guard let data = data, data.count == 12, error == nil else {
                if let error = error {
                    print("[ScrcpyStreamClient] Frame header read error: \(error)")
                }
                return
            }
            
            // Check if MSB of the first byte is set to 1 (Session Packet)
            if (data[0] & 0x80) != 0 {
                // Session Packet: [4: Flags (MSB=1)][4: Width][4: Height]
                let flags = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).byteSwapped }
                let width = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).byteSwapped }
                let height = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).byteSwapped }
                
                print("[ScrcpyStreamClient] Session Packet: Flags: 0x\(String(format: "%08X", flags)), Resolution: \(width)x\(height)")
                
                DispatchQueue.main.async {
                    self?.videoWidth = width
                    self?.videoHeight = height
                }
                
                // Immediately read the next packet header (no packet payload follows a session packet)
                self?.readFrameHeader()
            } else {
                // Media Packet: [8: PTS][4: Size]
                // Note: The two most significant bits of PTS contain flags:
                // Bit 62 is SC_PACKET_FLAG_CONFIG, Bit 61 is SC_PACKET_FLAG_KEY_FRAME.
                // The actual PTS is stored in the remaining 62 bits.
                let ptsWithFlags = data.subdata(in: 0..<8).withUnsafeBytes { $0.load(as: UInt64.self).byteSwapped }
                let isConfig = (ptsWithFlags & (1 << 62)) != 0
                let isKeyframe = (ptsWithFlags & (1 << 61)) != 0
                let pts = ptsWithFlags & 0x1FFFFFFFFFFFFFFF
                
                let packetSize = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).byteSwapped }
                
                self?.readPacket(size: Int(packetSize), isConfig: isConfig, isKeyframe: isKeyframe, pts: pts)
            }
        }
    }
    
    private func readPacket(size: Int, isConfig: Bool, isKeyframe: Bool, pts: UInt64) {
        connection?.receive(minimumIncompleteLength: size, maximumLength: size) { [weak self] data, context, isComplete, error in
            guard let data = data, data.count == size, error == nil else {
                print("[ScrcpyStreamClient] Failed to read packet payload of size \(size)")
                return
            }
            
            self?.onPacketReceived?(data, isConfig, isKeyframe, pts)
            
            // Loop for next frame
            self?.readFrameHeader()
        }
    }
}
