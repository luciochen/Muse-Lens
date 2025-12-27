//
//  PlaybackView.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import SwiftUI
import UIKit
import AVFoundation
import Combine

struct PlaybackView: View {
    let artworkInfo: ArtworkInfo
    let narration: String
    let artistIntroduction: String
    let userImage: UIImage?
    let confidence: Double? // Optional confidence value
    
    @StateObject private var artworkTTS = TTSPlayback()
    @StateObject private var artistTTS = TTSPlayback()
    @State private var selectedTab = 0
    @Environment(\.dismiss) private var dismiss
    
    // Check if we're in loading state
    // Only show loading when we truly have placeholder data
    private var isLoading: Bool {
        artworkInfo.title == "正在识别..." && narration.isEmpty
    }
    
    // Get confidence level
    private var confidenceLevel: RecognitionConfidenceLevel? {
        guard let confidence = confidence else { return nil }
        if confidence >= 0.8 {
            return .high
        } else if confidence >= 0.5 {
            return .medium
        } else {
            return .low
        }
    }
    
    var body: some View {
        ZStack {
            // Background to prevent overlap
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with artwork image and info
                headerView
                
                // Tab View
                TabView(selection: $selectedTab) {
                    // Tab 1: 作品讲解
                    artworkNarrationTab
                        .tag(0)
                    
                    // Tab 2: 艺术家介绍
                    artistIntroductionTab
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .safeAreaInset(edge: .top) {
                // Top bar with close button
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .background(Color(.systemBackground))
            }
            .onChange(of: selectedTab) { oldValue, newValue in
                // Pause (not stop) the other tab's playback when switching tabs
                // This preserves the playback state for resume
                if newValue == 0 {
                    artistTTS.pause()
                } else {
                    artworkTTS.pause()
                }
            }
            // Removed auto-play: narration will only play when user clicks play button
            .onDisappear {
                // Stop all playback when view disappears
                artworkTTS.stop()
                artistTTS.stop()
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 16) {
            // Artwork Image
            // IMPORTANT: Always prioritize user's photo over backend reference image
            // Backend imageURL is only a reference from museum API, not user's personal photo
            Group {
                if let userImage = userImage {
                    // Always use user's photo first (user's personal photo of the artwork)
                    Image(uiImage: userImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let imageURL = artworkInfo.imageURL, let url = URL(string: imageURL) {
                    // Fallback to reference image from museum API (only if user photo not available)
                    // This is a reference image, not user's photo
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .failure(_), .empty:
                            imagePlaceholder
                        @unknown default:
                            imagePlaceholder
                        }
                    }
                } else {
                    imagePlaceholder
                }
            }
            .frame(maxHeight: 250)
            .cornerRadius(12)
            .shadow(radius: 8)
            .padding(.horizontal)
            
            // Artwork Info
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    // Skeleton loading for header
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 24)
                            .shimmer()
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 180, height: 18)
                            .shimmer()
                    }
                } else {
                    Text(artworkInfo.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text(artworkInfo.artist)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if let year = artworkInfo.year {
                            Text("· \(year)")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let style = artworkInfo.style {
                        Text(style)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    // Confidence level indicator - only show for medium/low confidence
                    if let level = confidenceLevel, level != .high {
                        confidenceIndicator(level: level)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            
            // Tab Selector
            HStack(spacing: 0) {
                tabButton(title: "作品讲解", tag: 0)
                tabButton(title: "艺术家介绍", tag: 1)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(Color(.systemBackground))
    }
    
    private func tabButton(title: String, tag: Int) -> some View {
        Button(action: {
            withAnimation {
                selectedTab = tag
            }
        }) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: selectedTab == tag ? .semibold : .regular))
                    .foregroundColor(selectedTab == tag ? .blue : .secondary)
                
                Rectangle()
                    .fill(selectedTab == tag ? Color.blue : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Artwork Narration Tab
    private var artworkNarrationTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    // Skeleton loading - show only when truly loading
                    skeletonLoadingView()
                        .padding()
                } else if !narration.isEmpty {
                    // Show actual content when available
                    // Show different content based on confidence level
                    if let level = confidenceLevel {
                        switch level {
                        case .high:
                            // High confidence: Show full narration with audio controls
                            audioControlsView(tts: artworkTTS, text: narration)
                            narrationTextView(text: narration, isLoading: false, tts: artworkTTS)
                            
                        case .medium:
                            // Medium confidence: Show style description with disclaimer
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.orange)
                                    Text("识别不确定")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.orange)
                                }
                                .padding()
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                                
                                audioControlsView(tts: artworkTTS, text: narration)
                                narrationTextView(text: narration, isLoading: false, tts: artworkTTS)
                            }
                            
                        case .low:
                            // Low confidence: Show friendly message
                            VStack(spacing: 16) {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(.gray)
                                
                                Text("无法识别作品")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                Text(narration)
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                
                                VStack(spacing: 8) {
                                    Text("建议：")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Text("• 尝试重新扫描作品")
                                    Text("• 确保作品清晰可见")
                                    Text("• 尝试扫描其他作品")
                                }
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    } else {
                        // Default: Show narration
                        audioControlsView(tts: artworkTTS, text: narration)
                        narrationTextView(text: narration, isLoading: false, tts: artworkTTS)
                    }
                } else {
                    // Empty state - no content available
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("暂无内容")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .padding()
        }
    }
    
    // MARK: - Artist Introduction Tab
    private var artistIntroductionTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    // Show skeleton loading when loading
                    skeletonLoadingView()
                        .padding()
                } else if artistIntroduction.isEmpty {
                    // Empty state
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("暂无艺术家介绍")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                        Text("无法识别艺术家信息")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    // Audio Controls
                    audioControlsView(tts: artistTTS, text: artistIntroduction)
                    
                    // Artist Introduction Text
                    narrationTextView(text: artistIntroduction, isLoading: false, tts: artistTTS)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Skeleton Loading View
    private func skeletonLoadingView() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Skeleton for audio controls
            VStack(spacing: 16) {
                // Progress bar skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 4)
                    .shimmer()
                
                // Control buttons skeleton
                HStack(spacing: 40) {
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 24, height: 24)
                        .shimmer()
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 60, height: 60)
                        .shimmer()
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 24, height: 24)
                        .shimmer()
                }
                .frame(maxWidth: .infinity)
                
                // Toggle button skeleton
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 120, height: 36)
                    .shimmer()
            }
            
            // Skeleton for text content
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 20)
                            .frame(width: index % 3 == 0 ? 280 : (index % 3 == 1 ? 240 : 200))
                            .shimmer()
                        if index % 3 != 2 {
                            Spacer()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Narration Text View with Spotify-style Highlighting
    private func narrationTextView(text: String, isLoading: Bool, tts: TTSPlayback? = nil) -> some View {
        Group {
            if text.isEmpty && !isLoading {
                Text("暂无内容")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            } else {
                // Spotify-style highlighted text with scrolling
                let paragraphs = formatNarrationText(text)
                
                HighlightedTextView(
                    paragraphs: paragraphs,
                    text: text,
                    tts: tts
                )
            }
        }
    }
    
    // MARK: - Audio Controls View
    private func audioControlsView(tts: TTSPlayback, text: String) -> some View {
        VStack(spacing: 16) {
            // Progress Bar
            if tts.isGenerating {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    Text("正在生成高质量语音...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            } else if tts.duration > 0 {
                ProgressSliderView(tts: tts)
            } else if !text.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    Text("准备播放...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            // Control Buttons
            HStack(spacing: 40) {
                // Skip Back 15s
                Button(action: {
                    tts.skipBackward15()
                }) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 24))
                        .foregroundColor(tts.duration > 0 ? .blue : .gray)
                }
                .disabled(tts.duration <= 0)
                
                // Play/Pause
                Button(action: {
                    if tts.isPlaying {
                        tts.pause()
                    } else {
                        // Resume or start playback
                        if !text.isEmpty && !tts.isGenerating {
                            // Check if we have cached audio or player is already set up
                            // If player exists, just resume playback
                            // Otherwise, generate and play audio
                            if tts.duration > 0 || tts.currentTime > 0 {
                                // Already have audio, just resume
                                tts.play()
                            } else {
                                // Need to generate audio first
                                // Stop any existing playback before starting new one (prevent overlap)
                                tts.stop()
                                Task {
                                    await tts.speak(text: text, language: "zh-CN")
                                }
                            }
                        }
                    }
                }) {
                    Image(systemName: tts.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor((text.isEmpty || tts.isGenerating) ? .gray : .blue)
                }
                .disabled(text.isEmpty || tts.isGenerating)
                
                // Skip Forward 15s
                Button(action: {
                    tts.skipForward15()
                }) {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 24))
                        .foregroundColor(tts.duration > 0 ? .blue : .gray)
                }
                .disabled(tts.duration <= 0)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: "photo.artframe")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
            )
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Format narration text with proper paragraph breaks - returns array of paragraphs
    private func formatNarrationText(_ text: String) -> [String] {
        // Split by double newlines (paragraph breaks) and ensure proper spacing
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // If no double newlines, try splitting by single newlines for shorter texts
        if paragraphs.count == 1 && text.contains("\n") {
            return text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        
        return paragraphs
    }
    
    /// Calculate which paragraph should be highlighted based on current playback time
    /// Returns the index of the paragraph that should be highlighted
    private func calculateHighlightedParagraphIndex(
        paragraphs: [String],
        currentTime: TimeInterval,
        totalDuration: TimeInterval,
        text: String
    ) -> Int {
        guard !paragraphs.isEmpty, totalDuration > 0, currentTime >= 0 else {
            return 0
        }
        
        // Calculate approximate time per paragraph based on character count
        let totalCharacters = text.count
        guard totalCharacters > 0 else { return 0 }
        
        let progress = currentTime / totalDuration
        let targetCharacterIndex = Int(Double(totalCharacters) * progress)
        
        // Find which paragraph contains this character index
        var charCount = 0
        for (index, paragraph) in paragraphs.enumerated() {
            charCount += paragraph.count
            if charCount >= targetCharacterIndex {
                return index
            }
        }
        
        // Return last paragraph if we've passed all paragraphs
        return max(0, paragraphs.count - 1)
    }
    
    // MARK: - Confidence Indicator
    private func confidenceIndicator(level: RecognitionConfidenceLevel) -> some View {
        HStack {
            Image(systemName: level == .high ? "checkmark.circle.fill" : level == .medium ? "exclamationmark.circle.fill" : "questionmark.circle.fill")
                .foregroundColor(level == .high ? .green : level == .medium ? .orange : .gray)
            Text(level == .high ? "识别成功" : level == .medium ? "识别不确定" : "无法识别")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(level == .high ? .green : level == .medium ? .orange : .gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background((level == .high ? Color.green : level == .medium ? Color.orange : Color.gray).opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Progress Slider View
/// Progress slider component that handles dragging smoothly with proper seek behavior
struct ProgressSliderView: View {
    @ObservedObject var tts: TTSPlayback
    @State private var isDragging = false
    @State private var dragValue: TimeInterval = 0
    
    var body: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: {
                        // Use dragValue when dragging, otherwise use currentTime from player
                        isDragging ? dragValue : tts.currentTime
                    },
                    set: { newValue in
                        dragValue = newValue
                        // Update displayed time immediately for responsive UI
                        if !isDragging {
                            isDragging = true
                            // Set seeking flag to prevent time observer from interfering
                            tts.isSeeking = true
                        }
                        // Update currentTime for immediate UI feedback
                        tts.currentTime = newValue
                    }
                ),
                in: 0...max(tts.duration, 0.1),
                onEditingChanged: { editing in
                    if editing {
                        // Drag started
                        isDragging = true
                        tts.isSeeking = true
                    } else {
                        // Drag ended - seek to final position
                        isDragging = false
                        let targetTime = dragValue
                        // Seek to the target time
                        tts.seek(to: targetTime)
                    }
                }
            )
            .tint(.blue)
            
            HStack {
                Text(formatTime(tts.currentTime))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTime(tts.duration))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: tts.currentTime) { oldValue, newValue in
            // Update dragValue when currentTime changes from player
            // But only if we're not dragging (to avoid conflicts)
            if !isDragging {
                dragValue = newValue
            }
        }
        .onChange(of: tts.isSeeking) { oldValue, newValue in
            // When seeking flag is cleared (seek completed), update dragValue
            if !newValue && !isDragging {
                dragValue = tts.currentTime
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Shimmer effect for skeleton loading
extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: 0.3),
                            .init(color: .white.opacity(0.4), location: 0.5),
                            .init(color: .clear, location: 0.7),
                            .init(color: .clear, location: 1.0)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                    .mask(content)
                }
            )
            .clipped()
            .onAppear {
                phase = 0
                withAnimation(Animation.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}

#Preview {
    PlaybackView(
        artworkInfo: ArtworkInfo(
            title: "示例作品",
            artist: "示例艺术家",
            year: "2023",
            style: "印象派",
            sources: ["https://example.com"]
        ),
        narration: "这是一段示例讲解内容，用于展示播放界面的效果。",
        artistIntroduction: "这是艺术家介绍内容，包括艺术家的生平、风格特点和在艺术史上的地位。",
        userImage: nil,
        confidence: 0.9
    )
}

