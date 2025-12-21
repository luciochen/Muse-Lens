//
//  HighlightedTextView.swift
//  Muse Lens
//
//  Created for Spotify-style text highlighting during playback
//  Highlights individual sentences instead of paragraphs
//

import SwiftUI
import Combine

struct HighlightedTextView: View {
    let paragraphs: [String]
    let text: String
    let tts: TTSPlayback?
    
    @State private var highlightedSentenceIndex: Int = -1
    @State private var lastScrollIndex: Int = -1
    @State private var sentences: [(text: String, startCharIndex: Int, endCharIndex: Int)] = []
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if sentences.isEmpty {
                        // Fallback: Show paragraphs if sentences not parsed
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                            Text(paragraph)
                                .font(.system(size: 17))
                                .foregroundColor(.primary)
                                .lineSpacing(8)
                                .padding(.vertical, 8)
                                .id("paragraph-\(index)")
                        }
                    } else {
                        // Show sentences with highlighting
                        ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                            let isHighlighted = index == highlightedSentenceIndex
                            
                            Text(sentence.text)
                                .font(.system(size: 17, weight: isHighlighted ? .semibold : .regular))
                                .foregroundColor(isHighlighted ? .primary : .secondary)
                                .opacity(isHighlighted ? 1.0 : 0.6)
                                .lineSpacing(8)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isHighlighted ? Color.blue.opacity(0.15) : Color.clear)
                                        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
                                )
                                .id(index)
                                .transition(.opacity)
                        }
                    }
                }
                .padding()
            }
            .onAppear {
                parseSentences()
            }
            .onReceive(tts?.$currentTime.eraseToAnyPublisher() ?? Just(0.0).eraseToAnyPublisher()) { _ in
                updateHighlightedSentence(proxy: proxy)
            }
            .onReceive(tts?.$isPlaying.eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()) { _ in
                updateHighlightedSentence(proxy: proxy)
            }
        }
    }
    
    /// Parse text into sentences (split by sentence endings: 。！？; and English: .!?)
    private func parseSentences() {
        var result: [(text: String, startCharIndex: Int, endCharIndex: Int)] = []
        var currentSentence = ""
        var currentStartIndex = 0
        var charIndex = 0
        
        // Combine all paragraphs into single text, preserving character positions
        let fullText = paragraphs.joined(separator: "\n\n")
        
        // Sentence endings: Chinese (。！？) and English (.!?)
        let sentenceEndings: [Character] = ["。", "！", "？", ".", "!", "?", ";", "\n"]
        
        let chars = Array(fullText)
        var i = 0
        
        while i < chars.count {
            let char = chars[i]
            currentSentence.append(char)
            
            // Check if current character is a sentence ending
            if sentenceEndings.contains(char) {
                let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    result.append((
                        text: trimmed,
                        startCharIndex: currentStartIndex,
                        endCharIndex: charIndex + 1
                    ))
                    currentSentence = ""
                    currentStartIndex = charIndex + 1
                }
            }
            
            charIndex += 1
            i += 1
        }
        
        // Add remaining text as last sentence if any
        let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result.append((
                text: trimmed,
                startCharIndex: currentStartIndex,
                endCharIndex: charIndex
            ))
        }
        
        // If no sentences found, create sentences from paragraphs as fallback
        if result.isEmpty {
            var charCount = 0
            for paragraph in paragraphs {
                if !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let start = charCount
                    let end = charCount + paragraph.count
                    result.append((
                        text: paragraph.trimmingCharacters(in: .whitespacesAndNewlines),
                        startCharIndex: start,
                        endCharIndex: end
                    ))
                    charCount = end
                }
            }
        }
        
        sentences = result
        print("📝 Parsed \(sentences.count) sentences from text (total chars: \(fullText.count))")
    }
    
    /// Update which sentence should be highlighted based on playback progress
    private func updateHighlightedSentence(proxy: ScrollViewProxy) {
        guard let tts = tts, tts.duration > 0, tts.isPlaying, !sentences.isEmpty else {
            highlightedSentenceIndex = -1
            return
        }
        
        // Calculate which character we're at based on playback progress
        let totalCharacters = text.count
        guard totalCharacters > 0 else { return }
        
        let progress = tts.currentTime / tts.duration
        let targetCharacterIndex = Int(Double(totalCharacters) * progress)
        
        // Find which sentence contains this character index
        var newHighlightedIndex = -1
        for (index, sentence) in sentences.enumerated() {
            if targetCharacterIndex >= sentence.startCharIndex && targetCharacterIndex <= sentence.endCharIndex {
                newHighlightedIndex = index
                break
            }
        }
        
        // If no exact match, find the closest sentence
        if newHighlightedIndex == -1 && !sentences.isEmpty {
            // Find the sentence that contains or is closest to the target character
            for (index, sentence) in sentences.enumerated() {
                if targetCharacterIndex < sentence.startCharIndex {
                    newHighlightedIndex = max(0, index - 1)
                    break
                }
            }
            // If we're past all sentences, highlight the last one
            if newHighlightedIndex == -1 {
                newHighlightedIndex = sentences.count - 1
            }
        }
        
        // Update highlighted sentence index
        if newHighlightedIndex != highlightedSentenceIndex && newHighlightedIndex >= 0 {
            highlightedSentenceIndex = newHighlightedIndex
            
            // Auto-scroll to highlighted sentence (only scroll if index changed)
            if abs(newHighlightedIndex - lastScrollIndex) >= 1 {
                lastScrollIndex = newHighlightedIndex
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(newHighlightedIndex, anchor: .center)
                }
            }
        }
    }
}

