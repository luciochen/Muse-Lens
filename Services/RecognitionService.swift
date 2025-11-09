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
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw RecognitionError.imageProcessingFailed
        }
        
        let base64Image = imageData.base64EncodedString()
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": """
                            Analyze this artwork image and identify the painting. 
                            Return a JSON array with top 3 candidates, each containing:
                            - artworkName: the full title of the artwork
                            - artist: the artist name (if identifiable)
                            - confidence: a number between 0 and 1
                            
                            If you cannot identify a specific artwork, try to identify the art style or movement.
                            Format: [{"artworkName": "...", "artist": "...", "confidence": 0.9}, ...]
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
            "max_tokens": 500,
            "temperature": 0.3
        ]
        
        guard let url = URL(string: baseURL) else {
            throw RecognitionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RecognitionError.apiRequestFailed
        }
        
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
        let jsonString = cleanedContent
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw RecognitionError.invalidResponse
        }
        
        let candidates = try JSONDecoder().decode([RecognitionCandidate].self, from: jsonData)
        
        return candidates.sorted { $0.confidence > $1.confidence }
    }
    
    enum RecognitionError: LocalizedError {
        case apiKeyMissing
        case imageProcessingFailed
        case invalidURL
        case apiRequestFailed
        case invalidResponse
        
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
            }
        }
    }
}

