//  RadioPlayer.swift
//  Digitaal Hit FM player
//
//  Created by John van Schaijk on 08/06/2025.
//  Digitaal Hit FM

import AVFoundation
import MediaPlayer
import Combine
import UIKit

class RadioPlayer: ObservableObject {
    static let shared = RadioPlayer()


    private var player: AVPlayer?
    @Published var isPlaying = false
    @Published var volume: Float = 0.5 {
        didSet {
            player?.volume = volume
        }
    }
    @Published var artist: String = "Loading artist..."
    @Published var title: String = "Loading title..."
    var currentStreamName: String = ""

    @Published var isBuffering = false
    @Published var bufferSeconds: Double = 0

    private var streamURL: URL?
    private var metadataURL: URL?
    private var metadataTimer: Timer?
    private var timeControlObserver: NSKeyValueObservation?
    private var rotationTimer: Timer?
    private var rotationStep: Int = -1
    private var lastDetectedArtist: String = ""
    private var lastDetectedTitle: String = ""
    private var marqueeTimer: Timer?
    private var marqueeString = ""
    private var marqueeOffset = 0
    private var marqueePass = 0
    
    init() {
        setupAudioSession()
        player = nil
        setupRemoteCommandCenter()
        setupInterruptionHandling()
    }
    
    func setStream(named streamName: String) {
        guard let entry = ConfigLoader.shared.stream(named: streamName) else { return }
        currentStreamName = streamName
        setStream(streamURL: entry.streamURL, metadataURL: entry.metadataURL)
    }
    
    func setStream(streamURL: String, metadataURL: String) {
        guard let newStreamURL = URL(string: streamURL) else {
            print("Invalid stream URL")
            return
        }
        self.streamURL = newStreamURL
        
        if let newMetadataURL = URL(string: metadataURL) {
            self.metadataURL = newMetadataURL
        } else {
            self.metadataURL = nil
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.artist = "Loading artist..."
            self.title = "Loading title..."
            self.rotationStep = -1
            self.lastDetectedArtist = ""
            self.lastDetectedTitle = ""
            self.stopRotationTimer()
            self.setupPlayer()
            self.player?.play()
            self.isPlaying = true
            self.updateNowPlaying(isPlaying: true)
            self.startMetadataTimer()
        }
    }
    
    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            DispatchQueue.main.async {
                self.isPlaying = false
                self.stopRotationTimer()
            }
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                DispatchQueue.main.async {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self.player?.play()
                    self.isPlaying = true
                    self.updateNowPlaying(isPlaying: true)
                    self.startMetadataTimer()
                }
            }
        @unknown default:
            break
        }
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    private func setupPlayer() {
        guard let streamURL = streamURL else { return }
        let playerItem = AVPlayerItem(url: streamURL)
        if let player = player {
            player.replaceCurrentItem(with: playerItem)
        } else {
            player = AVPlayer(playerItem: playerItem)
            player?.volume = volume
        }
        timeControlObserver = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self?.updateBufferSeconds()
            }
        }
    }
    
    func togglePlayback() {
        guard let player = player else { return }
        if isPlaying {
            player.volume = 0
            isPlaying = false
            updateNowPlaying(isPlaying: false)
            stopMetadataTimer()
            stopRotationTimer()
        } else {
            player.volume = volume
            isPlaying = true
            updateNowPlaying(isPlaying: true)
            startMetadataTimer()
        }
    }
    
    private func startMetadataTimer() {
        stopMetadataTimer()
        guard metadataURL != nil else { return }
        
        metadataTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.fetchMetadata()
            self?.updateBufferSeconds()
        }
        metadataTimer?.fire()
    }
    
    private func stopMetadataTimer() {
        metadataTimer?.invalidate()
        metadataTimer = nil
    }

    private func startTrackRotation() {
        stopRotationTimer()
        rotationStep = 0
        marqueeString = "\(artist) - \(title)     "
        marqueeOffset = 0
        marqueePass = 0
        sendMarqueeFrame()
        marqueeTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tickMarquee()
        }
    }

    private func tickMarquee() {
        marqueeOffset += 1
        if marqueeOffset >= marqueeString.count {
            marqueePass += 1
            if marqueePass >= 2 {
                stopMarqueeTimer()
                rotationStep = 2
                sendNowPlayingStep()
                return
            }
            marqueeOffset = 0
        }
        sendMarqueeFrame()
    }

    private func sendMarqueeFrame() {
        let idx = marqueeString.index(marqueeString.startIndex, offsetBy: marqueeOffset)
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtist] = ""
        info[MPMediaItemPropertyTitle] = String(marqueeString[idx...])
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func stopMarqueeTimer() {
        marqueeTimer?.invalidate()
        marqueeTimer = nil
    }

    private func stopRotationTimer() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        stopMarqueeTimer()
    }

    private func sendNowPlayingStep() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtist] = ""
        info[MPMediaItemPropertyTitle] = currentStreamName
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateBufferSeconds() {
        guard let item = player?.currentItem,
              let range = item.loadedTimeRanges.first?.timeRangeValue else {
            bufferSeconds = 0; return
        }
        let buffered = CMTimeAdd(range.start, range.duration)
        let current  = item.currentTime()
        bufferSeconds = max(0, CMTimeGetSeconds(CMTimeSubtract(buffered, current)))
    }

    private func fetchMetadata() {
        guard let metadataURL = metadataURL else { return }
        
        let task = URLSession.shared.dataTask(with: metadataURL) { [weak self] data, _, error in
            guard let self = self else { return }
            guard let data = data, error == nil else {
                print("Metadata fetch error: \(error?.localizedDescription ?? "unknown error")")
                return
            }
            
            var streamTitle: String?
            var isJSON = false
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let icestats = json["icestats"] as? [String: Any] {
                isJSON = true
                if let source = icestats["source"] as? [String: Any] {
                    streamTitle = source["title"] as? String
                } else if let sources = icestats["source"] as? [[String: Any]] {
                    for source in sources {
                        if let listenURL = source["listenurl"] as? String,
                           listenURL.contains(self.streamURL?.lastPathComponent ?? "") {
                            streamTitle = source["title"] as? String
                            break
                        }
                    }
                }
            }
            
            if streamTitle == nil {
                if let html = self.decodeMetadataText(from: data) {
                    streamTitle = self.parseHTMLMetadata(from: html)
                }
            }
            
            DispatchQueue.main.async {
                if let streamTitle = streamTitle, !streamTitle.isEmpty {
                    let parts = streamTitle.components(separatedBy: " - ")
                    let newArtist = (parts.first ?? "Unknown Artist").decodedHTMLEntities
                    let newTitle = parts.dropFirst().joined(separator: " - ").decodedHTMLEntities
                    let a = newArtist.isEmpty ? "Unknown Artist" : newArtist
                    let t = newTitle.isEmpty ? "Unknown Title" : newTitle
                    if a != self.lastDetectedArtist || t != self.lastDetectedTitle {
                        self.lastDetectedArtist = a
                        self.lastDetectedTitle = t
                        self.artist = a
                        self.title = t
                        if self.isPlaying {
                            self.startTrackRotation()
                        }
                    }
                } else {
                    self.artist = ""
                    self.title = ""
                }
                self.updateNowPlaying(isPlaying: self.isPlaying)
            }
            
            if !isJSON {
                print("Parsed metadata from HTML for: \(metadataURL)")
            }
        }
        task.resume()
    }
    
    private func updateNowPlaying(isPlaying: Bool? = nil) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

        if let image = UIImage(named: "digitaal_hitfm_logo") {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        let playing = isPlaying ?? self.isPlaying
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0

        // Before first track: show station name as initial display
        if rotationStep == -1 {
            let subtitle = ConfigLoader.shared.stream(named: currentStreamName)?.subtitle ?? currentStreamName
            info[MPMediaItemPropertyArtist] = subtitle
            info[MPMediaItemPropertyTitle] = currentStreamName
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.player?.volume = self.volume
            self.isPlaying = true
            self.updateNowPlaying(isPlaying: true)
            self.startMetadataTimer()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.player?.volume = 0
            self.isPlaying = false
            self.updateNowPlaying(isPlaying: false)
            self.stopMetadataTimer()
            self.stopRotationTimer()
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
    }
    
    private func decodeMetadataText(from data: Data) -> String? {
        let encodings: [String.Encoding] = [.utf8, .isoLatin1, .windowsCP1252, .ascii]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                let fixed = fixMojibake(text)
                if !fixed.isEmpty {
                    return fixed
                }
            }
        }
        return nil
    }
    
    private func fixMojibake(_ text: String) -> String {
        guard text.contains("Ã") || text.contains("â") else {
            return text
        }

        let bytes = Data(text.unicodeScalars.compactMap { scalar in
            guard scalar.value <= 0xFF else { return nil }
            return UInt8(scalar.value)
        })

        if let repaired = String(data: bytes, encoding: .utf8) {
            return repaired
        }

        return text
    }

    private func parseHTMLMetadata(from html: String) -> String? {
        guard let streamURL = streamURL else { return nil }
        let mountName = streamURL.lastPathComponent
        let startIndex = html.range(of: "Mount Point /\(mountName)")?.lowerBound ?? html.startIndex
        let tail = html[startIndex...]
        let section = String(tail)
        let regexPattern = "Currently playing:</td>\\s*<td[^>]*>(.*?)</td>"
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(section.startIndex..<section.endIndex, in: section)
        if let match = regex.firstMatch(in: section, options: [], range: range),
           let captureRange = Range(match.range(at: 1), in: section) {
            let rawTitle = String(section[captureRange])
            return rawTitle.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        return nil
    }
    
    deinit {
        metadataTimer?.invalidate()
    }
}

private extension String {
    var decodedHTMLEntities: String {
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " ")
        ]
        return entities.reduce(self) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}
