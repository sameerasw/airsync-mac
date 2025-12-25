//
//  AudioStreamPlayer.swift
//  airsync-mac
//
//  Audio player for streaming audio from Android device
//

import Foundation
import AVFoundation

/// Plays audio streamed from Android device via WebSocket
class AudioStreamPlayer {
    static let shared = AudioStreamPlayer()
    
    // Audio configuration (must match Android side)
    private var sampleRate: Double = 44100
    private var channels: Int = 2
    private var bitsPerSample: Int = 16
    
    // Audio engine
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    
    // Thread-safe state management
    private let audioQueue = DispatchQueue(label: "com.airsync.audioQueue", qos: .userInitiated)
    private let stateLock = NSLock()
    private var _isPlaying = false
    private var isPlaying: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _isPlaying }
        set { stateLock.lock(); _isPlaying = newValue; stateLock.unlock() }
    }
    
    // Prevent audio from blocking mirror frames
    private var pendingBuffers = 0
    private let maxPendingBuffers = 5
    
    private init() {}
    
    /// Configure audio parameters from Android
    func configure(sampleRate: Int, channels: Int, bitsPerSample: Int) {
        self.sampleRate = Double(sampleRate)
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        
        print("[audio] Configured: sampleRate=\(sampleRate), channels=\(channels), bits=\(bitsPerSample)")
    }
    
    /// Start audio playback
    func start() {
        audioQueue.async { [weak self] in
            self?.setupAudioEngine()
        }
    }
    
    /// Stop audio playback
    func stop() {
        // Mark as not playing immediately to stop accepting new frames
        isPlaying = false
        
        audioQueue.async { [weak self] in
            self?.teardownAudioEngine()
        }
    }
    
    /// Receive audio frame from Android - non-blocking
    func receiveFrame(_ base64Data: String, frameIndex: Int64) {
        // Quick exit if not playing
        guard isPlaying else { return }
        
        // Drop frames if we're falling behind to prevent blocking
        guard pendingBuffers < maxPendingBuffers else {
            return
        }
        
        guard let data = Data(base64Encoded: base64Data) else {
            return
        }
        
        pendingBuffers += 1
        
        audioQueue.async { [weak self] in
            self?.processAudioFrame(data)
            self?.pendingBuffers -= 1
        }
    }
    
    // MARK: - Private Methods
    
    private func setupAudioEngine() {
        guard !_isPlaying else { return }
        
        do {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            
            // Create audio format for PCM 16-bit stereo
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channels),
                interleaved: true
            ) else {
                print("[audio] Failed to create audio format")
                return
            }
            
            // Attach and connect nodes
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            
            // Start engine
            try engine.start()
            player.play()
            
            self.audioEngine = engine
            self.playerNode = player
            self.audioFormat = format
            self.isPlaying = true
            self.pendingBuffers = 0
            
            print("[audio] Audio engine started")
            
        } catch {
            print("[audio] Error setting up audio engine: \(error)")
            teardownAudioEngine()
        }
    }
    
    private func teardownAudioEngine() {
        // Stop player first
        playerNode?.stop()
        
        // Stop engine
        if audioEngine?.isRunning == true {
            audioEngine?.stop()
        }
        
        // Detach player
        if let player = playerNode, let engine = audioEngine {
            engine.detach(player)
        }
        
        playerNode = nil
        audioEngine = nil
        audioFormat = nil
        _isPlaying = false
        pendingBuffers = 0
        
        print("[audio] Audio engine stopped")
    }
    
    private func processAudioFrame(_ data: Data) {
        guard _isPlaying, let player = playerNode, let format = audioFormat else { return }
        
        // Validate data size
        let bytesPerFrame = channels * (bitsPerSample / 8)
        guard data.count >= bytesPerFrame else { return }
        
        let frameCount = AVAudioFrameCount(data.count / bytesPerFrame)
        guard frameCount > 0 else { return }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        
        buffer.frameLength = frameCount
        
        // Copy data to buffer
        data.withUnsafeBytes { rawBufferPointer in
            if let baseAddress = rawBufferPointer.baseAddress,
               let int16Data = buffer.int16ChannelData {
                memcpy(int16Data[0], baseAddress, data.count)
            }
        }
        
        // Schedule buffer for playback - don't wait for completion
        player.scheduleBuffer(buffer)
    }
}
