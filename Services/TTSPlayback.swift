//
//  TTSPlayback.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import Foundation
import AVFoundation
import Combine

/// Service for text-to-speech playback and audio controls
class TTSPlayback: NSObject, ObservableObject {
    static let shared = TTSPlayback()
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackError: String?
    
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var timer: Timer?
    private var startTime: Date?
    
    private override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    /// Convert text to speech and play
    func speak(text: String, language: String = "zh-CN") {
        stop()
        
        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            playbackError = "Failed to configure audio: \(error.localizedDescription)"
            return
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.5 // Moderate speaking rate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // Estimate duration (rough calculation: ~150 words per minute)
        let wordCount = text.components(separatedBy: .whitespaces).count
        duration = TimeInterval(wordCount) / 150.0 * 60.0 // seconds
        
        currentUtterance = utterance
        synthesizer.speak(utterance)
        isPlaying = true
        startTime = Date()
        
        startTimer()
    }
    
    /// Play or resume
    func play() {
        if !synthesizer.isSpeaking {
            // Resume from current position if we have an utterance
            if let utterance = currentUtterance {
                synthesizer.speak(utterance)
                isPlaying = true
                startTimer()
            }
        }
    }
    
    /// Pause playback
    func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
        isPlaying = false
        stopTimer()
    }
    
    /// Stop playback
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        currentTime = 0
        stopTimer()
        currentUtterance = nil
    }
    
    /// Skip forward by 15 seconds
    func skipForward15() {
        // AVSpeechSynthesizer doesn't support precise seeking
        // We'll restart from a later point in the text
        // For now, just pause/resume as a workaround
        // In production, consider using a more advanced TTS service with seeking support
        pause()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.play()
        }
    }
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.startTime else { return }
            self.currentTime = Date().timeIntervalSince(startTime)
            if self.currentTime >= self.duration {
                self.stop()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension TTSPlayback: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = self.duration
            self.stopTimer()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.stopTimer()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = true
        }
    }
}

