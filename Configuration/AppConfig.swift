//
//  AppConfig.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import Foundation

/// Application configuration
/// 
/// For production, use environment variables or secure storage (Keychain)
/// For development, you can temporarily set the API key here
struct AppConfig {
    /// OpenAI API Key
    /// 
    /// Set via environment variable OPENAI_API_KEY or configure in Xcode Scheme:
    /// Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
    static var openAIApiKey: String? {
        // Priority 1: Environment variable (recommended)
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return key
        }
        
        // Priority 2: UserDefaults (for development/testing only)
        // Remove this in production!
        if let key = UserDefaults.standard.string(forKey: "OPENAI_API_KEY"), !key.isEmpty {
            return key
        }
        
        // Priority 3: Hardcoded (NOT RECOMMENDED for production)
        // Only use for quick testing, remove before App Store submission
        // return "your-api-key-here"
        
        return nil
    }
    
    /// Check if API key is configured
    static var isConfigured: Bool {
        return openAIApiKey != nil
    }
    
    /// Set API key (for development/testing only)
    /// In production, use environment variables or Keychain
    static func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "OPENAI_API_KEY")
    }
}

