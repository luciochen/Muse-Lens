//
//  HistoryService.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import Foundation

/// Service for managing local history storage (last 10 items)
class HistoryService {
    static let shared = HistoryService()
    
    private let maxHistoryItems = 10
    private let historyKey = "MuseLensHistory"
    
    private init() {}
    
    /// Save history item to local storage
    func saveHistoryItem(_ item: HistoryItem) {
        var history = loadHistory()
        
        // Check if this artwork already exists in history (by title and artist)
        // If exists, remove it first to avoid duplicates
        history.removeAll { existingItem in
            existingItem.artworkInfo.title == item.artworkInfo.title &&
            existingItem.artworkInfo.artist == item.artworkInfo.artist
        }
        
        // Remove oldest items if we exceed max
        while history.count >= maxHistoryItems {
            history.removeLast()
        }
        
        // Insert at beginning (most recent first)
        history.insert(item, at: 0)
        
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
            print("✅ History item saved: \(item.artworkInfo.title) by \(item.artworkInfo.artist) (Total: \(history.count) items)")
        } else {
            print("❌ Failed to encode history item")
        }
    }
    
    /// Load history from local storage
    func loadHistory() -> [HistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else {
            print("⚠️ No history data found in UserDefaults")
            return []
        }
        
        do {
            let history = try JSONDecoder().decode([HistoryItem].self, from: data)
            print("✅ Loaded \(history.count) history items")
            return history
        } catch {
            print("❌ Failed to decode history: \(error)")
            // Try to decode with legacy format (without artistIntroduction and confidence)
            if let legacyHistory = try? JSONDecoder().decode([LegacyHistoryItem].self, from: data) {
                print("⚠️ Found legacy history format, converting...")
                let convertedHistory = legacyHistory.map { legacy in
                    HistoryItem(
                        artworkInfo: legacy.artworkInfo,
                        narration: legacy.narration,
                        artistIntroduction: nil,
                        confidence: nil,
                        userPhotoData: legacy.userPhotoData
                    )
                }
                // Save converted history
                if let encoded = try? JSONEncoder().encode(convertedHistory) {
                    UserDefaults.standard.set(encoded, forKey: historyKey)
                }
                return convertedHistory
            }
            return []
        }
    }
    
    /// Clear all history
    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
        print("✅ History cleared")
    }
    
    /// Get history count
    func getHistoryCount() -> Int {
        return loadHistory().count
    }
}

// Legacy history item format (for backward compatibility)
private struct LegacyHistoryItem: Codable {
    let id: UUID
    let artworkInfo: ArtworkInfo
    let narration: String
    let timestamp: Date
    let userPhotoData: Data?
}

