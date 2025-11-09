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
        Task {
            print("🚀 App starting - verifying API key...")
            let result = await TTSPlayback.shared.verifyAPIKey()
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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
