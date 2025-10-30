import Foundation
import AppKit
import CoreMedia

/**
 A software H.264 decoder using FFmpeg (libavcodec).
 
 This class is designed to replace the native VideoToolbox decoder (`H264Decoder`)
 to handle non-standard H.264 streams (e.g., from certain Android encoders)
 that VideoToolbox might reject.
 
 ⚠️ **Setup Requirements:**
 1.  Install FFmpeg: `brew install ffmpeg`
 2.  Add a Bridging Header to your Xcode project and add the `#include` statements
     from the `airsync-mac-Bridging-Header.h` file.
 3.  Set the "Objective-C Bridging Header" build setting to point to that header file.
 4.  Link the FFmpeg libraries:
     - Find the `.dylib` files (e.g., in `/opt/homebrew/lib/`).
     - Add `libavcodec.dylib`, `libavutil.dylib`, and `libswscale.dylib` to
       "Frameworks, Libraries, and Embedded Content" in your target's settings.
     - Set them to "Embed & Sign".
 5.  You may need to add the Homebrew library path (e.g., `/opt/homebrew/lib`) to
     "Library Search Paths" in your build settings.
 */
final class FFmpegDecoder {
    
    // Singleton instance for easy access
    static let shared = FFmpegDecoder()

    // FFmpeg C pointers
    private var codec: UnsafePointer<AVCodec>?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var parserContext: UnsafeMutablePointer<AVCodecParserContext>?
    private var packet: UnsafeMutablePointer<AVPacket>?
    private var yuvFrame: UnsafeMutablePointer<AVFrame>?
    
    // For converting the YUV frame to RGB for NSImage
    private var swsContext: UnsafeMutablePointer<SwsContext>?
    private var rgbFrame: UnsafeMutablePointer<AVFrame>?
    private var rgbFrameBuffer: UnsafeMutablePointer<UInt8>?

    private let decodeQueue = DispatchQueue(label: "ffmpeg.decode.queue")
    
    /// Callback that fires on the main thread with a successfully decoded image.
    var onDecodedFrame: ((NSImage) -> Void)?

    init() {
        // 1. Find H.264 decoder
        guard let codec = avcodec_find_decoder(AV_CODEC_ID_H264) else {
            print("[FFmpegDecoder] ❌ H.264 decoder not found.")
            fatalError("FFmpeg H.264 decoder not found.")
        }
        self.codec = codec

        // 2. Create a parser context to handle NAL units from the Annex B stream
        guard let parser = av_parser_init(codec.pointee.id.rawValue) else {
            print("[FFmpegDecoder] ❌ Could not create parser context.")
            fatalError("FFmpeg parser context could not be created.")
        }
        self.parserContext = parser

        // 3. Allocate codec context
        guard let context = avcodec_alloc_context3(codec) else {
            print("[FFmpegDecoder] ❌ Could not allocate codec context.")
            fatalError("FFmpeg codec context could not be allocated.")
        }
        self.codecContext = context

        // 4. Open the codec
        if avcodec_open2(context, codec, nil) < 0 {
            print("[FFmpegDecoder] ❌ Could not open codec.")
            fatalError("FFmpeg codec could not be opened.")
        }

        // 5. Allocate packet and frames
        self.packet = av_packet_alloc()
        self.yuvFrame = av_frame_alloc()
        self.rgbFrame = av_frame_alloc()

        print("[FFmpegDecoder] ✅ FFmpeg H.264 decoder initialized successfully.")
    }

    deinit {
        // Clean up all C-allocated memory
        print("[FFmpegDecoder] Cleaning up FFmpeg resources.")
        av_parser_close(parserContext)
        avcodec_free_context(&codecContext)
        av_packet_free(&packet)
        av_frame_free(&yuvFrame)
        av_frame_free(&rgbFrame)
        av_free(rgbFrameBuffer)
        sws_freeContext(swsContext)
    }

    /// Feeds raw Annex B stream data (with start codes 00 00 01 or 00 00 00 01) to the decoder.
    /// This is the main entry point for data from the WebSocket.
    func decode(frameData: Data) {
        decodeQueue.async { [weak self] in
            guard let self = self,
                  let context = self.codecContext,
                  let parser = self.parserContext,
                  let pkt = self.packet else { return }

            // We must make a mutable copy of the data to feed to the parser's C API
            var frameData = frameData
            frameData.withUnsafeMutableBytes { (rawBufferPointer) in
                guard var inData = rawBufferPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                var inDataSize = frameData.count
                
                // Use the parser to extract complete packets (which may include SPS/PPS)
                // from the raw byte stream.
                while inDataSize > 0 {
                    var outData: UnsafeMutablePointer<UInt8>?
                    var outDataSize: Int32 = 0
                    
                    let bytesParsed = av_parser_parse2(
                        parser, context,
                        &outData, &outDataSize,
                        inData, Int32(inDataSize),
                        AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0
                    )

                    if bytesParsed < 0 {
                        print("[FFmpegDecoder] ❌ Parser error")
                        inDataSize = 0 // Stop parsing
                        break
                    }
                    
                    // Advance the pointer and remaining size
                    inData = inData.advanced(by: Int(bytesParsed))
                    inDataSize -= Int(bytesParsed)

                    // If the parser output a complete packet (outDataSize > 0), decode it
                    if outDataSize > 0 {
                        av_init_packet(pkt)
                        pkt.pointee.data = outData
                        pkt.pointee.size = outDataSize
                        self.sendPacketForDecoding(pkt)
                    }
                }
            }
        }
    }

    /// Sends a parsed packet to the decoder and tries to receive decoded frames.
    private func sendPacketForDecoding(_ packet: UnsafeMutablePointer<AVPacket>?) {
        guard let context = self.codecContext, let frame = self.yuvFrame else { return }

        // Send packet to decoder
        var ret = avcodec_send_packet(context, packet)
        if ret < 0 {
            logFfmpegError(ret, message: "Error sending packet to decoder")
            return
        }

        // Receive all available frames
        while ret >= 0 {
            ret = avcodec_receive_frame(context, frame)
            
            if ret == -EAGAIN || ret == AVERROR_EOF {
                return // Need more data or end of stream
            } else if ret < 0 {
                logFfmpegError(ret, message: "Error receiving frame from decoder")
                return // Decoding error
            }
            
            // Success! We have a decoded frame in `self.yuvFrame`
            // It's in YUV format, so we must convert it to RGB for NSImage
            self.processDecodedFrame(frame.pointee)
        }
    }

    /// Converts a decoded YUV frame to an RGBA NSImage and fires the callback.
    private func processDecodedFrame(_ frame: AVFrame) {
        guard let context = self.codecContext else { return }
        
        let width = Int(context.pointee.width)
        let height = Int(context.pointee.height)
        let pixelFormat = AV_PIX_FMT_RGBA // Target format for NSImage

        // 1. Setup SwsContext (color space converter) if not already setup
        //    or if the resolution has changed.
        if self.swsContext == nil || self.rgbFrame?.pointee.width != width || self.rgbFrame?.pointee.height != height {
            print("[FFmpegDecoder] 🔧 Initializing SWS color converter for \(width)x\(height)")
            sws_freeContext(self.swsContext) // Free old one if it exists
            
            self.swsContext = sws_getContext(
                width, height, context.pointee.pix_fmt, // Input
                width, height, pixelFormat,             // Output
                SWS_BILINEAR, nil, nil, nil // Use fast bilinear scaling
            )
            
            guard self.swsContext != nil else {
                print("[FFmpegDecoder] ❌ Failed to create SWS context")
                return
            }
            
            // Allocate buffer for the RGB frame
            av_free(self.rgbFrameBuffer) // Free old buffer
            let bufferSize = av_image_get_buffer_size(pixelFormat, Int32(width), Int32(height), 1)
            self.rgbFrameBuffer = unsafeBitCast(av_malloc(bufferSize), to: UnsafeMutablePointer<UInt8>.self)
            av_image_fill_arrays(
                &self.rgbFrame!.pointee.data.0,
                &self.rgbFrame!.pointee.linesize.0,
                self.rgbFrameBuffer,
                pixelFormat, Int32(width), Int32(height), 1
            )
        }

        guard let swsCtx = self.swsContext, let rgbFrame = self.rgbFrame, let rgbBuffer = self.rgbFrameBuffer else {
            print("[FFmpegDecoder] ❌ SWS Context or RGB frame not ready.")
            return
        }

        // 2. Perform the color conversion
        sws_scale(
            swsCtx,
            frame.data, frame.linesize, // Input YUV frame data
            0, Int32(height),
            &rgbFrame.pointee.data.0,   // Output RGB frame data
            &rgbFrame.pointee.linesize.0
        )

        // 3. Create NSImage from the RGB data
        let bytesPerRow = Int(rgbFrame.pointee.linesize.0)
        let dataLength = bytesPerRow * height
        
        // Create a Data buffer *without* copying the bytes
        let rgbData = Data(bytesNoCopy: rgbBuffer, count: dataLength, deallocator: .none)

        // Create the CGImage
        guard let provider = CGDataProvider(data: rgbData as CFData),
              let cgImage = CGImage(
                  width: width, height: height,
                  bitsPerComponent: 8,       // 8 bits per R, G, B, A channel
                  bitsPerPixel: 32,      // 8 * 4 = 32
                  bytesPerRow: bytesPerRow,  // From the rgbFrame linesize
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            print("[FFmpegDecoder] ❌ Failed to create CGImage from buffer")
            return
        }

        // 4. Send the NSImage to the callback on the main thread
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        DispatchQueue.main.async {
            self.onDecodedFrame?(nsImage)
        }
    }
    
    /// Flushes the decoder buffers. Call when the stream is interrupted or stopped.
    func reset() {
        decodeQueue.async { [weak self] in
             guard let self = self,
                   let context = self.codecContext,
                   let parser = self.parserContext else { return }
            print("[FFmpegDecoder] Resetting decoder state (flushing buffers).")
            avcodec_flush_buffers(context)
            av_parser_parse2(parser, context, nil, nil, nil, 0, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0) // Reset parser
        }
    }
    
    /// Helper to print FFmpeg error messages
    private func logFfmpegError(_ errorCode: Int32, message: String) {
        let bufferSize = 256
        var errorBuffer = [CChar](repeating: 0, count: bufferSize)
        av_strerror(errorCode, &errorBuffer, bufferSize)
        let errorString = String(cString: errorBuffer)
        print("[FFmpegDecoder] \(message) (Code \(errorCode)): \(errorString)")
    }
}
