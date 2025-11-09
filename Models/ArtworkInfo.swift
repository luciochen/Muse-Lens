//
//  ArtworkInfo.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import Foundation

/// Represents artwork information retrieved from reliable sources
struct ArtworkInfo: Codable, Identifiable {
    let id: UUID
    let title: String
    let artist: String
    let year: String?
    let style: String?
    let medium: String?
    let museum: String?
    let sources: [String]
    let imageURL: String?
    let recognized: Bool // true if specific artwork, false if style-based
    
    init(
        title: String,
        artist: String,
        year: String? = nil,
        style: String? = nil,
        medium: String? = nil,
        museum: String? = nil,
        sources: [String] = [],
        imageURL: String? = nil,
        recognized: Bool = true
    ) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.year = year
        self.style = style
        self.medium = medium
        self.museum = museum
        self.sources = sources
        self.imageURL = imageURL
        self.recognized = recognized
    }
}

/// Response structure for AI-generated narration
struct NarrationResponse: Codable {
    let title: String
    let artist: String
    let year: String?
    let style: String?
    let summary: String
    let narration: String // 250-350 words, 1-2 minutes audio
    let sources: [String]
    
    /// Convert to ArtworkInfo
    func toArtworkInfo(imageURL: String? = nil, recognized: Bool = true) -> ArtworkInfo {
        return ArtworkInfo(
            title: title,
            artist: artist,
            year: year,
            style: style,
            sources: sources,
            imageURL: imageURL,
            recognized: recognized
        )
    }
}

/// Recognition candidate from vision model
struct RecognitionCandidate: Codable {
    let artworkName: String
    let artist: String?
    let confidence: Double
}

/// History item stored locally
struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let artworkInfo: ArtworkInfo
    let narration: String
    let timestamp: Date
    let userPhotoData: Data? // Compressed user photo
    
    init(artworkInfo: ArtworkInfo, narration: String, userPhotoData: Data? = nil) {
        self.id = UUID()
        self.artworkInfo = artworkInfo
        self.narration = narration
        self.timestamp = Date()
        self.userPhotoData = userPhotoData
    }
}

