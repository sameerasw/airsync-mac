//
//  CallAudioManager.swift
//  airsync-mac
//
//  Manages call audio streaming between Mac and Android
//  Allows using Mac's mic and speaker for phone calls
//

import Foundation
import AVFoundation
internal import Combine

class CallAudioManager: ObservableObject {
    static let shared = CallAudioManager()
    
    @Published var isCallAudioActive = false
    @Published var isMicEnabled = false
    @Published var isSpeakerEnabled = true
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var micBuffer: AVAudioPCMBuffer?
    private var sendTimer: Timer?
    
    // Audio format for call audio (8kHz mono for telephony)
    private let callSampleRate: Double = 8000
    private let callChannels: AVAudioChannelCount = 1
    
    private init() {}
    
    // MARK: - Call Audio Control
    
    /// Start call audio mode - enables mic capture and speaker output
    func startCallAudio() {
        guard !isCallAudioActive else { return }
        
        print("[CallAudio] Starting call audio mode")
        
        // Request mic permission
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted else {
                print("[CallAudio] Microphone permission denied")
                return
            }
            
            DispatchQueue.main.async {
                // Configure audio player for call audio (8kHz mono)
                AudioStreamPlayer.shared.stop() // Stop any existing stream
                AudioStreamPlayer.shared.configure(sampleRate: Int(self?.callSampleRate ?? 8000), channels: Int(self?.callChannels ?? 1), bitsPerSample: 16)
                AudioStreamPlayer.shared.start()
                
                self?.setupAudioEngine()
                self?.isCallAudioActive = true
            }
        }
        
        // Notify Android to route call audio to us
        sendCallAudioCommand(action: "startCallAudio")
    }
    
    /// Stop call audio mode
    func stopCallAudio() {
        guard isCallAudioActive else { return }
        
        print("[CallAudio] Stopping call audio mode")
        
        sendTimer?.invalidate()
        sendTimer = nil
        
        audioEngine?.stop()
        audioEngine = nil
        audioEngine = nil
        inputNode = nil
        
        // Stop audio player
        AudioStreamPlayer.shared.stop()
        
        isCallAudioActive = false
        isMicEnabled = false
        
        // Notify Android to stop routing call audio
        sendCallAudioCommand(action: "stopCallAudio")
    }
    
    /// Toggle microphone on/off
    func toggleMic() {
        isMicEnabled.toggle()
        
        if isMicEnabled {
            startMicCapture()
        } else {
            stopMicCapture()
        }
        
        print("[CallAudio] Mic \(isMicEnabled ? "enabled" : "disabled")")
    }
    
    /// Toggle speaker on/off
    func toggleSpeaker() {
        isSpeakerEnabled.toggle()
        print("[CallAudio] Speaker \(isSpeakerEnabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Audio Engine Setup
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
        
        do {
            try audioEngine?.start()
            print("[CallAudio] Audio engine started")
        } catch {
            print("[CallAudio] Failed to start audio engine: \(error)")
        }
    }
    
    private func startMicCapture() {
        guard let inputNode = inputNode else { return }
        
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            self?.processMicBuffer(buffer)
        }
        
        print("[CallAudio] Mic capture started")
    }
    
    private func stopMicCapture() {
        inputNode?.removeTap(onBus: 0)
        print("[CallAudio] Mic capture stopped")
    }
    
    private func processMicBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isMicEnabled, isCallAudioActive else { return }
        
        // Convert to base64 and send to Android
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        var samples = [Int16](repeating: 0, count: frameLength)
        
        // Convert float samples to Int16
        for i in 0..<frameLength {
            let sample = channelData[0][i]
            samples[i] = Int16(max(-1, min(1, sample)) * Float(Int16.max))
        }
        
        // Convert to Data and base64
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let base64 = data.base64EncodedString()
        
        // Send to Android
        sendMicAudio(base64: base64)
    }
    
    // MARK: - Receive Call Audio from Android
    
    /// Handle incoming call audio from Android
    func handleCallAudio(base64Data: String) {
        guard isCallAudioActive, isSpeakerEnabled else { return }
        
        // Decode and play through AudioStreamPlayer
        guard Data(base64Encoded: base64Data) != nil else { return }
        
        // Use existing audio player infrastructure
        // AudioStreamPlayer uses receiveFrame method
        AudioStreamPlayer.shared.receiveFrame(base64Data, frameIndex: 0)
    }
    
    // MARK: - WebSocket Communication
    
    private func sendCallAudioCommand(action: String) {
        let message = """
        {
            "type": "callAudioControl",
            "data": {
                "action": "\(action)"
            }
        }
        """
        WebSocketServer.shared.sendToFirstAvailable(message: message)
    }
    
    private func sendMicAudio(base64: String) {
        let message = """
        {
            "type": "callMicAudio",
            "data": {
                "audio": "\(base64)"
            }
        }
        """
        WebSocketServer.shared.sendToFirstAvailable(message: message)
    }
}
