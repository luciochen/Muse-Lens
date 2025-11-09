//
//  CameraView.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import SwiftUI
import AVFoundation
import UIKit

struct CameraView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.cameraCaptureMode = .photo
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedImage = image
            }
            parent.isPresented = false
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

/// Main camera interface view
struct CameraCaptureView: View {
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showPlayback = false
    @State private var artworkInfo: ArtworkInfo?
    @State private var narration: String?
    @State private var showHistory = false
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // App Title
                VStack(spacing: 8) {
                    Text("MuseLens")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("拍一眼，就懂艺术")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 60)
                
                // History Button
                Button(action: {
                    showHistory = true
                }) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("历史记录")
                    }
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                }
                .padding(.top, 8)
                
                Spacer()
                
                // Camera Button
                Button(action: {
                    checkCameraPermission()
                }) {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        
                        Text("拍摄艺术品")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 200, height: 200)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                }
                .disabled(isProcessing)
                .opacity(isProcessing ? 0.6 : 1.0)
                
                if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在识别中...")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView(capturedImage: $capturedImage, isPresented: $showCamera)
        }
        .fullScreenCover(isPresented: $showPlayback) {
            if let artworkInfo = artworkInfo, let narration = narration {
                PlaybackView(
                    artworkInfo: artworkInfo,
                    narration: narration,
                    userImage: capturedImage
                )
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
        .onChange(of: capturedImage) { newImage in
            if let image = newImage {
                processImage(image)
            }
        }
    }
    
    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        errorMessage = "需要相机权限才能拍摄艺术品"
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "请在设置中允许相机权限"
        @unknown default:
            errorMessage = "无法访问相机"
        }
    }
    
    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                // Check API key configuration
                guard AppConfig.isConfigured else {
                    await MainActor.run {
                        errorMessage = "API Key 未配置。请在 Xcode Scheme 中设置 OPENAI_API_KEY 环境变量。"
                        isProcessing = false
                    }
                    return
                }
                
                // Step 1: Recognize artwork
                let candidates = try await RecognitionService.shared.recognizeArtwork(from: image)
                
                guard !candidates.isEmpty else {
                    await MainActor.run {
                        errorMessage = "未能识别出艺术品，请重试"
                        isProcessing = false
                    }
                    return
                }
                
                // Step 2: Retrieve artwork information
                var artwork: ArtworkInfo?
                
                if let retrievedInfo = await RetrievalService.shared.retrieveArtworkInfo(candidates: candidates) {
                    artwork = retrievedInfo
                } else if let firstCandidate = candidates.first,
                          let style = firstCandidate.artworkName.components(separatedBy: " style").first?.trimmingCharacters(in: .whitespaces) {
                    // Fallback to style information
                    artwork = await RetrievalService.shared.getStyleInformation(style: style) ?? ArtworkInfo(
                        title: firstCandidate.artworkName,
                        artist: firstCandidate.artist ?? "Unknown",
                        recognized: false
                    )
                } else {
                    // Last resort fallback
                    let firstCandidate = candidates.first!
                    artwork = ArtworkInfo(
                        title: firstCandidate.artworkName,
                        artist: firstCandidate.artist ?? "Unknown",
                        recognized: false
                    )
                }
                
                guard let finalArtwork = artwork else {
                    await MainActor.run {
                        errorMessage = "无法获取艺术品信息"
                        isProcessing = false
                    }
                    return
                }
                
                // Step 3: Generate narration
                let narrationResponse = try await NarrationService.shared.generateNarration(artworkInfo: finalArtwork)
                
                // Step 4: Save to history
                let historyItem = HistoryItem(
                    artworkInfo: narrationResponse.toArtworkInfo(imageURL: finalArtwork.imageURL, recognized: finalArtwork.recognized),
                    narration: narrationResponse.narration,
                    userPhotoData: image.jpegData(compressionQuality: 0.5)
                )
                HistoryService.shared.saveHistoryItem(historyItem)
                
                // Step 5: Show playback view
                await MainActor.run {
                    self.artworkInfo = narrationResponse.toArtworkInfo(imageURL: finalArtwork.imageURL, recognized: finalArtwork.recognized)
                    self.narration = narrationResponse.narration
                    self.isProcessing = false
                    self.showPlayback = true
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

#Preview {
    CameraCaptureView()
}

