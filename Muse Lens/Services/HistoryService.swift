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
    
    // File system directory for storing history photos
    private var photosDirectory: URL {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsURL = urls[0]
        let photosURL = documentsURL.appendingPathComponent("HistoryPhotos", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: photosURL.path) {
            try? FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        return photosURL
    }
    
    private init() {}
    
    /// Save history item to local storage
    /// If item contains userPhotoData, it will be saved to file system and converted to userPhotoPath
    func saveHistoryItem(_ item: HistoryItem) {
        var history = loadHistory()
        
        // Check if this artwork already exists in history (by title and artist)
        // If exists, remove it first to avoid duplicates
        let existingItem = history.first { existingItem in
            existingItem.artworkInfo.title == item.artworkInfo.title &&
            existingItem.artworkInfo.artist == item.artworkInfo.artist
        }
        
        // Delete old photo file if item already exists
        if let existing = existingItem, let oldPhotoPath = existing.userPhotoPath {
            try? FileManager.default.removeItem(atPath: oldPhotoPath)
        }
        
        history.removeAll { existingItem in
            existingItem.artworkInfo.title == item.artworkInfo.title &&
            existingItem.artworkInfo.artist == item.artworkInfo.artist
        }
        
        // Remove oldest items if we exceed max
        while history.count >= maxHistoryItems {
            let oldestItem = history.removeLast()
            // Delete photo file for removed item
            if let photoPath = oldestItem.userPhotoPath {
                try? FileManager.default.removeItem(atPath: photoPath)
            }
        }
        
        // Handle photo: save to file system if we have photo data but no path
        var photoPath: String? = item.userPhotoPath
        
        // If item has photo data but no path, save it to file system.
        // Use `photoData` (path-first, legacy fallback) so this works reliably across formats.
        if photoPath == nil, let photoData = item.photoData {
            let fileName = "\(item.id.uuidString).jpg"
            let fileURL = photosDirectory.appendingPathComponent(fileName)
            
            do {
                try photoData.write(to: fileURL)
                photoPath = fileURL.path
                print("✅ Saved photo to file system: \(fileURL.path)")
            } catch {
                print("❌ Failed to save photo to file system: \(error)")
            }
        }
        
        // Create new history item with file path (not data)
        let historyItemToSave = HistoryItem(
            artworkInfo: item.artworkInfo,
            narration: item.narration,
            artistIntroduction: item.artistIntroduction,
            narrationLanguage: item.narrationLanguage,
            confidence: item.confidence,
            userPhotoPath: photoPath,
            userPhotoData: nil // Don't store data, only path
        )
        
        // Insert at beginning (most recent first)
        history.insert(historyItemToSave, at: 0)
        
        // Save to UserDefaults (now only contains text data and file paths, not photo data)
        if let encoded = try? JSONEncoder().encode(history) {
            let dataSize = encoded.count
            print("📊 History data size: \(dataSize) bytes (\(String(format: "%.2f", Double(dataSize) / 1024.0)) KB)")
            
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
        
        let dataSize = data.count
        print("📊 Loading history data: \(dataSize) bytes (\(String(format: "%.2f", Double(dataSize) / 1024.0)) KB)")
        
        do {
            var history = try JSONDecoder().decode([HistoryItem].self, from: data)
            
            // Migrate any items that still have photo data but no path
            var needsMigration = false
            for (index, item) in history.enumerated() {
                if item.userPhotoPath == nil, let photoData = item.photoData {
                    // Migrate this item's photo to file system
                    let fileName = "\(item.id.uuidString).jpg"
                    let fileURL = photosDirectory.appendingPathComponent(fileName)
                    
                    do {
                        try photoData.write(to: fileURL)
                        // Create new item with path
                        let migratedItem = HistoryItem(
                            artworkInfo: item.artworkInfo,
                            narration: item.narration,
                            artistIntroduction: item.artistIntroduction,
                            narrationLanguage: item.narrationLanguage,
                            confidence: item.confidence,
                            userPhotoPath: fileURL.path,
                            userPhotoData: nil
                        )
                        history[index] = migratedItem
                        needsMigration = true
                        print("✅ Migrated photo for item: \(item.artworkInfo.title)")
                    } catch {
                        print("❌ Failed to migrate photo for item: \(item.artworkInfo.title), error: \(error)")
                    }
                }
            }
            
            // Save migrated history if needed
            if needsMigration {
                if let encoded = try? JSONEncoder().encode(history) {
                    UserDefaults.standard.set(encoded, forKey: historyKey)
                    print("✅ Migrated history items to file system storage")
                }
            }
            
            print("✅ Loaded \(history.count) history items")
            return history
        } catch {
            print("❌ Failed to decode history: \(error)")
            // Try to decode with legacy format (without artistIntroduction and confidence)
            if let legacyHistory = try? JSONDecoder().decode([LegacyHistoryItem].self, from: data) {
                print("⚠️ Found legacy history format, converting...")
                var convertedHistory: [HistoryItem] = []
                
                for legacy in legacyHistory {
                    var photoPath: String? = nil
                    
                    // Migrate photo data to file system
                    if let photoData = legacy.userPhotoData {
                        let fileName = "\(legacy.id.uuidString).jpg"
                        let fileURL = photosDirectory.appendingPathComponent(fileName)
                        
                        do {
                            try photoData.write(to: fileURL)
                            photoPath = fileURL.path
                            print("✅ Migrated legacy photo: \(fileURL.path)")
                        } catch {
                            print("❌ Failed to migrate legacy photo: \(error)")
                        }
                    }
                    
                    let converted = HistoryItem(
                        artworkInfo: legacy.artworkInfo,
                        narration: legacy.narration,
                        artistIntroduction: nil,
                        narrationLanguage: ContentLanguage.zh,
                        confidence: nil,
                        userPhotoPath: photoPath,
                        userPhotoData: nil
                    )
                    convertedHistory.append(converted)
                }
                
                // Save converted history
                if let encoded = try? JSONEncoder().encode(convertedHistory) {
                    UserDefaults.standard.set(encoded, forKey: historyKey)
                    print("✅ Saved converted history")
                }
                return convertedHistory
            }
            return []
        }
    }
    
    /// Clear all history
    func clearHistory() {
        // Delete all photo files
        if let files = try? FileManager.default.contentsOfDirectory(at: photosDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
            print("✅ Deleted \(files.count) photo files")
        }
        
        UserDefaults.standard.removeObject(forKey: historyKey)
        print("✅ History cleared")
    }
    
    /// Load photo data from file system for a history item
    func loadPhotoData(for item: HistoryItem) -> Data? {
        // Use HistoryItem's unified accessor (path-first with legacy fallback)
        return item.photoData
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

