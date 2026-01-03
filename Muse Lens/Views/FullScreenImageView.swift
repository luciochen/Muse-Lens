//
//  FullScreenImageView.swift
//  Muse Lens
//
//  Created for full-screen image viewing
//

import SwiftUI

struct FullScreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea()
            
            // Image with zoom and pan
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = scale * delta
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            // Limit scale
                            if scale < 1.0 {
                                withAnimation(.spring()) {
                                    scale = 1.0
                                    offset = .zero
                                }
                            } else if scale > 5.0 {
                                withAnimation(.spring()) {
                                    scale = 5.0
                                }
                            }
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                            )
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    }
                    .padding(.top, 50)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
        }
        .onTapGesture(count: 2) {
            // Double tap to reset zoom
            withAnimation(.spring()) {
                scale = 1.0
                offset = .zero
                lastOffset = .zero
            }
        }
    }
}

#Preview {
    FullScreenImageView(image: UIImage(systemName: "photo")!)
}

