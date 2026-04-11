//
//  NowPlayingPublisher.swift
//  AirSync
//
//  Publishes Android now-playing info into macOS MPNowPlayingInfoCenter
// so boring.notch (via MediaRemote.framework) picks it up naturally.
// Uses silent audio to make the app audio-eligible for MediaRemote reporting.
//

import Foundation
import AppKit
import AVFoundation
import MediaPlayer

final class NowPlayingPublisher {
    static let shared = NowPlayingPublisher()

    // MARK: - Silent Audio Engine (makes app audio-eligible for MediaRemote)
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isSilentAudioRunning: Bool = false

    // MARK: - State
    private var currentInfo: NowPlayingInfo?
    private var commandCenterRegistered = false

    /// Timestamp of the last remote command we sent to Android.
    private var lastCommandSentAt: Date = .distantPast
    /// Timestamp of the last time we updated MPNowPlayingInfoCenter.
    private var lastStateUpdateAt: Date = .distantPast
    
    // Short debounces to provide an instant UI while preventing macOS feedback loops:
    // 0.35s limits how fast the user can mash buttons, and blocks automated
    // counter-commands that macOS fires right after we update the info center.
    private let commandDebounceInterval: TimeInterval = 0.35
    private let stateUpdateDebounceInterval: TimeInterval = 0.35

    private init() {}

    // MARK: - Public API

    /// Call once at app startup. Sets up remote commands and starts silent audio.
    func start() {
        registerRemoteCommands()
        // Start silent audio immediately so the app is ALWAYS audio-eligible.
        // If we wait until the first play command, macOS sees us publish
        // MPNowPlayingInfoCenter data without backing audio and fires a pauseCommand
        // to "correct" the state — which is the root cause of the glitch loop.
        startSilentAudio()
    }

    /// Update now-playing with Android media info.
    /// During the 1-second window after the user clicks a button, we ignore incoming
    /// status updates. This protects our instant optimistic UI from being overwritten
    /// by stale network packets that Android dispatched before the command took effect.
    func update(info: NowPlayingInfo) {
        let timeSinceCommand = Date().timeIntervalSince(lastCommandSentAt)
        if timeSinceCommand < 1.0 {
            return
        }
        
        currentInfo = info

        // Always publish metadata on the main thread (MPNowPlayingInfoCenter requirement)
        DispatchQueue.main.async {
            self.lastStateUpdateAt = Date()
            self.publishToNowPlayingInfoCenter(info: info)
        }
        // Silent audio is always running (started in start()), nothing to do here.
    }

    /// Clear now-playing info (e.g., Android disconnected)
    func clear() {
        currentInfo = nil
        stopSilentAudio()  // Only place we stop the engine
        DispatchQueue.main.async {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }

    // MARK: - Silent Audio

    private func startSilentAudio() {
        guard !isSilentAudioRunning else { return }
        isSilentAudioRunning = true

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)

        // Generate one second of silence
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let frameCount = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            isSilentAudioRunning = false
            return
        }
        buffer.frameLength = frameCount
        // Buffer is already zeroed by default — silence

        // BUG FIX: engine.start() MUST come before player.play() / scheduleBuffer.
        // Calling player.play() on an un-started engine produces:
        //   "Engine is not running because it was not explicitly started"
        do {
            try engine.start()
        } catch {
            print("[NowPlayingPublisher] Failed to start silent audio engine: \(error)")
            isSilentAudioRunning = false
            return
        }

        audioEngine = engine
        playerNode = player

        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()

        print("[NowPlayingPublisher] Silent audio engine started — app is now audio-eligible")
    }

    private func stopSilentAudio() {
        guard isSilentAudioRunning else { return }
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine?.reset()
        audioEngine = nil
        playerNode = nil
        isSilentAudioRunning = false
        print("[NowPlayingPublisher] Silent audio engine stopped")
    }

    // MARK: - Publish to MPNowPlayingInfoCenter

    private func publishToNowPlayingInfoCenter(info: NowPlayingInfo) {
        let center = MPNowPlayingInfoCenter.default()

        var mpInfo: [String: Any] = [
            MPMediaItemPropertyTitle: info.title ?? "",
            MPMediaItemPropertyArtist: info.artist ?? "",
            MPMediaItemPropertyAlbumTitle: info.album ?? "",
        ]

        if let duration = info.duration, duration > 0 {
            mpInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let elapsed = info.elapsedTime {
            mpInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        mpInfo[MPNowPlayingInfoPropertyPlaybackRate] = info.isPlaying == true ? 1.0 : 0.0

        if let artworkData = info.artworkData,
           let nsImage = NSImage(data: artworkData) {
            let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: nsImage.size.width, height: nsImage.size.height)) { _ in
                return nsImage
            }
            mpInfo[MPMediaItemPropertyArtwork] = artwork
        }

        center.nowPlayingInfo = mpInfo
        // Restore playbackState so UI elements like boringNotch know it's explicitly playing/paused.
        // Automated counter-commands triggered by this change will be dropped by stateUpdateDebounceInterval.
        center.playbackState = info.isPlaying == true ? .playing : .paused
    }

    // MARK: - Remote Commands
    
    private func processCommand(name: String, action: String, optimisticUpdate: ((NowPlayingPublisher) -> Void)? = nil) -> MPRemoteCommandHandlerStatus {
        let now = Date()
        let timeSinceCommand = now.timeIntervalSince(lastCommandSentAt)
        let timeSinceState = now.timeIntervalSince(lastStateUpdateAt)
        
        if timeSinceCommand < commandDebounceInterval {
            return .success
        }
        if timeSinceState < stateUpdateDebounceInterval {
            return .success
        }
        
        lastCommandSentAt = now
        WebSocketServer.shared.sendAndroidMediaControl(action: action)
        optimisticUpdate?(self)
        
        return .success
    }

    private func registerRemoteCommands() {
        guard !commandCenterRegistered else { return }
        commandCenterRegistered = true

        let commandCenter = MPRemoteCommandCenter.shared()

        // NOTE: Commands are forwarded to Android via WebSocket (not NowPlayingCLI which
        // controls LOCAL Mac media via the `media-control` binary). This music is from
        // the phone, so control actions must go back over the WebSocket connection.
        // IMPORTANT: macOS often fires automated counter-commands when we update MPNowPlayingInfoCenter.
        // We drop any commands received within `stateUpdateDebounceInterval` of our last update.
        // We also do optimistic updates so the UI responds instantly to clicks.
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            return self?.processCommand(name: "Play", action: "play") { $0.publishPlaybackStateUpdate(playing: true) } ?? .commandFailed
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            return self?.processCommand(name: "Pause", action: "pause") { $0.publishPlaybackStateUpdate(playing: false) } ?? .commandFailed
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            let isPlaying = self?.currentInfo?.isPlaying == true
            let explicitAction = isPlaying ? "pause" : "play"
            return self?.processCommand(name: "TogglePlayPause", action: explicitAction) { publisher in
                publisher.publishPlaybackStateUpdate(playing: !isPlaying)
            } ?? .commandFailed
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            return self?.processCommand(name: "NextTrack", action: "nextTrack") ?? .commandFailed
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            return self?.processCommand(name: "PreviousTrack", action: "previousTrack") ?? .commandFailed
        }

        // Seeking not yet supported for Android remote
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        print("[NowPlayingPublisher] Remote commands registered")
    }

    private func publishPlaybackStateUpdate(playing: Bool) {
        guard var info = currentInfo else { return }
        info.isPlaying = playing
        currentInfo = info
        DispatchQueue.main.async {
            self.lastStateUpdateAt = Date()
            self.publishToNowPlayingInfoCenter(info: info)
        }
    }
}
