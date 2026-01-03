//
//  ArtistDetailView.swift
//  Muse Lens
//
//  Created for displaying artist biography
//

import SwiftUI

struct ArtistDetailView: View {
    let artistName: String // From artist table: "name" field
    let artistIntroduction: String // From artist table: "artist_introduction" field
    let isIdentified: Bool // Whether the artist was successfully identified
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Show identification status if not identified
                    if !isIdentified {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("artist.detail.not_identified")
                                .font(.system(size: 15))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    if artistIntroduction.isEmpty {
                        // Empty state
                        VStack(spacing: 16) {
                            Image(systemName: "person.circle")
                                .font(.system(size: 64))
                                .foregroundColor(.secondary)
                            
                            Text(isIdentified ? "artist.detail.no_info" : "artist.detail.no_info_unidentified")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        // Artist introduction
                        Text(artistIntroduction)
                            .font(.system(size: 17))
                            .foregroundColor(.primary)
                            .lineSpacing(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle(artistName)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

#Preview("Identified Artist with Info") {
    ArtistDetailView(
        artistName: "克劳德·莫奈",
        artistIntroduction: "克劳德·莫奈（1840-1926）是法国印象派画家，被誉为\"印象派之父\"。他的作品以捕捉光线和色彩的变化而闻名，代表作包括《日出·印象》、《睡莲》等系列作品。",
        isIdentified: true
    )
}

#Preview("Unidentified Artist") {
    ArtistDetailView(
        artistName: "未知艺术家",
        artistIntroduction: "",
        isIdentified: false
    )
}

#Preview("Identified Artist No Info") {
    ArtistDetailView(
        artistName: "约翰·史密斯",
        artistIntroduction: "",
        isIdentified: true
    )
}

