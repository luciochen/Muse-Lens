//
//  Muse_LensApp.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import SwiftUI

@main
struct Muse_LensApp: App {
    init() {
        // Verify API key on app startup (async, non-blocking)
        // Use Task with low priority to avoid blocking app startup
        Task.detached(priority: .utility) {
            // Add a small delay to ensure app is fully initialized and network is ready
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            print("🚀 App starting - verifying API key...")
            
            // Verify API key with timeout protection
            // The verifyAPIKey method already has timeout in its network requests
            let result = await TTSPlayback.shared.verifyAPIKey()
            
            // Access result properties on MainActor to avoid isolation issues
            await MainActor.run {
                print("📊 API Key Verification Result:")
                print("   \(result.summary)")
                
                if !result.isValid {
                    print("⚠️ WARNING: API key verification failed!")
                    print("⚠️ OpenAI TTS may not work properly.")
                    print("⚠️ Please check your OPENAI_API_KEY configuration.")
                } else {
                    print("✅ API key verified successfully!")
                }
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
