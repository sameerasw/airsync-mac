import Foundation
import AVFoundation
import AppKit
import CoreMedia

/**
 * Unified frame decoder that handles both raw JPEG frames and H.264 streams
 * Automatically detects format and uses appropriate decoder
 * Raw JPEG is preferred for simplicity and lower latency
 */
final class UnifiedFrameDecoder: NSObject {
    static let shared = UnifiedFrameDecoder()
    
    var onDecodedFrame: ((NSImage) -> Void)?
    
    private let h264Decoder = H264Decoder.shared
    private let decodeQueue = DispatchQueue(label: "unified.decode.queue", qos: .userInteractive, attributes: .concurrent)
    
    // Frame throttling - adaptive based on decode performance
    private var lastFrameDisplayTime = Date.distantPast
    private var targetFrameInterval: TimeInterval = 1.0 / 60.0 // Target 60 FPS
    private let minFrameInterval: TimeInterval = 1.0 / 90.0 // Allow up to 90 FPS bursts for smoother scrolling
    
    // Double buffering for smoother display
    private var pendingFrame: NSImage?
    private let frameLock = NSLock()
    
    // Performance tracking
    private var frameCount: Int = 0
    private var droppedFrames: Int = 0
    private var lastLogTime = Date()
    private var totalBytes: Int64 = 0
    private var decodeTimeSum: TimeInterval = 0
    
    // Latency tracking
    private var lastFrameTimestamp: Int64 = 0
    private var latencySum: TimeInterval = 0
    private var latencyCount: Int = 0
    
    override init() {
        super.init()
        
        // Set up H.264 decoder callback
        h264Decoder.onDecodedFrame = { [weak self] nsImage in
            self?.deliverFrame(nsImage)
        }
        
        print("[UnifiedDecoder] ⚡ Initialized with JPEG (primary) and H.264 (fallback) support")
    }
    
    /// Decode frame data - automatically detects format
    func decode(frameData: Data, format: String? = nil, isConfig: Bool = false, timestamp: Int64 = 0) {
        decodeQueue.async { [weak self] in
            guard let self = self else { return }
            
            let decodeStart = Date()
            
            // Track latency if timestamp provided
            if timestamp > 0 {
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                let latency = Double(now - timestamp) / 1000.0
                self.latencySum += latency
                self.latencyCount += 1
            }
            
            // Track data
            self.totalBytes += Int64(frameData.count)
            
            // Determine format
            let detectedFormat = format?.lowercased() ?? self.detectFormat(frameData)
            
            switch detectedFormat {
            case "jpeg", "jpg":
                self.decodeJPEG(frameData)
                
            case "h264", "avc":
                self.h264Decoder.decode(frameData: frameData, isConfig: isConfig)
                
            default:
                // Try to auto-detect
                if self.isJPEG(frameData) {
                    self.decodeJPEG(frameData)
                } else {
                    // Assume H.264
                    self.h264Decoder.decode(frameData: frameData, isConfig: isConfig)
                }
            }
            
            // Track decode time for adaptive throttling
            self.decodeTimeSum += Date().timeIntervalSince(decodeStart)
            
            // Track performance
            self.frameCount += 1
            let now = Date()
            if now.timeIntervalSince(self.lastLogTime) >= 5.0 {
                let elapsed = now.timeIntervalSince(self.lastLogTime)
                let fps = Double(self.frameCount) / elapsed
                let kbps = (Double(self.totalBytes) * 8 / 1024) / elapsed
                let avgDecodeMs = (self.decodeTimeSum / Double(max(1, self.frameCount))) * 1000
                let avgLatencyMs = self.latencyCount > 0 ? (self.latencySum / Double(self.latencyCount)) * 1000 : 0
                
                if self.droppedFrames > 0 {
                    let dropRate = Double(self.droppedFrames) / Double(self.frameCount + self.droppedFrames) * 100
                    print("[UnifiedDecoder] 📊 Performance: \(String(format: "%.1f", fps)) FPS, \(String(format: "%.0f", kbps)) kbps, decode: \(String(format: "%.1f", avgDecodeMs))ms, latency: \(String(format: "%.0f", avgLatencyMs))ms, dropped: \(String(format: "%.1f", dropRate))%")
                } else {
                    print("[UnifiedDecoder] 📊 Performance: \(String(format: "%.1f", fps)) FPS, \(String(format: "%.0f", kbps)) kbps, decode: \(String(format: "%.1f", avgDecodeMs))ms, latency: \(String(format: "%.0f", avgLatencyMs))ms")
                }
                
                // Adaptive frame interval based on actual performance
                if fps > 55 {
                    self.targetFrameInterval = 1.0 / 60.0
                } else if fps > 25 {
                    self.targetFrameInterval = 1.0 / 30.0
                }
                
                self.frameCount = 0
                self.droppedFrames = 0
                self.totalBytes = 0
                self.decodeTimeSum = 0
                self.latencySum = 0
                self.latencyCount = 0
                self.lastLogTime = now
            }
        }
    }
    
    /// Decode JPEG frame - optimized for performance with smart throttling
    private func decodeJPEG(_ data: Data) {
        // Use CGImageSource for faster decoding with optimized options
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: false
        ]
        
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, options as CFDictionary) else {
            print("[UnifiedDecoder] ❌ Failed to decode JPEG frame")
            return
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        deliverFrame(nsImage)
    }
    
    /// Deliver frame with smart throttling
    private func deliverFrame(_ image: NSImage) {
        let now = Date()
        let timeSinceLastFrame = now.timeIntervalSince(lastFrameDisplayTime)
        
        // Smart throttling: allow frames through if enough time has passed
        // or if we haven't shown a frame recently (prevent stuck frames)
        if timeSinceLastFrame < minFrameInterval {
            // Too fast, drop this frame
            droppedFrames += 1
            
            // But store it as pending in case we need it
            frameLock.lock()
            pendingFrame = image
            frameLock.unlock()
            return
        }
        
        lastFrameDisplayTime = now
        
        // Deliver on main thread without blocking decode queue
        DispatchQueue.main.async { [weak self] in
            self?.onDecodedFrame?(image)
        }
    }
    
    /// Detect format from data
    private func detectFormat(_ data: Data) -> String {
        if isJPEG(data) {
            return "jpeg"
        } else if isH264(data) {
            return "h264"
        }
        return "unknown"
    }
    
    /// Check if data is JPEG
    private func isJPEG(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        return data[0] == 0xFF && data[1] == 0xD8 // JPEG magic bytes
    }
    
    /// Check if data is H.264 (Annex B format)
    private func isH264(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        // Check for Annex B start code: 00 00 00 01 or 00 00 01
        if data[0] == 0x00 && data[1] == 0x00 {
            if data[2] == 0x00 && data[3] == 0x01 {
                return true
            } else if data[2] == 0x01 {
                return true
            }
        }
        return false
    }
    
    /// Reset decoder state
    func reset() {
        decodeQueue.async { [weak self] in
            guard let self = self else { return }
            self.h264Decoder.reset()
            self.frameCount = 0
            self.droppedFrames = 0
            self.totalBytes = 0
            self.decodeTimeSum = 0
            self.lastLogTime = Date()
            self.lastFrameDisplayTime = Date.distantPast
            self.frameLock.lock()
            self.pendingFrame = nil
            self.frameLock.unlock()
            print("[UnifiedDecoder] 🔄 Reset decoder state")
        }
    }
    
    /// Flush pending frames
    func flush() {
        decodeQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Deliver any pending frame
            self.frameLock.lock()
            let pending = self.pendingFrame
            self.pendingFrame = nil
            self.frameLock.unlock()
            
            if let frame = pending {
                DispatchQueue.main.async { [weak self] in
                    self?.onDecodedFrame?(frame)
                }
            }
            
            self.h264Decoder.flush()
            print("[UnifiedDecoder] ✅ Flushed decoder")
        }
    }
}
