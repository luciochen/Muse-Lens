//
//  CameraView.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import SwiftUI
import AVFoundation
import UIKit
import Foundation

struct CameraView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        
        // Check if running on simulator
        #if targetEnvironment(simulator)
        // Always use photo library on simulator (no camera available)
        picker.sourceType = .photoLibrary
        #else
        // On real device, try to use camera if available and authorized
        // Otherwise fallback to photo library
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if authStatus == .authorized {
                picker.sourceType = .camera
                // CRITICAL: Don't set cameraCaptureMode or cameraDevice explicitly
                // Let UIImagePickerController automatically select the best camera configuration
                // Setting these properties can trigger errors with unsupported devices:
                // - BackAuto, BackWideDual, etc.
                // The system will automatically choose a supported camera mode
            } else {
                // Camera not authorized, fallback to photo library
                picker.sourceType = .photoLibrary
            }
        } else {
            // Camera not available, use photo library
            picker.sourceType = .photoLibrary
        }
        #endif
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Update camera configuration if needed
        // Avoid changing sourceType here to prevent configuration errors
    }
    
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
            // Dismiss on main thread
            DispatchQueue.main.async {
                self.parent.isPresented = false
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            // Dismiss on main thread
            DispatchQueue.main.async {
                self.parent.isPresented = false
            }
        }
        
        // Handle presentation errors silently
        func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
            // This is called when the picker is successfully presented
            // Silently handle any presentation errors
        }
        
        func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
            // Silently handle any presentation warnings
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
    @State private var artistIntroduction: String?
    @State private var confidence: Double?
    @State private var showHistory = false
    @State private var lastCapturedImage: UIImage? // Store image for retry
    @State private var searchText = ""
    @State private var showSearchResults = false
    @State private var searchResults: [ArtworkInfo] = []
    @State private var isSearching = false
    
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
                
                // Search Bar - Temporarily hidden
                // HStack {
                //     Image(systemName: "magnifyingglass")
                //         .foregroundColor(.secondary)
                //     
                //     TextField("搜索作品或艺术家", text: $searchText)
                //         .textFieldStyle(PlainTextFieldStyle())
                //         .onSubmit {
                //             performSearch()
                //         }
                //     
                //     if !searchText.isEmpty {
                //         Button(action: {
                //             searchText = ""
                //             searchResults = []
                //             showSearchResults = false
                //         }) {
                //             Image(systemName: "xmark.circle.fill")
                //                 .foregroundColor(.secondary)
                //         }
                //     }
                //     
                //     if isSearching {
                //         ProgressView()
                //             .scaleEffect(0.8)
                //     } else if !searchText.isEmpty {
                //         Button(action: {
                //             performSearch()
                //         }) {
                //             Text("搜索")
                //                 .font(.system(size: 14, weight: .medium))
                //                 .foregroundColor(.blue)
                //         }
                //     }
                // }
                // .padding()
                // .background(Color(.systemGray6))
                // .cornerRadius(12)
                // .padding(.horizontal)
                // .padding(.top, 8)
                
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
                    VStack(spacing: 12) {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        
                        if lastCapturedImage != nil {
                            Button(action: {
                                if let image = lastCapturedImage {
                                    processImage(image)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("重试")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(8)
                            }
                        }
                    }
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
                    artistIntroduction: artistIntroduction ?? "",
                    userImage: capturedImage,
                    confidence: confidence
                )
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
        // Search results sheet - temporarily disabled
        // .sheet(isPresented: $showSearchResults) {
        //     SearchResultsView(
        //         results: searchResults,
        //         onSelect: { artwork in
        //             showSearchResults = false
        //             navigateToArtwork(artwork)
        //         }
        //     )
        // }
        .onChange(of: capturedImage) { oldValue, newValue in
            if let image = newValue {
                lastCapturedImage = image // Save for retry
                processImage(image)
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        isSearching = true
        showSearchResults = true
        
        Task {
            let results = await SearchService.shared.searchArtworks(query: searchText)
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }
    
    private func navigateToArtwork(_ artwork: ArtworkInfo) {
        // Generate narration for the selected artwork using AI
        Task {
            // Try to generate narration using NarrationService with the artwork image
            if let imageURL = artwork.imageURL, let url = URL(string: imageURL) {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = UIImage(data: data) {
                        // Convert image to base64
                        let imageBase64 = image.jpegData(compressionQuality: 0.7)?.base64EncodedString() ?? ""
                        
                        // Generate narration from image
                        let narrationResponse = try await NarrationService.shared.generateNarrationFromImage(imageBase64: imageBase64)
                        
                        await MainActor.run {
                            self.artworkInfo = narrationResponse.toArtworkInfo(imageURL: artwork.imageURL, recognized: true)
                            self.narration = narrationResponse.narration
                            self.artistIntroduction = narrationResponse.artistIntroduction ?? ""
                            self.confidence = narrationResponse.confidence
                            self.showPlayback = true
                        }
                        return
                    }
                } catch {
                    print("⚠️ Failed to load image or generate narration: \(error)")
                }
            }
            
            // Fallback: Create simple narration based on artwork info
            await MainActor.run {
                let narration = """
                这是\(artwork.title)，由\(artwork.artist)创作。
                \(artwork.year.map { "创作于\($0)年。" } ?? "")
                \(artwork.style.map { "属于\($0)风格。" } ?? "")
                
                这是一件珍贵的艺术作品，展现了艺术家的独特视角和创作技巧。
                """
                
                self.artworkInfo = artwork
                self.narration = narration
                self.artistIntroduction = nil
                self.confidence = 1.0 // High confidence for searched artworks
                self.showPlayback = true
            }
        }
    }
    
    private func checkCameraPermission() {
        // Check if running in preview mode
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            // In preview mode, don't try to access camera
            errorMessage = "预览模式下无法使用相机功能，请在模拟器或真机上运行"
            return
        }
        #endif
        
        // Check if running on simulator
        #if targetEnvironment(simulator)
        // On simulator, always use photo library (no camera available)
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            showCamera = true
        } else {
            errorMessage = "设备不支持照片库"
        }
        return
        #endif
        
        // On real device, check camera availability and permissions
        // First check if photo library is available (always fallback option)
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            errorMessage = "设备不支持照片库"
            return
        }
        
        // Check if camera is available
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            // Request camera permission on real device
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            
            switch status {
            case .authorized:
                // Camera permission granted, show camera
                showCamera = true
            case .notDetermined:
                // Request permission
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        if granted {
                            showCamera = true
                        } else {
                            // If camera permission denied, fallback to photo library
                            showCamera = true // Still show picker, it will use photo library
                        }
                    }
                }
            case .denied, .restricted:
                // Camera permission denied, fallback to photo library
                showCamera = true // Show picker, it will use photo library as fallback
            @unknown default:
                // Unknown status, use photo library
                showCamera = true
            }
        } else {
            // Camera not available, use photo library
            showCamera = true
        }
    }
    
    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil
        lastCapturedImage = image // Save for retry
        
        Task {
            let totalStartTime = Date()
            do {
                // Check API key configuration
                guard AppConfig.isConfigured else {
                    await MainActor.run {
                        errorMessage = "API Key 未配置。请在 Xcode Scheme 中设置 OPENAI_API_KEY 环境变量。"
                        isProcessing = false
                    }
                    return
                }
                
                print("🎨 Starting AI analysis of image...")
                
                // Prepare image for AI analysis (optimized for speed - smaller size for faster upload)
                let imageBase64: String = {
                    // More aggressive compression for faster upload (target 300KB for speed)
                    let targetSize = 300 * 1024 // 300KB max for faster upload
                    let compressionQuality: CGFloat = 0.35 // Lower quality for faster processing
                    
                    // Helper function to resize image
                    func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
                        UIGraphicsBeginImageContextWithOptions(size, false, 0.8) // Lower scale for faster processing
                        defer { UIGraphicsEndImageContext() }
                        image.draw(in: CGRect(origin: .zero, size: size))
                        return UIGraphicsGetImageFromCurrentImageContext()
                    }
                    
                    // First, resize if image is too large (max 800px on longest side for faster processing)
                    let maxDimension: CGFloat = 800
                    var processedImage = image
                    if max(image.size.width, image.size.height) > maxDimension {
                        let scale = maxDimension / max(image.size.width, image.size.height)
                        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        if let resized = resizeImage(image, to: newSize) {
                            processedImage = resized
                            print("📐 Resized image: \(Int(newSize.width))x\(Int(newSize.height))")
                        }
                    }
                    
                    // Compress with lower quality
                    var imageData = processedImage.jpegData(compressionQuality: compressionQuality)
                    
                    // If still too large, resize further
                    if let data = imageData, data.count > targetSize {
                        let scale = sqrt(Double(targetSize) / Double(data.count))
                        let newSize = CGSize(width: processedImage.size.width * scale, height: processedImage.size.height * scale)
                        if let resizedImage = resizeImage(processedImage, to: newSize) {
                            imageData = resizedImage.jpegData(compressionQuality: compressionQuality)
                        }
                    }
                    
                    if let data = imageData {
                        let base64 = data.base64EncodedString()
                        print("📸 Prepared image for AI: \(data.count / 1024)KB, base64: \(base64.count) chars")
                        return base64
                    }
                    // Fallback if compression fails
                    return processedImage.jpegData(compressionQuality: compressionQuality)?.base64EncodedString() ?? ""
                }()
                
                guard !imageBase64.isEmpty else {
                    throw NarrationService.NarrationError.imageProcessingFailed
                }
                
                // Immediately show playback view with skeleton loading
                // Create placeholder artwork info for skeleton loading
                let placeholderInfo = ArtworkInfo(
                    title: "正在识别...",
                    artist: "分析中",
                    recognized: false
                )
                
                await MainActor.run {
                    self.artworkInfo = placeholderInfo
                    self.narration = ""
                    self.isProcessing = false
                    self.showPlayback = true
                    print("✅ Showing playback view with skeleton loading")
                }
                
                // Start generating narration in background
                print("🤖 Sending image to ChatGPT for analysis and narration generation...")
                let narrationStartTime = Date()
                
                // Generate narration with confidence assessment
                var narrationResponse = try await NarrationService.shared.generateNarrationFromImage(
                    imageBase64: imageBase64
                )
                
                // Validate narration is not empty
                guard !narrationResponse.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NarrationService.NarrationError.invalidResponse
                }
                
                print("📊 Recognition confidence: \(narrationResponse.confidence) (\(narrationResponse.confidenceLevel))")
                print("📝 AI-generated info - Title: '\(narrationResponse.title)', Artist: '\(narrationResponse.artist)', Year: '\(narrationResponse.year ?? "null")', Style: '\(narrationResponse.style ?? "null")'")
                
                // For high confidence, ALWAYS verify information from online sources
                if narrationResponse.confidenceLevel == .high {
                    print("🔍 High confidence detected, verifying information from online sources...")
                    
                    // Try multiple search strategies with the AI-generated information
                    var searchCandidates: [RecognitionCandidate] = []
                    
                    // Strategy 1: Use AI-generated title and artist
                    searchCandidates.append(RecognitionCandidate(
                        artworkName: narrationResponse.title,
                        artist: narrationResponse.artist != "未知艺术家" ? narrationResponse.artist : nil,
                        confidence: narrationResponse.confidence
                    ))
                    
                    // Strategy 2: Try with artist name variations (if available)
                    let artist = narrationResponse.artist
                    if artist != "未知艺术家" && !artist.isEmpty {
                        // Try English name if Chinese name was provided
                        if artist.contains("·") || artist.contains("达") {
                            // Might be Chinese name, try searching with just artwork name first
                            searchCandidates.append(RecognitionCandidate(
                                artworkName: narrationResponse.title,
                                artist: nil,
                                confidence: narrationResponse.confidence
                            ))
                        }
                    }
                    
                    // Try to retrieve verified information
                    var verifiedInfo: ArtworkInfo? = nil
                    for candidate in searchCandidates {
                        if let info = await RetrievalService.shared.retrieveArtworkInfo(candidates: [candidate]) {
                            verifiedInfo = info
                            break
                        }
                    }
                    
                    // PRIORITIZE AI-generated information (from narration) over API verification
                    // The narration content is more accurate according to user feedback
                    // Only use verified info if AI info is missing or clearly wrong
                    if let verified = verifiedInfo {
                        print("✅ Found verified information from online sources")
                        print("📝 Verified info - Title: '\(verified.title)', Artist: '\(verified.artist)', Year: '\(verified.year ?? "null")', Style: '\(verified.style ?? "null")'")
                        print("📝 AI info - Title: '\(narrationResponse.title)', Artist: '\(narrationResponse.artist)', Year: '\(narrationResponse.year ?? "null")', Style: '\(narrationResponse.style ?? "null")'")
                        
                        // PRIORITY: Use AI-generated info (from narration) as primary source
                        // Only supplement with verified info if AI info is missing
                        // Convert verified info to Chinese if needed
                        let finalTitle = narrationResponse.title.isEmpty || narrationResponse.title == "无法识别的作品" ? verified.title : narrationResponse.title
                        let finalArtist = narrationResponse.artist.isEmpty || narrationResponse.artist == "未知艺术家" ? verified.artist : narrationResponse.artist
                        let finalYear = narrationResponse.year ?? verified.year
                        let finalStyle = narrationResponse.style ?? verified.style
                        
                        // Merge sources
                        var allSources = narrationResponse.sources
                        for source in verified.sources {
                            if !allSources.contains(source) {
                                allSources.append(source)
                            }
                        }
                        
                        narrationResponse = NarrationResponse(
                            title: finalTitle, // Prioritize AI title (from narration)
                            artist: finalArtist, // Prioritize AI artist (from narration)
                            year: finalYear, // Use AI year if available, else verified
                            style: finalStyle, // Use AI style if available, else verified
                            summary: narrationResponse.summary, // Keep AI summary
                            narration: narrationResponse.narration, // Keep AI-generated narration (most accurate)
                            artistIntroduction: narrationResponse.artistIntroduction, // Keep AI-generated artist intro
                            sources: allSources, // Merge sources
                            confidence: narrationResponse.confidence // Keep AI confidence
                        )
                        print("✅ Using AI-generated info (from narration) as primary source")
                        print("✅ Final info - Title: '\(narrationResponse.title)', Artist: '\(narrationResponse.artist)', Year: '\(narrationResponse.year ?? "null")', Style: '\(narrationResponse.style ?? "null")'")
                    } else {
                        print("⚠️ Could not verify information from online sources")
                        print("✅ Using AI-generated information (from narration) as primary source")
                        // Keep AI-generated info as-is since verification failed
                        // The narration content is the source of truth
                    }
                } else {
                    // For medium/low confidence, still try to verify if possible
                    if narrationResponse.title != "无法识别的作品" && !narrationResponse.title.contains("印象派") && !narrationResponse.title.contains("风格") {
                        print("🔍 Medium/low confidence, attempting verification...")
                        let candidate = RecognitionCandidate(
                            artworkName: narrationResponse.title,
                            artist: narrationResponse.artist != "未知艺术家" ? narrationResponse.artist : nil,
                            confidence: narrationResponse.confidence
                        )
                        
                        if let verified = await RetrievalService.shared.retrieveArtworkInfo(candidates: [candidate]) {
                            print("✅ Found verified information, updating...")
                            narrationResponse = NarrationResponse(
                                title: verified.title,
                                artist: verified.artist,
                                year: verified.year ?? narrationResponse.year,
                                style: verified.style ?? narrationResponse.style,
                                summary: narrationResponse.summary,
                                narration: narrationResponse.narration,
                                artistIntroduction: narrationResponse.artistIntroduction,
                                sources: verified.sources,
                                confidence: min(narrationResponse.confidence + 0.1, 1.0) // Slightly increase confidence if verified
                            )
                        }
                    }
                }
                
                let elapsed = Date().timeIntervalSince(narrationStartTime)
                print("✅ Narration generated successfully in \(String(format: "%.2f", elapsed))s")
                print("📝 Title: \(narrationResponse.title)")
                print("📝 Artist: \(narrationResponse.artist)")
                print("📝 Confidence: \(narrationResponse.confidence) - \(narrationResponse.confidenceLevel)")
                print("📝 Narration length: \(narrationResponse.narration.count) characters")
                
                // Determine recognized status based on confidence
                let isRecognized = narrationResponse.confidenceLevel == .high
                
                // Save to history
                let finalArtworkInfo = narrationResponse.toArtworkInfo(recognized: isRecognized)
                let historyItem = HistoryItem(
                    artworkInfo: finalArtworkInfo,
                    narration: narrationResponse.narration,
                    userPhotoData: image.jpegData(compressionQuality: 0.5)
                )
                HistoryService.shared.saveHistoryItem(historyItem)
                
                // Update playback view with final data
                let totalElapsed = Date().timeIntervalSince(totalStartTime)
                print("⏱️ Total processing time: \(String(format: "%.2f", totalElapsed))s")
                
                await MainActor.run {
                    self.artworkInfo = finalArtworkInfo
                    self.narration = narrationResponse.narration
                    self.artistIntroduction = narrationResponse.artistIntroduction ?? ""
                    self.confidence = narrationResponse.confidence
                    print("✅ Updated playback view with final data")
                }
                
            } catch {
                await MainActor.run {
                    // Provide user-friendly error messages
                    if let narrationError = error as? NarrationService.NarrationError {
                        switch narrationError {
                        case .apiKeyMissing:
                            errorMessage = "API Key 未配置。请在 Xcode Scheme 中设置 OPENAI_API_KEY 环境变量。"
                        case .invalidURL:
                            errorMessage = "网络请求配置错误"
                        case .apiRequestFailed(let details):
                            if let details = details, details.contains("API key") || details.contains("401") {
                                errorMessage = "API Key 无效。请检查 OPENAI_API_KEY 是否正确。"
                            } else {
                                errorMessage = "生成讲解失败：\(details ?? "请检查网络连接后重试")"
                            }
                        case .invalidResponse:
                            errorMessage = "讲解生成服务返回了无效的响应，请重试"
                        case .imageProcessingFailed:
                            errorMessage = "图片处理失败，请重试"
                        case .networkTimeout:
                            errorMessage = "请求超时。请检查网络连接后重试。"
                        case .networkUnavailable:
                            errorMessage = "网络不可用。请检查您的网络连接。"
                        case .apiError(let code, let message):
                            if code == 401 {
                                errorMessage = "API Key 无效或已过期。请检查 OPENAI_API_KEY。"
                            } else if code == 429 {
                                errorMessage = "请求过于频繁，请稍后再试。"
                            } else if let message = message {
                                errorMessage = "API 错误 (\(code)): \(message)"
                            } else {
                                errorMessage = "API 错误 (\(code))，请重试。"
                            }
                        }
                    } else {
                        let errorDesc = error.localizedDescription
                        if errorDesc.contains("correct format") || errorDesc.contains("JSON") {
                            errorMessage = "数据格式错误，请重试。如果问题持续，请检查 API Key 是否正确。"
                        } else if errorDesc.contains("timeout") || errorDesc.contains("timed out") {
                            errorMessage = "请求超时，请检查网络连接后重试。"
                        } else {
                            errorMessage = "发生错误：\(errorDesc)"
                        }
                    }
                    isProcessing = false
                }
            }
        }
    }
}

#Preview {
    // Preview without camera access to avoid crashes
    VStack(spacing: 30) {
        VStack(spacing: 8) {
            Text("MuseLens")
                .font(.system(size: 36, weight: .bold))
            Text("拍一眼，就懂艺术")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.top, 60)
        
        Spacer()
        
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
        
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
}

