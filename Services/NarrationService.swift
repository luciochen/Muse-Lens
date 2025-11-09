//
//  NarrationService.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import Foundation

/// Service for generating narration based on retrieved artwork information
class NarrationService {
    static let shared = NarrationService()
    
    private let apiKey: String? // Should be set from environment or config
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    private init() {
        // Load API key from AppConfig
        self.apiKey = AppConfig.openAIApiKey
    }
    
    /// Generate narration script based on artwork information
    func generateNarration(artworkInfo: ArtworkInfo, additionalContext: String? = nil) async throws -> NarrationResponse {
        guard let apiKey = apiKey else {
            throw NarrationError.apiKeyMissing
        }
        
        var context = """
        Title: \(artworkInfo.title)
        Artist: \(artworkInfo.artist)
        """
        
        if let year = artworkInfo.year {
            context += "\nYear: \(year)"
        }
        if let style = artworkInfo.style {
            context += "\nStyle: \(style)"
        }
        if let medium = artworkInfo.medium {
            context += "\nMedium: \(medium)"
        }
        if let museum = artworkInfo.museum {
            context += "\nMuseum: \(museum)"
        }
        
        if let additional = additionalContext {
            context += "\n\nAdditional Context: \(additional)"
        }
        
        context += "\n\nSources: \(artworkInfo.sources.joined(separator: ", "))"
        
        let prompt: String
        if artworkInfo.recognized {
            prompt = """
            Based ONLY on the provided artwork information from verified sources, create a 1-2 minute audio narration (250-350 words) in Chinese.
            
            Requirements:
            1. Strictly base content on the provided facts - DO NOT fabricate or infer information
            2. Write in a conversational, engaging tone suitable for general museum visitors
            3. Include: what the artwork depicts, its historical context, artistic techniques, and significance
            4. Keep it accessible and interesting, not academic
            5. If information is incomplete, only mention what you know from the sources
            
            Artwork Information:
            \(context)
            
            Return a JSON object with this exact structure:
            {
                "title": "artwork title",
                "artist": "artist name",
                "year": "year or null",
                "style": "style or null",
                "summary": "2-3 sentence summary",
                "narration": "full narration text (250-350 words)",
                "sources": ["source URL 1", "source URL 2"]
            }
            """
        } else {
            prompt = """
            This artwork was not specifically identified, but it appears to be in the \(artworkInfo.style ?? "unknown") style.
            
            Create a 1-2 minute audio narration (250-350 words) in Chinese explaining this art style or movement.
            
            Requirements:
            1. Base content on verified information from Wikipedia or other reliable sources
            2. Explain the characteristics, origins, and notable artists of this style
            3. Write in a conversational, engaging tone
            4. Keep it accessible and interesting
            
            Style Information:
            \(context)
            
            Return a JSON object with this exact structure:
            {
                "title": "Art Style Name",
                "artist": "Various Artists",
                "year": null,
                "style": "style name",
                "summary": "2-3 sentence summary",
                "narration": "full narration text (250-350 words)",
                "sources": ["source URL 1"]
            }
            """
        }
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "system",
                    "content": "You are a museum guide assistant. You ONLY provide information based on verified sources. Never invent or infer facts."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": 800,
            "temperature": 0.7,
            "response_format": ["type": "json_object"] as [String: Any]
        ]
        
        guard let url = URL(string: baseURL) else {
            throw NarrationError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NarrationError.apiRequestFailed
        }
        
        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = jsonResponse?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NarrationError.invalidResponse
        }
        
        guard let jsonData = content.data(using: .utf8) else {
            throw NarrationError.invalidResponse
        }
        
        let narrationResponse = try JSONDecoder().decode(NarrationResponse.self, from: jsonData)
        return narrationResponse
    }
    
    enum NarrationError: LocalizedError {
        case apiKeyMissing
        case invalidURL
        case apiRequestFailed
        case invalidResponse
        
        var errorDescription: String? {
            switch self {
            case .apiKeyMissing:
                return "API key not configured"
            case .invalidURL:
                return "Invalid API URL"
            case .apiRequestFailed:
                return "Failed to generate narration. Please check your network connection."
            case .invalidResponse:
                return "Invalid response from narration service"
            }
        }
    }
}

