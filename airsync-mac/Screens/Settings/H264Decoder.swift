import Foundation
import AVFoundation
import VideoToolbox
import AppKit
import CoreMedia

final class H264Decoder: NSObject {
    static let shared = H264Decoder()

    var onDecodedImage: ((CVImageBuffer, CMTime) -> Void)?
    var onDecodedFrame: ((NSImage) -> Void)?

    private let decodeQueue = DispatchQueue(label: "h264.decode.queue", qos: .userInteractive)
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?
    
    // Performance tracking
    private var frameCount: Int = 0
    private var lastLogTime = Date()

    private var useFFmpegFallback = false
    
    override init() {
        super.init()
        print("[H264Decoder] ⚡ Attempting native VideoToolbox hardware decoder")
    }

    // MARK: - Public API

    func feedAnnexB(_ data: Data, pts: CMTime? = nil) {
        if useFFmpegFallback {
            decodeQueue.async {
                FFmpegDecoder.shared.decode(frameData: data)
            }
            return
        }
        
        decodeQueue.async { [weak self] in
            self?.processAnnexBData(data, pts: pts ?? .zero)
        }
    }

    func feed(nalUnits: [Data], pts: CMTime) {
        decodeQueue.async { [weak self] in
            var annexB = Data()
            for nal in nalUnits {
                annexB.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                annexB.append(nal)
            }
            self?.processAnnexBData(annexB, pts: pts)
        }
    }

    func decode(frameData: Data, isConfig: Bool) {
        if useFFmpegFallback {
            decodeQueue.async {
                FFmpegDecoder.shared.decode(frameData: frameData)
            }
            return
        }
        feedAnnexB(frameData)
    }

    func setParameterSets(sps: Data, pps: Data) {
        decodeQueue.async { [weak self] in
            self?.createFormatDescription(sps: sps, pps: pps)
        }
    }

    func flush() {
        decodeQueue.async { [weak self] in
            if let session = self?.decompressionSession {
                VTDecompressionSessionWaitForAsynchronousFrames(session)
            }
            print("[H264Decoder] ✅ Flushed decoder")
        }
    }

    func reset() {
        decodeQueue.async { [weak self] in
            self?.destroySession()
            self?.formatDescription = nil
            self?.frameCount = 0
            print("[H264Decoder] 🔄 Reset decoder")
        }
    }

    // MARK: - Private Methods

    private func processAnnexBData(_ data: Data, pts: CMTime) {
        // Parse NAL units from Annex B format
        let nalUnits = parseAnnexB(data)
        
        for nal in nalUnits {
            guard nal.count > 0 else { continue }
            
            let nalType = nal[0] & 0x1F
            
            // SPS (7) or PPS (8) - create format description
            if nalType == 7 || nalType == 8 {
                handleParameterSet(nal, nalType: nalType)
            }
            // IDR (5) or non-IDR (1) - decode frame
            else if nalType == 5 || nalType == 1 {
                decodeFrame(nal, pts: pts)
            }
        }
    }

    private func parseAnnexB(_ data: Data) -> [Data] {
        var nalUnits: [Data] = []
        var currentStart = 0
        
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let ptr = bytes.bindMemory(to: UInt8.self)
            var i = 0
            
            while i < ptr.count - 3 {
                // Look for start code: 0x00 0x00 0x00 0x01 or 0x00 0x00 0x01
                if ptr[i] == 0 && ptr[i+1] == 0 {
                    let startCodeLength: Int
                    if ptr[i+2] == 0 && ptr[i+3] == 1 {
                        startCodeLength = 4
                    } else if ptr[i+2] == 1 {
                        startCodeLength = 3
                    } else {
                        i += 1
                        continue
                    }
                    
                    // Found start code
                    if currentStart > 0 {
                        // Extract previous NAL unit
                        let nalData = data.subdata(in: currentStart..<i)
                        nalUnits.append(nalData)
                    }
                    
                    currentStart = i + startCodeLength
                    i += startCodeLength
                } else {
                    i += 1
                }
            }
            
            // Add last NAL unit
            if currentStart < ptr.count {
                let nalData = data.subdata(in: currentStart..<ptr.count)
                nalUnits.append(nalData)
            }
        }
        
        return nalUnits
    }

    private var spsData: Data?
    private var ppsData: Data?

    private func handleParameterSet(_ nal: Data, nalType: UInt8) {
        if nalType == 7 {
            spsData = nal
        } else if nalType == 8 {
            ppsData = nal
        }
        
        // Create format description when we have both SPS and PPS
        if let sps = spsData, let pps = ppsData, formatDescription == nil {
            createFormatDescription(sps: sps, pps: pps)
        }
    }

    private func createFormatDescription(sps: Data, pps: Data) {
        print("[H264Decoder] 🔧 Creating format description with SPS(\(sps.count) bytes) PPS(\(pps.count) bytes)")
        
        guard sps.count > 0 && pps.count > 0 else {
            print("[H264Decoder] ❌ Invalid parameter sets: SPS or PPS is empty")
            return
        }
        
        // Check profile from SPS
        if sps.count > 1 {
            let profile = sps[1]
            let profileName: String
            switch profile {
            case 0x42: profileName = "Baseline"
            case 0x4D: profileName = "Main"
            case 0x64: profileName = "High"
            default: profileName = "Unknown(0x\(String(format: "%02X", profile)))"
            }
            print("[H264Decoder] 📊 Detected profile: \(profileName)")
            
            // VideoToolbox on Apple Silicon prefers Main/High profile
            // Baseline profile (0x42) often causes kVTParameterErr (-12712)
            if profile == 0x42 {
                print("[H264Decoder] ⚠️ Baseline profile detected - VideoToolbox may reject this")
                print("[H264Decoder] 💡 Android encoder should use Main (0x4D) or High (0x64) profile")
            }
        }
        
        let parameterSets = [sps, pps]
        var parameterSetPointers: [UnsafePointer<UInt8>] = []
        var parameterSetSizes: [Int] = []
        
        // Hold references to the data
        parameterSets.forEach { data in
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                if let baseAddress = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                    parameterSetPointers.append(baseAddress)
                    parameterSetSizes.append(data.count)
                }
            }
        }
        
        var formatDesc: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: 2,
            parameterSetPointers: parameterSetPointers,
            parameterSetSizes: parameterSetSizes,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &formatDesc
        )
        
        if status == noErr, let formatDesc = formatDesc {
            self.formatDescription = formatDesc
            createDecompressionSession()
            print("[H264Decoder] ✅ Created format description")
        } else {
            let errorName: String
            switch status {
            case -12712: errorName = "kVTParameterErr (invalid parameters - likely Baseline profile)"
            case -12913: errorName = "kVTInvalidSessionErr"
            case -12210: errorName = "kVTFormatDescriptionChangeNotSupportedErr"
            default: errorName = "Unknown error"
            }
            print("[H264Decoder] ❌ Failed to create format description: \(status) (\(errorName))")
            print("[H264Decoder] 📊 SPS first bytes: \(sps.prefix(min(8, sps.count)).map { String(format: "%02X", $0) }.joined(separator: " "))")
            print("[H264Decoder] 📊 PPS first bytes: \(pps.prefix(min(8, pps.count)).map { String(format: "%02X", $0) }.joined(separator: " "))")
            
            // Fall back to FFmpeg if VideoToolbox fails
            if !useFFmpegFallback {
                print("[H264Decoder] 🔄 Falling back to FFmpeg software decoder")
                useFFmpegFallback = true
                FFmpegDecoder.shared.onDecodedFrame = self.onDecodedFrame
            }
        }
    }

    private func createDecompressionSession() {
        guard let formatDescription = formatDescription else { return }
        
        destroySession()
        
        let decoderParameters = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true
        ] as CFDictionary
        
        let decompressionProperties = [
            kVTDecompressionPropertyKey_RealTime: true,
            kVTDecompressionPropertyKey_ThreadCount: 2
        ] as CFDictionary
        
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: decoderParameters,
            outputCallback: nil,
            decompressionSessionOut: &session
        )
        
        if status == noErr, let session = session {
            VTSessionSetProperties(session, propertyDictionary: decompressionProperties)
            self.decompressionSession = session
            print("[H264Decoder] ⚡ Created hardware decompression session")
        } else {
            print("[H264Decoder] ❌ Failed to create decompression session: \(status)")
        }
    }

    private func decodeFrame(_ nal: Data, pts: CMTime) {
        guard let session = decompressionSession else {
            print("[H264Decoder] ⚠️ No decompression session")
            return
        }
        
        // Convert to AVCC format (length prefix instead of start code)
        var avccData = Data()
        var length = UInt32(nal.count).bigEndian
        avccData.append(Data(bytes: &length, count: 4))
        avccData.append(nal)
        
        // Create sample buffer
        var blockBuffer: CMBlockBuffer?
        let status1 = avccData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: avccData.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: avccData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }
        
        guard status1 == noErr, let blockBuffer = blockBuffer else {
            print("[H264Decoder] ❌ Failed to create block buffer")
            return
        }
        
        // Copy data to block buffer
        let copyStatus = avccData.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: avccData.count
            )
        }
        
        guard copyStatus == noErr else {
            print("[H264Decoder] ❌ Failed to copy data to block buffer")
            return
        }
        
        var sampleBuffer: CMSampleBuffer?
        let status2 = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        guard status2 == noErr, let sampleBuffer = sampleBuffer else {
            print("[H264Decoder] ❌ Failed to create sample buffer")
            return
        }
        
        // Decode frame
        var flagsOut = VTDecodeInfoFlags()
        let status3 = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: &flagsOut,
            outputHandler: { [weak self] status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration in
                guard status == noErr, let imageBuffer = imageBuffer else {
                    print("[H264Decoder] ❌ Decode failed: \(status)")
                    return
                }
                
                self?.handleDecodedFrame(imageBuffer, pts: presentationTimeStamp)
            }
        )
        
        if status3 != noErr {
            print("[H264Decoder] ❌ Failed to decode frame: \(status3)")
        }
        
        // Track performance
        frameCount += 1
        let now = Date()
        if now.timeIntervalSince(lastLogTime) >= 5.0 {
            let fps = Double(frameCount) / now.timeIntervalSince(lastLogTime)
            print("[H264Decoder] 📊 Decoding at \(String(format: "%.1f", fps)) FPS")
            frameCount = 0
            lastLogTime = now
        }
    }

    private func handleDecodedFrame(_ imageBuffer: CVImageBuffer, pts: CMTime) {
        // Call image buffer callback
        onDecodedImage?(imageBuffer, pts)
        
        // Convert to NSImage for frame callback
        if onDecodedFrame != nil {
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            let context = CIContext(options: [.useSoftwareRenderer: false])
            
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                
                DispatchQueue.main.async { [weak self] in
                    self?.onDecodedFrame?(nsImage)
                }
            }
        }
    }

    private func destroySession() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
    }

    deinit {
        destroySession()
    }
}
