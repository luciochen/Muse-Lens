//
//  SearchService.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import Foundation

/// Service for searching artworks from public museum APIs
class SearchService {
    static let shared = SearchService()
    
    private init() {}
    
    /// Search artworks by query string (title or artist)
    func searchArtworks(query: String) async -> [ArtworkInfo] {
        print("🔍 Searching for: '\(query)'")
        var results: [ArtworkInfo] = []
        
        // Search multiple sources in parallel
        async let metResults = searchMetMuseum(query: query)
        async let artInstituteResults = searchArtInstitute(query: query)
        
        let (met, artInstitute) = await (metResults, artInstituteResults)
        
        print("📊 Met Museum results: \(met.count)")
        print("📊 Art Institute results: \(artInstitute.count)")
        
        results.append(contentsOf: met)
        results.append(contentsOf: artInstitute)
        
        // Remove duplicates based on title and artist
        var uniqueResults: [ArtworkInfo] = []
        var seen = Set<String>()
        
        for result in results {
            let key = "\(result.title)|\(result.artist)"
            if !seen.contains(key) {
                seen.insert(key)
                uniqueResults.append(result)
            }
        }
        
        print("✅ Total unique results: \(uniqueResults.count)")
        return uniqueResults
    }
    
    /// Search The Metropolitan Museum of Art
    private func searchMetMuseum(query: String) async -> [ArtworkInfo] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://collectionapi.metmuseum.org/public/collection/v1/search?q=\(encodedQuery)") else {
            print("❌ Invalid URL for Met Museum search")
            return []
        }
        
        print("🔍 Met Museum search URL: \(url.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Met Museum HTTP status: \(httpResponse.statusCode)")
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Met Museum: Invalid JSON response")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 Response: \(responseString.prefix(500))")
                }
                return []
            }
            
            print("📊 Met Museum JSON keys: \(json.keys.joined(separator: ", "))")
            
            // Check for objectIDs array
            guard let objectIDs = json["objectIDs"] as? [Int] else {
                print("❌ Met Museum: No objectIDs in response")
                if let total = json["total"] as? Int {
                    print("📊 Total results: \(total)")
                }
                return []
            }
            
            print("✅ Met Museum found \(objectIDs.count) object IDs")
            
            if objectIDs.isEmpty {
                return []
            }
            
            // Get details for first 10 results (use TaskGroup for parallel fetching)
            let limit = min(10, objectIDs.count)
            var artworks: [ArtworkInfo] = []
            
            await withTaskGroup(of: ArtworkInfo?.self) { group in
                for objectID in objectIDs.prefix(limit) {
                    group.addTask {
                        await self.getMetObjectDetails(objectID: objectID)
                    }
                }
                
                for await artwork in group {
                    if let artwork = artwork {
                        artworks.append(artwork)
                    }
                }
            }
            
            print("✅ Met Museum: Retrieved \(artworks.count) artworks with images")
            return artworks
        } catch {
            print("❌ Met Museum search error: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Get details for a Met Museum object
    private func getMetObjectDetails(objectID: Int) async -> ArtworkInfo? {
        guard let url = URL(string: "https://collectionapi.metmuseum.org/public/collection/v1/objects/\(objectID)") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("⚠️ Met Museum object \(objectID): Invalid JSON")
                return nil
            }
            
            let title = json["title"] as? String ?? "Untitled"
            
            // Skip if title is empty or just whitespace
            if title.trimmingCharacters(in: .whitespaces).isEmpty {
                return nil
            }
            
            let artist = json["artistDisplayName"] as? String
                ?? json["artistAlphaSort"] as? String
                ?? json["culture"] as? String
                ?? "Unknown Artist"
            
            let year = json["objectDate"] as? String
            let style = json["period"] as? String ?? json["culture"] as? String
            
            // Try multiple image fields (primaryImage is larger, primaryImageSmall is smaller)
            var imageURL = json["primaryImageSmall"] as? String
            if imageURL == nil || imageURL!.isEmpty {
                imageURL = json["primaryImage"] as? String
            }
            if imageURL == nil || imageURL!.isEmpty {
                // Try additionalImages as fallback
                if let additionalImages = json["additionalImages"] as? [String], !additionalImages.isEmpty {
                    imageURL = additionalImages.first
                }
            }
            
            // Skip if still no image (but log it)
            guard let finalImageURL = imageURL, !finalImageURL.isEmpty else {
                print("⚠️ Met Museum object \(objectID) '\(title)' has no image")
                return nil
            }
            
            let artwork = ArtworkInfo(
                title: title,
                artist: artist,
                year: year,
                style: style,
                sources: ["https://www.metmuseum.org/art/collection/search/\(objectID)"],
                imageURL: finalImageURL,
                recognized: true
            )
            
            return artwork
        } catch {
            print("❌ Met Museum object \(objectID) details error: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Search Art Institute of Chicago
    private func searchArtInstitute(query: String) async -> [ArtworkInfo] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.artic.edu/api/v1/artworks/search?q=\(encodedQuery)&limit=10") else {
            print("❌ Invalid URL for Art Institute search")
            return []
        }
        
        print("🔍 Art Institute search URL: \(url.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Art Institute HTTP status: \(httpResponse.statusCode)")
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Art Institute: Invalid JSON response")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 Response: \(responseString.prefix(500))")
                }
                return []
            }
            
            guard let dataArray = json["data"] as? [[String: Any]] else {
                print("❌ Art Institute: No data array in response")
                if let pagination = json["pagination"] as? [String: Any] {
                    print("📊 Pagination: \(pagination)")
                }
                return []
            }
            
            print("✅ Art Institute found \(dataArray.count) results")
            
            var artworks: [ArtworkInfo] = []
            
            for item in dataArray {
                let id = item["id"] as? Int ?? 0
                let title = item["title"] as? String ?? "Untitled"
                
                // Skip if title is empty
                if title.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }
                
                let artist = (item["artist_title"] as? String) ?? "Unknown Artist"
                let year = item["date_display"] as? String
                
                // Get image URL
                var imageURL: String? = nil
                if let imageID = item["image_id"] as? String, !imageID.isEmpty {
                    imageURL = "https://www.artic.edu/iiif/2/\(imageID)/full/843,/0/default.jpg"
                }
                
                // Skip if no image
                guard let finalImageURL = imageURL else {
                    print("⚠️ Art Institute artwork \(id) '\(title)' has no image")
                    continue
                }
                
                let artwork = ArtworkInfo(
                    title: title,
                    artist: artist,
                    year: year,
                    style: nil,
                    sources: ["https://www.artic.edu/artworks/\(id)"],
                    imageURL: finalImageURL,
                    recognized: true
                )
                artworks.append(artwork)
            }
            
            print("✅ Art Institute: Retrieved \(artworks.count) artworks with images")
            return artworks
        } catch {
            print("❌ Art Institute search error: \(error.localizedDescription)")
            return []
        }
    }
}

