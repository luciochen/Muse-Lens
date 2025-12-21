//
//  HistoryView.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import SwiftUI
import UIKit

struct HistoryView: View {
    @State private var history: [HistoryItem] = []
    @State private var selectedItem: HistoryItem?
    
    var body: some View {
        NavigationStack {
            List {
                if history.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("暂无历史记录")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                        Text("识别作品后，记录会显示在这里")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(history) { item in
                        HistoryRow(item: item)
                            .onTapGesture {
                                selectedItem = item
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete(perform: deleteHistoryItems)
                }
            }
            .listStyle(.plain)
            .navigationTitle("历史记录")
            .toolbar {
                if !history.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("清除") {
                            HistoryService.shared.clearHistory()
                            loadHistory()
                        }
                    }
                }
            }
        }
        .onAppear {
            loadHistory()
        }
        .fullScreenCover(item: $selectedItem) { item in
            PlaybackView(
                artworkInfo: item.artworkInfo,
                narration: item.narration,
                artistIntroduction: item.artistIntroduction ?? "",
                userImage: item.userPhotoData.flatMap { UIImage(data: $0) },
                confidence: item.confidence
            )
        }
    }
    
    private func loadHistory() {
        let loadedHistory = HistoryService.shared.loadHistory()
        history = loadedHistory
        print("📚 HistoryView: Loaded \(loadedHistory.count) items")
        
        // Debug: Print history items
        for (index, item) in loadedHistory.enumerated() {
            print("  \(index + 1). \(item.artworkInfo.title) by \(item.artworkInfo.artist) - \(item.timestamp)")
        }
    }
    
    private func deleteHistoryItems(at offsets: IndexSet) {
        var updatedHistory = history
        updatedHistory.remove(atOffsets: offsets)
        
        // Save updated history
        if let encoded = try? JSONEncoder().encode(updatedHistory) {
            UserDefaults.standard.set(encoded, forKey: "MuseLensHistory")
            history = updatedHistory
            print("✅ Deleted \(offsets.count) history item(s)")
        }
    }
}

struct HistoryRow: View {
    let item: HistoryItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let photoData = item.userPhotoData,
               let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "photo.artframe")
                            .foregroundColor(.secondary)
                    )
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.artworkInfo.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                
                Text(item.artworkInfo.artist)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    // Confidence badge (if available)
                    if let confidence = item.confidence {
                        let level: RecognitionConfidenceLevel = confidence >= 0.8 ? .high : (confidence >= 0.5 ? .medium : .low)
                        Text(level == .high ? "高确定性" : (level == .medium ? "中确定性" : "低确定性"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(level == .high ? .green : (level == .medium ? .orange : .red))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill((level == .high ? Color.green : (level == .medium ? Color.orange : Color.red)).opacity(0.1))
                            )
                    }
                    
                    Text(item.timestamp, style: .relative)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    HistoryView()
}

