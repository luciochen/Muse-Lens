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
    let narration: String // 作品讲解内容
    let artistIntroduction: String? // 艺术家介绍内容
    let sources: [String]
    let confidence: Double // 识别确定性 (0.0-1.0): >=0.8高确定性, 0.5-0.8中等确定性, <0.5低确定性
    
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
    
    /// Get recognition confidence level
    var confidenceLevel: RecognitionConfidenceLevel {
        if confidence >= 0.8 {
            return .high
        } else if confidence >= 0.5 {
            return .medium
        } else {
            return .low
        }
    }
}

/// Recognition confidence levels
enum RecognitionConfidenceLevel {
    case high    // >= 0.8: 识别成功，提供完整讲解
    case medium  // 0.5-0.8: 识别模糊，简短描述风格
    case low     // < 0.5: 无法识别，友好提示
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
    let artistIntroduction: String? // 艺术家介绍
    let confidence: Double? // 识别置信度
    let timestamp: Date
    let userPhotoData: Data? // Compressed user photo
    
    init(
        artworkInfo: ArtworkInfo,
        narration: String,
        artistIntroduction: String? = nil,
        confidence: Double? = nil,
        userPhotoData: Data? = nil
    ) {
        self.id = UUID()
        self.artworkInfo = artworkInfo
        self.narration = narration
        self.artistIntroduction = artistIntroduction
        self.confidence = confidence
        self.timestamp = Date()
        self.userPhotoData = userPhotoData
    }
}

