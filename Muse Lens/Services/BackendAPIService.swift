//
//  BackendAPIService.swift
//  Muse Lens
//
//  Backend API service for shared artwork cache
//

import Foundation

/// Backend API service for artwork cache
class BackendAPIService {
    static let shared = BackendAPIService()
    
    // Backend URL (Supabase or custom backend)
    private let baseURL: String?
    private let apiKey: String?
    
    private init() {
        // Load from AppConfig
        self.baseURL = AppConfig.backendAPIURL
        self.apiKey = AppConfig.backendAPIKey
    }
    
    /// Check if backend is configured
    var isConfigured: Bool {
        return baseURL != nil && apiKey != nil
    }
    
    // MARK: - Artwork API
    
    /// Check if artwork exists by combined identifier
    /// Returns: Artwork if found, nil if not found
    func findArtwork(identifier: ArtworkIdentifier, retryCount: Int = 1) async throws -> BackendArtwork? {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            throw BackendAPIError.unauthorized
        }
        
        guard let encodedHash = identifier.combinedHash.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/rest/v1/artworks?combined_hash=eq.\(encodedHash)&select=*") else {
            throw BackendAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8.0 // 8 second timeout for read operations
        
        var lastError: Error?
        for attempt in 0...retryCount {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BackendAPIError.invalidResponse
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    if httpResponse.statusCode == 401 {
                        throw BackendAPIError.unauthorized
                    }
                    throw BackendAPIError.requestFailed
                }
                
                let decoder = JSONDecoder()
                // Use flexible date decoding to handle various date formats
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateString = try container.decode(String.self)
                    
                    // Try multiple date formats
                    let formatters: [DateFormatter] = [
                        {
                            let f = DateFormatter()
                            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
                            f.timeZone = TimeZone(secondsFromGMT: 0)
                            return f
                        }(),
                        {
                            let f = DateFormatter()
                            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                            f.timeZone = TimeZone(secondsFromGMT: 0)
                            return f
                        }(),
                        {
                            let f = DateFormatter()
                            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                            f.timeZone = TimeZone(secondsFromGMT: 0)
                            return f
                        }(),
                        {
                            let f = ISO8601DateFormatter()
                            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            return DateFormatter() // Placeholder, we'll use ISO8601DateFormatter directly
                        }()
                    ]
                    
                    // Try ISO8601DateFormatter first
                    let iso8601Formatter = ISO8601DateFormatter()
                    iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = iso8601Formatter.date(from: dateString) {
                        return date
                    }
                    
                    // Try without fractional seconds
                    iso8601Formatter.formatOptions = [.withInternetDateTime]
                    if let date = iso8601Formatter.date(from: dateString) {
                        return date
                    }
                    
                    // Try custom formatters
                    for formatter in formatters.prefix(3) {
                        if let date = formatter.date(from: dateString) {
                            return date
                        }
                    }
                    
                    // If all fail, return a default date (current date) instead of throwing
                    // This allows us to read the record even if date parsing fails
                    print("⚠️ Failed to parse date: \(dateString), using current date as fallback")
                    return Date()
                }
                
                do {
                    let artworks = try decoder.decode([BackendArtwork].self, from: data)
                    return artworks.first
                } catch {
                    // If decoding fails due to date issues, try decoding without dates
                    print("⚠️ Decoding failed, trying without date fields: \(error)")
                    // Return nil to allow retry or fallback
                    throw error
                }
            } catch let error as BackendAPIError {
                // Don't retry for authorization errors
                if case .unauthorized = error {
                    throw error
                }
                lastError = error
                if attempt < retryCount {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                }
            } catch let urlError as URLError {
                // Network errors: retry if possible
                let isRetriable = urlError.code == .networkConnectionLost ||
                                 urlError.code == .notConnectedToInternet ||
                                 urlError.code == .timedOut ||
                                 urlError.code == .cannotConnectToHost ||
                                 urlError.code == .cannotFindHost
                
                if isRetriable && attempt < retryCount {
                    lastError = urlError
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                } else {
                    // Non-retriable error or max retries reached
                    print("⚠️ Network error finding artwork: \(urlError.localizedDescription)")
                    throw BackendAPIError.networkError
                }
            } catch {
                lastError = error
                if attempt < retryCount {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                }
            }
        }
        
        // All retries failed, return nil (not found) instead of throwing
        // This allows the app to continue with local generation
        if let lastError = lastError {
            print("⚠️ Failed to find artwork after retries: \(lastError)")
        }
        return nil
    }
    
    /// Search artwork by title and artist (fuzzy matching)
    func searchArtwork(title: String, artist: String) async throws -> [BackendArtwork] {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            throw BackendAPIError.unauthorized
        }
        
        let normalizedTitle = ArtworkIdentifier.generate(title: title, artist: "").normalizedTitle
        let normalizedArtist = ArtworkIdentifier.generate(title: "", artist: artist).normalizedArtist
        
        guard let encodedTitle = normalizedTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = normalizedArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/rest/v1/artworks?normalized_title=ilike.\(encodedTitle)%&normalized_artist=ilike.\(encodedArtist)%&select=*&limit=5") else {
            throw BackendAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw BackendAPIError.requestFailed
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([BackendArtwork].self, from: data)
        } catch {
            print("❌ Backend search error: \(error)")
            throw BackendAPIError.requestFailed
        }
    }
    
    /// Save artwork to backend with retry mechanism
    /// Uses upsert: checks if artwork exists (by combined_hash), updates if found, inserts if not
    func saveArtwork(_ artwork: BackendArtwork, retryCount: Int = 2) async throws {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            print("❌ Backend not configured: baseURL=\(baseURL ?? "nil"), apiKey=\(apiKey != nil ? "set" : "nil")")
            throw BackendAPIError.unauthorized
        }
        
        // First, check if artwork already exists by combined_hash
        let identifier = ArtworkIdentifier.generate(
            title: artwork.title,
            artist: artwork.artist,
            year: artwork.year
        )
        
        let existingArtwork = try? await findArtwork(identifier: identifier, retryCount: 0)
        let artworkExists = existingArtwork != nil
        
        // Use PATCH for update, POST for insert
        let httpMethod: String
        let urlString: String
        
        if artworkExists, let artworkId = existingArtwork?.id {
            // Update existing artwork
            httpMethod = "PATCH"
            urlString = "\(baseURL)/rest/v1/artworks?id=eq.\(artworkId)"
            print("🔄 Updating existing artwork: '\(artwork.title)' by '\(artwork.artist)' (ID: \(artworkId))")
        } else {
            // Insert new artwork
            httpMethod = "POST"
            urlString = "\(baseURL)/rest/v1/artworks"
            print("➕ Inserting new artwork: '\(artwork.title)' by '\(artwork.artist)'")
        }
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
            throw BackendAPIError.invalidResponse
        }
        
        print("💾 Attempting to save artwork: '\(artwork.title)' by '\(artwork.artist)'")
        print("💾 URL: \(url.absoluteString)")
        print("💾 Method: \(httpMethod)")
        
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        // Supabase REST API requires both apikey and Authorization header
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.timeoutInterval = 10.0 // 10 second timeout
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        // For PATCH (update), only send fields that should be updated
        let jsonData: Data
        do {
            if httpMethod == "PATCH" {
                // Only update fields that might have changed (exclude id, timestamps, view_count)
                let updateData: [String: Any?] = [
                    "title": artwork.title,
                    "artist": artwork.artist,
                    "year": artwork.year,
                    "style": artwork.style,
                    "medium": artwork.medium,
                    "museum": artwork.museum,
                    "image_url": artwork.imageUrl,
                    "sources": artwork.sources,
                    "narration": artwork.narration,
                    "summary": artwork.summary,
                    "confidence": artwork.confidence,
                    "recognized": artwork.recognized,
                    "normalized_title": artwork.normalizedTitle,
                    "normalized_artist": artwork.normalizedArtist
                ]
                
                // Remove nil values
                let filteredData = updateData.compactMapValues { $0 }
                jsonData = try JSONSerialization.data(withJSONObject: filteredData)
            } else {
                // For POST (insert), manually build JSON to exclude fields that might cause schema cache issues
                // Exclude: lastViewedAt, viewCount, createdAt, updatedAt - let database handle these with defaults
                let insertData: [String: Any?] = [
                    "combined_hash": artwork.combinedHash,
                    "normalized_title": artwork.normalizedTitle,
                    "normalized_artist": artwork.normalizedArtist,
                    "title": artwork.title,
                    "title_en": artwork.titleEn,
                    "artist": artwork.artist,
                    "artist_en": artwork.artistEn,
                    "year": artwork.year,
                    "style": artwork.style,
                    "medium": artwork.medium,
                    "museum": artwork.museum,
                    "image_url": artwork.imageUrl,
                    "sources": artwork.sources,
                    "narration": artwork.narration,
                    "narration_en": artwork.narrationEn,
                    "summary": artwork.summary,
                    "confidence": artwork.confidence,
                    "recognized": artwork.recognized
                    // Exclude view_count, last_viewed_at, created_at, updated_at
                    // Database will use defaults: view_count DEFAULT 0, timestamps DEFAULT NOW()
                ]
                
                // Remove nil values
                let filteredData = insertData.compactMapValues { $0 }
                jsonData = try JSONSerialization.data(withJSONObject: filteredData)
            }
            
            request.httpBody = jsonData
            
            // Debug: Print JSON payload (first 500 chars)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("💾 JSON payload size: \(jsonData.count) bytes")
                print("💾 JSON preview: \(String(jsonString.prefix(500)))...")
            }
        } catch {
            print("❌ Failed to encode artwork: \(error)")
            print("❌ Encoding error details: \(error.localizedDescription)")
            throw BackendAPIError.saveFailed
        }
        
        var lastError: Error?
        for attempt in 0...retryCount {
            do {
                print("📡 Sending \(httpMethod) request (attempt \(attempt + 1)/\(retryCount + 1))...")
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid HTTP response type")
                    throw BackendAPIError.invalidResponse
                }
                
                print("📡 HTTP Status: \(httpResponse.statusCode)")
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    let errorData = String(data: data, encoding: .utf8) ?? "Unable to decode error"
                    print("❌ Backend API error (HTTP \(httpResponse.statusCode)): \(errorData)")
                    
                    // Print all response headers for debugging
                    print("📡 Response headers:")
                    for (key, value) in httpResponse.allHeaderFields {
                        print("   \(key): \(value)")
                    }
                    
                    if httpResponse.statusCode == 401 {
                        print("❌ Unauthorized - check API key")
                        throw BackendAPIError.unauthorized
                    } else if httpResponse.statusCode == 403 {
                        print("❌ Forbidden - check RLS policies")
                        throw BackendAPIError.unauthorized
                    } else if httpResponse.statusCode == 400 {
                        print("❌ Bad Request - check data format")
                        print("❌ Error details: \(errorData)")
                    } else if httpResponse.statusCode == 409 {
                        // Conflict - record already exists, try to find and update it
                        print("⚠️ Conflict (409) - artwork already exists, attempting to find and update...")
                        
                        // Try to find existing artwork by combined_hash (without date parsing issues)
                        do {
                            if let existing = try await findArtworkByHashOnly(combinedHash: artwork.combinedHash) {
                                print("✅ Found existing artwork, updating instead of inserting...")
                                // Update existing artwork using PATCH
                                return try await updateArtworkById(artworkId: existing.id!, artwork: artwork, retryCount: retryCount - attempt)
                            } else {
                                print("⚠️ Could not find existing artwork by hash, but 409 suggests it exists")
                                // Try a direct query without date parsing
                                if let existing = try await findArtworkDirect(combinedHash: artwork.combinedHash) {
                                    print("✅ Found existing artwork via direct query, updating...")
                                    return try await updateArtworkById(artworkId: existing.id!, artwork: artwork, retryCount: retryCount - attempt)
                                }
                            }
                        } catch {
                            print("⚠️ Failed to find existing artwork: \(error)")
                        }
                        
                        print("❌ Conflict error - unable to resolve (artwork exists but cannot be found/updated)")
                    }
                    throw BackendAPIError.saveFailed
                }
                
                // Success - print response data if available
                if let responseString = String(data: data, encoding: .utf8), !responseString.isEmpty {
                    print("✅ Artwork saved successfully. Response: \(responseString.prefix(200))")
                } else {
                    print("✅ Artwork saved to backend successfully (no response data)")
                }
                return // Success, exit
            } catch let error as BackendAPIError {
                // Don't retry for authorization errors
                if case .unauthorized = error {
                    print("❌ Authorization error - not retrying")
                    throw error
                }
                lastError = error
                if attempt < retryCount {
                    let delay = Double(attempt + 1) * 1.0 // Exponential backoff: 1s, 2s
                    print("⚠️ Save attempt \(attempt + 1) failed, retrying in \(delay)s...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch let urlError as URLError {
                // Network errors: retry if possible
                let isRetriable = urlError.code == .networkConnectionLost ||
                                 urlError.code == .notConnectedToInternet ||
                                 urlError.code == .timedOut ||
                                 urlError.code == .cannotConnectToHost ||
                                 urlError.code == .cannotFindHost
                
                if isRetriable && attempt < retryCount {
                    lastError = urlError
                    let delay = Double(attempt + 1) * 1.0 // Exponential backoff: 1s, 2s
                    print("⚠️ Network error (attempt \(attempt + 1)/\(retryCount + 1)): \(urlError.localizedDescription)")
                    print("⚠️ Error code: \(urlError.code.rawValue)")
                    print("⚠️ Retrying in \(delay)s...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    // Non-retriable error or max retries reached
                    print("❌ Network error (non-retriable or max retries): \(urlError.localizedDescription)")
                    print("❌ Error code: \(urlError.code.rawValue)")
                    throw BackendAPIError.networkError
                }
            } catch {
                lastError = error
                print("❌ Failed to save artwork (attempt \(attempt + 1)): \(error)")
                print("❌ Error type: \(type(of: error))")
                if attempt < retryCount {
                    let delay = Double(attempt + 1) * 1.0
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        // All retries failed
        if let lastError = lastError {
            print("❌ Failed to save artwork after \(retryCount + 1) attempts")
            print("❌ Last error: \(lastError)")
            print("❌ Error type: \(type(of: lastError))")
            throw BackendAPIError.saveFailed
        } else {
            print("❌ Failed to save artwork - unknown error")
            throw BackendAPIError.saveFailed
        }
    }
    
    /// Find artwork by combined_hash only (simplified, for conflict resolution)
    /// This version doesn't parse dates to avoid decoding errors
    private func findArtworkByHashOnly(combinedHash: String) async throws -> BackendArtwork? {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            throw BackendAPIError.unauthorized
        }
        
        guard let encodedHash = combinedHash.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/rest/v1/artworks?combined_hash=eq.\(encodedHash)&select=id,combined_hash,title,artist") else {
            throw BackendAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        
        // Parse minimal JSON (only id, combined_hash, title, artist) to avoid date parsing issues
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = jsonArray.first,
           let id = first["id"] as? String {
            // Create minimal BackendArtwork with just the ID
            return BackendArtwork(
                id: id,
                combinedHash: combinedHash,
                normalizedTitle: first["title"] as? String ?? "",
                normalizedArtist: first["artist"] as? String ?? "",
                title: first["title"] as? String ?? "",
                titleEn: nil,
                artist: first["artist"] as? String ?? "",
                artistEn: nil,
                year: nil,
                style: nil,
                medium: nil,
                museum: nil,
                imageUrl: nil,
                sources: [],
                narration: "",
                narrationEn: nil,
                summary: "",
                confidence: 0.0,
                recognized: true,
                viewCount: nil,
                lastViewedAt: nil,
                createdAt: nil,
                updatedAt: nil
            )
        }
        
        return nil
    }
    
    /// Find artwork directly without full decoding (for conflict resolution)
    private func findArtworkDirect(combinedHash: String) async throws -> BackendArtwork? {
        // Use the same method as findArtworkByHashOnly
        return try await findArtworkByHashOnly(combinedHash: combinedHash)
    }
    
    /// Update artwork by ID (helper for conflict resolution)
    private func updateArtworkById(artworkId: String, artwork: BackendArtwork, retryCount: Int = 2) async throws {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            throw BackendAPIError.unauthorized
        }
        
        guard let url = URL(string: "\(baseURL)/rest/v1/artworks?id=eq.\(artworkId)") else {
            throw BackendAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.timeoutInterval = 10.0
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let updateData: [String: Any?] = [
            "title": artwork.title,
            "artist": artwork.artist,
            "year": artwork.year,
            "style": artwork.style,
            "medium": artwork.medium,
            "museum": artwork.museum,
            "image_url": artwork.imageUrl,
            "sources": artwork.sources,
            "narration": artwork.narration,
            "summary": artwork.summary,
            "confidence": artwork.confidence,
            "recognized": artwork.recognized,
            "normalized_title": artwork.normalizedTitle,
            "normalized_artist": artwork.normalizedArtist
        ]
        
        let filteredData = updateData.compactMapValues { $0 }
        request.httpBody = try JSONSerialization.data(withJSONObject: filteredData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            let errorData = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Failed to update artwork: Invalid HTTP response")
            throw BackendAPIError.saveFailed
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorData = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Failed to update artwork: HTTP \(httpResponse.statusCode), \(errorData)")
            
            // Check for schema cache errors
            if errorData.contains("PGRST204") || errorData.contains("schema cache") || errorData.contains("last_viewed_at") {
                print("")
                print("⚠️⚠️⚠️ SCHEMA CACHE ERROR DETECTED ⚠️⚠️⚠️")
                print("The database schema cache needs to be refreshed.")
                print("Please execute migration scripts in Supabase SQL Editor,")
                print("then wait 2-5 minutes for cache refresh.")
                print("See SCHEMA_CACHE_FIX.md for detailed instructions")
                print("⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️")
                print("")
            }
            throw BackendAPIError.saveFailed
        }
        
        print("✅ Artwork updated successfully via PATCH")
    }
    
    /// Increment view count (async, non-blocking)
    /// This is a fire-and-forget operation - failures are silently ignored
    func incrementViewCount(artworkId: String) async {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            return
        }
        
        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/increment_artwork_view_count") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0 // 5 second timeout for non-critical operation
        
        let body = ["artwork_id": artworkId]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            // Silently fail - this is not critical
            return
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                // Success - no need to log for non-critical operation
            }
        } catch {
            // Silently fail - view count increment is not critical
            // Network errors are expected and should not be logged
        }
    }
    
    // MARK: - Artist API
    
    /// Find artist introduction by artist name
    /// First tries exact match by name, then normalized_name, then fuzzy matching
    func findArtistIntroduction(artist: String, retryCount: Int = 1) async throws -> BackendArtist? {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            throw BackendAPIError.unauthorized
        }
        
        let normalizedName = ArtworkIdentifier.generate(title: "", artist: artist).normalizedArtist
        
        // First, try exact match by name (as requested by user)
        guard let encodedName = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedNormalizedName = normalizedName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw BackendAPIError.invalidResponse
        }
        
        // Try exact match by name first
        let nameMatchUrlString = "\(baseURL)/rest/v1/artists?name=eq.\(encodedName)&select=*"
        guard let nameMatchUrl = URL(string: nameMatchUrlString) else {
            throw BackendAPIError.invalidResponse
        }
        
        var nameRequest = URLRequest(url: nameMatchUrl)
        nameRequest.setValue(apiKey, forHTTPHeaderField: "apikey")
        nameRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        nameRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        nameRequest.timeoutInterval = 8.0
        
        // Try name match first
        do {
            let (data, response) = try await URLSession.shared.data(for: nameRequest)
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                let decoder = JSONDecoder()
                // Use same flexible date decoding as artworks
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateString = try container.decode(String.self)
                    
                    let iso8601Formatter = ISO8601DateFormatter()
                    iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = iso8601Formatter.date(from: dateString) {
                        return date
                    }
                    
                    iso8601Formatter.formatOptions = [.withInternetDateTime]
                    if let date = iso8601Formatter.date(from: dateString) {
                        return date
                    }
                    
                    print("⚠️ Failed to parse artist date: \(dateString), using current date as fallback")
                    return Date()
                }
                
                do {
                    let artists = try decoder.decode([BackendArtist].self, from: data)
                    if let artist = artists.first {
                        print("✅ Found artist by name: '\(artist.name)'")
                        return artist
                    }
                } catch {
                    print("⚠️ Failed to decode artist, trying minimal decode: \(error)")
                    // Try minimal decode (just id and name)
                    if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                       let first = jsonArray.first,
                       let id = first["id"] as? String,
                       let name = first["name"] as? String {
                        return BackendArtist(
                            id: id,
                            name: name,
                            nameEn: first["name_en"] as? String,
                            normalizedName: first["normalized_name"] as? String ?? normalizedName,
                            artistIntroduction: first["artist_introduction"] as? String,
                            artworksCount: first["artworks_count"] as? Int,
                            createdAt: nil,
                            updatedAt: nil
                        )
                    }
                }
            }
        } catch {
            print("⚠️ Name match failed, trying normalized_name: \(error.localizedDescription)")
        }
        
        // If name match failed, try normalized_name
        let exactMatchUrlString = "\(baseURL)/rest/v1/artists?normalized_name=eq.\(encodedNormalizedName)&select=*"
        guard let exactMatchUrl = URL(string: exactMatchUrlString) else {
            throw BackendAPIError.invalidResponse
        }
        
        var request = URLRequest(url: exactMatchUrl)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8.0 // 8 second timeout
        
        var lastError: Error?
        var triedFuzzyMatch = false
        
        for attempt in 0...retryCount {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BackendAPIError.invalidResponse
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    // If exact match failed (404 or empty result), try fuzzy match only once
                    if attempt == 0 && !triedFuzzyMatch {
                        triedFuzzyMatch = true
                        print("⚠️ Normalized name match failed (HTTP \(httpResponse.statusCode)), trying fuzzy match...")
                        
                        // Try fuzzy match by name first, then normalized_name
                        let fuzzyNameUrlString = "\(baseURL)/rest/v1/artists?name=ilike.\(encodedName)%&select=*&limit=5"
                        guard let fuzzyNameUrl = URL(string: fuzzyNameUrlString) else {
                            throw BackendAPIError.invalidResponse
                        }
                        
                        var fuzzyNameRequest = URLRequest(url: fuzzyNameUrl)
                        fuzzyNameRequest.setValue(apiKey, forHTTPHeaderField: "apikey")
                        fuzzyNameRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                        fuzzyNameRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        fuzzyNameRequest.timeoutInterval = 6.0
                        
                        do {
                            let (fuzzyNameData, fuzzyNameResponse) = try await URLSession.shared.data(for: fuzzyNameRequest)
                            if let fuzzyNameHttpResponse = fuzzyNameResponse as? HTTPURLResponse,
                               (200...299).contains(fuzzyNameHttpResponse.statusCode) {
                                let decoder = JSONDecoder()
                                decoder.dateDecodingStrategy = .iso8601
                                let artists = try decoder.decode([BackendArtist].self, from: fuzzyNameData)
                                
                                // Find the best match using fuzzy matching
                                if let bestMatch = findBestArtistMatch(artists: artists, targetName: artist) {
                                    print("✅ Found artist using fuzzy name match: '\(bestMatch.name)'")
                                    return bestMatch
                                }
                            }
                        } catch {
                            print("⚠️ Fuzzy name match failed: \(error)")
                        }
                        
                        // Try fuzzy match by normalized_name
                        let fuzzyUrlString = "\(baseURL)/rest/v1/artists?normalized_name=ilike.\(encodedNormalizedName)%&select=*&limit=5"
                        guard let fuzzyUrl = URL(string: fuzzyUrlString) else {
                            throw BackendAPIError.invalidResponse
                        }
                        
                        var fuzzyRequest = URLRequest(url: fuzzyUrl)
                        fuzzyRequest.setValue(apiKey, forHTTPHeaderField: "apikey")
                        fuzzyRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                        fuzzyRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        fuzzyRequest.timeoutInterval = 6.0 // 6 second timeout (reduced to prevent hanging)
                        
                        do {
                            let (fuzzyData, fuzzyResponse) = try await URLSession.shared.data(for: fuzzyRequest)
                            if let fuzzyHttpResponse = fuzzyResponse as? HTTPURLResponse,
                               (200...299).contains(fuzzyHttpResponse.statusCode) {
                                let decoder = JSONDecoder()
                                decoder.dateDecodingStrategy = .iso8601
                                let artists = try decoder.decode([BackendArtist].self, from: fuzzyData)
                                
                                // Find the best match using fuzzy matching
                                if let bestMatch = findBestArtistMatch(artists: artists, targetName: normalizedName) {
                                    print("✅ Found artist using fuzzy match: '\(bestMatch.name)'")
                                    return bestMatch
                                }
                            }
                        } catch {
                            print("⚠️ Fuzzy match also failed: \(error)")
                            // Continue to throw original error
                        }
                    }
                    
                    // If it's a 404 or empty result, return nil (not found) instead of throwing
                    if httpResponse.statusCode == 404 || (httpResponse.statusCode == 200 && data.count < 10) {
                        print("ℹ️ Artist not found in database")
                        return nil
                    }
                    
                    throw BackendAPIError.requestFailed
                }
                
                let decoder = JSONDecoder()
                // Use flexible date decoding
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateString = try container.decode(String.self)
                    
                    let iso8601Formatter = ISO8601DateFormatter()
                    iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = iso8601Formatter.date(from: dateString) {
                        return date
                    }
                    
                    iso8601Formatter.formatOptions = [.withInternetDateTime]
                    if let date = iso8601Formatter.date(from: dateString) {
                        return date
                    }
                    
                    print("⚠️ Failed to parse date: \(dateString), using current date as fallback")
                    return Date()
                }
                
                do {
                    let artists = try decoder.decode([BackendArtist].self, from: data)
                    
                    // If empty result, return nil
                    if artists.isEmpty {
                        print("ℹ️ No artists found in database")
                        return nil
                    }
                    
                    // If we got multiple results (from fuzzy match), find the best match
                    if artists.count > 1 {
                        if let bestMatch = findBestArtistMatch(artists: artists, targetName: normalizedName) {
                            print("✅ Found artist using fuzzy match: '\(bestMatch.name)'")
                            return bestMatch
                        }
                    }
                    
                    return artists.first
                } catch {
                    print("⚠️ Failed to decode artists, trying minimal decode: \(error)")
                    // Try minimal decode
                    if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                       let first = jsonArray.first,
                       let id = first["id"] as? String,
                       let name = first["name"] as? String {
                        return BackendArtist(
                            id: id,
                            name: name,
                            nameEn: first["name_en"] as? String,
                            normalizedName: first["normalized_name"] as? String ?? normalizedName,
                            artistIntroduction: first["artist_introduction"] as? String,
                            artworksCount: first["artworks_count"] as? Int,
                            createdAt: nil,
                            updatedAt: nil
                        )
                    }
                    throw error
                }
            } catch let urlError as URLError {
                // Network errors: retry if possible
                let isRetriable = urlError.code == .networkConnectionLost ||
                                 urlError.code == .notConnectedToInternet ||
                                 urlError.code == .timedOut ||
                                 urlError.code == .cannotConnectToHost ||
                                 urlError.code == .cannotFindHost
                
                if isRetriable && attempt < retryCount {
                    lastError = urlError
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                } else {
                    // Non-retriable error or max retries reached
                    print("⚠️ Network error finding artist: \(urlError.localizedDescription)")
                    return nil // Return nil instead of throwing to allow app to continue
                }
            } catch {
                lastError = error
                if attempt < retryCount {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                }
            }
        }
        
        // All retries failed, return nil (not found) instead of throwing
        if let lastError = lastError {
            print("⚠️ Failed to find artist after retries: \(lastError)")
        }
        return nil
    }
    
    /// Find the best matching artist from a list of candidates
    private func findBestArtistMatch(artists: [BackendArtist], targetName: String) -> BackendArtist? {
        guard !artists.isEmpty else { return nil }
        
        // If only one result, return it
        if artists.count == 1 {
            return artists.first
        }
        
        // Find the best match using similarity
        var bestMatch: BackendArtist?
        var bestScore: Double = 0.0
        
        let targetIdentifier = ArtworkIdentifier.generate(title: "", artist: targetName)
        
        for artist in artists {
            let artistIdentifier = ArtworkIdentifier.generate(title: "", artist: artist.name)
            
            // Calculate similarity
            if targetIdentifier.matches(artistIdentifier, fuzzy: true) {
                // Calculate detailed similarity score
                let titleSimilarity = calculateStringSimilarity(targetIdentifier.normalizedArtist, artistIdentifier.normalizedArtist)
                
                if titleSimilarity > bestScore {
                    bestScore = titleSimilarity
                    bestMatch = artist
                }
            }
        }
        
        // If we found a good match (> 0.85 similarity), return it
        if let match = bestMatch, bestScore > 0.85 {
            return match
        }
        
        // Otherwise, return the first one (might be the best we can do)
        return artists.first
    }
    
    /// Calculate string similarity using Levenshtein distance
    private func calculateStringSimilarity(_ s1: String, _ s2: String) -> Double {
        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)
        guard maxLength > 0 else { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLength))
    }
    
    /// Calculate Levenshtein distance
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count
        
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m {
            matrix[i][0] = i
        }
        for j in 0...n {
            matrix[0][j] = j
        }
        
        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
    
    /// Save artist introduction to backend with retry mechanism
    /// Uses upsert: checks if artist exists, updates if found, inserts if not
    func saveArtistIntroduction(artist: String, artistIntroduction: String, retryCount: Int = 2) async throws {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            print("❌ Backend not configured: baseURL=\(baseURL ?? "nil"), apiKey=\(apiKey != nil ? "set" : "nil")")
            throw BackendAPIError.unauthorized
        }
        
        let normalizedName = ArtworkIdentifier.generate(title: "", artist: artist).normalizedArtist
        
        // First, check if artist already exists
        let existingArtist = try? await findArtistIntroduction(artist: artist, retryCount: 0)
        let artistExists = existingArtist != nil
        
        let backendArtist = BackendArtist(
            id: existingArtist?.id, // Use existing ID if found
            name: artist,
            nameEn: nil,
            normalizedName: normalizedName,
            artistIntroduction: artistIntroduction,
            artworksCount: existingArtist?.artworksCount ?? 1,
            createdAt: existingArtist?.createdAt,
            updatedAt: nil // Will be set by database
        )
        
        // Use PATCH for update, POST for insert
        let httpMethod: String
        let urlString: String
        
        if artistExists, let artistId = existingArtist?.id {
            // Update existing artist
            httpMethod = "PATCH"
            urlString = "\(baseURL)/rest/v1/artists?id=eq.\(artistId)"
            print("🔄 Updating existing artist introduction: '\(artist)' (ID: \(artistId))")
        } else {
            // Insert new artist
            httpMethod = "POST"
            urlString = "\(baseURL)/rest/v1/artists"
            print("➕ Inserting new artist introduction: '\(artist)'")
        }
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
            throw BackendAPIError.invalidResponse
        }
        
        print("💾 Attempting to save artist introduction: '\(artist)'")
        print("💾 URL: \(url.absoluteString)")
        print("💾 Method: \(httpMethod)")
        
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.timeoutInterval = 10.0 // 10 second timeout
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        // For PATCH (update), only send fields that should be updated
        let jsonData: Data
        do {
            if httpMethod == "PATCH" {
                // Only update artist_introduction and normalized_name (in case artist name changed)
                let updateData: [String: Any] = [
                    "artist_introduction": artistIntroduction,
                    "normalized_name": normalizedName
                ]
                jsonData = try JSONSerialization.data(withJSONObject: updateData)
            } else {
                // For POST (insert), send full artist object
                jsonData = try encoder.encode(backendArtist)
            }
            
            request.httpBody = jsonData
            
            // Debug: Print JSON payload
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("💾 JSON payload size: \(jsonData.count) bytes")
                print("💾 JSON preview: \(String(jsonString.prefix(300)))...")
            }
        } catch {
            print("❌ Failed to encode artist: \(error)")
            print("❌ Encoding error details: \(error.localizedDescription)")
            throw BackendAPIError.saveFailed
        }
        
        var lastError: Error?
        for attempt in 0...retryCount {
            do {
                print("📡 Sending \(httpMethod) request (attempt \(attempt + 1)/\(retryCount + 1))...")
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid HTTP response type")
                    throw BackendAPIError.invalidResponse
                }
                
                print("📡 HTTP Status: \(httpResponse.statusCode)")
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    let errorData = String(data: data, encoding: .utf8) ?? "Unable to decode error"
                    print("❌ Backend API error (HTTP \(httpResponse.statusCode)): \(errorData)")
                    
                    // Print all response headers for debugging
                    print("📡 Response headers:")
                    for (key, value) in httpResponse.allHeaderFields {
                        print("   \(key): \(value)")
                    }
                    
                    if httpResponse.statusCode == 401 {
                        print("❌ Unauthorized - check API key")
                        throw BackendAPIError.unauthorized
                    } else if httpResponse.statusCode == 403 {
                        print("❌ Forbidden - check RLS policies")
                        throw BackendAPIError.unauthorized
                    } else if httpResponse.statusCode == 400 {
                        print("❌ Bad Request - check data format")
                        print("❌ Error details: \(errorData)")
                    } else if httpResponse.statusCode == 409 {
                        // Conflict - artist already exists, try to find and update instead
                        print("⚠️ Conflict (409) - artist already exists, attempting to find and update...")
                        if httpMethod == "POST" {
                            // Try to find existing artist by name (without date parsing issues)
                            if let existing = try? await findArtistByNameOnly(artistName: artist) {
                                print("✅ Found existing artist, updating instead of inserting...")
                                // Update existing artist
                                return try await updateArtistIntroduction(artistId: existing.id!, artistIntroduction: artistIntroduction, retryCount: retryCount - attempt)
                            } else {
                                // Try with normalized name
                                if let existing = try? await findArtistByNormalizedNameOnly(normalizedName: normalizedName) {
                                    print("✅ Found existing artist by normalized name, updating...")
                                    return try await updateArtistIntroduction(artistId: existing.id!, artistIntroduction: artistIntroduction, retryCount: retryCount - attempt)
                                }
                            }
                        }
                        print("❌ Conflict error - unable to resolve (artist exists but cannot be found/updated)")
                    }
                    throw BackendAPIError.saveFailed
                }
                
                // Success - print response data if available
                if let responseString = String(data: data, encoding: .utf8), !responseString.isEmpty {
                    print("✅ Artist introduction saved successfully. Response: \(responseString.prefix(200))")
                } else {
                    print("✅ Artist introduction saved to backend successfully (no response data)")
                }
                return // Success, exit
            } catch let urlError as URLError {
                // Network errors: retry if possible
                let isRetriable = urlError.code == .networkConnectionLost ||
                                 urlError.code == .notConnectedToInternet ||
                                 urlError.code == .timedOut ||
                                 urlError.code == .cannotConnectToHost ||
                                 urlError.code == .cannotFindHost
                
                if isRetriable && attempt < retryCount {
                    lastError = urlError
                    let delay = Double(attempt + 1) * 1.0
                    print("⚠️ Network error saving artist (attempt \(attempt + 1)/\(retryCount + 1)): \(urlError.localizedDescription)")
                    print("⚠️ Error code: \(urlError.code.rawValue)")
                    print("⚠️ Retrying in \(delay)s...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    // Non-retriable error or max retries reached
                    print("❌ Network error saving artist (non-retriable or max retries): \(urlError.localizedDescription)")
                    print("❌ Error code: \(urlError.code.rawValue)")
                    throw BackendAPIError.networkError
                }
            } catch {
                lastError = error
                print("❌ Failed to save artist introduction (attempt \(attempt + 1)): \(error)")
                print("❌ Error type: \(type(of: error))")
                if attempt < retryCount {
                    let delay = Double(attempt + 1) * 1.0
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        // All retries failed
        if let lastError = lastError {
            print("❌ Failed to save artist introduction after \(retryCount + 1) attempts")
            print("❌ Last error: \(lastError)")
            print("❌ Error type: \(type(of: lastError))")
            throw BackendAPIError.saveFailed
        } else {
            print("❌ Failed to save artist introduction - unknown error")
            throw BackendAPIError.saveFailed
        }
    }
    
    /// Find artist by name only (simplified, for conflict resolution)
    /// This version doesn't parse dates to avoid decoding errors
    private func findArtistByNameOnly(artistName: String) async throws -> BackendArtist? {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            throw BackendAPIError.unauthorized
        }
        
        guard let encodedName = artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/rest/v1/artists?name=eq.\(encodedName)&select=id,name,normalized_name,artist_introduction") else {
            throw BackendAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        
        // Parse minimal JSON (only id, name, normalized_name, artist_introduction) to avoid date parsing issues
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = jsonArray.first,
           let id = first["id"] as? String,
           let name = first["name"] as? String {
            return BackendArtist(
                id: id,
                name: name,
                nameEn: first["name_en"] as? String,
                normalizedName: first["normalized_name"] as? String ?? "",
                artistIntroduction: first["artist_introduction"] as? String,
                artworksCount: first["artworks_count"] as? Int,
                createdAt: nil,
                updatedAt: nil
            )
        }
        
        return nil
    }
    
    /// Find artist by normalized name only (simplified, for conflict resolution)
    private func findArtistByNormalizedNameOnly(normalizedName: String) async throws -> BackendArtist? {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            throw BackendAPIError.unauthorized
        }
        
        guard let encodedName = normalizedName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/rest/v1/artists?normalized_name=eq.\(encodedName)&select=id,name,normalized_name,artist_introduction") else {
            throw BackendAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        
        // Parse minimal JSON
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = jsonArray.first,
           let id = first["id"] as? String,
           let name = first["name"] as? String {
            return BackendArtist(
                id: id,
                name: name,
                nameEn: first["name_en"] as? String,
                normalizedName: first["normalized_name"] as? String ?? normalizedName,
                artistIntroduction: first["artist_introduction"] as? String,
                artworksCount: first["artworks_count"] as? Int,
                createdAt: nil,
                updatedAt: nil
            )
        }
        
        return nil
    }
    
    /// Update existing artist introduction (helper method)
    private func updateArtistIntroduction(artistId: String, artistIntroduction: String, retryCount: Int = 2) async throws {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            throw BackendAPIError.unauthorized
        }
        
        guard let url = URL(string: "\(baseURL)/rest/v1/artists?id=eq.\(artistId)") else {
            throw BackendAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.timeoutInterval = 10.0
        
        let updateData: [String: Any] = ["artist_introduction": artistIntroduction]
        request.httpBody = try JSONSerialization.data(withJSONObject: updateData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            let errorData = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Failed to update artist introduction: Invalid HTTP response")
            throw BackendAPIError.saveFailed
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorData = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Failed to update artist introduction: HTTP \(httpResponse.statusCode), \(errorData)")
            
            // Check for schema cache errors
            if errorData.contains("PGRST204") || errorData.contains("schema cache") || errorData.contains("artist_introduction") {
                print("")
                print("⚠️⚠️⚠️ SCHEMA CACHE ERROR DETECTED ⚠️⚠️⚠️")
                print("The 'artist_introduction' column is not found in the schema cache.")
                print("Please execute migration script 006_rename_biography_to_artist_introduction.sql")
                print("in Supabase SQL Editor, then wait 2-5 minutes for cache refresh.")
                print("See SCHEMA_CACHE_FIX.md for detailed instructions")
                print("⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️")
                print("")
            }
            throw BackendAPIError.saveFailed
        }
        
        print("✅ Artist introduction updated successfully")
    }
}


