//
//  ScrcpyVideoDecoder.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-04-01.
//

import Foundation
import VideoToolbox
import CoreMedia

class ScrcpyVideoDecoder: NSObject {
    static let shared = ScrcpyVideoDecoder()
    
    private var formatDescription: CMVideoFormatDescription?
    private var decompressionSession: VTDecompressionSession?
    
    // Callback for decoded frames
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?
    
    func decodePacket(data: Data, isConfig: Bool, pts: UInt64) {
        // Detect VPS (32), SPS (33), or PPS (34) in H.265 Annex-B
        // Start codes are 00 00 00 01
        if data.count > 4 {
            let naluType = (data[4] & 0x7E) >> 1
            if naluType == 32 || naluType == 33 || naluType == 34 {
                setupDecoder(with: data)
                return
            }
        }
        
        if isConfig {
            setupDecoder(with: data)
            return
        }
        
        guard let session = decompressionSession else { return }
        
        // Android is Annex-B (00 00 00 01), VideoToolbox is AVCC (length-prefixed)
        let avccData = annexBToAVCC(data)
        
        var blockBuffer: CMBlockBuffer?
        let status = avccData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSStatus in
            return CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: UnsafeMutableRawPointer(mutating: bytes.baseAddress),
                blockLength: avccData.count,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: avccData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }
        
        guard status == noErr, let buffer = blockBuffer else { return }
        
        var sampleBuffer: CMSampleBuffer?
        let sampleSize = [avccData.count]
        
        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        
        guard let sample = sampleBuffer else { return }
        
        var flagsOut: VTDecodeInfoFlags = []
        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil,
            infoFlagsOut: &flagsOut
        )
    }
    
    private func setupDecoder(with configData: Data) {
        // H.265 Configuration Data contains VPS, SPS, PPS
        // We need to parse these to create the format description
        // In Annex-B, they are separated by 00 00 00 01
        
        let naluStart = Data([0x00, 0x00, 0x00, 0x01])
        var nalus: [Data] = []
        
        var currentIdx = 0
        while currentIdx < configData.count {
            // Find next start code
            if let range = configData.range(of: naluStart, options: [], in: currentIdx..<configData.count) {
                let segmentEnd = range.lowerBound
                if segmentEnd > currentIdx {
                    nalus.append(configData.subdata(in: currentIdx..<segmentEnd))
                }
                currentIdx = range.upperBound
            } else {
                nalus.append(configData.subdata(in: currentIdx..<configData.count))
                break
            }
        }
        
        let validNalus = nalus.filter { !$0.isEmpty }
        
        // We must ensure the pointers stay valid during the call
        var parameterSetPointers: [UnsafePointer<UInt8>] = []
        var parameterSetSizes: [Int] = []
        
        let parameterSets = validNalus.map { [UInt8]($0) }
        for i in 0..<parameterSets.count {
            parameterSets[i].withUnsafeBufferPointer { buffer in
                if let baseAddress = buffer.baseAddress {
                    parameterSetPointers.append(baseAddress)
                    parameterSetSizes.append(buffer.count)
                }
            }
        }
        
        
        let status = validNalus.withUnsafeParameterSets { pointers, sizes, count in
            return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: count,
                parameterSetPointers: pointers,
                parameterSetSizes: sizes,
                nalUnitHeaderLength: 4,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            )
        }
        
        guard status == noErr, let desc = formatDescription else {
            print("[ScrcpyVideoDecoder] Failed to create format description: \(status)")
            return
        }
        
        createSession(with: desc)
    }
    
    private func createSession(with desc: CMVideoFormatDescription) {
        let destinationImageBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { (decompressionOutputRefCon, sourceFrameRefCon, status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration) in
                guard status == noErr, let buffer = imageBuffer else { return }
                let decoder = Unmanaged<ScrcpyVideoDecoder>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()
                decoder.onDecodedFrame?(buffer)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: desc,
            decoderSpecification: nil,
            imageBufferAttributes: destinationImageBufferAttributes as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &decompressionSession
        )
        
        if status != noErr {
            print("[ScrcpyVideoDecoder] Failed to create decompression session: \(status)")
        } else {
            print("[ScrcpyVideoDecoder] Decompression session created")
        }
    }
    
    private func annexBToAVCC(_ data: Data) -> Data {
        
        var result = Data()
        var i = 0
        while i < data.count {
            if i + 4 <= data.count && data[i] == 0 && data[i+1] == 0 && data[i+2] == 0 && data[i+3] == 1 {
                let start = i + 4
                var end = data.count
                
                // Search for next start code
                if let nextRange = data.range(of: Data([0x00, 0x00, 0x00, 0x01]), options: [], in: start..<data.count) {
                    end = nextRange.lowerBound
                }
                
                let length = UInt32(end - start).bigEndian
                withUnsafeBytes(of: length) { result.append(contentsOf: $0) }
                result.append(data.subdata(in: start..<end))
                i = end
            } else if i + 3 <= data.count && data[i] == 0 && data[i+1] == 0 && data[i+2] == 1 {
                // 3-byte start code
                let start = i + 3
                var end = data.count
                if let nextRange = data.range(of: Data([0x00, 0x00, 0x00, 0x01]), options: [], in: start..<data.count) {
                    end = nextRange.lowerBound
                }
                let length = UInt32(end - start).bigEndian
                withUnsafeBytes(of: length) { result.append(contentsOf: $0) }
                result.append(data.subdata(in: start..<end))
                i = end
            } else {
                if result.isEmpty {
                   let length = UInt32(data.count).bigEndian
                   withUnsafeBytes(of: length) { result.append(contentsOf: $0) }
                   result.append(data)
                   break
                }
                i += 1
            }
        }
        return result
    }
}

extension Array where Element == Data {
    func withUnsafeParameterSets<T>(_ body: (UnsafePointer<UnsafePointer<UInt8>>, UnsafePointer<Int>, Int) -> T) -> T {
        let parameterSets = self.map { [UInt8]($0) }
        var pointers = [UnsafePointer<UInt8>]()
        var sizes = [Int]()
        
        return recursivelyGetPointers(index: 0, currentPointers: &pointers, currentSizes: &sizes, parameterSets: parameterSets, body: body)
    }
    
    private func recursivelyGetPointers<T>(index: Int, currentPointers: inout [UnsafePointer<UInt8>], currentSizes: inout [Int], parameterSets: [[UInt8]], body: (UnsafePointer<UnsafePointer<UInt8>>, UnsafePointer<Int>, Int) -> T) -> T {
        if index == parameterSets.count {
            return body(currentPointers, currentSizes, parameterSets.count)
        }
        
        return parameterSets[index].withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                currentPointers.append(baseAddress)
                currentSizes.append(buffer.count)
            }
            let result = recursivelyGetPointers(index: index + 1, currentPointers: &currentPointers, currentSizes: &currentSizes, parameterSets: parameterSets, body: body)
            if !currentPointers.isEmpty { currentPointers.removeLast() }
            if !currentSizes.isEmpty { currentSizes.removeLast() }
            return result
        }
    }
}
