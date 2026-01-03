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
    private static let keychainService = "com.muselens.secrets"
    private static let openAIKeychainAccount = "OPENAI_API_KEY"

    /// OpenAI API Key
    /// 
    /// Set via environment variable OPENAI_API_KEY or configure in Xcode Scheme:
    /// Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
    static var openAIApiKey: String? {
        // Priority 0: Keychain (recommended for on-device storage)
        if let key = KeychainHelper.readString(service: keychainService, account: openAIKeychainAccount),
           !key.isEmpty {
            return key
        }
        
        // Priority 1: Info.plist (optional; avoid committing real keys)
        if let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
           !key.isEmpty {
            return key
        }
        
        // Priority 2: Environment variable (works when set in Xcode Scheme)
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return key
        }
        
        // Priority 3: UserDefaults (for development/testing only)
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
        // Store in Keychain (preferred)
        _ = KeychainHelper.upsertString(key, service: keychainService, account: openAIKeychainAccount)
        
        // Backward-compatible: also store in UserDefaults (do NOT delete any existing keys)
        UserDefaults.standard.set(key, forKey: "OPENAI_API_KEY")
    }
    
    /// Backend API URL (Supabase or custom backend)
    /// 
    /// Set via environment variable BACKEND_API_URL or configure in Xcode Scheme:
    /// Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
    static var backendAPIURL: String? {
        // Priority 1: Environment variable (recommended)
        if let url = ProcessInfo.processInfo.environment["BACKEND_API_URL"], !url.isEmpty {
            return url
        }
        
        // Priority 2: UserDefaults (for development/testing only)
        if let url = UserDefaults.standard.string(forKey: "BACKEND_API_URL"), !url.isEmpty {
            return url
        }
        
        return nil
    }
    
    /// Backend API Key (Supabase anon key or custom API key)
    /// 
    /// Set via environment variable BACKEND_API_KEY or configure in Xcode Scheme:
    /// Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
    static var backendAPIKey: String? {
        // Priority 1: Environment variable (recommended)
        if let key = ProcessInfo.processInfo.environment["BACKEND_API_KEY"], !key.isEmpty {
            return key
        }
        
        // Priority 2: UserDefaults (for development/testing only)
        if let key = UserDefaults.standard.string(forKey: "BACKEND_API_KEY"), !key.isEmpty {
            return key
        }
        
        return nil
    }
    
    /// Check if backend API is configured
    static var isBackendConfigured: Bool {
        return backendAPIURL != nil && backendAPIKey != nil
    }
    
    /// Set backend API URL (for development/testing only)
    static func setBackendAPIURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "BACKEND_API_URL")
    }
    
    /// Set backend API key (for development/testing only)
    static func setBackendAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "BACKEND_API_KEY")
    }
}

