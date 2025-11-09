//
//  RetrievalService.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import Foundation

/// Service for retrieving artwork information from reliable sources
class RetrievalService {
    static let shared = RetrievalService()
    
    private init() {}
    
    /// Retrieve artwork information from multiple sources
    func retrieveArtworkInfo(candidates: [RecognitionCandidate]) async -> ArtworkInfo? {
        // Try each candidate in order of confidence
        for candidate in candidates {
            // Try museum APIs first
            if let info = await searchMetMuseumAPI(candidate: candidate) {
                return info
            }
            
            if let info = await searchSmithsonianAPI(candidate: candidate) {
                return info
            }
            
            if let info = await searchArtInstituteAPI(candidate: candidate) {
                return info
            }
            
            // Fallback to Wikipedia
            if let info = await searchWikipedia(candidate: candidate) {
                return info
            }
        }
        
        return nil
    }
    
    /// Search The Metropolitan Museum of Art Collection API
    private func searchMetMuseumAPI(candidate: RecognitionCandidate) async -> ArtworkInfo? {
        guard let query = candidate.artworkName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://collectionapi.metmuseum.org/public/collection/v1/search?q=\(query)") else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let objectIDs = json["objectIDs"] as? [Int],
                  let firstObjectID = objectIDs.first else {
                return nil
            }
            
            // Get detailed object info
            return await getMetObjectDetails(objectID: firstObjectID)
        } catch {
            return nil
        }
    }
    
    private func getMetObjectDetails(objectID: Int) async -> ArtworkInfo? {
        guard let url = URL(string: "https://collectionapi.metmuseum.org/public/collection/v1/objects/\(objectID)") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let title = json["title"] as? String,
                  let artist = json["artistDisplayName"] as? String ?? json["culture"] as? String ?? "Unknown" else {
                return nil
            }
            
            let year = json["objectDate"] as? String
            let medium = json["medium"] as? String
            let department = json["department"] as? String
            let imageURL = json["primaryImage"] as? String
            let sourceURL = "https://www.metmuseum.org/art/collection/search/\(objectID)"
            
            return ArtworkInfo(
                title: title,
                artist: artist,
                year: year,
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
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
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
            let detailJson = try JSONSerialization.jsonObject(with: detailData) as? [String: Any]
            
            guard let artworkData = detailJson["data"] as? [String: Any],
                  let title = artworkData["title"] as? String else {
                return nil
            }
            
            let artist = artworkData["artist_display"] as? String ?? "Unknown"
            let date = artworkData["date_display"] as? String
            let medium = artworkData["medium_display"] as? String
            let style = artworkData["style_title"] as? String
            let imageID = artworkData["image_id"] as? String
            let imageURL = imageID.map { "https://www.artic.edu/iiif/2/\($0)/full/843,/0/default.jpg" }
            let sourceURL = "https://www.artic.edu/artworks/\(id)"
            
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
        // Use Wikipedia API to search
        guard let query = candidate.artworkName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(query)") else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let title = json["title"] as? String,
                  let extract = json["extract"] as? String else {
                return nil
            }
            
            let contentURL = json["content_urls"] as? [String: Any]??
            let desktop = contentURL?["desktop"] as? [String: Any]??
            let pageURL = desktop?["page"] as? String
            
            // Extract artist and year from extract text (basic parsing)
            let artist = candidate.artist ?? extract.components(separatedBy: " by ").last?.components(separatedBy: " is ").first?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
            
            let thumbnail = json["thumbnail"] as? [String: Any]
            let imageURL = thumbnail?["source"] as? String
            
            return ArtworkInfo(
                title: title,
                artist: artist,
                sources: pageURL.map { [$0] } ?? [],
                imageURL: imageURL
            )
        } catch {
            return nil
        }
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
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let title = json["title"] as? String else {
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

