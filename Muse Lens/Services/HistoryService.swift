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
        
        // Remove oldest items if we exceed max
        if history.count >= maxHistoryItems {
            history.removeLast()
        }
        
        // Insert at beginning (most recent first)
        history.insert(item, at: 0)
        
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }
    
    /// Load history from local storage
    func loadHistory() -> [HistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            return []
        }
        return history
    }
    
    /// Clear all history
    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
}

