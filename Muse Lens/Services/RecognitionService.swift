//
//  RecognitionService.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import Foundation
import UIKit

/// Service for recognizing artworks from photos using OpenAI Vision API
class RecognitionService {
    static let shared = RecognitionService()
    
    private let apiKey: String? // Should be set from environment or config
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    private init() {
        // Load API key from AppConfig
        self.apiKey = AppConfig.openAIApiKey
    }
    
    /// Recognize artwork from image, returns top 3 candidates
    func recognizeArtwork(from image: UIImage) async throws -> [RecognitionCandidate] {
        guard let apiKey = apiKey else {
            throw RecognitionError.apiKeyMissing
        }
        
        // Compress image to reduce size and improve API response time
        // Use lower quality for faster processing
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw RecognitionError.imageProcessingFailed
        }
        
        // Limit image size to avoid API errors (OpenAI has size limits)
        let maxSize = 4 * 1024 * 1024 // 4MB
        let finalImageData: Data
        if imageData.count > maxSize {
            // Resize image if too large
            let scale = sqrt(Double(maxSize) / Double(imageData.count))
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            if let resizedImage = resizeImage(image, to: newSize),
               let resizedData = resizedImage.jpegData(compressionQuality: 0.7) {
                finalImageData = resizedData
            } else {
                finalImageData = imageData
            }
        } else {
            finalImageData = imageData
        }
        
        let base64Image = finalImageData.base64EncodedString()
        print("📸 Image processed: \(finalImageData.count / 1024)KB, base64 length: \(base64Image.count)")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": """
                            You are a world-class art historian and expert. Your task is to identify famous artworks from images.
                            
                            CRITICAL: This image may contain a famous artwork. Look carefully for:
                            - Mona Lisa (La Gioconda) by Leonardo da Vinci - look for a woman with a mysterious smile, dark background, Renaissance style
                            - The Starry Night by Vincent van Gogh - swirling sky, cypress tree, village below
                            - The Last Supper by Leonardo da Vinci - Jesus and 12 disciples at a table
                            - The Scream by Edvard Munch - figure with hands on face, swirling background
                            - Girl with a Pearl Earring by Johannes Vermeer - young woman with pearl earring, dark background
                            - Sunflowers by Vincent van Gogh - yellow sunflowers in a vase
                            - The Persistence of Memory by Salvador Dalí - melting clocks
                            - And many other famous paintings
                            
                            Analyze the image VERY CAREFULLY. Look for distinctive features, composition, style, and subjects.
                            
                            Return a JSON array with 1-3 candidates. Each candidate must be a JSON object with exactly these fields:
                            - "artworkName": string (the EXACT artwork title - use most common name like "Mona Lisa" not "La Gioconda")
                            - "artist": string or null (the EXACT full artist name, e.g., "Leonardo da Vinci", "Vincent van Gogh")
                            - "confidence": number between 0.1 and 1.0 (use high confidence 0.85-1.0 for famous artworks you're certain about)
                            
                            PRIORITY:
                            1. FIRST: Look for famous, well-known artworks (Mona Lisa, Starry Night, etc.) - be confident if you see distinctive features
                            2. SECOND: If not famous, try to identify the specific artwork title and artist
                            3. LAST: If completely unknown, identify the art style (e.g., "Impressionism", "Baroque", "Renaissance")
                            
                            IMPORTANT:
                            - Be CONFIDENT if you recognize a famous artwork - use confidence 0.85-1.0
                            - Use the artwork's most common English name (e.g., "Mona Lisa" not "La Gioconda")
                            - Use full artist names (e.g., "Leonardo da Vinci" not just "da Vinci" or "Leonardo")
                            - Always return at least one candidate
                            - Return ONLY the JSON array, no markdown, no explanation, no other text
                            
                            Example for famous artwork (be confident):
                            [{"artworkName": "Mona Lisa", "artist": "Leonardo da Vinci", "confidence": 0.95}]
                            
                            Example for less known artwork:
                            [{"artworkName": "The Starry Night", "artist": "Vincent van Gogh", "confidence": 0.9}]
                            
                            Example for unknown artwork:
                            [{"artworkName": "Impressionism", "artist": null, "confidence": 0.6}]
                            """
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 300,
            "temperature": 0.2
        ]
        
        guard let url = URL(string: baseURL) else {
            throw RecognitionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 10.0 // 10 second timeout
        
        // Use URLSession with timeout and error handling
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw RecognitionError.apiRequestFailed
            }
            
            return try await parseResponse(data: data)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw RecognitionError.timeout
            } else {
                throw RecognitionError.apiRequestFailed
            }
        } catch {
            throw error
        }
    }
    
    private func parseResponse(data: Data) async throws -> [RecognitionCandidate] {
        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = jsonResponse?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw RecognitionError.invalidResponse
        }
        
        // Parse JSON from response content
        let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Extract JSON array from markdown code blocks if present
        var jsonString = cleanedContent
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to extract JSON array from the response
        // Find the first '[' and last ']' to extract the JSON array
        if let firstBracket = jsonString.firstIndex(of: "["),
           let lastBracket = jsonString.lastIndex(of: "]"),
           firstBracket < lastBracket {
            jsonString = String(jsonString[firstBracket...lastBracket])
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw RecognitionError.invalidResponse
        }
        
        // Try to decode with better error handling
        do {
            let candidates = try JSONDecoder().decode([RecognitionCandidate].self, from: jsonData)
            
            // Validate and filter candidates
            // Don't filter too strictly - accept all candidates with non-empty names
            var validCandidates = candidates.filter { candidate in
                // Accept candidates with non-empty artwork name (even if confidence is low)
                !candidate.artworkName.trimmingCharacters(in: .whitespaces).isEmpty
            }
            
            // Log all candidates for debugging
            print("📊 All candidates received:")
            for (index, candidate) in candidates.enumerated() {
                print("  \(index + 1). \(candidate.artworkName) by \(candidate.artist ?? "Unknown") (confidence: \(candidate.confidence))")
            }
            
            // If no valid candidates, use the first candidate anyway (even if low confidence)
            if validCandidates.isEmpty && !candidates.isEmpty {
                // Create a valid candidate from the first one, ensuring minimum confidence
                let first = candidates[0]
                let adjustedCandidate = RecognitionCandidate(
                    artworkName: first.artworkName.isEmpty ? "Unknown Artwork" : first.artworkName,
                    artist: first.artist,
                    confidence: max(first.confidence, 0.3) // Ensure minimum confidence
                )
                validCandidates = [adjustedCandidate]
            }
            
            // Always return at least one candidate
            if validCandidates.isEmpty {
                // Last resort: create a fallback candidate
                print("⚠️ No valid candidates found, creating fallback")
                return [RecognitionCandidate(
                    artworkName: "Unknown Artwork",
                    artist: nil,
                    confidence: 0.3
                )]
            }
            
            return validCandidates.sorted { $0.confidence > $1.confidence }
        } catch {
            // If parsing fails, try to create a fallback candidate from the text
            print("❌ JSON parsing error: \(error)")
            print("📝 Response content: \(content)")
            print("📄 JSON string: \(jsonString)")
            
            // Try to extract artwork name from the text response
            let fallbackName = extractArtworkName(from: content)
            let fallbackCandidate = RecognitionCandidate(
                artworkName: fallbackName,
                artist: nil,
                confidence: 0.4
            )
            print("✅ Created fallback candidate: \(fallbackName)")
            return [fallbackCandidate]
        }
    }
    
    /// Extract artwork name from text response as fallback
    private func extractArtworkName(from text: String) -> String {
        // Try to find artwork name patterns
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Look for lines that might contain artwork names
            if !trimmed.isEmpty && trimmed.count > 3 && trimmed.count < 100 {
                // Remove common prefixes
                let cleaned = trimmed
                    .replacingOccurrences(of: "Title:", with: "")
                    .replacingOccurrences(of: "Artwork:", with: "")
                    .replacingOccurrences(of: "Name:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        return "Unknown Artwork"
    }
    
    /// Resize image to reduce file size
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    enum RecognitionError: LocalizedError {
        case apiKeyMissing
        case imageProcessingFailed
        case invalidURL
        case apiRequestFailed
        case invalidResponse
        case timeout
        
        var errorDescription: String? {
            switch self {
            case .apiKeyMissing:
                return "API key not configured. Please set OPENAI_API_KEY environment variable."
            case .imageProcessingFailed:
                return "Failed to process image"
            case .invalidURL:
                return "Invalid API URL"
            case .apiRequestFailed:
                return "API request failed. Please check your network connection."
            case .invalidResponse:
                return "Invalid response from recognition service"
            case .timeout:
                return "Request timed out. Please try again."
            }
        }
    }
}

