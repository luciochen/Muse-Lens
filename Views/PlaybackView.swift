//
//  PlaybackView.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import SwiftUI
import UIKit

struct PlaybackView: View {
    let artworkInfo: ArtworkInfo
    let narration: String
    let userImage: UIImage?
    
    @StateObject private var ttsPlayback = TTSPlayback.shared
    @State private var showText = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Artwork Image
                    Group {
                        if let imageURL = artworkInfo.imageURL, let url = URL(string: imageURL) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                case .failure(_), .empty:
                                    imagePlaceholder
                                @unknown default:
                                    imagePlaceholder
                                }
                            }
                        } else if let userImage = userImage {
                            Image(uiImage: userImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            imagePlaceholder
                        }
                    }
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .shadow(radius: 8)
                    .padding(.horizontal)
                    
                    // Artwork Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text(artworkInfo.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.primary)
                        
                        HStack {
                            Text(artworkInfo.artist)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            if let year = artworkInfo.year {
                                Text("· \(year)")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let style = artworkInfo.style {
                            Text(style)
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        if !artworkInfo.recognized {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.orange)
                                Text("我们未能找到这幅具体作品的信息，但它看起来属于\(artworkInfo.style ?? "这种风格")，让我给你介绍一下这种画风的起源吧。")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    // Audio Controls
                    VStack(spacing: 16) {
                        // Progress Bar
                        if ttsPlayback.duration > 0 {
                            VStack(spacing: 8) {
                                ProgressView(value: ttsPlayback.currentTime, total: ttsPlayback.duration)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                
                                HStack {
                                    Text(formatTime(ttsPlayback.currentTime))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatTime(ttsPlayback.duration))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        // Control Buttons
                        HStack(spacing: 40) {
                            // Skip Back 15s (placeholder for future)
                            Button(action: {
                                // Future: skip back 15s
                            }) {
                                Image(systemName: "gobackward.15")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                            }
                            .disabled(true)
                            .opacity(0.5)
                            
                            // Play/Pause
                            Button(action: {
                                if ttsPlayback.isPlaying {
                                    ttsPlayback.pause()
                                } else {
                                    if ttsPlayback.currentTime == 0 {
                                        ttsPlayback.speak(text: narration, language: "zh-CN")
                                    } else {
                                        ttsPlayback.play()
                                    }
                                }
                            }) {
                                Image(systemName: ttsPlayback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.blue)
                            }
                            
                            // Skip Forward 15s
                            Button(action: {
                                ttsPlayback.skipForward15()
                            }) {
                                Image(systemName: "goforward.15")
                                    .font(.system(size: 24))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        // Toggle Text View
                        Button(action: {
                            showText.toggle()
                        }) {
                            HStack {
                                Image(systemName: showText ? "eye.slash.fill" : "eye.fill")
                                Text(showText ? "隐藏文字" : "显示文字")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Narration Text
                    if showText {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("讲解内容")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text(narration)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // Sources
                    if !artworkInfo.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("信息来源")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            ForEach(artworkInfo.sources, id: \.self) { source in
                                Link(source, destination: URL(string: source) ?? URL(string: "https://example.com")!)
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        ttsPlayback.stop()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Auto-play narration when view appears
            ttsPlayback.speak(text: narration, language: "zh-CN")
        }
        .onDisappear {
            ttsPlayback.stop()
        }
    }
    
    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: "photo.artframe")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
            )
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    PlaybackView(
        artworkInfo: ArtworkInfo(
            title: "示例作品",
            artist: "示例艺术家",
            year: "2023",
            style: "印象派",
            sources: ["https://example.com"]
        ),
        narration: "这是一段示例讲解内容，用于展示播放界面的效果。",
        userImage: nil
    )
}

