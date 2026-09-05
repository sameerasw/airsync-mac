//
//  WebDAVManager.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2026-05-21.
//

import Foundation
import Cocoa
import Combine

class WebDAVManager {
    static let shared = WebDAVManager()
    
    private let mountPoint = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/com.airsync.mac/AndroidVolume")
    
    private(set) var isMounted = false
    
    private init() {}
    
    func mount(ipAddress: String, port: Int = 9081, volumeName: String = "Android") {
        guard !isMounted else { return }
        
        let urlString = "http://\(ipAddress):\(port)/"
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Force unmount and clean directory
            self.unmountSilently()
            
            do {
                if FileManager.default.fileExists(atPath: self.mountPoint.path) {
                    try? FileManager.default.removeItem(at: self.mountPoint)
                }
                try FileManager.default.createDirectory(at: self.mountPoint, withIntermediateDirectories: true)
                
                // 2. Mount the WebDAV server
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/mount_webdav")
                
                // WebDAV URLs should have a trailing slash for the root
                let finalUrl = urlString.hasSuffix("/") ? urlString : "\(urlString)/"
                
                print("[webdav] Attempting to mount \(finalUrl) to \(self.mountPoint.path)")
                
                // Revert to simple command that works
                process.arguments = [finalUrl, self.mountPoint.path]
                
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    self.isMounted = true
                    print("[webdav] Successfully mounted Android volume")
                    DispatchQueue.main.async {
                        AppState.shared.objectWillChange.send()
                    }
                } else {
                    print("[webdav] Failed to mount WebDAV volume. Status: \(process.terminationStatus)")
                }
            } catch {
                print("[webdav] Error in mount process: \(error)")
            }
        }
    }
    
    func unmount() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.unmountSilently()
            self.isMounted = false
            DispatchQueue.main.async {
                AppState.shared.objectWillChange.send()
            }
        }
    }
    
    private func unmountSilently() {
        // Try diskutil first
        let diskutil = Process()
        diskutil.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        diskutil.arguments = ["unmount", "force", self.mountPoint.path]
        try? diskutil.run()
        diskutil.waitUntilExit()
        
        // Fallback to umount if directory still exists or diskutil failed
        let umount = Process()
        umount.executableURL = URL(fileURLWithPath: "/sbin/umount")
        umount.arguments = ["-f", self.mountPoint.path]
        try? umount.run()
        umount.waitUntilExit()
    }
    
    func openInFinder() {
        if FileManager.default.fileExists(atPath: mountPoint.path) {
            NSWorkspace.shared.open(mountPoint)
        }
    }
}
