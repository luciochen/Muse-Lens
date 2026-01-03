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
    let textColor: Color
    let secondaryTextColor: Color
    let highlightColor: Color
    
    @State private var highlightedSentenceIndex: Int = -1
    @State private var sentences: [(text: String, startCharIndex: Int, endCharIndex: Int)] = []
    
    init(paragraphs: [String], text: String, tts: TTSPlayback?, textColor: Color = .primary, secondaryTextColor: Color = .secondary, highlightColor: Color = .blue) {
        self.paragraphs = paragraphs
        self.text = text
        self.tts = tts
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.highlightColor = highlightColor
    }
    
    var body: some View {
        // IMPORTANT: No internal ScrollView here.
        // This view is meant to be embedded inside the page-level ScrollView in `PlaybackView`.
        VStack(alignment: .leading, spacing: 12) {
            if sentences.isEmpty {
                // Fallback: Show paragraphs if sentences not parsed
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: 17))
                        .foregroundColor(textColor)
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            } else {
                // Show sentences with highlighting
                ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                    let isHighlighted = index == highlightedSentenceIndex
                    
                    Text(sentence.text)
                        .font(.system(size: 17, weight: isHighlighted ? .semibold : .regular))
                        .foregroundColor(isHighlighted ? textColor : secondaryTextColor)
                        .opacity(isHighlighted ? 1.0 : 0.8)
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isHighlighted ? highlightColor.opacity(0.3) : Color.clear)
                                .animation(.easeInOut(duration: 0.3), value: isHighlighted)
                        )
                        .id(index)
                        .onTapGesture {
                            seekToSentence(at: index)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .onAppear {
            parseSentences()
        }
        .onReceive(tts?.$currentTime.eraseToAnyPublisher() ?? Just(0.0).eraseToAnyPublisher()) { _ in
            updateHighlightedSentence()
        }
        .onReceive(tts?.$isPlaying.eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()) { _ in
            updateHighlightedSentence()
        }
    }
    
    /// Parse text into natural segments (20-80 chars per segment, split at sentence boundaries)
    private func parseSentences() {
        // Step 1: Parse into individual sentences first
        let individualSentences = parseIntoIndividualSentences()
        
        // Step 2: Combine sentences into natural segments (20-80 chars)
        let minCharsPerSegment = 20
        let maxCharsPerSegment = 80
        
        var result: [(text: String, startCharIndex: Int, endCharIndex: Int)] = []
        var currentSegment = ""
        var segmentStartIndex = 0
        
        for (index, sentence) in individualSentences.enumerated() {
            // Initialize segment start index
            if currentSegment.isEmpty {
                segmentStartIndex = sentence.startCharIndex
            }
            
            let potentialSegment = currentSegment + sentence.text
            let isLastSentence = (index == individualSentences.count - 1)
            
            // Decision: should we create a segment now?
            let shouldCreateSegment: Bool
            if isLastSentence {
                // Last sentence: always create segment
                shouldCreateSegment = true
            } else if currentSegment.isEmpty {
                // First sentence in segment: never create alone unless it's >= maxChars
                shouldCreateSegment = sentence.text.count >= maxCharsPerSegment
            } else if potentialSegment.count >= minCharsPerSegment && potentialSegment.count <= maxCharsPerSegment {
                // Within ideal range: create segment
                shouldCreateSegment = true
            } else if potentialSegment.count > maxCharsPerSegment {
                // Exceeded max: create segment with current accumulated text (before adding this sentence)
                // Then start new segment with this sentence
                if currentSegment.count >= minCharsPerSegment {
                    // Current segment is valid, finalize it
                    result.append((
                        text: currentSegment.trimmingCharacters(in: .whitespacesAndNewlines),
                        startCharIndex: segmentStartIndex,
                        endCharIndex: individualSentences[index - 1].endCharIndex
                    ))
                    // Start new segment with current sentence
                    currentSegment = sentence.text
                    segmentStartIndex = sentence.startCharIndex
                    shouldCreateSegment = false
                } else {
                    // Current segment too short, must include this sentence even if > max
                    shouldCreateSegment = true
                }
            } else {
                // Below min: continue accumulating
                shouldCreateSegment = false
            }
            
            if shouldCreateSegment {
                currentSegment += sentence.text
                result.append((
                    text: currentSegment.trimmingCharacters(in: .whitespacesAndNewlines),
                    startCharIndex: segmentStartIndex,
                    endCharIndex: sentence.endCharIndex
                ))
                currentSegment = ""
            } else if potentialSegment.count <= maxCharsPerSegment {
                // Continue accumulating
                currentSegment += sentence.text
            }
        }
        
        // Add any remaining segment
        if !currentSegment.isEmpty {
            let lastSentence = individualSentences.last!
            result.append((
                text: currentSegment.trimmingCharacters(in: .whitespacesAndNewlines),
                startCharIndex: segmentStartIndex,
                endCharIndex: lastSentence.endCharIndex
            ))
        }
        
        sentences = result
        
        // Log segment stats
        let charCounts = sentences.map { $0.text.count }
        let avgChars = charCounts.isEmpty ? 0 : charCounts.reduce(0, +) / charCounts.count
        let minChars = charCounts.min() ?? 0
        let maxChars = charCounts.max() ?? 0
        print("📝 Parsed \(sentences.count) natural segments (avg: \(avgChars) chars, range: \(minChars)-\(maxChars) chars)")
    }
    
    /// Parse text into individual sentences (helper function)
    private func parseIntoIndividualSentences() -> [(text: String, startCharIndex: Int, endCharIndex: Int)] {
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
        
        return result
    }
    
    /// Seek to the start of a specific sentence
    private func seekToSentence(at index: Int) {
        guard let tts = tts, tts.duration > 0, index >= 0, index < sentences.count else {
            return
        }
        
        // Calculate the start time for this sentence
        let sentenceTimeEstimates = calculateSentenceTimeRanges()
        guard index < sentenceTimeEstimates.count else { return }
        
        // Add a small negative offset to ensure we start from the very first character/word
        // This compensates for any timing estimation inaccuracies
        let targetTime = max(0, sentenceTimeEstimates[index].startTime - 0.1)
        print("🎯 Seeking to sentence \(index + 1)/\(sentences.count) at \(String(format: "%.2f", targetTime))s (sentence start: \(String(format: "%.2f", sentenceTimeEstimates[index].startTime))s)")
        
        // Seek to the start time of the sentence
        tts.seek(to: targetTime)
        
        // If not playing, start playing
        if !tts.isPlaying {
            tts.play()
        }
    }
    
    /// Calculate time ranges for all sentences based on weighted time estimation
    /// Uses enhanced weighting for more accurate TTS sync
    private func calculateSentenceTimeRanges() -> [(startTime: TimeInterval, endTime: TimeInterval)] {
        guard let tts = tts, tts.duration > 0, !sentences.isEmpty else {
            return []
        }
        
        var sentenceTimeEstimates: [(startTime: TimeInterval, endTime: TimeInterval)] = []
        
        // Calculate weight for each sentence with enhanced factors
        let sentenceWeights = sentences.map { sentence -> Double in
            let text = sentence.text
            
            // Base weight: character count
            var weight = Double(text.count)
            
            // Factor 1: Punctuation pause time (major impact)
            // Long pause: 。！？ (~0.5s each)
            let longPauseCount = text.filter { "。！？".contains($0) }.count
            weight += Double(longPauseCount) * 4.0
            
            // Medium pause: .!? (~0.3s each)
            let mediumPauseCount = text.filter { ".!?".contains($0) }.count
            weight += Double(mediumPauseCount) * 3.0
            
            // Short pause: ，、； (~0.2s each)
            let shortPauseCount = text.filter { "，、；,;".contains($0) }.count
            weight += Double(shortPauseCount) * 2.0
            
            // Factor 2: Numbers and dates (slower to read)
            let digitCount = text.filter { $0.isNumber }.count
            weight += Double(digitCount) * 0.5
            
            // Factor 3: English words (faster to read in TTS)
            let latinCount = text.filter { $0.isLetter && ($0 >= "A" && $0 <= "Z" || $0 >= "a" && $0 <= "z") }.count
            weight += Double(latinCount) * 0.8
            
            // Factor 4: Quotes and parentheses (slight pause)
            let quotePauseCount = text.filter { "「」『』\"\"《》()（）".contains($0) }.count
            weight += Double(quotePauseCount) * 0.5
            
            // Factor 5: Minimum weight per sentence (prevent zero or very small weights)
            weight = max(weight, 10.0)
            
            return weight
        }
        
        let totalWeight = sentenceWeights.reduce(0, +)
        guard totalWeight > 0 else { return [] }
        
        // Calculate time ranges for each sentence
        var accumulatedTime: TimeInterval = 0
        for (index, weight) in sentenceWeights.enumerated() {
            let sentenceDuration = (weight / totalWeight) * tts.duration
            let startTime = accumulatedTime
            let endTime = accumulatedTime + sentenceDuration
            sentenceTimeEstimates.append((startTime: startTime, endTime: endTime))
            accumulatedTime = endTime
            
            // Debug: Print time ranges for first call only
            if index < 3 {
                print("🎯 Sentence \(index + 1): \(String(format: "%.1f", startTime))s - \(String(format: "%.1f", endTime))s (weight: \(String(format: "%.0f", weight)))")
            }
        }
        
        return sentenceTimeEstimates
    }
    
    /// Update which sentence should be highlighted based on playback progress
    /// Uses weighted time estimation based on sentence length for more accurate sync
    private func updateHighlightedSentence() {
        guard let tts = tts, tts.duration > 0, tts.isPlaying, !sentences.isEmpty else {
            highlightedSentenceIndex = -1
            return
        }
        
        // Get time ranges for all sentences
        let sentenceTimeEstimates = calculateSentenceTimeRanges()
        guard !sentenceTimeEstimates.isEmpty else { return }
        
        let currentTime = tts.currentTime
        
        // Find which sentence corresponds to current playback time
        // Add a small tolerance (±0.2s) to handle timing variations
        let tolerance: TimeInterval = 0.2
        var newHighlightedIndex = -1
        
        for (index, timeRange) in sentenceTimeEstimates.enumerated() {
            // Check if current time falls within this sentence's time range (with tolerance)
            if currentTime >= (timeRange.startTime - tolerance) && currentTime < (timeRange.endTime + tolerance) {
                newHighlightedIndex = index
                break
            }
        }
        
        // If no exact match, find the closest sentence
        if newHighlightedIndex == -1 && !sentences.isEmpty {
            // If current time is before all sentences, highlight first
            if currentTime < sentenceTimeEstimates[0].startTime {
                newHighlightedIndex = 0
            }
            // If current time is after all sentences, highlight last
            else if currentTime >= sentenceTimeEstimates.last!.endTime {
                newHighlightedIndex = sentences.count - 1
            }
            // Otherwise find the closest sentence by start time
            else {
                var minDistance = TimeInterval.greatestFiniteMagnitude
                for (index, timeRange) in sentenceTimeEstimates.enumerated() {
                    // Prefer matching by start time for more intuitive highlighting
                    let distance = abs(currentTime - timeRange.startTime)
                    if distance < minDistance {
                        minDistance = distance
                        newHighlightedIndex = index
                    }
                }
            }
        }
        
        // Update highlighted sentence index
        if newHighlightedIndex != highlightedSentenceIndex && newHighlightedIndex >= 0 {
            let previousIndex = highlightedSentenceIndex
            highlightedSentenceIndex = newHighlightedIndex
            
            // Debug log (only show transitions, not every update)
            if previousIndex != newHighlightedIndex {
                let timeRange = sentenceTimeEstimates[newHighlightedIndex]
                print("🎯 Highlight: Sentence \(newHighlightedIndex + 1)/\(sentences.count) at \(String(format: "%.1f", currentTime))s (expected: \(String(format: "%.1f", timeRange.startTime))s-\(String(format: "%.1f", timeRange.endTime))s)")
            }
        }
    }
}

