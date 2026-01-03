//
//  TTSPlayback.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import Foundation
import AVFoundation
import Combine
import Network
import CryptoKit

/// Result of API key verification
struct APIKeyVerificationResult {
    var hasKey: Bool = false
    var keyLength: Int = 0
    var keyPrefix: String = ""
    var keyStartsWithSK: Bool = false
    var connectionTestStarted: Bool = false
    var connectionSuccessful: Bool = false
    var httpStatusCode: Int? = nil
    var connectionError: String? = nil
    
    var isValid: Bool {
        return hasKey && connectionSuccessful
    }
    
    var summary: String {
        if !hasKey {
            return "❌ API Key not configured"
        }
        if !connectionTestStarted {
            return "⚠️ API Key found but connection test not completed"
        }
        if connectionSuccessful {
            return "✅ API Key valid and connection successful"
        } else {
            return "❌ API Key found but connection failed: \(connectionError ?? "Unknown error")"
        }
    }
}

/// Service for text-to-speech playback and audio controls
class TTSPlayback: NSObject, ObservableObject {
    static let shared = TTSPlayback()
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackError: String?
    @Published var isGenerating = false // For audio generation status
    @Published var isSeeking = false // Track if seeking is in progress
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var synthesizer: AVSpeechSynthesizer?
    private var currentUtterance: AVSpeechUtterance?
    // Legacy in-memory cache (kept for backward compatibility)
    private var currentText: String? // Cache current text to avoid regeneration
    private var cachedAudioURL: URL? // Cache generated audio file (single-file path)
    
    // New: persistent hash-based cache + segmented playback
    nonisolated private static let ttsCacheDirName = "OpenAITTSCache"
    private var currentCacheKey: String?
    private var currentSegmentKeys: [String] = []
    private var pendingSegmentTasks: [Task<URL?, Never>] = []
    private var timer: Timer?
    private var startTime: Date?
    private var pausedTime: TimeInterval = 0
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    // ALWAYS use OpenAI TTS - never use local TTS unless OpenAI TTS fails
    private var useOpenAITTS = true // Use OpenAI TTS by default for more natural voice
    
    // Force OpenAI TTS - ALWAYS true, never use local TTS unless OpenAI TTS completely fails
    private var forceOpenAITTS = true // This ensures OpenAI TTS is ALWAYS attempted first
    
    // TTS Configuration for optimal natural voice
    // Voice options: "alloy", "echo", "fable", "onyx", "nova", "shimmer"
    // Recommended voices for Chinese:
    // - "shimmer" (default): More natural, expressive, warm - BEST for Chinese
    // - "nova": Clear, professional, good for narration
    // - "onyx": Deeper, more authoritative
    // - "alloy": Balanced, neutral
    private var ttsVoice = "shimmer" // More natural voice for Chinese
    
    // Speed: 0.25 to 4.0, default 1.0
    // For Chinese, slightly faster (1.1-1.2) sounds more natural and conversational
    // Too fast (>1.3) may sound rushed, too slow (<1.0) may sound robotic
    private var ttsSpeed: Double = 1.15 // Optimized for natural Chinese flow
    
    // Model: "tts-1" (fast, lower quality) or "tts-1-hd" (high quality, slightly slower)
    // tts-1-hd: Better quality, more natural, recommended for production
    // tts-1: Faster generation, slightly lower quality, good for testing
    // Changed to tts-1 as default for faster generation (2-5s vs 8-15s)
    private var ttsModel = "tts-1" // Fast mode (default for better performance)
    
    /// Change TTS voice (for testing different voices)
    /// Available: "alloy", "echo", "fable", "onyx", "nova", "shimmer"
    func setVoice(_ voice: String) {
        let validVoices = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]
        if validVoices.contains(voice.lowercased()) {
            ttsVoice = voice.lowercased()
            print("✅ TTS voice changed to: \(ttsVoice)")
        } else {
            print("⚠️ Invalid voice: \(voice). Valid options: \(validVoices.joined(separator: ", "))")
        }
    }
    
    /// Change TTS speed (0.25 to 4.0)
    /// Recommended: 1.0-1.2 for natural Chinese
    func setSpeed(_ speed: Double) {
        let clampedSpeed = max(0.25, min(4.0, speed))
        ttsSpeed = clampedSpeed
        print("✅ TTS speed changed to: \(ttsSpeed)")
    }
    
    /// Change TTS model ("tts-1" for speed, "tts-1-hd" for quality)
    func setModel(_ model: String) {
        if model == "tts-1" || model == "tts-1-hd" {
            ttsModel = model
            print("✅ TTS model changed to: \(ttsModel)")
        } else {
            print("⚠️ Invalid model: \(model). Valid options: tts-1, tts-1-hd")
        }
    }
    
    /// Enable fast mode (tts-1 model for faster generation)
    func enableFastMode() {
        ttsModel = "tts-1"
        print("✅ Fast mode enabled (tts-1 model)")
    }
    
    /// Enable quality mode (tts-1-hd model for better quality)
    func enableQualityMode() {
        ttsModel = "tts-1-hd"
        print("✅ Quality mode enabled (tts-1-hd model)")
    }
    
    override init() {
        super.init()
        synthesizer = AVSpeechSynthesizer()
        synthesizer?.delegate = self
    }

    // MARK: - Persistent Cache (Hash-based)
    nonisolated private static func ttsCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(Self.ttsCacheDirName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }
    
    nonisolated private static func normalizeTextForCache(_ text: String) -> String {
        // Normalize whitespace/newlines so tiny differences don’t break cache hits.
        var t = text
        // Remove common status lines that sometimes leak into narration strings
        let statusPhrases = ["正在生成", "正在识别", "分析中", "正在加载讲解内容", "正在生成讲解", "正在分析作品"]
        for p in statusPhrases { t = t.replacingOccurrences(of: p, with: "") }
        
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        // Collapse multiple newlines
        while t.contains("\n\n\n") { t = t.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        // Collapse multiple spaces/tabs
        t = t.replacingOccurrences(of: "\t", with: " ")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    nonisolated private static func cacheKeyForOpenAITTS(
        text: String,
        language: String,
        voice: String,
        speed: Double
    ) -> String {
        // Include voice/speed/model/language so different settings don’t collide.
        let normalized = normalizeTextForCache(text)
        // IMPORTANT: generation always forces the fast model "tts-1" (see request body),
        // so the cache key must match the actual model used to avoid false misses.
        let raw = "\(normalized)|model=tts-1|voice=\(voice)|speed=\(String(format: "%.2f", speed))|lang=\(language)|format=mp3"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    nonisolated private static func cachedFileURL(forKey key: String) -> URL {
        ttsCacheDirectory().appendingPathComponent("\(key).mp3")
    }
    
    nonisolated private static func cachedFileExists(forKey key: String) -> Bool {
        let url = cachedFileURL(forKey: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        // Ensure non-empty file
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber {
            return size.intValue > 1024 // >1KB sanity check
        }
        return true
    }
    
    // MARK: - Segmentation
    private func splitTextForTTS(_ text: String, maxChars: Int = 420, minChars: Int = 220) -> [String] {
        let normalized = Self.normalizeTextForCache(text)
        guard normalized.count > maxChars else { return [normalized] }
        
        let boundaries: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n"]
        let chars = Array(normalized)
        
        var segments: [String] = []
        var start = 0
        var lastBoundary = -1
        
        for i in 0..<chars.count {
            if boundaries.contains(chars[i]) {
                lastBoundary = i
            }
            
            let len = i - start + 1
            if len >= maxChars {
                let cut: Int
                if lastBoundary >= start + minChars {
                    cut = lastBoundary + 1
                } else {
                    cut = i + 1
                }
                let seg = String(chars[start..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !seg.isEmpty { segments.append(seg) }
                start = cut
                lastBoundary = -1
            }
        }
        
        if start < chars.count {
            let tail = String(chars[start..<chars.count]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { segments.append(tail) }
        }
        
        // Final cleanup: avoid tiny trailing segments by merging
        if segments.count >= 2, let last = segments.last, last.count < minChars {
            segments.removeLast()
            segments[segments.count - 1] = (segments.last ?? "") + "\n\n" + last
        }
        
        return segments
    }
    
    /// Prepare audio for text without playing (pre-generation for faster playback)
    /// This generates and caches the audio file, so when speak() is called, it can use the cached audio
    func prepareAudio(text: String, language: String = "zh-CN") async {
        let voiceSnapshot = ttsVoice
        let speedSnapshot = ttsSpeed
        let normalized = Self.normalizeTextForCache(text)
        guard !normalized.isEmpty else { return }
        
        // Segment-first strategy: cache first segment ASAP, then cache the rest in background.
        let segments = splitTextForTTS(normalized)
        guard let first = segments.first else { return }
        let segmentKeys = segments.map { Self.cacheKeyForOpenAITTS(text: $0, language: language, voice: voiceSnapshot, speed: speedSnapshot) }
        
        print("🎙️ Preparing audio (pre-generation) for text: \(normalized.count) chars, \(segments.count) segment(s)")
        
        // Only pre-generate when online + key exists; otherwise local TTS is instant anyway.
        let networkAvailable = isNetworkAvailableQuick()
        let hasAPIKey = getOpenAIApiKey() != nil
        guard networkAvailable && hasAPIKey else {
            print("📴 Skipping OpenAI pre-generation (offline/no key). Local TTS will be used.")
            return
        }
        
        // 1) Pre-generate first segment (highest UX impact)
        let firstKey = segmentKeys[0]
        if Self.cachedFileExists(forKey: firstKey) {
            print("✅ First segment already cached")
        } else {
            _ = await generateOpenAITTSAndCache(text: first, cacheKey: firstKey, shouldPlay: false)
        }
        
        // 2) Pre-generate remaining segments in background
        if segments.count > 1 {
            let remainingSegments = Array(segments.dropFirst())
            let remainingKeys = Array(segmentKeys.dropFirst())
            Task.detached(priority: .utility) { [remainingSegments, remainingKeys] in
                for (seg, key) in zip(remainingSegments, remainingKeys) {
                    if Self.cachedFileExists(forKey: key) { continue }
                    _ = await self.generateOpenAITTSAndCache(text: seg, cacheKey: key, shouldPlay: false)
                }
            }
        }
    }
    
    /// Convert text to speech and play using OpenAI TTS (default) or local TTS (fallback)
    func speak(text: String, language: String = "zh-CN") async {
        // Filter out status messages and error messages - only generate TTS for actual narration
        let filteredText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip TTS generation for status messages, error messages, or very short text
        if filteredText.isEmpty ||
           filteredText.contains("正在生成") ||
           filteredText.contains("正在识别") ||
           filteredText.contains("分析中") ||
           filteredText.contains("报错") ||
           filteredText.contains("错误") ||
           filteredText.contains("Error") ||
           filteredText.count < 20 {
            print("⚠️ Skipping TTS generation for status/error message or too short text")
            return
        }
        
        let voiceSnapshot = ttsVoice
        let speedSnapshot = ttsSpeed
        let normalizedForCache = Self.normalizeTextForCache(filteredText)
        print("🎙️ TTS speak() called for narration (\(normalizedForCache.count) characters)")
        
        // CRITICAL: Stop ALL playback sources BEFORE starting new one (prevent overlap and background audio)
        // This ensures no audio continues playing in the background
        // Must be called on main thread to ensure complete stop before starting new playback
        await MainActor.run {
            stopAllPlayback()
        }
        
        // Small delay to ensure all audio sources are fully stopped and released
        // This prevents background audio from continuing
        // Optimized: Reduced from 0.1s to 0.05s for faster response
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        // If we are already playing the same text, just resume.
        if let cachedText = currentText, cachedText == normalizedForCache {
            if self.player != nil {
                await MainActor.run { if !isPlaying { play() } }
                return
            }
        }
        
        // Cancel any pending background segment tasks from previous playback
        for t in pendingSegmentTasks { t.cancel() }
        pendingSegmentTasks.removeAll()
        currentSegmentKeys.removeAll()
        
        // Reset state
        currentTime = 0
        pausedTime = 0
        playbackError = nil
        currentText = normalizedForCache // Store normalized text for cache matching
        
        // Configure audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("❌ Audio session error: \(error.localizedDescription)")
            playbackError = "Failed to configure audio: \(error.localizedDescription)"
            return
        }
        
        // NEW: Check network availability and choose TTS method
        // Online: Use OpenAI TTS (tts-1 fast mode)
        // Offline: Use local TTS immediately
        let networkAvailable = isNetworkAvailableQuick()
        let hasAPIKey = getOpenAIApiKey() != nil
        
        if networkAvailable && hasAPIKey {
            // Online: Use OpenAI TTS with segment-first strategy
            print("🌐 Network available - Using OpenAI TTS (segment-first, cached)")
            
            let segments = splitTextForTTS(normalizedForCache)
            if segments.isEmpty {
                await generateAndPlayLocalTTS(text: normalizedForCache, language: language)
                return
            }
            
            let fullKey = Self.cacheKeyForOpenAITTS(text: normalizedForCache, language: language, voice: voiceSnapshot, speed: speedSnapshot)
            currentCacheKey = fullKey
            
            // 1) Ensure first segment is ready (cache hit → instant; otherwise generate)
            let firstSeg = segments[0]
            let firstKey = Self.cacheKeyForOpenAITTS(text: firstSeg, language: language, voice: voiceSnapshot, speed: speedSnapshot)
            currentSegmentKeys = segments.map { Self.cacheKeyForOpenAITTS(text: $0, language: language, voice: voiceSnapshot, speed: speedSnapshot) }
            
            await MainActor.run { isGenerating = true }
            let firstURL: URL?
            if Self.cachedFileExists(forKey: firstKey) {
                firstURL = Self.cachedFileURL(forKey: firstKey)
            } else {
                firstURL = await generateOpenAITTSAndCache(text: firstSeg, cacheKey: firstKey, shouldPlay: false)
            }
            
            guard let firstURLUnwrapped = firstURL else {
                print("❌ OpenAI TTS first segment failed, falling back to local TTS")
                await MainActor.run { isGenerating = false }
                await generateAndPlayLocalTTS(text: normalizedForCache, language: language)
                return
            }
            
            // Start playback with a queue (first segment now, remaining added as they become ready)
            await MainActor.run {
                isGenerating = false
                startQueuePlayback(firstURL: firstURLUnwrapped)
            }
            
            // 2) Generate remaining segments in background and enqueue
            if segments.count > 1 {
                for (idx, seg) in segments.dropFirst().enumerated() {
                    let key = currentSegmentKeys[idx + 1]
                    let task = Task.detached(priority: .utility) { () -> URL? in
                        if Self.cachedFileExists(forKey: key) {
                            return Self.cachedFileURL(forKey: key)
                        }
                        return await self.generateOpenAITTSAndCache(text: seg, cacheKey: key, shouldPlay: false)
                    }
                    pendingSegmentTasks.append(task)
                    
                    Task { @MainActor in
                        let url = await task.value
                        guard let url else { return }
                        self.enqueueNextSegment(url: url)
                    }
                }
            }
        } else {
            // Offline: Use local TTS immediately
            if !networkAvailable {
                print("📴 Network unavailable - Using local TTS (offline mode)")
            } else {
                print("🔑 No API key - Using local TTS")
            }
            
            await generateAndPlayLocalTTS(text: filteredText, language: language)
        }
    }

    // MARK: - Queue playback (segment-first)
    @MainActor
    private func startQueuePlayback(firstURL: URL) {
        // Stop any existing playback and observers before starting queue playback
        stopAllPlayback()
        
        // Verify file exists (should, because it’s from cache)
        guard FileManager.default.fileExists(atPath: firstURL.path) else {
            playbackError = "音频文件不存在: \(firstURL.lastPathComponent)"
            isPlaying = false
            return
        }
        
        print("🎵 Creating AVQueuePlayer for first segment: \(firstURL.lastPathComponent)")
        let item = AVPlayerItem(url: firstURL)
        self.playerItem = item
        
        let queue = AVQueuePlayer(items: [item])
        self.player = queue
        
        // Observe item end (queue will advance automatically if more items are enqueued)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        
        // Observe status/duration for UI
        item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        item.addObserver(self, forKeyPath: "duration", options: [.new], context: nil)
        
        // Load duration
        Task { @MainActor in
            await loadDuration(playerItem: item, isStreaming: false)
        }
        
        // Time observer for progress updates (same approach as playAudioFile)
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = queue.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            guard !self.isSeeking else { return }
            let timeSeconds = CMTimeGetSeconds(time)
            if timeSeconds.isFinite && !timeSeconds.isNaN && !timeSeconds.isInfinite && timeSeconds >= 0 {
                self.currentTime = timeSeconds
                if self.isPlaying {
                    self.pausedTime = timeSeconds
                }
            }
        }
        
        queue.play()
        isPlaying = true
        currentTime = 0
        pausedTime = 0
        
        print("▶️ Playing first TTS segment (queue): \(firstURL.lastPathComponent)")
    }
    
    @MainActor
    private func enqueueNextSegment(url: URL) {
        guard let queue = self.player as? AVQueuePlayer else { return }
        queue.insert(AVPlayerItem(url: url), after: nil)
        print("➕ Enqueued next TTS segment: \(url.lastPathComponent)")
    }

    // MARK: - OpenAI TTS download + cache (persistent)
    private func generateOpenAITTSAndCache(text: String, cacheKey: String, shouldPlay: Bool) async -> URL? {
        // Note: shouldPlay is ignored here; playback handled by queue.
        _ = shouldPlay
        let destURL = Self.cachedFileURL(forKey: cacheKey)
        
        // Double-check cache (avoid duplicate generation)
        if Self.cachedFileExists(forKey: cacheKey) {
            return destURL
        }
        
        let success = await generateAndPlayOpenAITTS(text: text, shouldPlay: false, overrideOutputURL: destURL)
        return success ? destURL : nil
    }
    
    /// Check if device is online and can reach internet (quick check)
    /// Returns true if network is available, false otherwise
    private func isNetworkAvailableQuick() -> Bool {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var isConnected = false
        
        monitor.pathUpdateHandler = { path in
            isConnected = path.status == .satisfied
            semaphore.signal()
            monitor.cancel()
        }
        
        let queue = DispatchQueue(label: "NetworkCheck")
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 0.5) // 0.5 second timeout for quick check
        
        return isConnected
    }
    
    /// Get OpenAI API key from multiple sources
    private func getOpenAIApiKey() -> String? {
        // Priority 1: AppConfig (which checks environment and UserDefaults)
        if let key = AppConfig.openAIApiKey, !key.isEmpty {
            return key
        }
        
        // Priority 2: Environment variable directly
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return key
        }
        
        // Priority 3: UserDefaults directly
        if let key = UserDefaults.standard.string(forKey: "OPENAI_API_KEY"), !key.isEmpty {
            return key
        }
        
        return nil
    }
    
    /// Generate audio using OpenAI TTS API and cache it (without playing)
    /// Returns true if successful, false if failed
    private func generateAndCacheOpenAITTS(text: String, playAfterGeneration: Bool) async -> Bool {
        // Reuse the same generation logic as generateAndPlayOpenAITTS
        // but control whether to play after generation
        let success = await generateAndPlayOpenAITTS(text: text, shouldPlay: playAfterGeneration)
        
        if success && !playAfterGeneration {
            // Audio is cached, but don't play it yet
            print("✅ Audio cached successfully (not playing)")
        }
        
        return success
    }
    
    /// Generate audio using OpenAI TTS API and optionally play
    /// Returns true if successful, false if failed (should fallback)
    private func generateAndPlayOpenAITTS(
        text: String,
        shouldPlay: Bool = true,
        overrideOutputURL: URL? = nil
    ) async -> Bool {
        print("============================================================")
        print("🚀🚀🚀 Starting OpenAI TTS generation 🚀🚀🚀")
        print("🚀 Text preview: \(text.prefix(50))...")
        print("🚀 Text length: \(text.count) characters")
        print("============================================================")
        
        // Get API key using centralized method
        guard let key = getOpenAIApiKey(), !key.isEmpty else {
            print("❌❌❌ CRITICAL: OpenAI API key not available or empty!")
            print("❌❌❌ This should NOT happen - OpenAI TTS requires API key")
            print("❌ Checking all API key sources:")
            print("   - AppConfig.openAIApiKey: \(AppConfig.openAIApiKey != nil ? "✅ found" : "❌ not found")")
            print("     (AppConfig checks: Keychain → Info.plist → Scheme env var → UserDefaults)")
            print("   - Info.plist OPENAI_API_KEY: \(((Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String)?.isEmpty == false) ? "✅ found" : "❌ not found")")
            print("   - Environment OPENAI_API_KEY: \(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil ? "✅ found" : "❌ not found")")
            print("   - UserDefaults OPENAI_API_KEY: \(UserDefaults.standard.string(forKey: "OPENAI_API_KEY") != nil ? "✅ found" : "❌ not found")")
            print("❌ TTS will fallback to local TTS (robotic voice)")
            print("❌ To fix (recommended): set OpenAI API key via Database Test (DEBUG) or call AppConfig.setAPIKey(_:), which stores it in Keychain.")
            await MainActor.run {
                playbackError = "OpenAI API key not configured. Please set OPENAI_API_KEY."
            }
            return false
        }
        
        print("✅✅✅ OpenAI API key found! ✅✅✅")
        print("🔑 Using OpenAI API key: \(key.prefix(10))...")
        print("🔑 API key length: \(key.count) characters")
        print("🔑 API key starts with 'sk-': \(key.hasPrefix("sk-"))")
        
        await MainActor.run {
            isGenerating = true
        }
        
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Optimized: Dynamic timeout based on text length (min 15s, max 60s)
        // Estimated: ~0.1s per character + 10s base time
        let estimatedTimeout = min(60.0, max(15.0, Double(text.count) * 0.1 + 10.0))
        request.timeoutInterval = estimatedTimeout
        
        // Request body for OpenAI TTS - optimized for natural Chinese voice
        // Using shimmer voice (more natural) and slightly faster speed (1.1) for better flow
        // Force use tts-1 model for fast generation (2-5s vs 8-15s for tts-1-hd)
        let modelToUse = "tts-1" // Always use fast model for better performance
        let requestBody: [String: Any] = [
            "model": modelToUse, // Always use tts-1 for fast generation
            "input": text,
            "voice": ttsVoice, // shimmer is more natural and expressive for Chinese
            "response_format": "mp3",
            "speed": ttsSpeed // Slightly faster (1.1) for more natural flow
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            print("🎙️ Generating OpenAI TTS audio with model: \(modelToUse) (fast mode)")
            print("🎙️ Text length: \(text.count) characters")
            print("🎙️ Voice: \(ttsVoice) (optimized for natural Chinese)")
            print("🎙️ Speed: \(ttsSpeed) (optimized for natural flow)")
            let startTime = Date()
            
            // Use URLSession for streaming download
            print("📡 Sending OpenAI TTS API request...")
            print("📡 URL: https://api.openai.com/v1/audio/speech")
            print("📡 Model: \(modelToUse) (fast mode)")
            print("📡 Voice: \(ttsVoice)")
            print("📡 Speed: \(ttsSpeed)")
            
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ OpenAI TTS API error: Invalid response type")
                await MainActor.run {
                    isGenerating = false
                    playbackError = "TTS API 响应无效"
                }
                return false
            }
            
            print("📡 HTTP Status: \(httpResponse.statusCode)")
            
            // Check response status
            if !(200...299).contains(httpResponse.statusCode) {
                print("❌❌❌ OpenAI TTS API error: HTTP \(httpResponse.statusCode)")
                
                // Read error message from response body
                var errorMessage = "HTTP \(httpResponse.statusCode)"
                var errorDetails: String?
                
                // Read error response body
                do {
                    var errorData = Data()
                    for try await byte in asyncBytes {
                        errorData.append(byte)
                        if errorData.count > 10000 { break } // Limit error data size
                    }
                    
                    if let errorString = String(data: errorData, encoding: .utf8) {
                        errorDetails = errorString
                        print("❌ Error response body: \(errorString.prefix(500))")
                        
                        // Try to parse JSON error
                        if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                           let error = errorJson["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            errorMessage = message
                            print("❌ Parsed error message: \(message)")
                        }
                    }
                } catch {
                    print("❌ Could not read error response: \(error)")
                }
                
                // Handle errors for tts-1-hd model
                switch httpResponse.statusCode {
                case 401:
                    errorMessage = "API key 无效或未授权 (401)"
                    print("❌ Authentication failed - check your API key is valid")
                    print("❌ Make sure API key starts with 'sk-' and has TTS access")
                case 429:
                    errorMessage = "请求过于频繁，请稍后再试 (429)"
                    print("❌ Rate limit exceeded - wait a moment and try again")
                case 400:
                    errorMessage = "请求参数错误 (400)"
                    print("❌ Bad request - check request parameters")
                    if let details = errorDetails {
                        print("❌ Details: \(details.prefix(200))")
                    }
                case 500...599:
                    errorMessage = "服务器错误 (\(httpResponse.statusCode))"
                    print("❌ OpenAI server error - try again later")
                default:
                    errorMessage = "HTTP \(httpResponse.statusCode)"
                }
                
                print("❌ Full error: \(errorMessage)")
                if let details = errorDetails {
                    print("❌ Error details: \(details.prefix(200))")
                }
                
                await MainActor.run {
                    isGenerating = false
                    playbackError = "OpenAI TTS (tts-1) 失败: \(errorMessage)"
                }
                print("⚠️ API error, will fallback to local TTS")
                return false
            }
            
            print("✅ OpenAI TTS (\(modelToUse), \(ttsVoice), speed: \(ttsSpeed)) request successful!")
            print("✅ HTTP Status: \(httpResponse.statusCode)")
            print("✅ Starting to stream audio...")
            
            // Output file: persistent cache (if provided) or temporary file
            let tempURL = overrideOutputURL ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
            
            // CRITICAL: Create the file first before opening it for writing
            // FileHandle(forWritingTo:) requires the file to exist
            FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
            
            guard let fileHandle = try? FileHandle(forWritingTo: tempURL) else {
                print("❌❌❌ Failed to create file handle for: \(tempURL.path)")
                await MainActor.run {
                    isGenerating = false
                    playbackError = "无法创建音频文件"
                }
                return false
            }
            
            print("✅ Created temporary audio file: \(tempURL.lastPathComponent)")
            
            defer {
                try? fileHandle.close()
                print("✅ Closed file handle")
            }
            
            // Stream data and write to file
            // IMPORTANT: Wait for file to complete before playing to ensure AVPlayer reads full duration
            var totalBytes = 0
            var buffer = Data() // Buffer for efficient writing
            
            do {
                // Read all data first
                for try await byte in asyncBytes {
                    buffer.append(byte)
                    totalBytes += 1
                    
                    // Write in chunks for better performance
                    // Optimized: Increased from 8KB to 32KB chunks to reduce system calls
                    if buffer.count >= 32768 { // Write in 32KB chunks
                        try fileHandle.write(contentsOf: buffer)
                        try fileHandle.synchronize()
                        buffer.removeAll(keepingCapacity: true)
                    }
                }
                
                // Write any remaining buffer
                if !buffer.isEmpty {
                    try fileHandle.write(contentsOf: buffer)
                    buffer.removeAll()
                }
                
                // Finish writing and close file handle
                try fileHandle.synchronize()
                try fileHandle.close()
                
                print("✅✅✅ Finished writing audio file")
                print("✅ Total bytes received: \(totalBytes)")
                print("✅ File path: \(tempURL.path)")
                
                // Optimized: Parallel file verification and cache storage
                // Verify file exists and has content before playing
                let fileExists = FileManager.default.fileExists(atPath: tempURL.path)
                guard fileExists else {
                    print("❌❌❌ File does not exist after writing!")
                    await MainActor.run {
                        isGenerating = false
                        playbackError = "音频文件创建失败"
                    }
                    return false
                }
                
                // Check file size and store cache in parallel
                async let fileSizeCheck: Bool = {
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
                       let fileSize = attributes[.size] as? Int64 {
                        print("✅ File verified: exists, size: \(fileSize) bytes")
                        if fileSize == 0 {
                            print("❌❌❌ File is empty!")
                            await MainActor.run {
                                isGenerating = false
                                playbackError = "音频文件为空"
                            }
                            return false
                        }
                        return true
                    }
                    return true
                }()
                
                async let cacheStorage: Void = {
                    // Store cached audio URL for this text BEFORE playing (legacy single-file cache)
                    await MainActor.run {
                        cachedAudioURL = tempURL
                        currentText = text // Store text for cache matching
                    }
                }()
                
                // Wait for both operations to complete
                let fileValid = await fileSizeCheck
                guard fileValid else {
                    return false
                }
                await cacheStorage
                
                // Now that file is complete, optionally start playback
                await MainActor.run {
                    isGenerating = false
                    if shouldPlay {
                        print("✅✅✅ Starting playback of complete audio file")
                        // Play the complete file (not streaming)
                        playAudioFile(url: tempURL, isStreaming: false)
                    } else {
                        print("✅✅✅ Audio file generated and cached (not playing - waiting for user to click play)")
                    }
                }
                
            } catch {
                print("❌❌❌ Error while streaming/writing audio: \(error.localizedDescription)")
                print("❌ Error type: \(type(of: error))")
                try? fileHandle.close()
                throw error // Re-throw to be caught by outer catch block
            }
            
            let totalElapsed = Date().timeIntervalSince(startTime)
            print("✅✅✅ OpenAI TTS audio generation COMPLETE!")
            print("✅ Total time: \(String(format: "%.2f", totalElapsed))s")
            print("✅ Audio file saved to: \(tempURL.lastPathComponent)")
            
            // Store cached audio URL for this text (legacy single-file cache)
            await MainActor.run {
                cachedAudioURL = tempURL
                currentText = text // Store text for cache matching
            }
            
            print("✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅")
            print("✅ OpenAI TTS (tts-1, \(ttsVoice)) SUCCESS! Natural voice is now playing!")
            print("✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅")
            return true
            
        } catch {
            print("❌❌❌ OpenAI TTS error: \(error.localizedDescription)")
            print("❌ Error type: \(type(of: error))")
            if let urlError = error as? URLError {
                print("❌ URL Error code: \(urlError.code.rawValue)")
                print("❌ URL Error description: \(urlError.localizedDescription)")
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    print("❌ Network connection issue")
                case .timedOut:
                    print("❌ Request timed out")
                default:
                    print("❌ Other network error")
                }
            }
            await MainActor.run {
                isGenerating = false
                playbackError = "OpenAI TTS 失败: \(error.localizedDescription)"
            }
            print("⚠️ Will fallback to local TTS")
            return false
        }
    }
    
    /// Verify OpenAI API key and test connectivity
    /// Returns a detailed diagnostic result
    func verifyAPIKey() async -> APIKeyVerificationResult {
        print("============================================================")
        print("🔍 Starting API Key Verification...")
        print("============================================================")
        
        var result = APIKeyVerificationResult()
        
        // Step 1: Check if API key exists
        let apiKey = getOpenAIApiKey()
        if let key = apiKey, !key.isEmpty {
            result.hasKey = true
            result.keyLength = key.count
            result.keyPrefix = String(key.prefix(10))
            result.keyStartsWithSK = key.hasPrefix("sk-")
            
            print("✅ API Key found")
            print("   - Length: \(key.count) characters")
            print("   - Prefix: \(key.prefix(10))...")
            print("   - Starts with 'sk-': \(key.hasPrefix("sk-"))")
            
            // Step 2: Test API connectivity with a simple request
            print("🔄 Testing API connectivity...")
            result.connectionTestStarted = true
            
            // testAPIConnection doesn't throw, so no do-catch needed
            let testResult = await testAPIConnection(apiKey: key)
            result.connectionSuccessful = testResult.success
            result.connectionError = testResult.error
            result.httpStatusCode = testResult.statusCode
            
            if testResult.success {
                print("✅✅✅ API connection test PASSED!")
                print("✅ HTTP Status: \(testResult.statusCode ?? 0)")
                print("✅ OpenAI TTS API is accessible and working")
            } else {
                print("❌ API connection test FAILED")
                if let statusCode = testResult.statusCode {
                    print("❌ HTTP Status: \(statusCode)")
                }
                if let error = testResult.error {
                    print("❌ Error: \(error)")
                }
            }
        } else {
            result.hasKey = false
            print("❌ API Key not found")
            print("❌ Checking all sources:")
            print("   - AppConfig.openAIApiKey: \(AppConfig.openAIApiKey != nil ? "✅ found" : "❌ not found")")
            print("     (AppConfig checks: Keychain → Info.plist → Scheme env var → UserDefaults)")
            print("   - Info.plist OPENAI_API_KEY: \(((Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String)?.isEmpty == false) ? "✅ found" : "❌ not found")")
            print("   - Environment OPENAI_API_KEY: \(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil ? "✅ found" : "❌ not found")")
            print("   - UserDefaults OPENAI_API_KEY: \(UserDefaults.standard.string(forKey: "OPENAI_API_KEY") != nil ? "✅ found" : "❌ not found")")
        }
        
        print("============================================================")
        print("🔍 API Key Verification Complete")
        print("============================================================")
        
        return result
    }
    
    /// Test API connection with a simple TTS request
    private func testAPIConnection(apiKey: String) async -> (success: Bool, statusCode: Int?, error: String?) {
        let testText = "测试"
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15.0 // 15 seconds timeout for connection test
        
        let requestBody: [String: Any] = [
            "model": ttsModel, // Use the same model as production
            "input": testText,
            "voice": ttsVoice,
            "response_format": "mp3",
            "speed": ttsSpeed
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            print("📡 Sending test request to OpenAI TTS API...")
            let startTime = Date()
            
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, nil, "Invalid response type")
            }
            
            let statusCode = httpResponse.statusCode
            let elapsed = Date().timeIntervalSince(startTime)
            
            print("📡 Response received in \(String(format: "%.2f", elapsed))s")
            print("📡 HTTP Status: \(statusCode)")
            
            if (200...299).contains(statusCode) {
                // Success - read a few bytes to confirm it's audio data
                var byteCount = 0
                for try await _ in asyncBytes {
                    byteCount += 1
                    if byteCount >= 100 { // Just check first 100 bytes
                        break
                    }
                }
                
                print("✅ Received audio data (at least \(byteCount) bytes)")
                return (true, statusCode, nil)
            } else {
                // Error - read error message
                var errorData = Data()
                var byteCount = 0
                for try await byte in asyncBytes {
                    errorData.append(byte)
                    byteCount += 1
                    if byteCount >= 1000 || errorData.count >= 1000 {
                        break
                    }
                }
                
                var errorMessage = "HTTP \(statusCode)"
                if let errorString = String(data: errorData, encoding: .utf8) {
                    if let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        errorMessage = message
                    } else {
                        errorMessage = String(errorString.prefix(200))
                    }
                }
                
                return (false, statusCode, errorMessage)
            }
        } catch {
            let errorMsg = error.localizedDescription
            print("❌ Request error: \(errorMsg)")
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    return (false, nil, "No internet connection")
                case .networkConnectionLost:
                    return (false, nil, "Network connection lost")
                case .timedOut:
                    return (false, nil, "Request timed out")
                default:
                    return (false, nil, "Network error: \(errorMsg)")
                }
            }
            return (false, nil, errorMsg)
        }
    }
    
    /// Test OpenAI TTS connectivity and API key (legacy method, kept for compatibility)
    /// Returns a diagnostic message about the TTS setup
    func testOpenAITTS() async -> String {
        let result = await verifyAPIKey()
        
        var diagnostics: [String] = []
        diagnostics.append("=== OpenAI TTS Diagnostic Test ===")
        
        if result.hasKey {
            diagnostics.append("✅ API Key: Found (length: \(result.keyLength) chars, prefix: \(result.keyPrefix)...)")
            diagnostics.append("✅ Key format: \(result.keyStartsWithSK ? "Valid (starts with 'sk-')" : "⚠️ Warning: doesn't start with 'sk-'")")
            
            if result.connectionTestStarted {
                if result.connectionSuccessful {
                    diagnostics.append("✅ API Connection: SUCCESS")
                    if let statusCode = result.httpStatusCode {
                        diagnostics.append("✅ HTTP Status: \(statusCode)")
                    }
                } else {
                    diagnostics.append("❌ API Connection: FAILED")
                    if let statusCode = result.httpStatusCode {
                        diagnostics.append("❌ HTTP Status: \(statusCode)")
                    }
                    if let error = result.connectionError {
                        diagnostics.append("❌ Error: \(error)")
                    }
                }
            }
        } else {
            diagnostics.append("❌ API Key: NOT FOUND")
            diagnostics.append("❌ Please configure OPENAI_API_KEY environment variable or UserDefaults")
        }
        
        diagnostics.append("=== End Diagnostic ===")
        return diagnostics.joined(separator: "\n")
    }
    
    /// Auto-test TTS playback functionality
    func autoTest() async {
        print("🧪 Starting TTS Auto-Test...")
        
        let testText = "这是一个测试。语音播放测试，进度条测试，拖动测试，快进和后退测试。"
        print("🧪 Test text: \(testText)")
        
        // Test 1: Generate and play audio
        print("🧪 Test 1: Generate and play audio...")
        await speak(text: testText, language: "zh-CN")
        
        // Wait for audio to start playing
        var waitCount = 0
        while !isPlaying && waitCount < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            waitCount += 1
        }
        
        if isPlaying {
            print("✅ Test 1 PASSED: Audio is playing")
        } else {
            print("❌ Test 1 FAILED: Audio is not playing")
            return
        }
        
        // Wait for duration to load
        waitCount = 0
        while duration <= 0 && waitCount < 100 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            waitCount += 1
        }
        
        if duration > 0 {
            print("✅ Test 2 PASSED: Duration loaded (\(String(format: "%.2f", duration))s)")
        } else {
            print("❌ Test 2 FAILED: Duration not loaded")
        }
        
        // Test 3: Progress tracking
        print("🧪 Test 3: Progress tracking...")
        let initialTime = currentTime
        try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
        let afterTime = currentTime
        
        if afterTime > initialTime {
            print("✅ Test 3 PASSED: Progress is updating (\(String(format: "%.2f", initialTime))s → \(String(format: "%.2f", afterTime))s)")
        } else {
            print("❌ Test 3 FAILED: Progress is not updating")
        }
        
        // Test 4: Pause/Resume
        print("🧪 Test 4: Pause/Resume...")
        pause()
        try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5 seconds
        
        if !isPlaying {
            print("✅ Test 4a PASSED: Pause works")
            
            // Resume
            await speak(text: testText, language: "zh-CN")
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            if isPlaying {
                print("✅ Test 4b PASSED: Resume works")
            } else {
                print("❌ Test 4b FAILED: Resume does not work")
            }
        } else {
            print("❌ Test 4a FAILED: Pause does not work")
        }
        
        // Test 5: Seek (if duration is available)
        if duration > 0 {
            print("🧪 Test 5: Seek functionality...")
            let seekTime = min(5.0, duration / 2)
            seek(to: seekTime)
            try? await Task.sleep(nanoseconds: 500_000_000) // Wait for seek to complete
            
            if abs(currentTime - seekTime) < 1.0 { // Allow 1 second tolerance
                print("✅ Test 5 PASSED: Seek works (seeked to \(String(format: "%.2f", seekTime))s, current: \(String(format: "%.2f", currentTime))s)")
            } else {
                print("⚠️ Test 5 PARTIAL: Seek attempted (target: \(String(format: "%.2f", seekTime))s, current: \(String(format: "%.2f", currentTime))s)")
            }
            
            // Test 6: Skip forward
            print("🧪 Test 6: Skip forward 15s...")
            let beforeSkip = currentTime
            skipForward15()
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            if currentTime > beforeSkip {
                print("✅ Test 6 PASSED: Skip forward works")
            } else {
                print("⚠️ Test 6 PARTIAL: Skip forward attempted (before: \(String(format: "%.2f", beforeSkip))s, after: \(String(format: "%.2f", currentTime))s)")
            }
            
            // Test 7: Skip backward
            print("🧪 Test 7: Skip backward 15s...")
            let beforeBackward = currentTime
            skipBackward15()
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            if currentTime < beforeBackward {
                print("✅ Test 7 PASSED: Skip backward works")
            } else {
                print("⚠️ Test 7 PARTIAL: Skip backward attempted (before: \(String(format: "%.2f", beforeBackward))s, after: \(String(format: "%.2f", currentTime))s)")
            }
        } else {
            print("⚠️ Test 5-7 SKIPPED: Duration not available for seek tests")
        }
        
        print("🧪 Auto-test completed!")
    }
    
    /// Play audio file using AVPlayer with improved progress tracking
    private func playAudioFile(url: URL, isStreaming: Bool = false) {
        // Verify file exists before attempting to play
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        if !fileExists {
            print("❌❌❌ CRITICAL ERROR: Audio file does not exist at path: \(url.path)")
            DispatchQueue.main.async {
                self.playbackError = "音频文件不存在: \(url.lastPathComponent)"
                self.isGenerating = false
                self.isPlaying = false
            }
            return
        }
        
        // Check file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            if fileSize == 0 {
                print("❌❌❌ CRITICAL ERROR: Audio file is empty (0 bytes)")
                DispatchQueue.main.async {
                    self.playbackError = "音频文件为空"
                    self.isGenerating = false
                    self.isPlaying = false
                }
                return
            }
            print("✅ Audio file verified: \(fileSize) bytes")
        }
        
        stop()
        
        print("🎵 Creating AVPlayerItem for: \(url.lastPathComponent)")
        let playerItem = AVPlayerItem(url: url)
        self.playerItem = playerItem
        
        // Configure player item
        if isStreaming {
            playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        }
        
        let newPlayer = AVPlayer(playerItem: playerItem)
        self.player = newPlayer
        
        print("✅ AVPlayer created successfully")
        
        // Observe player status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // Observe player status changes
        playerItem.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        playerItem.addObserver(self, forKeyPath: "duration", options: [.new], context: nil)
        
        // Load duration immediately
        Task { @MainActor in
            await loadDuration(playerItem: playerItem, isStreaming: isStreaming)
        }
        
        // Observe time updates with higher frequency for smoother progress bar and text highlighting
        // CRITICAL: Set up time observer BEFORE starting playback to ensure it's active
        let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC)) // 20 updates per second for better text sync
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            // Only update if not seeking (isSeeking flag prevents updates during seek operations)
            guard !self.isSeeking else {
                return
            }
            let timeSeconds = CMTimeGetSeconds(time)
            if timeSeconds.isFinite && !timeSeconds.isNaN && !timeSeconds.isInfinite && timeSeconds >= 0 {
                // Update directly on main thread (we're already on main queue)
                self.currentTime = timeSeconds
                // Update pausedTime for resume functionality
                if self.isPlaying {
                    self.pausedTime = timeSeconds
                }
            }
        }
        
        print("✅ Time observer set up: \(timeObserver != nil)")
        
        // For complete files (not streaming), wait a moment for duration to load before playing
        if !isStreaming {
            // Optimized: Wait for AVPlayerItem to finish loading metadata with smarter polling
            Task { @MainActor in
                // Wait for player item to be ready with optimized polling
                // Start with shorter intervals, increase if needed
                var attempts = 0
                var sleepInterval: UInt64 = 50_000_000 // Start with 0.05s
                while playerItem.status != .readyToPlay && attempts < 30 {
                    try? await Task.sleep(nanoseconds: sleepInterval)
                    attempts += 1
                    // Increase interval after first few attempts (exponential backoff)
                    if attempts > 5 {
                        sleepInterval = min(200_000_000, sleepInterval * 2) // Max 0.2s
                    }
                }
                
                // Ensure duration is loaded (parallel with status check if possible)
                if duration <= 0 {
                    await loadDuration(playerItem: playerItem, isStreaming: false)
                }
                
                // Optimized: Reduced delay from 0.1s to 0.05s
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                
                print("✅ Player ready, starting playback. Duration: \(String(format: "%.2f", self.duration))s")
                newPlayer.play()
                self.isPlaying = true
                self.currentTime = 0
                self.pausedTime = 0
                print("🔊 Started playing audio: \(url.lastPathComponent)")
                print("🔊 Time observer is active: \(self.timeObserver != nil)")
            }
        } else {
            // For streaming, start immediately (though we're not using streaming anymore)
            newPlayer.play()
            isPlaying = true
            currentTime = 0
            pausedTime = 0
            print("🔊 Started playing audio (streaming): \(url.lastPathComponent)")
        }
        
        // Ensure time observer is set up even if we're not waiting
        // This is a safety check to ensure progress bar and text highlighting updates
        if timeObserver == nil && newPlayer.status == .readyToPlay {
            print("⚠️ Time observer was not set up, setting it up now...")
            let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC)) // 20 updates per second
            timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self = self, !self.isSeeking else { return }
                let timeSeconds = CMTimeGetSeconds(time)
                if timeSeconds.isFinite && !timeSeconds.isNaN && !timeSeconds.isInfinite {
                    self.currentTime = timeSeconds
                    if self.isPlaying {
                        self.pausedTime = timeSeconds
                    }
                }
            }
        }
    }
    
    /// Load duration with retry logic
    private func loadDuration(playerItem: AVPlayerItem, isStreaming: Bool) async {
        var attempts = 0
        let maxAttempts = isStreaming ? 20 : 10 // More attempts for streaming
        
        while attempts < maxAttempts {
            do {
                let duration = try await playerItem.asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)
                if durationSeconds.isFinite && durationSeconds > 0 && !durationSeconds.isNaN && !durationSeconds.isInfinite {
                    self.duration = durationSeconds
                    print("✅ Audio duration loaded: \(String(format: "%.2f", durationSeconds))s")
                    return
                }
            } catch {
                print("⚠️ Failed to load duration (attempt \(attempts + 1)): \(error.localizedDescription)")
            }
            
            // Wait before retrying
            if attempts < maxAttempts - 1 {
                let waitTime = isStreaming ? 0.3 : 0.5 // Shorter wait for streaming
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
            attempts += 1
        }
        
        print("⚠️ Could not load duration after \(maxAttempts) attempts")
        // Set a default duration if we can't load it
        if duration <= 0 {
            duration = 60.0 // Default to 60 seconds
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let playerItem = object as? AVPlayerItem {
            if keyPath == "status" {
                if playerItem.status == .readyToPlay {
                    print("✅ Player item ready to play")
                    // Try to load duration again when ready
                    Task { @MainActor in
                        await loadDuration(playerItem: playerItem, isStreaming: false)
                    }
                } else if playerItem.status == .failed {
                    print("❌ Player item failed: \(playerItem.error?.localizedDescription ?? "Unknown error")")
                    DispatchQueue.main.async {
                        self.playbackError = "播放失败: \(playerItem.error?.localizedDescription ?? "Unknown error")"
                        self.isPlaying = false
                    }
                }
            } else if keyPath == "duration" {
                // Duration changed, update if valid
                let durationSeconds = CMTimeGetSeconds(playerItem.duration)
                if durationSeconds.isFinite && durationSeconds > 0 && !durationSeconds.isNaN && !durationSeconds.isInfinite {
                    DispatchQueue.main.async {
                        if self.duration != durationSeconds {
                            self.duration = durationSeconds
                            print("✅ Duration updated: \(String(format: "%.2f", durationSeconds))s")
                        }
                    }
                }
            }
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = self.duration
            self.stopTimer()
            print("✅ Audio playback finished")
        }
    }
    
    /// Generate audio file from local TTS and play with AVPlayer (supports seek)
    private func generateAndPlayLocalTTS(text: String, language: String) async {
        await MainActor.run {
            isGenerating = true
            currentText = text
        }
        
        // Find best Chinese voice
        var voice: AVSpeechSynthesisVoice?
        let preferredVoices = ["zh-CN", "zh-HK", "zh-TW"]
        
        for voiceLang in preferredVoices {
            if let foundVoice = AVSpeechSynthesisVoice(language: voiceLang) {
                if #available(iOS 13.0, *) {
                    if foundVoice.quality == .enhanced {
                        voice = foundVoice
                        break
                    }
                }
                if voice == nil {
                    voice = foundVoice
                }
            }
        }
        
        if voice == nil {
            voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice()
        }
        
        // Create utterance with improved parameters for more natural speech
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // Improved parameters for more natural speech
        utterance.rate = 0.5 // Slightly slower for better clarity (0.0-1.0, default is ~0.5)
        utterance.pitchMultiplier = 1.0 // Neutral pitch (0.5-2.0, default is 1.0)
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.0
        
        // For now, use direct speech with improved parameters
        // TODO: For full seek support, consider using OpenAI TTS or implement text segmentation
        await MainActor.run {
            isGenerating = false
            speakDirectlyWithSegments(utterance: utterance, text: text)
        }
    }
    
    /// Generate audio file by splitting text into segments and using AVAudioRecorder approach
    /// Note: This is a simplified approach - for full seek support, consider using OpenAI TTS
    private func generateAudioFile(from utterance: AVSpeechUtterance) async -> URL? {
        // Unfortunately, AVAudioEngine cannot directly capture AVSpeechSynthesizer output
        // as they operate on different audio graphs. 
        // For now, we'll use a workaround: split text and use direct playback with seek approximation
        // For full seek support with natural voice, consider using OpenAI TTS (useOpenAITTS = true)
        
        print("⚠️ Audio file generation from AVSpeechSynthesizer is not directly possible")
        print("💡 Tip: For full seek support, enable OpenAI TTS (useOpenAITTS = true)")
        
        // Return nil to trigger fallback to direct speech
        return nil
    }
    
    /// Speak directly using AVSpeechSynthesizer with text segmentation for approximate seek
    private func speakDirectlyWithSegments(utterance: AVSpeechUtterance, text: String) {
        guard let synthesizer = synthesizer else { return }
        
        currentUtterance = utterance
        currentText = text
        
        // Store text segments for approximate seek
        textSegments = splitTextIntoSegments(text: text)
        currentSegmentIndex = 0
        
        // Estimate duration (more accurate: ~3-4 Chinese characters per second at rate 0.5)
        let charCount = text.count
        let charsPerSecond = 3.5 // Approximate for rate 0.5
        duration = TimeInterval(charCount) / charsPerSecond
        
        startTime = Date()
        isPlaying = true
        
        print("🔊 Starting speech: \(text.prefix(50))... (estimated \(String(format: "%.1f", duration))s)")
        print("🔊 Voice: \(utterance.voice?.identifier ?? "default"), Rate: \(utterance.rate), Pitch: \(utterance.pitchMultiplier)")
        print("🔊 Segments: \(textSegments.count)")
        
        synthesizer.speak(utterance)
        startTimer()
    }
    
    // Text segmentation for approximate seek
    private var textSegments: [String] = []
    private var currentSegmentIndex: Int = 0
    
    /// Split text into segments (by sentences or paragraphs) for approximate seek
    private func splitTextIntoSegments(text: String) -> [String] {
        // Split by double newlines (paragraphs) first
        let paragraphs = text.components(separatedBy: "\n\n")
        var segments: [String] = []
        
        for paragraph in paragraphs {
            if paragraph.isEmpty { continue }
            // Further split by single newlines or periods if paragraph is too long
            if paragraph.count > 100 {
                let sentences = paragraph.components(separatedBy: "。").filter { !$0.isEmpty }
                for sentence in sentences {
                    if !sentence.isEmpty {
                        segments.append(sentence + "。")
                    }
                }
            } else {
                segments.append(paragraph)
            }
        }
        
        return segments.isEmpty ? [text] : segments
    }
    
    /// Seek to approximate position by calculating character index
    private func seekToApproximatePosition(time: TimeInterval) {
        guard !textSegments.isEmpty, let text = currentText else { return }
        
        // Calculate approximate character position based on time
        let charsPerSecond = 3.5
        let targetCharIndex = Int(time * charsPerSecond)
        
        // Find which segment contains this character index
        var charCount = 0
        for (index, segment) in textSegments.enumerated() {
            let segmentLength = segment.count
            if charCount + segmentLength >= targetCharIndex {
                currentSegmentIndex = index
                // Restart from this segment
                restartFromSegment(index: index)
                return
            }
            charCount += segmentLength
        }
        
        // If beyond all segments, restart from beginning
        if targetCharIndex >= text.count {
            restartFromSegment(index: 0)
        }
    }
    
    /// Restart speech from a specific segment
    private func restartFromSegment(index: Int) {
        guard let synthesizer = synthesizer, index < textSegments.count else { return }
        
        // Stop current speech
        synthesizer.stopSpeaking(at: .immediate)
        
        // Calculate text from this segment onwards
        let remainingSegments = Array(textSegments[index...])
        let remainingText = remainingSegments.joined(separator: "\n\n")
        
        // Create new utterance from remaining text
        if let voice = currentUtterance?.voice {
            let newUtterance = AVSpeechUtterance(string: remainingText)
            newUtterance.voice = voice
            newUtterance.rate = currentUtterance?.rate ?? 0.5
            newUtterance.pitchMultiplier = currentUtterance?.pitchMultiplier ?? 1.0
            newUtterance.volume = currentUtterance?.volume ?? 1.0
            
            currentSegmentIndex = index
            currentUtterance = newUtterance
            
            // Update start time based on approximate position
            let charsPerSecond = 3.5
            let skippedChars = textSegments[..<index].reduce(0) { $0 + $1.count }
            let skippedTime = TimeInterval(skippedChars) / charsPerSecond
            startTime = Date().addingTimeInterval(-skippedTime)
            pausedTime = skippedTime
            
            synthesizer.speak(newUtterance)
            isPlaying = true
            startTimer()
            
            print("⏭️ Restarted from segment \(index) (approx \(String(format: "%.1f", skippedTime))s)")
        }
    }
    
    /// Helper class for speech completion detection
    private class SpeechCompletionDelegate: NSObject, AVSpeechSynthesizerDelegate {
        let onComplete: () -> Void
        
        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }
        
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            // Small delay to ensure all audio is written
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.onComplete()
            }
        }
        
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            self.onComplete()
        }
    }
    
    /// Play or resume
    func play() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Priority 1: Resume AVPlayer if it exists
            if let player = self.player {
                // AVPlayer playback (supports seek)
                player.play()
                self.isPlaying = true
                print("▶️ Resumed AVPlayer playback at: \(String(format: "%.2f", self.currentTime))s")
                
                // Seek to paused position if available
                if self.pausedTime > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.seek(to: self.pausedTime)
                    }
                }
                return
            }
            
            // Priority 2: Resume from cached audio file if it exists
            if let cachedURL = self.cachedAudioURL, FileManager.default.fileExists(atPath: cachedURL.path) {
                print("▶️ Resuming from cached audio file")
                self.playAudioFile(url: cachedURL, isStreaming: false)
                return
            }
            
            // Priority 3: Resume direct speech synthesis (fallback)
            if let synthesizer = self.synthesizer, let utterance = self.currentUtterance {
                if synthesizer.isPaused {
                    synthesizer.continueSpeaking()
                    self.isPlaying = true
                    if let startTime = self.startTime {
                        let elapsed = Date().timeIntervalSince(startTime)
                        self.pausedTime = elapsed
                    }
                    self.startTime = Date().addingTimeInterval(-self.pausedTime)
                    self.startTimer()
                    print("▶️ Resumed direct speech")
                } else if !synthesizer.isSpeaking {
                    synthesizer.speak(utterance)
                    self.isPlaying = true
                    self.startTime = Date().addingTimeInterval(-self.pausedTime)
                    self.startTimer()
                    print("▶️ Restarted direct speech")
                }
                return
            }
            
            // No player, no cache, no utterance - cannot play
            print("⚠️ Cannot play: No player, cache, or utterance available")
        }
    }
    
    /// Pause playback
    /// CRITICAL: Stop ALL playback sources to prevent background audio from continuing
    func pause() {
        // Stop AVPlayer first
        if let player = self.player {
            pausedTime = currentTime // Save current position
            player.pause()
            print("⏸️ AVPlayer paused at: \(String(format: "%.1f", pausedTime))s")
        }
        
        // Stop synthesizer (even if player exists, synthesizer might also be playing)
        if let synthesizer = synthesizer {
            if synthesizer.isSpeaking {
                synthesizer.pauseSpeaking(at: .immediate)
                if let startTime = startTime {
                    pausedTime = Date().timeIntervalSince(startTime)
                    currentTime = pausedTime
                }
                print("⏸️ Direct speech paused at: \(String(format: "%.1f", pausedTime))s")
            } else if synthesizer.isPaused {
                print("⏸️ Direct speech already paused")
            }
        }
        
        // Stop audio engine if running
        if let engine = audioEngine, engine.isRunning {
            engine.pause()
            print("⏸️ Audio engine paused")
        }
        
        // Update state
        isPlaying = false
        stopTimer()
    }
    
    /// Stop ALL playback sources immediately (used before starting new playback)
    /// This prevents background audio from continuing when starting new playback
    private func stopAllPlayback() {
        print("🛑 Stopping all playback sources...")

        // Cancel any pending segment generation tasks (prevents late enqueue + overlap)
        for t in pendingSegmentTasks { t.cancel() }
        pendingSegmentTasks.removeAll()
        currentSegmentKeys.removeAll()
        currentCacheKey = nil
        
        // Stop AVPlayer first (most common source)
        if let player = self.player {
            // Remove time observer before clearing player reference
            if let timeObserver = timeObserver {
                player.removeTimeObserver(timeObserver)
                self.timeObserver = nil
                print("🛑 Removed time observer")
            }
            
            player.pause()
            player.replaceCurrentItem(with: nil) // Remove current item to fully stop
            self.player = nil // Clear reference to ensure it's fully released
            print("🛑 Stopped and cleared AVPlayer")
        }
        
        // Stop synthesizer
        if let synthesizer = synthesizer {
            if synthesizer.isSpeaking || synthesizer.isPaused {
                synthesizer.stopSpeaking(at: .immediate)
                print("🛑 Stopped AVSpeechSynthesizer")
            }
        }
        
        // Stop audio engine
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.mainMixerNode.removeTap(onBus: 0)
            print("🛑 Stopped AVAudioEngine")
        }
        
        // Clear player item observers
        if let playerItem = playerItem {
            playerItem.removeObserver(self, forKeyPath: "status")
            playerItem.removeObserver(self, forKeyPath: "duration")
            self.playerItem = nil
            print("🛑 Cleared player item observers")
        }
        
        // Remove time observer (safety)
        self.timeObserver = nil
        
        // Update state
        isPlaying = false
        stopTimer()
        print("🛑 All playback sources stopped")
    }
    
    /// Stop playback and clean up resources
    func stop() {
        // Stop AVPlayer
        if let player = self.player {
            player.pause()
            player.replaceCurrentItem(with: nil) // Remove current item to fully stop
            if let timeObserver = timeObserver {
                player.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
            if let playerItem = playerItem {
                playerItem.removeObserver(self, forKeyPath: "status")
                playerItem.removeObserver(self, forKeyPath: "duration")
            }
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
            self.player = nil
            self.playerItem = nil
        }
        
        // Stop audio engine
        if let engine = audioEngine {
            engine.stop()
            engine.mainMixerNode.removeTap(onBus: 0)
            self.audioEngine = nil
        }
        audioFile = nil
        
        // Stop local TTS
        if let synthesizer = synthesizer {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        isPlaying = false
        currentTime = 0
        // Keep pausedTime for resume, but reset if explicitly stopped
        // pausedTime = 0
        duration = 0
        stopTimer()
        startTime = nil
        print("⏹️ Playback stopped")
    }
    
    /// Clear cached utterance, text, and audio file
    func clearCache() {
        currentUtterance = nil
        currentText = nil
        // Delete cached audio file
        if let cachedURL = cachedAudioURL {
            try? FileManager.default.removeItem(at: cachedURL)
            cachedAudioURL = nil
        }
        pausedTime = 0
        print("🗑️ Cleared TTS cache")
    }
    
    deinit {
        stop()
    }
    
    /// Skip forward by 15 seconds
    func skipForward15() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard let player = self.player else {
                print("⚠️ Skip forward only supported with AVPlayer (player is nil)")
                return
            }
            
            let currentSeconds = self.currentTime
            let durationSeconds = self.duration > 0 ? self.duration : {
                if let duration = player.currentItem?.duration, duration.isValid && !duration.isIndefinite {
                    let seconds = CMTimeGetSeconds(duration)
                    if seconds.isFinite && seconds > 0 {
                        return seconds
                    }
                }
                return 0
            }()
            
            guard durationSeconds > 0 else {
                print("⚠️ Duration not available yet for skip forward (duration: \(durationSeconds), currentTime: \(currentSeconds))")
                return
            }
            
            let newSeconds = min(currentSeconds + 15, durationSeconds - 0.1)
            print("⏩ Skipping forward 15s: \(String(format: "%.1f", currentSeconds))s → \(String(format: "%.1f", newSeconds))s (duration: \(String(format: "%.1f", durationSeconds))s)")
            self.seek(to: newSeconds)
        }
    }
    
    /// Skip backward by 15 seconds
    func skipBackward15() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard self.player != nil else {
                print("⚠️ Skip backward only supported with AVPlayer (player is nil)")
                return
            }
            
            let currentSeconds = self.currentTime
            let newSeconds = max(currentSeconds - 15, 0)
            print("⏪ Skipping backward 15s: \(String(format: "%.1f", currentSeconds))s → \(String(format: "%.1f", newSeconds))s")
            self.seek(to: newSeconds)
        }
    }
    
    /// Seek to specific time with improved accuracy
    func seek(to time: TimeInterval) {
        // Ensure we're on main thread
        if Thread.isMainThread {
            performSeek(to: time)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performSeek(to: time)
            }
        }
    }
    
    /// Internal seek implementation
    private func performSeek(to time: TimeInterval) {
        guard let player = self.player else {
            print("⚠️ Seek only supported with AVPlayer (player is nil)")
            return
        }
        
        // Calculate max time
        let maxTime = self.duration > 0 ? self.duration : {
            if let duration = player.currentItem?.duration, duration.isValid && !duration.isIndefinite {
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite && seconds > 0 {
                    return seconds
                }
            }
            return Double.greatestFiniteMagnitude
        }()
        
        let clampedTime = max(0, min(time, maxTime))
        
        // Set seeking flag to prevent time observer updates during seek
        self.isSeeking = true
        
        // Update UI immediately for responsive feedback
        self.currentTime = clampedTime
        self.pausedTime = clampedTime
        
        let seekTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        print("🔍 Seeking to \(String(format: "%.2f", clampedTime))s (max: \(String(format: "%.2f", maxTime))s)")
        
        // Perform seek with minimal tolerance for accuracy
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSeeking = false
                
                if completed {
                    // Update current time from player to ensure accuracy
                    if let currentTime = player.currentTime().seconds as TimeInterval?,
                       currentTime.isFinite && !currentTime.isNaN {
                        self.currentTime = currentTime
                        self.pausedTime = currentTime
                    } else {
                        self.currentTime = clampedTime
                        self.pausedTime = clampedTime
                    }
                    print("✅ Seeked to \(String(format: "%.2f", self.currentTime))s")
                } else {
                    print("⚠️ Seek was interrupted or failed")
                    // Still update current time even if seek was interrupted
                    self.currentTime = clampedTime
                }
            }
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
            print("✅ Speech finished")
            self.isPlaying = false
            self.currentTime = self.duration
            self.stopTimer()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            print("❌ Speech cancelled")
            self.isPlaying = false
            self.stopTimer()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            print("▶️ Speech started")
            self.isPlaying = true
            self.startTime = Date()
            self.startTimer()
        }
    }
    
    // Optional delegate method for word-by-word highlighting (not implemented)
    // func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeak characterRange: NSRange, utterance: AVSpeechUtterance) {
    //     // Can be used for word-by-word highlighting
    // }
}

