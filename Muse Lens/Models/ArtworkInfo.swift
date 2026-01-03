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
    let narrationLanguage: String // e.g. "zh" (future: "en")
    let confidence: Double? // 识别置信度
    let timestamp: Date
    let userPhotoPath: String? // File path to user photo (stored in file system, not UserDefaults)
    
    // Legacy support: old format had userPhotoData
    // NOTE: This exists only for decoding/migration of legacy history records.
    // It is intentionally NOT encoded (see encode(to:)).
    // Must be readable by HistoryService for migration.
    let userPhotoData: Data?
    
    // Computed property to load photo data from file system
    var photoData: Data? {
        if let photoPath = userPhotoPath {
            return try? Data(contentsOf: URL(fileURLWithPath: photoPath))
        }
        // Fallback to legacy data if path is nil but old data exists
        return userPhotoData
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case artworkInfo
        case narration
        case artistIntroduction
        case narrationLanguage
        case confidence
        case timestamp
        case userPhotoPath
        case userPhotoData // For backward compatibility when decoding
    }
    
    init(
        artworkInfo: ArtworkInfo,
        narration: String,
        artistIntroduction: String? = nil,
        narrationLanguage: String = ContentLanguage.zh,
        confidence: Double? = nil,
        userPhotoPath: String? = nil,
        userPhotoData: Data? = nil // For temporary use during migration
    ) {
        self.id = UUID()
        self.artworkInfo = artworkInfo
        self.narration = narration
        self.artistIntroduction = artistIntroduction
        self.narrationLanguage = narrationLanguage
        self.confidence = confidence
        self.timestamp = Date()
        self.userPhotoPath = userPhotoPath
        self.userPhotoData = userPhotoData // Only for backward compatibility
    }
    
    // Custom decoder to handle both old and new formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        artworkInfo = try container.decode(ArtworkInfo.self, forKey: .artworkInfo)
        narration = try container.decode(String.self, forKey: .narration)
        artistIntroduction = try container.decodeIfPresent(String.self, forKey: .artistIntroduction)
        narrationLanguage = (try? container.decodeIfPresent(String.self, forKey: .narrationLanguage)) ?? ContentLanguage.zh
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        
        // Try to decode new format first (userPhotoPath)
        if let path = try? container.decodeIfPresent(String.self, forKey: .userPhotoPath) {
            userPhotoPath = path
            userPhotoData = nil
        } else {
            // Fallback to old format (userPhotoData)
            userPhotoPath = nil
            userPhotoData = try container.decodeIfPresent(Data.self, forKey: .userPhotoData)
        }
    }
    
    // Custom encoder - only encode userPhotoPath, not userPhotoData
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(artworkInfo, forKey: .artworkInfo)
        try container.encode(narration, forKey: .narration)
        try container.encodeIfPresent(artistIntroduction, forKey: .artistIntroduction)
        try container.encode(narrationLanguage, forKey: .narrationLanguage)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(userPhotoPath, forKey: .userPhotoPath)
        // Do NOT encode userPhotoData - it should be migrated to file system
    }
}

