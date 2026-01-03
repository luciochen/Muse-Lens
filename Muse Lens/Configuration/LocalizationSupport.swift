//
//  LocalizationSupport.swift
//  Muse Lens
//
//  Lightweight localization + language plumbing.
//  Current release: Chinese only ("zh"), structured to add English later.
//

import Foundation

/// Language codes stored with generated content (keep simple: "zh", later "en", etc.)
enum ContentLanguage {
    static let zh = "zh"
    static let en = "en"
    
    /// Convert a stored content language code to a BCP-47 tag used by TTS.
    /// - Note: Keep this the single mapping so adding English is only prompts/voices/strings.
    static func ttsBCP47Tag(for contentLanguage: String) -> String {
        switch contentLanguage.lowercased() {
        case "zh", "zh-hans", "zh-cn":
            return "zh-CN"
        case "en", "en-us", "en-gb":
            return "en-US"
        default:
            // Safe fallback: Chinese for current release
            return "zh-CN"
        }
    }
}

/// Stable, non-localized placeholder tokens used for UI state.
/// These must never be shown directly to users; views should render localized strings instead.
enum UIPlaceholders {
    // New internal tokens
    static let recognizingTitleToken = "__RECOGNIZING__"
    static let narrationLoadingToken = "__NARRATION_LOADING__"
    static let narrationGeneratingToken = "__NARRATION_GENERATING__"
    
    // Legacy strings (for backward compatibility with existing history items)
    static let legacyRecognizingTitleZh = "正在识别..."
    static let legacyNarrationLoadingZh = "正在加载讲解内容..."
    static let legacyNarrationGeneratingZh = "正在生成讲解内容..."
    static let legacyNarrationGeneratingShortZh = "正在生成讲解..."
}


