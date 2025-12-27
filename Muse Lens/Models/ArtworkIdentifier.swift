//
//  ArtworkIdentifier.swift
//  Muse Lens
//
//  Combined identifier for unique artwork identification
//

import Foundation
import CommonCrypto

/// Combined identifier for artworks
/// Uses normalized title + artist to generate a unique hash identifier
struct ArtworkIdentifier: Codable {
    /// Normalized title (lowercase, trimmed, special chars removed)
    let normalizedTitle: String
    
    /// Normalized artist name (lowercase, trimmed, special chars removed)
    let normalizedArtist: String
    
    /// Combined hash identifier (SHA256 of normalized title + artist)
    let combinedHash: String
    
    /// Year (optional, for disambiguation)
    let year: String?
    
    /// Generate identifier from artwork information
    /// Uses variant matching to ensure same artwork has one name
    static func generate(
        title: String,
        artist: String,
        year: String? = nil
    ) -> ArtworkIdentifier {
        // Use variant matching to handle title variations
        return generateWithVariantMatching(title: title, artist: artist, year: year)
    }
    
    /// Clean title by removing 《》 characters
    /// This is used for display and storage
    static func cleanTitle(_ title: String) -> String {
        return title
            .replacingOccurrences(of: "《", with: "")
            .replacingOccurrences(of: "》", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Normalize title for matching - handles variants like "日落" and "日出"
    /// This creates a canonical form for matching similar titles
    /// For example: "国会大厦，日落" and "国会大厦，日出" will match as the same artwork
    static func normalizeTitleForMatching(_ title: String) -> String {
        var normalized = cleanTitle(title)
        
        // Normalize common title variants
        // Map similar terms to a canonical form for matching
        // This ensures "国会大厦，日落" and "国会大厦，日出" are treated as the same artwork
        let variantMappings: [String: String] = [
            "日落": "日出",  // Map "日落" to "日出" for matching (国会大厦系列)
            "黄昏": "日出",
            "傍晚": "日出",
            "夕阳": "日出",
            "晨光": "日出",
            "黎明": "日出",
            "日落时": "日出",
            "黄昏时": "日出",
            "傍晚时": "日出"
        ]
        
        // Replace variants with canonical form
        // Check each variant and replace if found
        for (variant, canonical) in variantMappings {
            if normalized.contains(variant) {
                normalized = normalized.replacingOccurrences(of: variant, with: canonical)
                // Continue to check for other variants (don't break)
            }
        }
        
        return normalized
    }
    
    /// Normalize text for matching
    /// Removes articles, special characters, and normalizes whitespace
    /// CRITICAL: Preserves Chinese characters for proper matching
    private static func normalizeText(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove ALL 《》 characters (not just prefix/suffix)
        normalized = normalized
            .replacingOccurrences(of: "《", with: "")
            .replacingOccurrences(of: "》", with: "")
        
        // Remove common articles (Chinese and English)
        let articles = ["the ", "a ", "an ", "la ", "le ", "les ", "un ", "une "]
        for article in articles {
            if normalized.hasPrefix(article) {
                normalized = String(normalized.dropFirst(article.count))
            }
            if normalized.hasSuffix(article) {
                normalized = String(normalized.dropLast(article.count))
            }
        }
        
        // Normalize whitespace (multiple spaces to single space)
        normalized = normalized
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        
        // For matching purposes, we keep the text as-is (preserving Chinese characters)
        // Only normalize case for English text, but keep Chinese characters intact
        // Convert to lowercase only for English characters
        let lowercaseNormalized = normalized.map { char -> String in
            if char.isASCII {
                return char.lowercased()
            } else {
                return String(char) // Keep Chinese and other non-ASCII characters as-is
            }
        }.joined()
        
        return lowercaseNormalized
    }
    
    /// Generate identifier with title normalization for variant matching
    static func generateWithVariantMatching(
        title: String,
        artist: String,
        year: String? = nil
    ) -> ArtworkIdentifier {
        // Clean title (remove 《》)
        let cleanedTitle = cleanTitle(title)
        
        // Normalize title for matching (handle variants)
        let normalizedTitleForMatching = normalizeTitleForMatching(cleanedTitle)
        
        // Normalize for hash generation
        let normalizedTitle = normalizeText(normalizedTitleForMatching)
        let normalizedArtist = normalizeText(artist)
        
        // Generate combined hash
        let combinedString = "\(normalizedTitle)|\(normalizedArtist)"
        let combinedHash = combinedString.sha256()
        
        return ArtworkIdentifier(
            normalizedTitle: normalizedTitle,
            normalizedArtist: normalizedArtist,
            combinedHash: combinedHash,
            year: year
        )
    }
    
    /// Check if two identifiers match (fuzzy matching)
    func matches(_ other: ArtworkIdentifier, fuzzy: Bool = true) -> Bool {
        // Exact match
        if combinedHash == other.combinedHash {
            return true
        }
        
        // Fuzzy match: check if titles and artists are similar
        if fuzzy {
            let titleSimilarity = calculateSimilarity(normalizedTitle, other.normalizedTitle)
            let artistSimilarity = calculateSimilarity(normalizedArtist, other.normalizedArtist)
            
            // If both title and artist are > 85% similar, consider it a match
            if titleSimilarity > 0.85 && artistSimilarity > 0.85 {
                return true
            }
        }
        
        return false
    }
    
    /// Calculate Levenshtein similarity (0.0-1.0)
    private func calculateSimilarity(_ s1: String, _ s2: String) -> Double {
        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)
        guard maxLength > 0 else { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLength))
    }
    
    /// Levenshtein distance calculation
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
}

extension String {
    /// SHA256 hash
    func sha256() -> String {
        let data = Data(self.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

