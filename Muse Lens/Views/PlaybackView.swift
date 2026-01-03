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
    let narrationLanguage: String
    let userImage: UIImage?
    let confidence: Double? // Optional confidence value
    
    @StateObject private var artworkTTS = TTSPlayback()
    @Environment(\.dismiss) private var dismiss
    @State private var showFullScreenImage = false
    @State private var showArtistDetail = false
    
    // Check if we're in loading state
    // Only show loading when we truly have placeholder data
    private var isLoading: Bool {
        let title = artworkInfo.title
        let isRecognizingTitle =
            (title == UIPlaceholders.recognizingTitleToken) ||
            (title == UIPlaceholders.legacyRecognizingTitleZh)
        return isRecognizingTitle && narration.isEmpty
    }

    private var isNarrationPending: Bool {
        let trimmed = narration.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        // Placeholder states used during incremental UI updates (tokens + legacy strings)
        if trimmed == UIPlaceholders.narrationLoadingToken { return true }
        if trimmed == UIPlaceholders.narrationGeneratingToken { return true }
        if trimmed == UIPlaceholders.legacyNarrationLoadingZh { return true }
        if trimmed == UIPlaceholders.legacyNarrationGeneratingZh { return true }
        if trimmed == UIPlaceholders.legacyNarrationGeneratingShortZh { return true }
        // If streaming JSON/SSE accidentally leaks into UI, treat as loading instead of showing gibberish.
        if trimmed.hasPrefix("{") { return true }
        if trimmed.contains("\"title\"") || trimmed.contains("\"narration\"") || trimmed.contains("\"artist\"") { return true }
        if trimmed.contains("data:") { return true }
        return false
    }
    
    private var displayTitle: String {
        let title = artworkInfo.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title == UIPlaceholders.recognizingTitleToken || title == UIPlaceholders.legacyRecognizingTitleZh {
            return String(localized: "playback.state.recognizing_title")
        }
        return title
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
        return ZStack {
            // CRITICAL: Ensure background fully covers the screen
            // Add solid black background first as base layer
            Color.black
                .ignoresSafeArea()
            
            backgroundImageView
                .ignoresSafeArea()
            
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Fixed header (1:1 layout block)
                    headerView
                        .padding(.top, geometry.safeAreaInsets.top + 4)
                        .padding(.bottom, 6)
                    
                    // Middle scrollable area (only this scrolls)
                    scrollableContentView
                        .frame(maxHeight: .infinity)
                    
                    // Fixed bottom player
                    fixedAudioPlayerView
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 6)
                }
                // IMPORTANT:
                // Apply padding BEFORE frame(maxWidth: .infinity). If we frame first and then pad,
                // the container becomes wider than the screen (width + 40pt) and content gets clipped.
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) // Fill screen space
            }
        }
        .onDisappear { artworkTTS.stop() }
        .contentShape(Rectangle())
        // Swipe RIGHT (from left edge) to go back to home (dismiss).
        .simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    // horizontal swipe only
                    guard abs(dx) > abs(dy) else { return }
                    // Require edge-start to avoid accidental triggers while scrolling
                    guard value.startLocation.x < 24 else { return }
                    // swipe right
                    guard dx > 90 else { return }
                    dismiss()
                }
        )
        .sheet(isPresented: $showFullScreenImage) {
            if let userImage = userImage {
                FullScreenImageView(image: userImage)
            }
        }
        .sheet(isPresented: $showArtistDetail) {
            ArtistDetailView(
                artistName: artworkInfo.artist,
                artistIntroduction: artistIntroduction,
                isIdentified: artworkInfo.recognized && artworkInfo.artist != "未知艺术家" && !artworkInfo.artist.isEmpty
            )
        }
    }
    
    // MARK: - Background Image View
    private var backgroundImageView: some View {
        // CRITICAL:
        // When `userImage` is present, an unconstrained resizable Image in a ZStack can
        // participate in layout sizing and cause the container to exceed screen bounds.
        // Constrain to screen size via GeometryReader and always clip.
        return GeometryReader { geometry in
            ZStack {
                if let userImage = userImage {
                    Image(uiImage: userImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: 50)
                } else if let imageURL = artworkInfo.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .blur(radius: 50)
                        } else {
                            Color.black
                        }
                    }
                } else {
                    Color.black
                }
                
                Color.black.opacity(0.6)
            }
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Header (Fixed)
    private var headerView: some View {
        return VStack(alignment: .leading, spacing: 10) {
            // Top row: Back button - Tertiary style (white text, no background)
            HStack {
                Button(action: { dismiss() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("nav.back")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                
                Spacer()
            }
            
            // Artwork header row
            HStack(alignment: .top, spacing: 12) {
                headerThumbnailView
                
                VStack(alignment: .leading, spacing: 4) {
                    if isLoading {
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.28))
                                .frame(height: 22)
                                .shimmer()
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 18)
                                .frame(maxWidth: 180, alignment: .leading)
                                .shimmer()
                        }
                    } else {
                        Text(displayTitle)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // Artist name - tappable
                        Text(headerSubtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                            .underline()
                            .onTapGesture {
                                if !artworkInfo.artist.isEmpty && artworkInfo.artist != "未知艺术家" {
                                    showArtistDetail = true
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerSubtitle: String {
        if let year = artworkInfo.year, !year.isEmpty {
            return "\(artworkInfo.artist) · \(year)"
        }
        return artworkInfo.artist
    }

    /// Thumbnail (always visible). If no image, show placeholder with border.
    private var headerThumbnailView: some View {
        let size: CGFloat = 44 // Match design
        return Group {
            if let userImage = userImage {
                Image(uiImage: userImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let imageURL = artworkInfo.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.75), lineWidth: 1)
        )
        .onTapGesture {
            if userImage != nil {
                showFullScreenImage = true
            }
        }
    }

    private var thumbnailPlaceholder: some View {
        return ZStack {
            Color.white.opacity(0.30)
            Image(systemName: "photo")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.95))
        }
    }
    
    // MARK: - Scrollable Content View (Text Only, No Audio Controls)
    private var scrollableContentView: some View {
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if isLoading {
                    skeletonLoadingView()
                        .padding(.vertical, 8)
                } else {
                    // Artwork narration/introduction should always render (even when pending)
                    VStack(alignment: .leading, spacing: 16) {
                        if let level = confidenceLevel, level == .low {
                            // Low confidence: show friendly message
                            VStack(spacing: 16) {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Text("playback.recognition_failed.title")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Text(narration.isEmpty ? String(localized: "playback.recognition_failed.no_narration") : narration)
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.25))
                                    .cornerRadius(12)
                            }
                            .frame(maxWidth: .infinity)
                        } else if isNarrationPending {
                            // Pending narration: show a simple text placeholder (always visible)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                    Text("playback.status.generating_narration")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.12))
                                    .frame(height: 18)
                                    .shimmer()
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.10))
                                    .frame(height: 18)
                                    .frame(maxWidth: 260, alignment: .leading)
                                    .shimmer()
                            }
                            .padding(.vertical, 8)
                        } else {
                            // Normal narration rendering
                            narrationTextView(text: narration, isLoading: false, tts: artworkTTS)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    
                    // Artist Introduction (if available)
                    if !artistIntroduction.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 1)
                                .padding(.top, 8)
                            
                            Text("playback.section.artist_intro")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Text(artistIntroduction)
                                .font(.system(size: 17))
                                .foregroundColor(.white.opacity(0.9))
                                .lineSpacing(8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity) // Fill available width
    }
    
    // MARK: - Fixed Audio Player View
    private var fixedAudioPlayerView: some View {
        return VStack(spacing: 0) {
            audioControlsView(tts: artworkTTS, text: narration)
                .padding(.horizontal, 0)
                .padding(.vertical, 10) // tighter vertical spacing
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Skeleton Loading View
    private func skeletonLoadingView() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Skeleton for audio controls
            VStack(spacing: 16) {
                // Progress bar skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4)
                    .shimmer()
                
                // Control buttons skeleton
                HStack(spacing: 40) {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 24, height: 24)
                        .shimmer()
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .shimmer()
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 24, height: 24)
                        .shimmer()
                }
                .frame(maxWidth: .infinity)
                
                // Toggle button skeleton
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 120, height: 36)
                    .shimmer()
            }
            
            // Skeleton for text content
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 20)
                            .frame(maxWidth: index % 3 == 0 ? 280 : (index % 3 == 1 ? 240 : 200))
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
                Text("playback.empty")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
                    .italic()
                    .padding()
            } else {
                // Spotify-style highlighted text with scrolling
                let paragraphs = formatNarrationText(text)
                
                HighlightedTextView(
                    paragraphs: paragraphs,
                    text: text,
                    tts: tts,
                    textColor: .white,
                    secondaryTextColor: .white.opacity(0.7),
                    highlightColor: Color(hex: "1F1F1F")
                )
                .frame(maxWidth: .infinity, alignment: .leading) // Ensure it respects parent width constraints
            }
        }
    }
    
    // MARK: - Audio Controls View
    private func audioControlsView(tts: TTSPlayback, text: String) -> some View {
        VStack(spacing: 10) { // tighter spacing
            // Progress Bar
            if tts.isGenerating {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    Text("playback.tts.generating_audio_guide")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
            } else if tts.duration > 0 {
                ProgressSliderView(tts: tts)
            } else if !text.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    Text("playback.tts.ready_to_play")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Control Buttons - White bg with #1F1F1F icons
            HStack(spacing: 40) {
                // Skip Back 15s
                Button(action: {
                    tts.skipBackward15()
                }) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 24))
                        .foregroundColor(tts.duration > 0 ? Color(hex: "1F1F1F") : .gray)
                        .padding(12)
                        .background(
                            Circle()
                                .fill(tts.duration > 0 ? Color.white : Color.white.opacity(0.3))
                        )
                }
                .disabled(tts.duration <= 0)
                
                // Play/Pause
                Button(action: {
                    if tts.isPlaying {
                        tts.pause()
                    } else {
                        // Resume or start playback
                        if !text.isEmpty && !tts.isGenerating {
                            // Check if playback has finished (at the end or stopped after completion)
                            let isAtEnd = tts.duration > 0 && (tts.currentTime >= (tts.duration - 0.5) || (!tts.isPlaying && tts.currentTime >= tts.duration * 0.95))
                            
                            if isAtEnd {
                                // Restart from beginning if at the end
                                print("🔄 Restarting playback from beginning")
                                tts.seek(to: 0)
                                // Small delay to ensure seek completes
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    tts.play()
                                }
                            } else if tts.duration > 0 || tts.currentTime > 0 {
                                // Already have audio, just resume
                                tts.play()
                            } else {
                                // Need to generate audio first
                                // Stop any existing playback before starting new one (prevent overlap)
                                tts.stop()
                                Task {
                                    await tts.speak(text: text, language: ContentLanguage.ttsBCP47Tag(for: narrationLanguage))
                                }
                            }
                        }
                    }
                }) {
                    Image(systemName: tts.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor((text.isEmpty || tts.isGenerating) ? .gray : Color(hex: "1F1F1F"))
                        .background(
                            Circle()
                                .fill((text.isEmpty || tts.isGenerating) ? Color.white.opacity(0.3) : Color.white)
                                .frame(width: 68, height: 68)
                        )
                }
                .disabled(text.isEmpty || tts.isGenerating)
                
                // Skip Forward 15s
                Button(action: {
                    tts.skipForward15()
                }) {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 24))
                        .foregroundColor(tts.duration > 0 ? Color(hex: "1F1F1F") : .gray)
                        .padding(12)
                        .background(
                            Circle()
                                .fill(tts.duration > 0 ? Color.white : Color.white.opacity(0.3))
                        )
                }
                .disabled(tts.duration <= 0)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var imagePlaceholder: some View {
        return RoundedRectangle(cornerRadius: 12)
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
                .foregroundColor(level == .high ? .green : level == .medium ? .orange : .white.opacity(0.7))
            Text(level == .high ? String(localized: "playback.confidence.high") : level == .medium ? String(localized: "playback.confidence.medium") : String(localized: "playback.confidence.low"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(level == .high ? .green : level == .medium ? .orange : .white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background((level == .high ? Color.green : level == .medium ? Color.orange : Color.white).opacity(0.2))
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
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(formatTime(tts.duration))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
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
        return self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        return content
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

#Preview("iPhone 15 Pro") {
    PlaybackView(
        artworkInfo: ArtworkInfo(
            title: "Water lilies in Claude Monet’s private garden in France",
            artist: "Claude Monet",
            year: "1872",
            style: "Impressionism",
            sources: ["https://en.wikipedia.org/wiki/Water_Lilies_(Monet_series)"]
        ),
        narration: """
印象派的兴起，打破了学院派对于光影与色彩的刻板规范。莫奈以更自由的笔触与大胆的色彩层次，捕捉瞬间的空气感与光线变化，形成一种更接近人眼真实感受的画面语言。

在这类作品中，水面既是镜子也是舞台：它反射天空与植物，同时又被涟漪与笔触重新组织成抽象的节奏。观者在近看时会注意到笔触的方向与速度；退后一步，色块又会在视网膜上“融合”，形成柔和的整体。

这种处理方式让作品在写实与抽象之间保持张力：它并不追求对物体轮廓的精确描摹，而是强调“看见”的过程本身——光如何落下、颜色如何转变、以及情绪如何被唤起。
""",
        artistIntroduction: "",
        narrationLanguage: ContentLanguage.zh,
        userImage: nil,
        confidence: 0.9
    )
}

#Preview("iPhone SE (3rd gen)") {
    PlaybackView(
        artworkInfo: ArtworkInfo(
            title: "悬崖上的散步（超长标题用于测试换行与裁切问题：确保不会被屏幕边缘裁掉）",
            artist: "克劳德·莫奈",
            year: "1882",
            style: "印象派",
            sources: []
        ),
        narration: """
这是一段较长的中文讲解，用来验证在小屏幕设备上文字不会被裁切，同时能够正常换行显示。这里会包含多段内容，并且每段都有一定长度，以模拟真实生成讲解的显示效果。

第二段继续增加长度：当内容变多时，滚动区域必须能够在 header 与 player 之间顺畅滚动，且不会出现左右贴边或字符被截断的问题。

第三段：如果你把系统字体调大（动态字体），也应该仍然能够看到完整内容，而不是被固定宽度的 frame 导致裁切。
""",
        artistIntroduction: "（可选）艺术家介绍也应当在同一滚动区域里正常换行显示。",
        narrationLanguage: ContentLanguage.zh,
        userImage: nil,
        confidence: 0.9
    )
}

