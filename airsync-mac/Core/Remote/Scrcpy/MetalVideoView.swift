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
        
        override func mouseDown(with event: NSEvent) { sendTouchEvent(action: 0, event: event) }
        override func mouseUp(with event: NSEvent) { sendTouchEvent(action: 1, event: event) }
        override func mouseDragged(with event: NSEvent) { sendTouchEvent(action: 2, event: event) }
        
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
