//
//  SearchResultsView.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import SwiftUI

struct SearchResultsView: View {
    let results: [ArtworkInfo]
    let onSelect: (ArtworkInfo) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            Group {
                if results.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("未找到结果")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                        Text("请尝试其他关键词")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(results) { artwork in
                            SearchResultRow(artwork: artwork)
                                .onTapGesture {
                                    onSelect(artwork)
                                }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("搜索结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let artwork: ArtworkInfo
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let imageURL = artwork.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure(_), .empty:
                            imagePlaceholder
                        @unknown default:
                            imagePlaceholder
                        }
                    }
                } else {
                    imagePlaceholder
                }
            }
            .frame(width: 80, height: 80)
            .cornerRadius(8)
            .clipped()
            
            // Artwork Info
            VStack(alignment: .leading, spacing: 4) {
                Text(artwork.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Text(artwork.artist)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let year = artwork.year {
                    Text(year)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: "photo.artframe")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
            )
    }
}

#Preview {
    SearchResultsView(
        results: [
            ArtworkInfo(
                title: "示例作品",
                artist: "示例艺术家",
                year: "2023",
                style: "印象派",
                imageURL: nil,
                recognized: true
            )
        ],
        onSelect: { _ in }
    )
}

