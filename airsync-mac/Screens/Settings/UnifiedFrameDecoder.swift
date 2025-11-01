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
    private let decodeQueue = DispatchQueue(label: "unified.decode.queue", qos: .userInteractive)
    
    // Frame throttling to prevent overwhelming the UI
    private var lastFrameDisplayTime = Date.distantPast
    private let minFrameInterval: TimeInterval = 1.0 / 60.0 // Max 60 FPS on display (smooth)
    
    // Performance tracking
    private var frameCount: Int = 0
    private var droppedFrames: Int = 0
    private var lastLogTime = Date()
    private var totalBytes: Int64 = 0
    
    override init() {
        super.init()
        
        // Set up H.264 decoder callback
        h264Decoder.onDecodedFrame = { [weak self] nsImage in
            self?.onDecodedFrame?(nsImage)
        }
        
        print("[UnifiedDecoder] ⚡ Initialized with JPEG (primary) and H.264 (fallback) support")
    }
    
    /// Decode frame data - automatically detects format
    func decode(frameData: Data, format: String? = nil, isConfig: Bool = false) {
        decodeQueue.async { [weak self] in
            guard let self = self else { return }
            
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
            
            // Track performance
            self.frameCount += 1
            let now = Date()
            if now.timeIntervalSince(self.lastLogTime) >= 5.0 {
                let elapsed = now.timeIntervalSince(self.lastLogTime)
                let fps = Double(self.frameCount) / elapsed
                let kbps = (Double(self.totalBytes) * 8 / 1024) / elapsed
                let avgSizeKB = Double(self.totalBytes) / Double(self.frameCount) / 1024
                if self.droppedFrames > 0 {
                    let dropRate = Double(self.droppedFrames) / Double(self.frameCount + self.droppedFrames) * 100
                    print("[UnifiedDecoder] 📊 Performance: \(String(format: "%.1f", fps)) FPS, \(String(format: "%.0f", kbps)) kbps, avg: \(String(format: "%.0f", avgSizeKB))KB, dropped: \(String(format: "%.1f", dropRate))%")
                } else {
                    print("[UnifiedDecoder] 📊 Performance: \(String(format: "%.1f", fps)) FPS, \(String(format: "%.0f", kbps)) kbps, avg: \(String(format: "%.0f", avgSizeKB))KB")
                }
                self.frameCount = 0
                self.droppedFrames = 0
                self.totalBytes = 0
                self.lastLogTime = now
            }
        }
    }
    
    /// Decode JPEG frame - optimized for performance with smart throttling
    private func decodeJPEG(_ data: Data) {
        // Use CGImageSource for faster decoding
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            print("[UnifiedDecoder] ❌ Failed to decode JPEG frame")
            return
        }
        
        // Check if we should throttle (but always decode to avoid stuck frames)
        let now = Date()
        let timeSinceLastFrame = now.timeIntervalSince(lastFrameDisplayTime)
        
        if timeSinceLastFrame < minFrameInterval {
            droppedFrames += 1
            // Still update occasionally to prevent stuck frames
            if droppedFrames % 3 != 0 {
                return
            }
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        lastFrameDisplayTime = now
        
        // Update UI on main thread without blocking
        DispatchQueue.main.async { [weak self] in
            self?.onDecodedFrame?(nsImage)
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
            self?.h264Decoder.reset()
            self?.frameCount = 0
            self?.totalBytes = 0
            self?.lastLogTime = Date()
            print("[UnifiedDecoder] 🔄 Reset decoder state")
        }
    }
    
    /// Flush pending frames
    func flush() {
        decodeQueue.async { [weak self] in
            self?.h264Decoder.flush()
            print("[UnifiedDecoder] ✅ Flushed decoder")
        }
    }
}
