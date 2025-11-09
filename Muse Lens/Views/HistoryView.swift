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
    @State private var showPlayback = false
    
    var body: some View {
        NavigationView {
            List {
                if history.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("暂无历史记录")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(history) { item in
                        HistoryRow(item: item)
                            .onTapGesture {
                                selectedItem = item
                                showPlayback = true
                            }
                    }
                }
            }
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
        .fullScreenCover(isPresented: $showPlayback) {
            if let item = selectedItem {
                        PlaybackView(
                            artworkInfo: item.artworkInfo,
                            narration: item.narration,
                            artistIntroduction: "", // History items don't have artist introduction
                            userImage: item.userPhotoData.flatMap { UIImage(data: $0) },
                            confidence: nil // History items don't have confidence data
                        )
            }
        }
    }
    
    private func loadHistory() {
        history = HistoryService.shared.loadHistory()
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
                    .cornerRadius(8)
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
                
                Text(item.timestamp, style: .relative)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HistoryView()
}

