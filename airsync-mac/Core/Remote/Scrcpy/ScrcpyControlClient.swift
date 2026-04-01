//
//  ScrcpyControlClient.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-04-01.
//

import Foundation
import Network

class ScrcpyControlClient {
    static let shared = ScrcpyControlClient()
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.sameerasw.airsync.scrcpy.control")
    
    func connect(host: String = "127.0.0.1", port: UInt16 = 1234) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port))
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[ScrcpyControlClient] Control channel ready")
            case .failed(let error):
                print("[ScrcpyControlClient] Control channel failed: \(error)")
            default:
                break
            }
        }
        
        self.connection = connection
        connection.start(queue: queue)
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
    }
    
    func sendTouchEvent(action: UInt8, x: UInt32, y: UInt32, width: UInt16, height: UInt16) {
        var data = Data()
        data.append(2) // Type 2: Inject touch event
        data.append(action) // 0: down, 1: up, 2: move
        
        // Pointer ID (8 bytes) - typically 0xFFFFFFFFFFFFFFFF for single touch/mouse
        let pointerId: UInt64 = 0xFFFFFFFFFFFFFFFF
        withUnsafeBytes(of: pointerId.bigEndian) { data.append(contentsOf: $0) }
        
        // X, Y (4 bytes each)
        withUnsafeBytes(of: x.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: y.bigEndian) { data.append(contentsOf: $0) }
        
        // Width, Height (2 bytes each)
        withUnsafeBytes(of: width.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: height.bigEndian) { data.append(contentsOf: $0) }
        
        // Pressure (2 bytes) - 0 to 65535
        let pressure: UInt16 = action == 1 ? 0 : 32767
        withUnsafeBytes(of: pressure.bigEndian) { data.append(contentsOf: $0) }
        
        // Action Button (4 bytes)
        let actionButton: UInt32 = 0
        withUnsafeBytes(of: actionButton.bigEndian) { data.append(contentsOf: $0) }
        
        // Buttons (4 bytes)
        let buttons: UInt32 = action == 1 ? 0 : 1 // 1 for primary button
        withUnsafeBytes(of: buttons.bigEndian) { data.append(contentsOf: $0) }
        
        send(data: data)
    }
    
    private func send(data: Data) {
        connection?.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("[ScrcpyControlClient] Send error: \(error)")
            }
        }))
    }
}
