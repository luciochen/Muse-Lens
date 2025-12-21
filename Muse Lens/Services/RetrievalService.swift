//
//  RetrievalService.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import Foundation

/// Service for retrieving artwork information from reliable sources test
class RetrievalService {
    static let shared = RetrievalService()
    
    private init() {}
    
    /// Retrieve artwork information from multiple sources
    func retrieveArtworkInfo(candidates: [RecognitionCandidate]) async -> ArtworkInfo? {
        // Try each candidate in order of confidence
        for candidate in candidates {
            // Try museum APIs first - ALWAYS use API-verified information for accuracy
            if let info = await searchMetMuseumAPI(candidate: candidate) {
                // CRITICAL: Always use API-verified information for accuracy
                // Only use candidate artist if API doesn't provide a valid one
                let finalArtist = (info.artist.isEmpty || info.artist == "Unknown" || info.artist == "未知") ? (candidate.artist ?? info.artist) : info.artist
                print("✅ Met Museum verified: Title='\(info.title)', Artist='\(finalArtist)', Year='\(info.year ?? "null")'")
                return ArtworkInfo(
                    title: info.title, // Always use API title for accuracy
                    artist: finalArtist,
                    year: info.year, // Always use API year for accuracy
                    style: info.style, // Always use API style for accuracy
                    medium: info.medium,
                    museum: info.museum,
                    sources: info.sources,
                    imageURL: info.imageURL,
                    recognized: info.recognized
                )
            }
            
            if let info = await searchSmithsonianAPI(candidate: candidate) {
                let finalArtist = (info.artist.isEmpty || info.artist == "Unknown") ? (candidate.artist ?? info.artist) : info.artist
                print("✅ Smithsonian verified: Title='\(info.title)', Artist='\(finalArtist)'")
                return ArtworkInfo(
                    title: info.title,
                    artist: finalArtist,
                    year: info.year,
                    style: info.style,
                    medium: info.medium,
                    museum: info.museum,
                    sources: info.sources,
                    imageURL: info.imageURL,
                    recognized: info.recognized
                )
            }
            
            if let info = await searchArtInstituteAPI(candidate: candidate) {
                // CRITICAL: Always use API-verified information for accuracy
                let finalArtist = (info.artist.isEmpty || info.artist == "Unknown") ? (candidate.artist ?? info.artist) : info.artist
                print("✅ Art Institute verified: Title='\(info.title)', Artist='\(finalArtist)', Year='\(info.year ?? "null")'")
                return ArtworkInfo(
                    title: info.title, // Always use API title
                    artist: finalArtist,
                    year: info.year, // Always use API year
                    style: info.style, // Always use API style
                    medium: info.medium,
                    museum: info.museum,
                    sources: info.sources,
                    imageURL: info.imageURL,
                    recognized: info.recognized
                )
            }
            
            // Fallback to Wikipedia (less reliable, but better than nothing)
            if let info = await searchWikipedia(candidate: candidate) {
                // Use Wikipedia info, but prefer candidate artist if Wikipedia artist is generic
                let finalArtist = (info.artist == "Unknown" || info.artist.isEmpty) ? (candidate.artist ?? info.artist) : info.artist
                print("✅ Wikipedia verified: Title='\(info.title)', Artist='\(finalArtist)'")
                return ArtworkInfo(
                    title: info.title, // Use Wikipedia title
                    artist: finalArtist,
                    year: info.year, // Wikipedia may not have year
                    style: info.style,
                    medium: info.medium,
                    museum: info.museum,
                    sources: info.sources,
                    imageURL: info.imageURL,
                    recognized: info.recognized
                )
            }
        }
        
        return nil
    }
    
    /// Search The Metropolitan Museum of Art Collection API
    private func searchMetMuseumAPI(candidate: RecognitionCandidate) async -> ArtworkInfo? {
        // Try multiple search strategies for better matching
        var searchQueries: [String] = []
        
        // Strategy 1: Full artwork name
        searchQueries.append(candidate.artworkName)
        
        // Strategy 2: Artist name + artwork name (for famous works)
        if let artist = candidate.artist {
            searchQueries.append("\(artist) \(candidate.artworkName)")
            searchQueries.append(artist) // Sometimes searching by artist alone works
        }
        
        // Strategy 3: Common variations (e.g., "Mona Lisa" vs "La Gioconda")
        if candidate.artworkName.lowercased().contains("mona lisa") {
            searchQueries.append("La Gioconda")
            searchQueries.append("Gioconda")
        }
        
        // Try each search query
        for query in searchQueries {
            guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://collectionapi.metmuseum.org/public/collection/v1/search?q=\(encodedQuery)") else {
                continue
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let objectIDs = json["objectIDs"] as? [Int],
                      !objectIDs.isEmpty else {
                    continue // Try next query
                }
                
                // Get detailed object info for the first result (most relevant match)
                // Try first few results to find the best match
                let maxAttempts = min(5, objectIDs.count)
                var bestMatch: ArtworkInfo? = nil
                var bestMatchScore = 0
                
                for i in 0..<maxAttempts {
                    if let artworkInfo = await getMetObjectDetails(objectID: objectIDs[i]) {
                        // Calculate match score for relevance
                        var matchScore = 0
                        
                        // Title matching (exact match = 3, partial match = 1)
                        let candidateTitleLower = candidate.artworkName.lowercased().trimmingCharacters(in: .whitespaces)
                        let artworkTitleLower = artworkInfo.title.lowercased().trimmingCharacters(in: .whitespaces)
                        
                        if candidateTitleLower == artworkTitleLower {
                            matchScore += 3 // Exact match
                        } else if artworkTitleLower.contains(candidateTitleLower) || candidateTitleLower.contains(artworkTitleLower) {
                            matchScore += 1 // Partial match
                        }
                        
                        // Artist matching (exact match = 2, partial match = 1)
                        if let candidateArtist = candidate.artist, !candidateArtist.isEmpty {
                            let candidateArtistLower = candidateArtist.lowercased().trimmingCharacters(in: .whitespaces)
                            let artworkArtistLower = artworkInfo.artist.lowercased().trimmingCharacters(in: .whitespaces)
                            
                            if candidateArtistLower == artworkArtistLower {
                                matchScore += 2 // Exact match
                            } else if artworkArtistLower.contains(candidateArtistLower) || candidateArtistLower.contains(artworkArtistLower) {
                                matchScore += 1 // Partial match
                            } else {
                                // Artist doesn't match, reduce score
                                matchScore -= 1
                            }
                        }
                        
                        // Only accept matches with positive score, or first result if no better match found
                        if matchScore > bestMatchScore || (bestMatch == nil && i == 0) {
                            bestMatch = artworkInfo
                            bestMatchScore = matchScore
                        }
                    }
                }
                
                // Only return if we have a reasonable match
                if let match = bestMatch, bestMatchScore >= 0 {
                    print("✅ Met Museum match found (score: \(bestMatchScore)): '\(match.title)' by '\(match.artist)'")
                    return match
                } else {
                    print("⚠️ Met Museum search found results but no good match (best score: \(bestMatchScore))")
                }
            } catch {
                continue // Try next query
            }
        }
        
        return nil
    }
    
    private func getMetObjectDetails(objectID: Int) async -> ArtworkInfo? {
        guard let url = URL(string: "https://collectionapi.metmuseum.org/public/collection/v1/objects/\(objectID)") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            guard let title = json["title"] as? String, !title.isEmpty else {
                return nil
            }
            
            // Get artist - prefer artistDisplayName, fallback to culture, but never use "Unknown" for real artworks
            var artist = json["artistDisplayName"] as? String ?? ""
            if artist.isEmpty {
                artist = json["culture"] as? String ?? ""
            }
            // If still empty, try other fields
            if artist.isEmpty {
                artist = json["artistAlphaSort"] as? String ?? ""
            }
            // Final fallback - but this should be rare
            if artist.isEmpty {
                artist = "Unknown Artist"
            }
            
            // Clean up artist name (remove extra spaces, normalize)
            artist = artist.trimmingCharacters(in: .whitespaces)
            
            // Get year - clean and normalize
            var year = json["objectDate"] as? String
            if let date = year {
                // Clean up date string - remove common prefixes and normalize
                year = date.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "ca. ", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "c. ", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "circa ", with: "", options: .caseInsensitive)
                    // If empty after cleaning, set to nil
                if year?.isEmpty == true {
                    year = nil
                }
            }
            
            // Get style from period or culture if available
            var style: String? = nil
            if let period = json["period"] as? String, !period.isEmpty {
                style = period
            } else if let culture = json["culture"] as? String, !culture.isEmpty, artist != culture {
                // Use culture as style only if it's different from artist
                style = culture
            }
            // Try to extract style from department
            if style == nil, let department = json["department"] as? String, !department.isEmpty {
                // Some departments indicate style (e.g., "European Paintings" -> might be Renaissance/Baroque)
                // But be careful not to use department name directly as style
                // For now, we'll leave style as nil if not explicitly found
            }
            
            let medium = json["medium"] as? String
            let department = json["department"] as? String
            let imageURL = json["primaryImage"] as? String
            let sourceURL = "https://www.metmuseum.org/art/collection/search/\(objectID)"
            
            print("📦 Met Museum object details: Title='\(title)', Artist='\(artist)', Year='\(year ?? "null")', Style='\(style ?? "null")'")
            
            return ArtworkInfo(
                title: title,
                artist: artist,
                year: year,
                style: style, // Now includes style if available
                medium: medium,
                museum: department,
                sources: [sourceURL],
                imageURL: imageURL
            )
        } catch {
            return nil
        }
    }
    
    /// Search Smithsonian Open Access API
    private func searchSmithsonianAPI(candidate: RecognitionCandidate) async -> ArtworkInfo? {
        // Smithsonian API requires API key, implement if available
        // For now, return nil as fallback to other sources
        return nil
    }
    
    /// Search The Art Institute of Chicago API
    private func searchArtInstituteAPI(candidate: RecognitionCandidate) async -> ArtworkInfo? {
        guard let query = candidate.artworkName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.artic.edu/api/v1/artworks/search?q=\(query)&limit=1") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            guard let dataArray = json["data"] as? [[String: Any]],
                  let firstArtwork = dataArray.first,
                  let id = firstArtwork["id"] as? Int else {
                return nil
            }
            
            // Get detailed artwork info
            guard let detailURL = URL(string: "https://api.artic.edu/api/v1/artworks/\(id)") else {
                return nil
            }
            
            let (detailData, _) = try await URLSession.shared.data(from: detailURL)
            guard let detailJson = try JSONSerialization.jsonObject(with: detailData) as? [String: Any],
                  let artworkData = detailJson["data"] as? [String: Any],
                  let title = artworkData["title"] as? String else {
                return nil
            }
            
            var artist = artworkData["artist_display"] as? String ?? ""
            if artist.isEmpty {
                // Try other artist fields
                if let artistTitles = artworkData["artist_titles"] as? [String], !artistTitles.isEmpty {
                    artist = artistTitles.joined(separator: ", ")
                }
            }
            if artist.isEmpty {
                artist = "Unknown Artist"
            }
            
            // Clean up artist name
            artist = artist.trimmingCharacters(in: .whitespaces)
            
            // Get date and clean it
            var date = artworkData["date_display"] as? String
            if let dateStr = date {
                date = dateStr.trimmingCharacters(in: .whitespaces)
                // Remove common prefixes
                date = date?.replacingOccurrences(of: "ca. ", with: "", options: .caseInsensitive)
                date = date?.replacingOccurrences(of: "c. ", with: "", options: .caseInsensitive)
                if date?.isEmpty == true {
                    date = nil
                }
            }
            
            let medium = artworkData["medium_display"] as? String
            
            // Get style - try multiple fields
            var style: String? = nil
            if let styleTitle = artworkData["style_title"] as? String, !styleTitle.isEmpty {
                style = styleTitle
            } else if let classificationTitle = artworkData["classification_title"] as? String, !classificationTitle.isEmpty {
                // Classification can sometimes indicate style
                style = classificationTitle
            }
            
            // Clean up style
            style = style?.trimmingCharacters(in: .whitespaces)
            if style?.isEmpty == true {
                style = nil
            }
            
            let imageID = artworkData["image_id"] as? String
            let imageURL = imageID.map { "https://www.artic.edu/iiif/2/\($0)/full/843,/0/default.jpg" }
            let sourceURL = "https://www.artic.edu/artworks/\(id)"
            
            print("📦 Art Institute object details: Title='\(title)', Artist='\(artist)', Year='\(date ?? "null")', Style='\(style ?? "null")'")
            
            return ArtworkInfo(
                title: title,
                artist: artist,
                year: date,
                style: style,
                medium: medium,
                museum: "Art Institute of Chicago",
                sources: [sourceURL],
                imageURL: imageURL
            )
        } catch {
            return nil
        }
    }
    
    /// Search Wikipedia for artwork information
    private func searchWikipedia(candidate: RecognitionCandidate) async -> ArtworkInfo? {
        // Try multiple search strategies for Wikipedia
        var searchQueries: [String] = []
        
        // Strategy 1: Artwork name
        searchQueries.append(candidate.artworkName)
        
        // Strategy 2: Artist + artwork name
        if let artist = candidate.artist {
            searchQueries.append("\(candidate.artworkName) \(artist)")
        }
        
        // Strategy 3: Common variations for famous works
        if candidate.artworkName.lowercased().contains("mona lisa") {
            searchQueries.append("Mona Lisa")
            searchQueries.append("La Gioconda")
        }
        
        // Try each search query
        for query in searchQueries {
            guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encodedQuery)") else {
                continue
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    continue // Try next query
                }
                
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                
                guard let title = json["title"] as? String,
                      let extract = json["extract"] as? String else {
                    continue
                }
                
                let contentURL = json["content_urls"] as? [String: Any]
                let desktop = contentURL?["desktop"] as? [String: Any]
                let pageURL = desktop?["page"] as? String
                
                // Use candidate's artist if available, otherwise try to extract from Wikipedia
                var artist = candidate.artist ?? ""
                
                // Try to extract artist from Wikipedia extract
                if artist.isEmpty {
                    // Look for patterns like "by Artist Name" or "Artist Name is"
                    if let byRange = extract.range(of: " by ", options: .caseInsensitive) {
                        let afterBy = String(extract[byRange.upperBound...])
                        if let endRange = afterBy.range(of: " ") {
                            artist = String(afterBy[..<endRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                        } else {
                            artist = afterBy.trimmingCharacters(in: .whitespaces)
                        }
                    }
                }
                
                // Clean up artist
                artist = artist.trimmingCharacters(in: .whitespaces)
                if artist.isEmpty {
                    artist = "Unknown Artist"
                }
                
                // Try to extract year from extract
                var year: String? = nil
                // Look for patterns like "painted in 1889" or "created in 1503"
                let yearPattern = #"\b(?:painted|created|made|completed)\s+(?:in\s+)?(\d{4})\b"#
                if let regex = try? NSRegularExpression(pattern: yearPattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: extract, range: NSRange(extract.startIndex..., in: extract)),
                   let yearRange = Range(match.range(at: 1), in: extract) {
                    year = String(extract[yearRange])
                }
                
                // Try to extract style from extract
                var style: String? = nil
                let styleKeywords = ["Renaissance", "Impressionism", "Baroque", "Modern", "Contemporary", "Romantic", "Neoclassical"]
                for keyword in styleKeywords {
                    if extract.lowercased().contains(keyword.lowercased()) {
                        style = keyword
                        break
                    }
                }
                
                let thumbnail = json["thumbnail"] as? [String: Any]
                let imageURL = thumbnail?["source"] as? String
                
                print("📦 Wikipedia object details: Title='\(title)', Artist='\(artist)', Year='\(year ?? "null")', Style='\(style ?? "null")'")
                
                return ArtworkInfo(
                    title: title,
                    artist: artist,
                    year: year,
                    style: style,
                    sources: pageURL.map { [$0] } ?? [],
                    imageURL: imageURL
                )
            } catch {
                continue // Try next query
            }
        }
        
        return nil
    }
    
    /// Get style information when artwork not recognized
    func getStyleInformation(style: String) async -> ArtworkInfo? {
        // Search for style information on Wikipedia
        guard let query = style.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(query)") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            guard json["title"] is String else {
                return nil
            }
            
            let contentURL = json["content_urls"] as? [String: Any]
            let desktop = contentURL?["desktop"] as? [String: Any]
            let pageURL = desktop?["page"] as? String
            
            return ArtworkInfo(
                title: "\(style) Art Style",
                artist: "Various Artists",
                style: style,
                sources: pageURL.map { [$0] } ?? [],
                recognized: false
            )
        } catch {
            return nil
        }
    }
}

