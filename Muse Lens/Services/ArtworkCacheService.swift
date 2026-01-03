//
//  ArtworkCacheService.swift
//  Muse Lens
//
//  Enhanced cache service with backend synchronization
//

import Foundation

/// Enhanced artwork cache service with backend synchronization
/// Handles both artwork narration and artist introduction caching
class ArtworkCacheService {
    static let shared = ArtworkCacheService()
    
    private let backendAPI = BackendAPIService.shared
    
    // OPTIMIZATION: Local cache for recently queried artworks (fast lookup)
    private let localCacheKey = "MuseLensArtworkCache"
    private let maxLocalCacheItems = 20 // Cache last 20 artworks
    private let localCacheExpirationHours = 24 // Cache expires after 24 hours
    
    private init() {}
    
    // MARK: - Local Cache Management
    
    /// Get artwork from local cache (fast, no network)
    private func getLocalCachedArtwork(identifier: ArtworkIdentifier) -> BackendArtwork? {
        guard let cacheData = UserDefaults.standard.data(forKey: localCacheKey),
              let cache = try? JSONDecoder().decode([CachedArtwork].self, from: cacheData) else {
            return nil
        }
        
        // Find matching artwork in cache
        if let cached = cache.first(where: { $0.identifier.combinedHash == identifier.combinedHash }) {
            // Check expiration
            let age = Date().timeIntervalSince(cached.cachedAt)
            if age < Double(localCacheExpirationHours * 3600) {
                print("✅ Found artwork in local cache (age: \(String(format: "%.1f", age/3600))h)")
                return cached.artwork
            } else {
                print("⚠️ Cached artwork expired (age: \(String(format: "%.1f", age/3600))h)")
            }
        }
        
        return nil
    }
    
    /// Save artwork to local cache
    private func saveToLocalCache(artwork: BackendArtwork, identifier: ArtworkIdentifier) {
        var cache: [CachedArtwork]
        
        if let cacheData = UserDefaults.standard.data(forKey: localCacheKey),
           let decoded = try? JSONDecoder().decode([CachedArtwork].self, from: cacheData) {
            cache = decoded
        } else {
            cache = []
        }
        
        // Remove existing entry if present
        cache.removeAll { $0.identifier.combinedHash == identifier.combinedHash }
        
        // Add new entry
        cache.insert(CachedArtwork(identifier: identifier, artwork: artwork, cachedAt: Date()), at: 0)
        
        // Limit cache size
        if cache.count > maxLocalCacheItems {
            cache = Array(cache.prefix(maxLocalCacheItems))
        }
        
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: localCacheKey)
            print("✅ Saved artwork to local cache (total: \(cache.count) items)")
        }
    }
    
    /// Clear local cache
    func clearLocalCache() {
        UserDefaults.standard.removeObject(forKey: localCacheKey)
        print("✅ Local cache cleared")
    }
    
    // MARK: - Artwork Narration Cache
    
    /// Get artwork narration (check local cache -> backend -> use provided)
    /// Returns cached narration if found, otherwise returns provided narration
    func getArtworkNarration(
        title: String,
        artist: String,
        year: String?,
        narrationResponse: NarrationResponse?,
        artworkInfo: ArtworkInfo? = nil
    ) async -> NarrationResponse? {
        // 1. Generate combined identifier
        let identifier = ArtworkIdentifier.generate(
            title: title,
            artist: artist,
            year: year
        )
        
        print("🔍 Looking up artwork: \(title) by \(artist)")
        print("🔑 Combined hash: \(identifier.combinedHash)")
        
        // OPTIMIZATION: Check local cache first (fast, no network)
        if let localCached = getLocalCachedArtwork(identifier: identifier) {
            print("✅ Found in local cache (instant access)")
            
            // Get artist introduction from backend (still need to query for latest)
            var artistIntro: String? = nil
            if !localCached.artist.isEmpty && localCached.artist != "未知艺术家" {
                if let backendArtist = try? await backendAPI.findArtistIntroduction(artist: localCached.artist) {
                    artistIntro = backendArtist.artistIntroduction
                }
            }
            
            return localCached.toNarrationResponse(artistIntroduction: artistIntro)
        }
        
        // 2. Check backend cache (shared across all users)
        if backendAPI.isConfigured {
            do {
                if let backendArtwork = try await backendAPI.findArtwork(identifier: identifier) {
                    print("✅ Found in backend cache (shared with other users)")
                    print("📝 Using cached narration, but user's photo will still be displayed")
                    
                    // Increment view count asynchronously (non-blocking, don't wait for it)
                    if let id = backendArtwork.id {
                        Task {
                            await backendAPI.incrementViewCount(artworkId: id)
                        }
                    }
                    
                    // OPTIMIZATION: Save to local cache for faster future access
                    saveToLocalCache(artwork: backendArtwork, identifier: identifier)
                    
                    // Return cached narration response
                    // Note: Backend artwork's imageURL is a reference image from museum API,
                    // NOT user's photo. User's photo is passed separately to PlaybackView.
                    // OPTIMIZATION: Parallel query - fetch artist introduction simultaneously
                    var artistIntro: String? = nil
                    if !backendArtwork.artist.isEmpty && backendArtwork.artist != "未知艺术家" {
                        // Query artist introduction in parallel (already have artwork, so this is independent)
                        if let backendArtist = try? await backendAPI.findArtistIntroduction(artist: backendArtwork.artist) {
                            artistIntro = backendArtist.artistIntroduction
                        }
                    }
                    return backendArtwork.toNarrationResponse(artistIntroduction: artistIntro)
                }
            } catch {
                // Network errors are handled internally and return nil
                // Other errors are logged but don't block the flow
                if case BackendAPIError.networkError = error {
                    print("⚠️ Network error checking backend cache, continuing with local generation")
                } else {
                    print("⚠️ Backend lookup failed: \(error)")
                }
                // Continue to use provided narration - network errors shouldn't block the app
            }
        } else {
            print("⚠️ Backend not configured, skipping backend cache")
        }
        
        // 3. If not found in backend, use provided narration response (newly generated)
        guard let narration = narrationResponse else {
            print("❌ No narration response provided")
            return nil
        }
        
        // 4. Before saving, check for similar artworks to ensure consistency
        // This prevents duplicate entries for the same artwork with different names
        let finalNarration = narration
        let finalIdentifier = identifier
        
        if narration.confidence >= 0.8 && narration.confidenceLevel == .high && backendAPI.isConfigured {
            do {
                // Search for similar artworks using fuzzy matching
                let similarArtworks = try await backendAPI.searchArtwork(title: narration.title, artist: narration.artist)
                
                if let existingArtwork = similarArtworks.first {
                    // Check if the existing artwork is similar enough to be the same
                    let existingIdentifier = ArtworkIdentifier.generate(
                        title: existingArtwork.title,
                        artist: existingArtwork.artist,
                        year: existingArtwork.year
                    )
                    
                    // Use fuzzy matching to check similarity
                    if identifier.matches(existingIdentifier, fuzzy: true) {
                        print("🔄 Found similar artwork in database: '\(existingArtwork.title)' by '\(existingArtwork.artist)'")
                        print("🔄 Using existing standardized name instead of: '\(narration.title)' by '\(narration.artist)'")
                        
                        // Use the existing artwork's complete information from database
                        // This ensures consistency - same artwork always has the same name
                        // Get artist introduction from artists table
                        var artistIntro: String? = nil
                        if !existingArtwork.artist.isEmpty && existingArtwork.artist != "未知艺术家" {
                            if let backendArtist = try? await backendAPI.findArtistIntroduction(artist: existingArtwork.artist) {
                                artistIntro = backendArtist.artistIntroduction
                            }
                        }
                        let existingNarration = existingArtwork.toNarrationResponse(artistIntroduction: artistIntro)
                        
                        // Increment view count asynchronously (non-blocking)
                        if let id = existingArtwork.id {
                            Task {
                                await backendAPI.incrementViewCount(artworkId: id)
                            }
                        }
                        
                        // Return existing artwork's narration to ensure consistency
                        print("✅ Using existing artwork record with standardized name, skipping save")
                        return existingNarration
                    }
                }
            } catch {
                // If search fails, continue with saving (don't block the flow)
                print("⚠️ Failed to search for similar artworks: \(error)")
                print("⚠️ Continuing with save operation")
            }
        }
        
        // 5. Save to backend (only high-confidence artworks)
        // IMPORTANT: Also ensure artist introduction is saved to artists table
        if finalNarration.confidence >= 0.8 && finalNarration.confidenceLevel == .high {
            if backendAPI.isConfigured {
                // First, ensure artist introduction is saved to artists table
                // This ensures the artist record exists and is up-to-date
                if !finalNarration.artist.isEmpty && finalNarration.artist != "未知艺术家",
                   let artistIntro = finalNarration.artistIntroduction, !artistIntro.isEmpty {
                    print("💾 Ensuring artist introduction is saved to artists table...")
                    print("💾 Artist: \(finalNarration.artist)")
                    
                    // Save artist introduction (this will update existing or create new)
                    Task {
                        do {
                            try await backendAPI.saveArtistIntroduction(
                                artist: finalNarration.artist,
                                artistIntroduction: artistIntro
                            )
                            print("✅ Artist introduction saved/updated in artists table: '\(finalNarration.artist)'")
                        } catch {
                            print("⚠️ Failed to save artist introduction: \(error.localizedDescription)")
                            // Continue with artwork save even if artist save fails
                        }
                    }
                }
                
                print("💾 Saving new artwork to backend cache...")
                print("💾 Title: \(finalNarration.title), Artist: \(finalNarration.artist)")
                print("💾 Confidence: \(finalNarration.confidence), Narration length: \(finalNarration.narration.count) chars")
                
                let backendArtwork = BackendArtwork.from(
                    narrationResponse: finalNarration,
                    identifier: finalIdentifier,
                    artworkInfo: artworkInfo
                )
                
                // Save artwork synchronously to ensure it's actually saved
                // Use Task but wait for it to complete to ensure save happens
                do {
                    try await backendAPI.saveArtwork(backendArtwork)
                    print("✅ Saved to backend cache successfully: '\(finalNarration.title)' by '\(finalNarration.artist)'")
                } catch let error as BackendAPIError {
                    // Log detailed error information
                    switch error {
                    case .unauthorized:
                        print("❌ Authorization failed - check API key and RLS policies")
                    case .networkError:
                        print("⚠️ Network error saving to backend (will retry on next attempt)")
                    case .saveFailed:
                        print("❌ Save failed - check data format and database schema")
                    case .requestFailed:
                        print("❌ Request failed - check network and API endpoint")
                    case .invalidResponse:
                        print("❌ Invalid response - check API endpoint URL")
                    case .notFound:
                        print("❌ Not found (unexpected for save operation)")
                    }
                    print("❌ Error details: \(error.localizedDescription)")
                    // Don't throw - allow app to continue even if save fails
                } catch {
                    print("❌ Failed to save to backend: \(error)")
                    print("❌ Error type: \(type(of: error))")
                    print("❌ Error description: \(error.localizedDescription)")
                    // Don't throw - allow app to continue even if save fails
                }
            } else {
                print("⚠️ Backend not configured - skipping save")
            }
        } else {
            print("⚠️ Low confidence artwork - not saving to backend (confidence: \(finalNarration.confidence))")
        }
        
        return finalNarration
    }
    
    // MARK: - Artist Introduction Cache
    
    /// Get artist introduction (check backend -> use provided)
    /// Returns cached introduction if found, otherwise returns provided introduction
    /// CRITICAL: Database introduction always takes priority over AI-generated introduction
    func getArtistIntroduction(
        artist: String,
        providedIntroduction: String?
    ) async -> String? {
        // Skip if artist is unknown
        if artist.isEmpty || artist == "未知艺术家" {
            return providedIntroduction
        }
        
        print("🔍 Looking up artist introduction: \(artist)")
        
        // 1. ALWAYS check backend cache FIRST - database introduction takes priority
        var foundInDatabase = false
        
        if backendAPI.isConfigured {
            do {
                if let backendArtist = try await backendAPI.findArtistIntroduction(artist: artist) {
                    foundInDatabase = true
                    if let artistIntro = backendArtist.artistIntroduction, !artistIntro.isEmpty {
                        print("✅ Found artist introduction in backend cache (using database version)")
                        print("📝 Database introduction length: \(artistIntro.count) characters")
                        // Return database version immediately
                        return artistIntro
                    } else {
                        print("⚠️ Artist found in database but artist_introduction is empty - will update with provided introduction")
                    }
                } else {
                    print("ℹ️ Artist not found in database, will use provided introduction if available")
                }
            } catch {
                // Network errors are handled internally and return nil
                // Other errors are logged but don't block the flow
                if case BackendAPIError.networkError = error {
                    print("⚠️ Network error checking artist cache, using provided introduction")
                } else {
                    print("⚠️ Backend artist lookup failed: \(error)")
                }
                // Continue to use provided introduction - network errors shouldn't block the app
            }
        } else {
            print("⚠️ Backend not configured, skipping database lookup")
        }
        
        // 2. If not found in database, use provided introduction (AI-generated)
        guard let introduction = providedIntroduction, !introduction.isEmpty else {
            print("⚠️ No artist introduction available (neither database nor provided)")
            return nil
        }
        
        print("ℹ️ Using provided (AI-generated) artist introduction (length: \(introduction.count) characters)")
        
        // 3. Save to backend (always save if we have a valid introduction)
        // This ensures:
        // - New artists are saved to database
        // - Artists with empty biography are updated with new introduction
        // - Existing artists with biography are not overwritten (already returned above)
        if backendAPI.isConfigured {
            print("💾 Saving artist introduction to backend cache...")
            if foundInDatabase {
                print("🔄 Updating existing artist record with new introduction")
            } else {
                print("➕ Creating new artist record")
            }
            print("💾 Artist: \(artist), Biography length: \(introduction.count) chars")
            
            // Save in background task but ensure it completes
            Task {
                do {
                    try await backendAPI.saveArtistIntroduction(artist: artist, artistIntroduction: introduction)
                    print("✅ Artist introduction saved to backend successfully: '\(artist)'")
                } catch let error as BackendAPIError {
                    // Log detailed error information
                    switch error {
                    case .unauthorized:
                        print("❌ Authorization failed - check API key and RLS policies")
                    case .networkError:
                        print("⚠️ Network error saving artist introduction (will retry on next attempt)")
                    case .saveFailed:
                        print("❌ Save failed - check data format and database schema")
                    case .requestFailed:
                        print("❌ Request failed - check network and API endpoint")
                    case .invalidResponse:
                        print("❌ Invalid response - check API endpoint URL")
                    case .notFound:
                        print("❌ Not found (unexpected for save operation)")
                    }
                    print("❌ Error details: \(error.localizedDescription)")
                } catch {
                    print("❌ Failed to save artist introduction to backend: \(error)")
                    print("❌ Error type: \(type(of: error))")
                    print("❌ Error description: \(error.localizedDescription)")
                }
            }
        } else {
            print("⚠️ Backend not configured - skipping artist introduction save")
        }
        
        return introduction
    }
    
    // MARK: - Combined Cache (Artwork + Artist Introduction)
    
    /// Get artwork narration with artist introduction (full cache lookup)
    /// This is the main method to use in the app
    /// 
    /// Note: artworkInfo.imageURL should only contain museum API reference image, NOT user's photo
    /// User's photo should be passed separately to PlaybackView and will always be displayed
    func getArtworkWithArtistIntroduction(
        title: String,
        artist: String,
        year: String?,
        narrationResponse: NarrationResponse?,
        artworkInfo: ArtworkInfo? = nil
    ) async -> NarrationResponse? {
        // 1. Get artwork narration (with backend cache)
        // When saving to backend, only museum API reference image is stored (not user's photo)
        let finalNarration = await getArtworkNarration(
            title: title,
            artist: artist,
            year: year,
            narrationResponse: narrationResponse,
            artworkInfo: artworkInfo // Contains only museum API reference image, NOT user photo
        )
        
        guard let narration = finalNarration else {
            return nil
        }
        
        // 2. Get artist introduction (with backend cache)
        // CRITICAL: Always check database for artist introduction, even for medium/low confidence
        // This ensures we use database introduction whenever available
        if !artist.isEmpty && artist != "未知艺术家" {
            print("🔍 Checking database for artist introduction: \(artist)")
            let cachedIntroduction = await getArtistIntroduction(
                artist: artist,
                providedIntroduction: narration.artistIntroduction
            )
            
            // If we got a database introduction, use it (even if different from provided)
            if let dbIntroduction = cachedIntroduction, !dbIntroduction.isEmpty {
                // Check if database introduction is different from provided
                if dbIntroduction != narration.artistIntroduction {
                    print("✅ Using artist introduction from database (different from provided)")
                    print("📝 Database: \(dbIntroduction.count) chars, Provided: \(narration.artistIntroduction?.count ?? 0) chars")
                } else {
                    print("ℹ️ Database introduction matches provided introduction")
                }
                
                // Update narration with database introduction
                let updatedNarration = NarrationResponse(
                    title: narration.title,
                    artist: narration.artist,
                    year: narration.year,
                    style: narration.style,
                    summary: narration.summary,
                    narration: narration.narration,
                    artistIntroduction: dbIntroduction, // Always use database introduction if available
                    sources: narration.sources,
                    confidence: narration.confidence
                )
                return updatedNarration
            } else {
                print("ℹ️ No database introduction found, using provided introduction")
            }
        }
        
        return narration
    }
}

// MARK: - Local Cache Model

/// Cached artwork entry for local storage
private struct CachedArtwork: Codable {
    let identifier: ArtworkIdentifier
    let artwork: BackendArtwork
    let cachedAt: Date
    let narrationLanguage: String
    
    enum CodingKeys: String, CodingKey {
        case identifier
        case artwork
        case cachedAt
        case narrationLanguage
    }
    
    init(
        identifier: ArtworkIdentifier,
        artwork: BackendArtwork,
        cachedAt: Date,
        narrationLanguage: String = ContentLanguage.zh
    ) {
        self.identifier = identifier
        self.artwork = artwork
        self.cachedAt = cachedAt
        self.narrationLanguage = narrationLanguage
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(ArtworkIdentifier.self, forKey: .identifier)
        artwork = try c.decode(BackendArtwork.self, forKey: .artwork)
        cachedAt = try c.decode(Date.self, forKey: .cachedAt)
        narrationLanguage = (try? c.decodeIfPresent(String.self, forKey: .narrationLanguage)) ?? ContentLanguage.zh
    }
}

