//
//  MetalVideoView.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-04-01.
//

import SwiftUI
import MetalKit

struct MetalVideoView: NSViewRepresentable {
    @ObservedObject var streamClient: ScrcpyStreamClient
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = ScrcpyMTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.framebufferOnly = false
        mtkView.colorPixelFormat = .bgra8Unorm
        
        // Pass stream client to view for coordinate mapping
        mtkView.streamClient = streamClient
        
        context.coordinator.setupMetal(device: mtkView.device!)
        
        return mtkView
    }
    
    class ScrcpyMTKView: MTKView {
        var streamClient: ScrcpyStreamClient?
        
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            sendTouchEvent(action: 0, event: event)
        }
        override func mouseUp(with event: NSEvent) { sendTouchEvent(action: 1, event: event) }
        override func mouseDragged(with event: NSEvent) { sendTouchEvent(action: 2, event: event) }
        
        // Keyboard event handling
        override func keyDown(with event: NSEvent) {
            if let keycode = androidKeycode(for: event.keyCode) {
                var metaState: UInt32 = 0
                let flags = event.modifierFlags
                let swap = UserDefaults.standard.swapCmdAndCtrl
                
                if flags.contains(.shift) { metaState |= 0x01 }
                if flags.contains(.option) { metaState |= 0x02 }
                if flags.contains(.capsLock) { metaState |= 0x100000 }
                
                if swap {
                    if flags.contains(.control) { metaState |= 0x10000 } // Control -> Meta
                    if flags.contains(.command) { metaState |= 0x1000 }  // Command -> Control
                } else {
                    if flags.contains(.control) { metaState |= 0x1000 }
                    if flags.contains(.command) { metaState |= 0x10000 }
                }
                
                ScrcpyControlClient.shared.sendKeyEvent(action: 0, keycode: keycode, metaState: metaState)
            } else {
                super.keyDown(with: event)
            }
        }
        
        override func keyUp(with event: NSEvent) {
            if let keycode = androidKeycode(for: event.keyCode) {
                var metaState: UInt32 = 0
                let flags = event.modifierFlags
                let swap = UserDefaults.standard.swapCmdAndCtrl
                
                if flags.contains(.shift) { metaState |= 0x01 }
                if flags.contains(.option) { metaState |= 0x02 }
                if flags.contains(.capsLock) { metaState |= 0x100000 }
                
                if swap {
                    if flags.contains(.control) { metaState |= 0x10000 } // Control -> Meta
                    if flags.contains(.command) { metaState |= 0x1000 }  // Command -> Control
                } else {
                    if flags.contains(.control) { metaState |= 0x1000 }
                    if flags.contains(.command) { metaState |= 0x10000 }
                }
                
                ScrcpyControlClient.shared.sendKeyEvent(action: 1, keycode: keycode, metaState: metaState)
            } else {
                super.keyUp(with: event)
            }
        }
        
        private func androidKeycode(for macKeycode: UInt16) -> UInt32? {
            let swap = UserDefaults.standard.swapCmdAndCtrl
            switch macKeycode {
            // Modifiers
            case 59: return swap ? 117 : 113 // Left Control
            case 55: return swap ? 113 : 117 // Left Command/Meta
            case 58: return 57               // Left Option/Alt
            case 56: return 59               // Left Shift
            case 62: return swap ? 118 : 114 // Right Control
            case 54: return swap ? 114 : 118 // Right Command/Meta
            case 61: return 58               // Right Option/Alt
            case 60: return 60               // Right Shift
            
            // Letters
            case 0: return 29  // A
            case 11: return 30 // B
            case 8: return 31  // C
            case 2: return 32  // D
            case 14: return 33 // E
            case 3: return 34  // F
            case 5: return 35  // G
            case 4: return 36  // H
            case 34: return 37 // I
            case 38: return 38 // J
            case 40: return 39 // K
            case 37: return 40 // L
            case 46: return 41 // M
            case 45: return 42 // N
            case 31: return 43 // O
            case 35: return 44 // P
            case 12: return 45 // Q
            case 15: return 46 // R
            case 1: return 47  // S
            case 17: return 48 // T
            case 32: return 49 // U
            case 9: return 50  // V
            case 13: return 51 // W
            case 7: return 52  // X
            case 16: return 53 // Y
            case 6: return 54  // Z
            
            // Numbers
            case 29: return 7  // 0
            case 18: return 8  // 1
            case 19: return 9  // 2
            case 20: return 10 // 3
            case 21: return 11 // 4
            case 23: return 12 // 5
            case 22: return 13 // 6
            case 26: return 14 // 7
            case 28: return 15 // 8
            case 25: return 16 // 9
            
            // Special / Navigation
            case 36: return 66  // Enter
            case 51: return 67  // Delete (Backspace)
            case 53: return 111 // Escape
            case 48: return 61  // Tab
            case 49: return 62  // Space
            case 123: return 21 // Left
            case 124: return 22 // Right
            case 126: return 19 // Up
            case 125: return 20 // Down
            
            // Additional symbols
            case 24: return 81  // Plus/Equal
            case 27: return 69  // Minus
            case 33: return 71  // Left Bracket
            case 30: return 72  // Right Bracket
            case 42: return 73  // Backslash
            case 41: return 74  // Semicolon
            case 39: return 75  // Apostrophe
            case 43: return 55  // Comma
            case 47: return 56  // Period
            case 44: return 76  // Slash
            case 50: return 68  // Grave (Backtick)
            
            default: return nil
            }
        }
        
        private var rightClickTimer: Timer?
        private var rightClickDidTriggerHome = false
        
        private func sendHomeButton() {
            ScrcpyControlClient.shared.sendKeyEvent(action: 0, keycode: 3)
            ScrcpyControlClient.shared.sendKeyEvent(action: 1, keycode: 3)
        }
        
        // Secondary click: long press sends Home (3), short press sends Back (4)
        override func rightMouseDown(with event: NSEvent) {
            rightClickDidTriggerHome = false
            rightClickTimer?.invalidate()
            rightClickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.rightClickDidTriggerHome = true
                self?.sendHomeButton()
            }
        }
        
        override func rightMouseUp(with event: NSEvent) {
            rightClickTimer?.invalidate()
            rightClickTimer = nil
            if !rightClickDidTriggerHome {
                ScrcpyControlClient.shared.sendKeyEvent(action: 0, keycode: 4)
                ScrcpyControlClient.shared.sendKeyEvent(action: 1, keycode: 4)
            }
        }
        
        // Middle click sends Home (3)
        override func otherMouseDown(with event: NSEvent) {
            if event.buttonNumber == 2 {
                sendHomeButton()
            } else {
                super.otherMouseDown(with: event)
            }
        }
        
        override func scrollWheel(with event: NSEvent) {
            guard let client = streamClient, client.videoWidth > 0, client.videoHeight > 0 else { return }
            
            let point = convert(event.locationInWindow, from: nil)
            
            // Coordinate mapping: NSView (flipped Y) to Android (0,0 is top-left)
            let x = Int32(max(0, min(1.0, point.x / frame.width)) * Double(client.videoWidth))
            let y = Int32(max(0, min(1.0, 1.0 - (point.y / frame.height))) * Double(client.videoHeight))
            
            // For scrcpy scroll events, positive scrolls left/up, negative scrolls right/down.
            // On macOS:
            // - scrollingDeltaY is positive when scrolling up (moving page down)
            // - scrollingDeltaX is positive when scrolling left (moving page right)
            // We pass the delta values directly so Android handles continuous/precise scrolling smoothly.
            let scrollX = Float(event.scrollingDeltaX)
            let scrollY = Float(event.scrollingDeltaY)
            
            ScrcpyControlClient.shared.sendScrollEvent(
                x: x,
                y: y,
                width: UInt16(client.videoWidth),
                height: UInt16(client.videoHeight),
                scrollX: scrollX,
                scrollY: scrollY
            )
        }
        
        private func sendTouchEvent(action: UInt8, event: NSEvent) {
            guard let client = streamClient, client.videoWidth > 0, client.videoHeight > 0 else { return }
            
            let point = convert(event.locationInWindow, from: nil)
            
            // Coordinate mapping: NSView (flipped Y) to Android (0,0 is top-left)
            let x = UInt32(max(0, min(1.0, point.x / frame.width)) * Double(client.videoWidth))
            let y = UInt32(max(0, min(1.0, 1.0 - (point.y / frame.height))) * Double(client.videoHeight))
            
            ScrcpyControlClient.shared.sendTouchEvent(
                action: action,
                x: x, y: y,
                width: UInt16(client.videoWidth),
                height: UInt16(client.videoHeight)
            )
        }
        
        override var acceptsFirstResponder: Bool { true }
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // Handle updates if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        private var device: MTLDevice?
        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLRenderPipelineState?
        private var textureCache: CVMetalTextureCache?
        
        private var currentBuffer: CVPixelBuffer?
        private let lock = NSLock()
        
        func setupMetal(device: MTLDevice) {
            self.device = device
            self.commandQueue = device.makeCommandQueue()
            
            let library = try? device.makeLibrary(source: scrcpyShaders, options: nil)
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = library?.makeFunction(name: "video_vertex")
            pipelineDescriptor.fragmentFunction = library?.makeFunction(name: "video_fragment")
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                print("[MetalVideoView] Pipeline error: \(error)")
            }
            
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
            
            // Subscribe to decoded frames
            ScrcpyVideoDecoder.shared.onDecodedFrame = { [weak self] buffer in
                self?.updateFrame(buffer)
            }
        }
        
        func updateFrame(_ buffer: CVPixelBuffer) {
            lock.lock()
            currentBuffer = buffer
            lock.unlock()
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            lock.lock()
            guard let buffer = currentBuffer,
                  let device = device,
                  let commandQueue = commandQueue,
                  let pipelineState = pipelineState,
                  let textureCache = textureCache,
                  let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor else {
                lock.unlock()
                return
            }
            lock.unlock()
            
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            
            var textureY: CVMetalTexture?
            var textureUV: CVMetalTexture?
            
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, buffer, nil, .r8Unorm, width, height, 0, &textureY)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, buffer, nil, .rg8Unorm, width/2, height/2, 1, &textureUV)
            
            guard let yTex = CVMetalTextureGetTexture(textureY!),
                  let uvTex = CVMetalTextureGetTexture(textureUV!) else { return }
            
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
            
            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentTexture(yTex, index: 0)
            encoder.setFragmentTexture(uvTex, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        // Inline shaders for robustness in development
        private let scrcpyShaders = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut video_vertex(uint vertexID [[vertex_id]]) {
            const float2 vertices[] = {
                { -1.0, -1.0 }, { 0.0, 1.0 },
                {  1.0, -1.0 }, { 1.0, 1.0 },
                { -1.0,  1.0 }, { 0.0, 0.0 },
                {  1.0,  1.0 }, { 1.0, 0.0 }
            };
            VertexOut out;
            out.position = float4(vertices[vertexID * 2], 0, 1);
            out.texCoord = vertices[vertexID * 2 + 1];
            return out;
        }

        fragment float4 video_fragment(VertexOut in [[stage_in]],
                                      texture2d<float, access::sample> textureY [[texture(0)]],
                                      texture2d<float, access::sample> textureUV [[texture(1)]]) {
            sampler s(address::clamp_to_edge, filter::linear);
            float y = textureY.sample(s, in.texCoord).r;
            float2 uv = textureUV.sample(s, in.texCoord).rg - float2(0.5, 0.5);
            float r = y + 1.5748 * uv.y;
            float g = y - 0.1873 * uv.x - 0.4681 * uv.y;
            float b = y + 1.8556 * uv.x;
            return float4(r, g, b, 1.0);
        }
        """
    }
}
