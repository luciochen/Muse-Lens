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

/// Data structure for PlaybackView - ensures view updates when data changes
struct PlaybackData: Identifiable {
    let id: UUID
    let artworkInfo: ArtworkInfo
    let narration: String
    let artistIntroduction: String
    let narrationLanguage: String
    let userImage: UIImage?
    let confidence: Double?
    
    init(
        id: UUID = UUID(),
        artworkInfo: ArtworkInfo,
        narration: String,
        artistIntroduction: String = "",
        narrationLanguage: String = ContentLanguage.zh,
        userImage: UIImage? = nil,
        confidence: Double? = nil
    ) {
        // IMPORTANT:
        // This id must remain stable while we update `playbackData` during generation.
        // If we tie it to `artworkInfo.id`, every ArtworkInfo rebuild creates a new UUID,
        // causing fullScreenCover(item:) to dismiss + re-present (appears as “jumping back home”).
        self.id = id
        self.artworkInfo = artworkInfo
        self.narration = narration
        self.artistIntroduction = artistIntroduction
        self.narrationLanguage = narrationLanguage
        self.userImage = userImage
        self.confidence = confidence
    }
}

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
    @State private var playbackData: PlaybackData? // Use PlaybackData instead of separate states
    @State private var showHistory = false
    @State private var showDatabaseTest = false
    @State private var lastCapturedImage: UIImage? // Store image for retry
    @State private var searchText = ""
    @State private var showSearchResults = false
    @State private var searchResults: [ArtworkInfo] = []
    @State private var isSearching = false
    
    var body: some View {
        ZStack {
            // Background: Image with dark overlay
            Image("HomeBgImage")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // App Logo
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 110)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .padding(.top, 180)
                
                Spacer()
                
                // Camera Button - White circle with #1F1F1F icon/text
                Button(action: {
                    checkCameraPermission()
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 50))
                            .foregroundColor(Color(hex: "1F1F1F"))
                        
                        Text("home.cta.capture")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(hex: "1F1F1F"))
                    }
                    .frame(width: 160, height: 160)
                    .background(
                        Circle()
                            .fill(Color.white)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                }
                .disabled(isProcessing)
                .opacity(isProcessing ? 0.6 : 1.0)
                
                // Navigation Buttons - Tertiary style (white text, no background)
                // Vertically stacked below camera button
                VStack(spacing: 24) {
                    // History Button
                    Button(action: {
                        showHistory = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("home.nav.history")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    }
                    
                    #if DEBUG
                    // Database Test Button (Development only)
                    Button(action: {
                        showDatabaseTest = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield.fill")
                            Text("home.nav.db_test")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    }
                    #endif
                }
                .padding(.top, 20)
                
                if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("home.status.recognizing")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.top, 20)
                }
                
                if let error = errorMessage {
                    VStack(spacing: 12) {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        if lastCapturedImage != nil {
                            Button(action: {
                                if let image = lastCapturedImage {
                                    processImage(image)
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("home.action.retry")
                                }
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color(hex: "1F1F1F"))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white)
                                )
                            }
                        }
                    }
                    .padding()
                    .background(Color.red.opacity(0.25))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $showCamera) {
            CameraView(capturedImage: $capturedImage, isPresented: $showCamera)
        }
        .fullScreenCover(item: $playbackData) { data in
            PlaybackView(
                artworkInfo: data.artworkInfo,
                narration: data.narration,
                artistIntroduction: data.artistIntroduction,
                narrationLanguage: data.narrationLanguage,
                userImage: data.userImage,
                confidence: data.confidence
            )
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
        .sheet(isPresented: $showDatabaseTest) {
            DatabaseTestView()
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
                            let sessionId = self.playbackData?.id ?? UUID()
                            let artworkInfo = narrationResponse.toArtworkInfo(imageURL: artwork.imageURL, recognized: true)
                            self.playbackData = PlaybackData(
                                id: sessionId,
                                artworkInfo: artworkInfo,
                                narration: narrationResponse.narration,
                                artistIntroduction: narrationResponse.artistIntroduction ?? "",
                                userImage: capturedImage,
                                confidence: narrationResponse.confidence
                            )
                        }
                        return
                    }
                } catch {
                    print("⚠️ Failed to load image or generate narration: \(error)")
                }
            }
            
            // Fallback: Create simple narration based on artwork info
            await MainActor.run {
                let sessionId = self.playbackData?.id ?? UUID()
                let narration = """
                这是\(artwork.title)，由\(artwork.artist)创作。
                \(artwork.year.map { "创作于\($0)年。" } ?? "")
                \(artwork.style.map { "属于\($0)风格。" } ?? "")
                
                这是一件珍贵的艺术作品，展现了艺术家的独特视角和创作技巧。
                """
                
                self.playbackData = PlaybackData(
                    id: sessionId,
                    artworkInfo: artwork,
                    narration: narration,
                    artistIntroduction: "",
                    userImage: capturedImage,
                    confidence: 1.0 // High confidence for searched artworks
                )
            }
        }
    }
    
    private func checkCameraPermission() {
        // Check if running in preview mode
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            // In preview mode, don't try to access camera
            errorMessage = String(localized: "camera.error.preview_mode")
            return
        }
        #endif
        
        // Check if running on simulator
        #if targetEnvironment(simulator)
        // On simulator, always use photo library (no camera available)
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            showCamera = true
        } else {
            errorMessage = String(localized: "camera.error.photo_library_unsupported")
        }
        return
        #endif
        
        // On real device, check camera availability and permissions
        // First check if photo library is available (always fallback option)
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            errorMessage = String(localized: "camera.error.photo_library_unsupported")
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
            let maxTotalTime: TimeInterval = 20.0 // Maximum total time: 20 seconds
            
            do {
                // Check API key configuration
                guard AppConfig.isConfigured else {
                    await MainActor.run {
                        errorMessage = String(localized: "error.openai_api_key_missing")
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
                    title: UIPlaceholders.recognizingTitleToken,
                    artist: "",
                    recognized: false
                )
                
                await MainActor.run {
                    let sessionId = self.playbackData?.id ?? UUID()
                    self.playbackData = PlaybackData(
                        id: sessionId,
                        artworkInfo: placeholderInfo,
                        narration: "",
                        artistIntroduction: "",
                        userImage: capturedImage,
                        confidence: nil
                    )
                    self.isProcessing = false
                    print("✅ Showing playback view with skeleton loading")
                }
                
                let narrationStartTime = Date()
                var narrationResponse: NarrationResponse? = nil
                
                // STEP 1: Quick identification to get basic artwork info
                print("🔍 Step 1: Quick identification to get basic artwork info...")
                var quickId: (title: String, artist: String, year: String?)? = nil
                do {
                    // Check total timeout before starting
                    let elapsed = Date().timeIntervalSince(totalStartTime)
                    if elapsed > maxTotalTime {
                        throw NarrationService.NarrationError.networkTimeout
                    }
                    
                    quickId = try await NarrationService.shared.quickIdentifyArtwork(imageBase64: imageBase64)
                    print("📝 Quick identification result: '\(quickId!.title)' by '\(quickId!.artist)'")
                    
                    // Check total timeout after Step 1
                    let elapsedAfterStep1 = Date().timeIntervalSince(totalStartTime)
                    if elapsedAfterStep1 > maxTotalTime {
                        throw NarrationService.NarrationError.networkTimeout
                    }
                } catch {
                    print("⚠️ Quick identification failed: \(error), will proceed with full generation")
                }
                
                // STEP 2: Check database for artwork and artist (if identification succeeded)
                // OPTIMIZATION: Incremental display - show basic info immediately after quick identification
                if let id = quickId, id.title != "无法识别" && id.artist != "未知艺术家" {
                    print("🔍 Step 2: Checking database for artwork and artist...")
                    
                    // OPTIMIZATION: Incremental display - update UI with quick identification results
                    await MainActor.run {
                        let sessionId = self.playbackData?.id ?? UUID()
                        let artworkInfo = ArtworkInfo(
                            title: ArtworkIdentifier.cleanTitle(id.title),
                            artist: id.artist,
                            year: id.year,
                            recognized: true
                        )
                        self.playbackData = PlaybackData(
                            id: sessionId,
                            artworkInfo: artworkInfo,
                            narration: UIPlaceholders.narrationLoadingToken,
                            artistIntroduction: "",
                            userImage: capturedImage,
                            confidence: nil
                        )
                        print("✅ Updated UI with quick identification results")
                    }
                    
                    // Generate identifier and check backend cache
                    let identifier = ArtworkIdentifier.generate(
                        title: id.title,
                        artist: id.artist,
                        year: id.year
                    )
                    
                    // Check if backend has cached narration for this artwork
                    if BackendAPIService.shared.isConfigured {
                        do {
                            // OPTIMIZATION: Parallel queries - check artwork and artist introduction simultaneously
                            let artistName = id.artist
                            let shouldCheckArtist = !artistName.isEmpty && artistName != "未知艺术家"
                            
                            async let artworkTask = BackendAPIService.shared.findArtwork(identifier: identifier)
                            async let artistTask: BackendArtist? = {
                                guard shouldCheckArtist else { return nil }
                                return try? await BackendAPIService.shared.findArtistIntroduction(artist: artistName)
                            }()
                            
                            // Check total timeout before waiting for database queries
                            let elapsedBeforeDB = Date().timeIntervalSince(totalStartTime)
                            if elapsedBeforeDB > maxTotalTime {
                                throw NarrationService.NarrationError.networkTimeout
                            }
                            
                            // Wait for both queries to complete
                            if let backendArtwork = try await artworkTask {
                                // Check total timeout after database queries
                                let elapsedAfterDB = Date().timeIntervalSince(totalStartTime)
                                if elapsedAfterDB > maxTotalTime {
                                    throw NarrationService.NarrationError.networkTimeout
                                }
                                
                                print("✅ Found artwork in database: '\(backendArtwork.title)' by '\(backendArtwork.artist)'")
                                print("📝 Using cached narration from database, skipping generation (saving time and API costs)")
                                
                                // Increment view count asynchronously (non-blocking)
                                if let artworkId = backendArtwork.id {
                                    Task {
                                        await BackendAPIService.shared.incrementViewCount(artworkId: artworkId)
                                    }
                                }
                                
                                // Get artist introduction result (already fetched in parallel)
                                var cachedIntroduction: String? = nil
                                if shouldCheckArtist {
                                    let backendArtist = await artistTask
                                    if let backendArtist = backendArtist {
                                        if let artistIntro = backendArtist.artistIntroduction, !artistIntro.isEmpty {
                                            cachedIntroduction = artistIntro
                                            print("✅ Found artist introduction in database: \(artistIntro.count) characters")
                                        } else {
                                            print("⚠️ Artist found in database but biography is empty")
                                        }
                                    } else {
                                        print("ℹ️ Artist not found in database, will use artwork's introduction if available")
                                    }
                                }
                                
                                // Create narration response from backend cache
                                // Use artist introduction from artists table (cachedIntroduction)
                                narrationResponse = backendArtwork.toNarrationResponse(artistIntroduction: cachedIntroduction)
                                
                                if let dbIntroduction = cachedIntroduction, !dbIntroduction.isEmpty {
                                    print("✅ Using artist introduction from artists table: \(dbIntroduction.count) characters")
                                } else {
                                    print("⚠️ No artist introduction available in artists table")
                                }
                                
                                print("✅ Using cached data from database (user's photo will be preserved)")
                            } else {
                                print("ℹ️ Artwork not found in database, will generate narration")
                            }
                        } catch {
                            // Network errors are handled internally and return nil
                            // Continue with full generation if backend check fails
                            if case BackendAPIError.networkError = error {
                                print("⚠️ Network error checking database, continuing with full generation")
                            } else {
                                print("⚠️ Database check failed: \(error), continuing with full generation")
                            }
                        }
                    } else {
                        print("⚠️ Backend not configured, skipping database check")
                    }
                } else {
                    print("⚠️ Quick identification uncertain or failed, skipping database check, will generate narration")
                }
                
                // STEP 3: If no cached data found in database, generate full narration
                if narrationResponse == nil {
                    print("🤖 Step 3: No cached data found in database, generating full narration...")
                    print("🤖 Sending image to ChatGPT for full analysis and narration generation...")
                    
                    // OPTIMIZATION: Incremental display - update UI to show "正在生成讲解..."
                    await MainActor.run {
                        let sessionId = self.playbackData?.id ?? UUID()
                        let currentData = self.playbackData
                        let currentInfo = currentData?.artworkInfo
                        let artworkInfo: ArtworkInfo = currentInfo ?? ArtworkInfo(
                            title: UIPlaceholders.recognizingTitleToken,
                            artist: "",
                            recognized: false
                        )
                        self.playbackData = PlaybackData(
                            id: sessionId,
                            artworkInfo: artworkInfo,
                            narration: UIPlaceholders.narrationGeneratingToken,
                            artistIntroduction: currentData?.artistIntroduction ?? "",
                            userImage: capturedImage,
                            confidence: currentData?.confidence
                        )
                    }
                    
                    // Check total timeout before starting narration generation
                    let elapsedBeforeGeneration = Date().timeIntervalSince(totalStartTime)
                    if elapsedBeforeGeneration > maxTotalTime {
                        throw NarrationService.NarrationError.networkTimeout
                    }
                    
                    // Generate narration with streaming support - updates UI progressively
                    var generatedNarrationResponse: NarrationResponse
                    let generationStartTime = Date()
                    let maxGenerationTime: TimeInterval = 12.0 // Maximum 12 seconds for generation
                    
                    do {
                        // Try streaming first for better UX
                        generatedNarrationResponse = try await NarrationService.shared.generateNarrationFromImageStreaming(
                            imageBase64: imageBase64
                        ) { partialText in
                            // Check timeout during streaming
                            let elapsed = Date().timeIntervalSince(generationStartTime)
                            if elapsed > maxGenerationTime {
                                // Don't throw here, let the request timeout naturally
                                print("⚠️ Generation taking longer than expected: \(String(format: "%.2f", elapsed))s")
                            }
                            
                            // IMPORTANT:
                            // Streaming response is JSON; showing it makes the UI display “...json...”.
                            // Keep skeleton/loading text until we have the final parsed NarrationResponse.
                            _ = partialText
                        }
                        
                        // Check total timeout after streaming generation
                        let elapsedAfterGeneration = Date().timeIntervalSince(totalStartTime)
                        if elapsedAfterGeneration > maxTotalTime {
                            throw NarrationService.NarrationError.networkTimeout
                        }
                    } catch let error as NarrationService.NarrationError {
                        // If streaming times out, don't fallback - fail fast
                        if error == .networkTimeout {
                            print("❌ Streaming generation timed out, failing fast instead of fallback")
                            throw error
                        }
                        
                        // Fallback to non-streaming only for non-timeout errors
                        print("⚠️ Streaming failed, using non-streaming: \(error)")
                        
                        // Check total timeout before fallback
                        let elapsedBeforeFallback = Date().timeIntervalSince(totalStartTime)
                        if elapsedBeforeFallback > maxTotalTime {
                            throw NarrationService.NarrationError.networkTimeout
                        }
                        
                        generatedNarrationResponse = try await NarrationService.shared.generateNarrationFromImage(
                            imageBase64: imageBase64
                        )
                        
                        // Check total timeout after fallback generation
                        let elapsedAfterFallback = Date().timeIntervalSince(totalStartTime)
                        if elapsedAfterFallback > maxTotalTime {
                            throw NarrationService.NarrationError.networkTimeout
                        }
                    } catch {
                        // For other errors, check timeout and rethrow
                        let elapsed = Date().timeIntervalSince(totalStartTime)
                        if elapsed > maxTotalTime {
                            throw NarrationService.NarrationError.networkTimeout
                        }
                        throw error
                    }
                    
                    // Validate narration is not empty
                    guard !generatedNarrationResponse.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw NarrationService.NarrationError.invalidResponse
                    }
                    
                    print("📊 Recognition confidence: \(generatedNarrationResponse.confidence) (\(generatedNarrationResponse.confidenceLevel))")
                    print("📝 AI-generated info - Title: '\(generatedNarrationResponse.title)', Artist: '\(generatedNarrationResponse.artist)', Year: '\(generatedNarrationResponse.year ?? "null")', Style: '\(generatedNarrationResponse.style ?? "null")'")
                    
                    // OPTIMIZATION: Update UI with final structured data
                    await MainActor.run {
                        let sessionId = self.playbackData?.id ?? UUID()
                        let artworkInfo = ArtworkInfo(
                            title: ArtworkIdentifier.cleanTitle(generatedNarrationResponse.title),
                            artist: generatedNarrationResponse.artist,
                            year: generatedNarrationResponse.year,
                            style: generatedNarrationResponse.style,
                            recognized: generatedNarrationResponse.confidenceLevel == .high
                        )
                        // Narration text is already updated progressively via streaming
                        // But ensure final version is set
                        // CRITICAL: Use stable sessionId to prevent view dismissal/re-presentation
                        self.playbackData = PlaybackData(
                            id: sessionId,
                            artworkInfo: artworkInfo,
                            narration: generatedNarrationResponse.narration,
                            artistIntroduction: self.playbackData?.artistIntroduction ?? "",
                            narrationLanguage: ContentLanguage.zh,
                            userImage: capturedImage,
                            confidence: generatedNarrationResponse.confidence
                        )
                        print("✅ Updated UI with final AI-generated data (stable ID: \(sessionId))")
                    }
                    
                    // Use cache service to get artwork narration (may save to backend)
                    narrationResponse = await ArtworkCacheService.shared.getArtworkWithArtistIntroduction(
                        title: generatedNarrationResponse.title,
                        artist: generatedNarrationResponse.artist,
                        year: generatedNarrationResponse.year,
                        narrationResponse: generatedNarrationResponse,
                        artworkInfo: nil // Will be set after verification
                    ) ?? generatedNarrationResponse
                    
                    // Update UI with artist introduction if available
                    if let artistIntro = narrationResponse?.artistIntroduction, !artistIntro.isEmpty {
                        await MainActor.run {
                            if let currentData = self.playbackData {
                                self.playbackData = PlaybackData(
                                    id: currentData.id,
                                    artworkInfo: currentData.artworkInfo,
                                    narration: currentData.narration,
                                    artistIntroduction: artistIntro,
                                    narrationLanguage: currentData.narrationLanguage,
                                    userImage: currentData.userImage,
                                    confidence: currentData.confidence
                                )
                                print("✅ Updated UI with artist introduction (\(artistIntro.count) characters)")
                            }
                        }
                    }
                }
                
                guard var finalNarrationResponse = narrationResponse else {
                    throw NarrationService.NarrationError.invalidResponse
                }
                
                print("📝 Final narration - Title: '\(finalNarrationResponse.title)', Artist: '\(finalNarrationResponse.artist)'")
                
                // Variable to store verified info for later use
                var verifiedInfo: ArtworkInfo? = nil
                
                // OPTIMIZATION: Online verification async - don't block main flow
                // For high confidence, verify information from online sources in background
                if finalNarrationResponse.confidenceLevel == .high {
                    print("🔍 High confidence detected, verifying information from online sources (async, non-blocking)...")
                    
                    // OPTIMIZATION: Run verification in background task, don't wait for it
                    Task.detached(priority: .utility) {
                        // Try multiple search strategies with the AI-generated information
                        var searchCandidates: [RecognitionCandidate] = []
                        
                        // Strategy 1: Use artwork title and artist
                        searchCandidates.append(RecognitionCandidate(
                            artworkName: finalNarrationResponse.title,
                            artist: finalNarrationResponse.artist != "未知艺术家" ? finalNarrationResponse.artist : nil,
                            confidence: finalNarrationResponse.confidence
                        ))
                        
                        // Strategy 2: Try with artist name variations (if available)
                        let artist = finalNarrationResponse.artist
                        if artist != "未知艺术家" && !artist.isEmpty {
                            // Try English name if Chinese name was provided
                            if artist.contains("·") || artist.contains("达") {
                                // Might be Chinese name, try searching with just artwork name first
                                searchCandidates.append(RecognitionCandidate(
                                    artworkName: finalNarrationResponse.title,
                                    artist: nil,
                                    confidence: finalNarrationResponse.confidence
                                ))
                            }
                        }
                        
                        // Try to retrieve verified information
                        var verified: ArtworkInfo? = nil
                        for candidate in searchCandidates {
                            if let info = await RetrievalService.shared.retrieveArtworkInfo(candidates: [candidate]) {
                                verified = info
                                break
                            }
                        }
                        
                        // Verification completed, but we don't use it to block the main flow
                        // The verified info can be used for future enhancements if needed
                        if verified != nil {
                            print("✅ Background verification completed (not blocking main flow)")
                        }
                    }
                    // Continue immediately without waiting for verification
                    
                    // PRIORITIZE AI-generated information (from narration) over API verification
                    // The narration content is more accurate according to user feedback
                    // Only use verified info if AI info is missing or clearly wrong
                    if let verified = verifiedInfo {
                        print("✅ Found verified information from online sources")
                        print("📝 Verified info - Title: '\(verified.title)', Artist: '\(verified.artist)', Year: '\(verified.year ?? "null")', Style: '\(verified.style ?? "null")'")
                        print("📝 Artwork info - Title: '\(finalNarrationResponse.title)', Artist: '\(finalNarrationResponse.artist)', Year: '\(finalNarrationResponse.year ?? "null")', Style: '\(finalNarrationResponse.style ?? "null")'")
                        
                        // PRIORITY: Use artwork info (from narration) as primary source
                        // Only supplement with verified info if artwork info is missing
                        // Convert verified info to Chinese if needed
                        var finalTitle = finalNarrationResponse.title.isEmpty || finalNarrationResponse.title == "无法识别的作品" ? verified.title : finalNarrationResponse.title
                        // Clean title: remove 《》 characters
                        finalTitle = ArtworkIdentifier.cleanTitle(finalTitle)
                        
                        let finalArtist = finalNarrationResponse.artist.isEmpty || finalNarrationResponse.artist == "未知艺术家" ? verified.artist : finalNarrationResponse.artist
                        let finalYear = finalNarrationResponse.year ?? verified.year
                        let finalStyle = finalNarrationResponse.style ?? verified.style
                        
                        // Merge sources
                        var allSources = finalNarrationResponse.sources
                        for source in verified.sources {
                            if !allSources.contains(source) {
                                allSources.append(source)
                            }
                        }
                        
                        finalNarrationResponse = NarrationResponse(
                            title: finalTitle, // Prioritize artwork title (from narration), cleaned
                            artist: finalArtist, // Prioritize artwork artist (from narration)
                            year: finalYear, // Use artwork year if available, else verified
                            style: finalStyle, // Use artwork style if available, else verified
                            summary: finalNarrationResponse.summary, // Keep artwork summary
                            narration: finalNarrationResponse.narration, // Keep artwork narration (most accurate)
                            artistIntroduction: finalNarrationResponse.artistIntroduction, // Keep artwork artist intro
                            sources: allSources, // Merge sources
                            confidence: finalNarrationResponse.confidence // Keep artwork confidence
                        )
                        print("✅ Using artwork info (from narration) as primary source")
                        print("✅ Final info - Title: '\(finalNarrationResponse.title)', Artist: '\(finalNarrationResponse.artist)', Year: '\(finalNarrationResponse.year ?? "null")', Style: '\(finalNarrationResponse.style ?? "null")'")
                    } else {
                        print("⚠️ Could not verify information from online sources")
                        print("✅ Using AI-generated information (from narration) as primary source")
                        // Keep AI-generated info as-is since verification failed
                        // The narration content is the source of truth
                    }
                } else {
                    // For medium/low confidence, still try to verify if possible
                    if finalNarrationResponse.title != "无法识别的作品" && !finalNarrationResponse.title.contains("印象派") && !finalNarrationResponse.title.contains("风格") {
                        print("🔍 Medium/low confidence, attempting verification...")
                        let candidate = RecognitionCandidate(
                            artworkName: finalNarrationResponse.title,
                            artist: finalNarrationResponse.artist != "未知艺术家" ? finalNarrationResponse.artist : nil,
                            confidence: finalNarrationResponse.confidence
                        )
                        
                        if let verified = await RetrievalService.shared.retrieveArtworkInfo(candidates: [candidate]) {
                            verifiedInfo = verified
                            print("✅ Found verified information, updating...")
                            finalNarrationResponse = NarrationResponse(
                                title: verified.title,
                                artist: verified.artist,
                                year: verified.year ?? finalNarrationResponse.year,
                                style: verified.style ?? finalNarrationResponse.style,
                                summary: finalNarrationResponse.summary,
                                narration: finalNarrationResponse.narration,
                                artistIntroduction: finalNarrationResponse.artistIntroduction,
                                sources: verified.sources,
                                confidence: min(finalNarrationResponse.confidence + 0.1, 1.0) // Slightly increase confidence if verified
                            )
                        }
                    }
                }
                
                // After verification, create final artwork info
                // CRITICAL: imageURL should ONLY be from museum API (reference image), NEVER user's photo
                // - verifiedInfo?.imageURL: Reference image from museum API (Met Museum, Art Institute, etc.)
                // - User's photo is stored separately in capturedImage and passed to PlaybackView as userImage
                // - Backend stores only museum reference images, NOT user photos
                // - PlaybackView always prioritizes userImage over artworkInfo.imageURL
                let finalArtworkInfo = finalNarrationResponse.toArtworkInfo(
                    imageURL: verifiedInfo?.imageURL, // Only museum API reference image, NOT user photo
                    recognized: finalNarrationResponse.confidenceLevel == .high
                )
                print("📸 User photo preserved in capturedImage (will be displayed in PlaybackView)")
                print("📸 Backend reference image (if available): \(verifiedInfo?.imageURL ?? "none")")
                
                // Save to backend cache with final verified information (only if not already cached)
                // Backend stores only reference image from museum API, NOT user's photo
                // CRITICAL: This method will fetch artist introduction from database if available
                if finalNarrationResponse.confidenceLevel == .high {
                    // Get cached narration (includes artist introduction from database if available)
                    // This method checks database first for artist introduction
                    let cachedNarration = await ArtworkCacheService.shared.getArtworkWithArtistIntroduction(
                        title: finalNarrationResponse.title,
                        artist: finalNarrationResponse.artist,
                        year: finalNarrationResponse.year,
                        narrationResponse: finalNarrationResponse,
                        artworkInfo: finalArtworkInfo // Contains only museum API reference image, NOT user photo
                    ) ?? finalNarrationResponse
                    
                    // CRITICAL: Always prefer cached narration if it has artist introduction from database
                    // This ensures we use database artist introduction instead of regenerating
                    let cachedHasIntro = cachedNarration.artistIntroduction != nil && 
                                        !cachedNarration.artistIntroduction!.isEmpty
                    let providedHasIntro = finalNarrationResponse.artistIntroduction != nil &&
                                          !finalNarrationResponse.artistIntroduction!.isEmpty
                    let introsDiffer = cachedNarration.artistIntroduction != finalNarrationResponse.artistIntroduction
                    
                    // Priority: Use cached if it has database introduction (even if same as provided)
                    if cachedHasIntro {
                        if introsDiffer {
                            print("✅ Using artist introduction from database (different from AI-generated)")
                            print("📝 Database: \(cachedNarration.artistIntroduction?.count ?? 0) chars")
                            print("📝 AI-generated: \(finalNarrationResponse.artistIntroduction?.count ?? 0) chars")
                        } else {
                            print("ℹ️ Using cached narration (artist introduction matches)")
                        }
                        finalNarrationResponse = cachedNarration
                    } else if cachedNarration.narration != finalNarrationResponse.narration {
                        print("✅ Using cached narration from backend (narration differs)")
                        finalNarrationResponse = cachedNarration
                    } else if providedHasIntro {
                        print("ℹ️ Using newly generated narration with AI artist introduction")
                        // Keep finalNarrationResponse as is (has AI-generated introduction)
                    } else {
                        print("ℹ️ Using newly generated narration (no artist introduction available)")
                    }
                    print("📸 User's photo will still be displayed (not backend reference image)")
                }
                
                // User's photo is already stored in capturedImage state variable
                // It will be passed to PlaybackView and always displayed (not overwritten by backend imageURL)
                // Backend only stores museum API reference image, NOT user's photo
                
                let elapsed = Date().timeIntervalSince(narrationStartTime)
                print("✅ Narration process completed in \(String(format: "%.2f", elapsed))s")
                print("📝 Title: \(finalNarrationResponse.title)")
                print("📝 Artist: \(finalNarrationResponse.artist)")
                print("📝 Confidence: \(finalNarrationResponse.confidence) - \(finalNarrationResponse.confidenceLevel)")
                print("📝 Narration length: \(finalNarrationResponse.narration.count) characters")
                
                // Save to history (include artist introduction and confidence)
                // User's photo is saved in history, NOT in backend
                let historyItem = HistoryItem(
                    artworkInfo: finalArtworkInfo,
                    narration: finalNarrationResponse.narration,
                    artistIntroduction: finalNarrationResponse.artistIntroduction,
                    narrationLanguage: ContentLanguage.zh,
                    confidence: finalNarrationResponse.confidence,
                    userPhotoData: image.jpegData(compressionQuality: 0.5)
                )
                HistoryService.shared.saveHistoryItem(historyItem)
                print("✅ History item saved: \(finalNarrationResponse.title) by \(finalNarrationResponse.artist)")
                
                // Update playback view with final data
                let totalElapsed = Date().timeIntervalSince(totalStartTime)
                print("⏱️ Total processing time: \(String(format: "%.2f", totalElapsed))s")
                
                await MainActor.run {
                    let sessionId = self.playbackData?.id ?? UUID()
                    // Update playback view with final data
                    // CRITICAL: User's photo (capturedImage) is preserved and will always be displayed
                    // Backend imageURL is only a reference from museum API, NOT user's photo
                    // PlaybackView prioritizes userImage over artworkInfo.imageURL
                    self.playbackData = PlaybackData(
                        id: sessionId,
                        artworkInfo: finalArtworkInfo,
                        narration: finalNarrationResponse.narration,
                        artistIntroduction: finalNarrationResponse.artistIntroduction ?? "",
                        narrationLanguage: ContentLanguage.zh,
                        userImage: capturedImage,
                        confidence: finalNarrationResponse.confidence
                    )
                    // capturedImage is already set and preserved - it contains user's photo
                    // It will be passed to PlaybackView as userImage parameter
                    print("✅ Updated playback view with final data")
                    print("✅ User photo preserved (capturedImage will be displayed, not backend reference image)")
                }
                
                // OPTIMIZATION: TTS pre-generation - start generating audio immediately after content is displayed
                // This allows audio to be ready when user clicks play button
                let fullText = finalNarrationResponse.narration
                if !fullText.isEmpty {
                    Task.detached(priority: .userInitiated) {
                        print("🎙️ Pre-generating TTS audio for narration (\(fullText.count) characters)...")
                        // Pre-generate audio (but don't play it yet)
                        // The speak() function will check for cached audio and use it if available
                        await TTSPlayback.shared.prepareAudio(
                            text: fullText,
                            language: ContentLanguage.ttsBCP47Tag(for: ContentLanguage.zh)
                        )
                        print("✅ TTS audio pre-generation completed")
                    }
                }
                
            } catch {
                let totalElapsed = Date().timeIntervalSince(totalStartTime)
                print("⏱️ Total processing time: \(String(format: "%.2f", totalElapsed))s")
                
                await MainActor.run {
                    // Provide user-friendly error messages
                    if let narrationError = error as? NarrationService.NarrationError {
                        switch narrationError {
                        case .apiKeyMissing:
                            errorMessage = String(localized: "error.openai_api_key_missing")
                        case .invalidURL:
                            errorMessage = String(localized: "error.network_config_invalid")
                        case .apiRequestFailed(let details):
                            if let details = details, details.contains("API key") || details.contains("401") {
                                errorMessage = String(localized: "error.openai_api_key_invalid")
                            } else {
                                let detailsText = details ?? String(localized: "error.check_network_retry")
                                errorMessage = String(format: String(localized: "error.narration_generation_failed_fmt"), detailsText)
                            }
                        case .invalidResponse:
                            errorMessage = String(localized: "error.invalid_response_retry")
                        case .imageProcessingFailed:
                            errorMessage = String(localized: "error.image_processing_failed_retry")
                        case .networkTimeout:
                            errorMessage = String(localized: "error.request_timed_out_retry")
                        case .networkUnavailable:
                            errorMessage = String(localized: "error.network_unavailable")
                        case .apiError(let code, let message):
                            if code == 401 {
                                errorMessage = String(localized: "error.openai_api_key_invalid_or_expired")
                            } else if code == 429 {
                                errorMessage = String(localized: "error.rate_limited")
                            } else if let message = message {
                                errorMessage = String(format: String(localized: "error.api_error_code_message_fmt"), code, message)
                            } else {
                                errorMessage = String(format: String(localized: "error.api_error_code_retry_fmt"), code)
                            }
                        }
                    } else {
                        let errorDesc = error.localizedDescription
                        if errorDesc.contains("correct format") || errorDesc.contains("JSON") {
                            errorMessage = String(localized: "error.data_format_retry")
                        } else if errorDesc.contains("timeout") || errorDesc.contains("timed out") {
                            errorMessage = String(localized: "error.request_timed_out_retry")
                        } else {
                            errorMessage = String(format: String(localized: "error.generic_fmt"), errorDesc)
                        }
                    }
                    
                    // CRITICAL: Update UI state on error
                    // Don't dismiss playback view on timeout - keep it showing with error message
                    // Only show error message, but keep the view visible
                    if let narrationError = error as? NarrationService.NarrationError {
                        // Keep playbackData visible - don't set to nil
                        // Error message will be shown in errorMessage state
                        print("⚠️ Error occurred but keeping playback view visible: \(narrationError)")
                    }
                    
                    isProcessing = false
                }
            }
        }
    }
}

#Preview {
    // Preview without camera access to avoid crashes
    ZStack {
        // Background: Dark gray to simulate the dark overlay
        Color.gray.opacity(0.3)
            .ignoresSafeArea()
        
        VStack(spacing: 40) {
            // App Title
            VStack(spacing: 8) {
                Text("app.name")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                Text("home.tagline")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.top, 60)
            
            Spacer()
            
            // Camera Button
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Color(hex: "1F1F1F"))
                
                Text("home.cta.capture")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(hex: "1F1F1F"))
            }
            .frame(width: 160, height: 160)
            .background(
                Circle()
                    .fill(Color.white)
            )
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            
            // Navigation Buttons - Tertiary style (white text, no background)
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("home.nav.history")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            }
            .padding(.top, 20)
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

