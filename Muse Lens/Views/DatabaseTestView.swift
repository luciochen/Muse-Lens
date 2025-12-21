//
//  DatabaseTestView.swift
//  Muse Lens
//
//  Database connection and cache testing view
//

import SwiftUI

struct DatabaseTestView: View {
    @State private var backendURL: String = ""
    @State private var backendKey: String = ""
    @State private var testResults: [TestResult] = []
    @State private var isTesting = false
    @State private var artworkCount: Int = 0
    @State private var artistCount: Int = 0
    
    var body: some View {
        NavigationView {
            List {
                // Configuration Section
                Section("后端配置") {
                    TextField("Backend URL", text: $backendURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                    
                    SecureField("Backend API Key", text: $backendKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
                    
                    Button("保存配置") {
                        saveConfiguration()
                    }
                    
                    if AppConfig.isBackendConfigured {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("后端已配置")
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("后端未配置")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // Test Section
                Section("测试功能") {
                    Button("运行完整QA测试") {
                        runQATests()
                    }
                    .disabled(isTesting || !AppConfig.isBackendConfigured)
                    .foregroundColor(.blue)
                    
                    Divider()
                    
                    Button("测试连接") {
                        testConnection()
                    }
                    .disabled(isTesting || !AppConfig.isBackendConfigured)
                    
                    Button("测试查询作品") {
                        testArtworkQuery()
                    }
                    .disabled(isTesting || !AppConfig.isBackendConfigured)
                    
                    Button("测试保存作品") {
                        testSaveArtwork()
                    }
                    .disabled(isTesting || !AppConfig.isBackendConfigured)
                    
                    Button("测试查询艺术家") {
                        testArtistQuery()
                    }
                    .disabled(isTesting || !AppConfig.isBackendConfigured)
                    
                    Button("获取统计信息") {
                        getStatistics()
                    }
                    .disabled(isTesting || !AppConfig.isBackendConfigured)
                    
                    if isTesting {
                        HStack {
                            ProgressView()
                            Text("测试中...")
                        }
                    }
                }
                
                // Statistics Section
                Section("统计信息") {
                    HStack {
                        Text("作品数量")
                        Spacer()
                        Text("\(artworkCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("艺术家数量")
                        Spacer()
                        Text("\(artistCount)")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Results Section
                Section("测试结果") {
                    ForEach(testResults) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.success ? .green : .red)
                                Text(result.testName)
                                    .font(.headline)
                            }
                            
                            if let message = result.message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let error = result.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("数据库测试")
            .onAppear {
                loadConfiguration()
                if AppConfig.isBackendConfigured {
                    getStatistics()
                }
            }
        }
    }
    
    private func saveConfiguration() {
        if !backendURL.isEmpty {
            AppConfig.setBackendAPIURL(backendURL)
        }
        if !backendKey.isEmpty {
            AppConfig.setBackendAPIKey(backendKey)
        }
        testResults.append(TestResult(
            testName: "配置保存",
            success: true,
            message: "配置已保存"
        ))
    }
    
    private func loadConfiguration() {
        backendURL = AppConfig.backendAPIURL ?? ""
        backendKey = AppConfig.backendAPIKey ?? ""
    }
    
    private func testConnection() {
        isTesting = true
        testResults.append(TestResult(
            testName: "连接测试",
            success: false,
            message: "测试中..."
        ))
        
        Task {
            let backendAPI = BackendAPIService.shared
            if backendAPI.isConfigured {
                // Try a simple query to test connection
                let identifier = ArtworkIdentifier.generate(
                    title: "测试作品",
                    artist: "测试艺术家"
                )
                
                do {
                    let _ = try await backendAPI.findArtwork(identifier: identifier)
                    await MainActor.run {
                        testResults[testResults.count - 1] = TestResult(
                            testName: "连接测试",
                            success: true,
                            message: "连接成功"
                        )
                        isTesting = false
                    }
                } catch {
                    await MainActor.run {
                        testResults[testResults.count - 1] = TestResult(
                            testName: "连接测试",
                            success: false,
                            message: "连接失败",
                            error: error.localizedDescription
                        )
                        isTesting = false
                    }
                }
            } else {
                await MainActor.run {
                    testResults[testResults.count - 1] = TestResult(
                        testName: "连接测试",
                        success: false,
                        message: "后端未配置"
                    )
                    isTesting = false
                }
            }
        }
    }
    
    private func testArtworkQuery() {
        isTesting = true
        testResults.append(TestResult(
            testName: "查询作品测试",
            success: false,
            message: "测试中..."
        ))
        
        Task {
            let identifier = ArtworkIdentifier.generate(
                title: "蒙娜丽莎",
                artist: "列奥纳多·达·芬奇"
            )
            
            do {
                if let artwork = try await BackendAPIService.shared.findArtwork(identifier: identifier) {
                    await MainActor.run {
                        testResults[testResults.count - 1] = TestResult(
                            testName: "查询作品测试",
                            success: true,
                            message: "找到作品: \(artwork.title) by \(artwork.artist)"
                        )
                        isTesting = false
                    }
                } else {
                    await MainActor.run {
                        testResults[testResults.count - 1] = TestResult(
                            testName: "查询作品测试",
                            success: true,
                            message: "未找到作品（这是正常的，如果数据库中还没有该作品）"
                        )
                        isTesting = false
                    }
                }
            } catch {
                await MainActor.run {
                    testResults[testResults.count - 1] = TestResult(
                        testName: "查询作品测试",
                        success: false,
                        message: "查询失败",
                        error: error.localizedDescription
                    )
                    isTesting = false
                }
            }
        }
    }
    
    private func testSaveArtwork() {
        isTesting = true
        testResults.append(TestResult(
            testName: "保存作品测试",
            success: false,
            message: "测试中..."
        ))
        
        Task {
            let testNarration = NarrationResponse(
                title: "测试作品",
                artist: "测试艺术家",
                year: "2024年",
                style: "测试风格",
                summary: "测试摘要",
                narration: "这是一个测试作品讲解内容，用于验证数据库保存功能。讲解内容应该足够长，以测试500-600字的讲解长度要求。",
                artistIntroduction: "这是一个测试艺术家的介绍，用于验证艺术家介绍缓存功能。介绍内容应该足够长，以测试300-400字的介绍长度要求。",
                sources: ["https://example.com"],
                confidence: 0.9
            )
            
            let identifier = ArtworkIdentifier.generate(
                title: testNarration.title,
                artist: testNarration.artist,
                year: testNarration.year
            )
            
            let backendArtwork = BackendArtwork.from(
                narrationResponse: testNarration,
                identifier: identifier
            )
            
            do {
                try await BackendAPIService.shared.saveArtwork(backendArtwork)
                await MainActor.run {
                    testResults[testResults.count - 1] = TestResult(
                        testName: "保存作品测试",
                        success: true,
                        message: "作品保存成功"
                    )
                    isTesting = false
                    getStatistics()
                }
            } catch {
                await MainActor.run {
                    testResults[testResults.count - 1] = TestResult(
                        testName: "保存作品测试",
                        success: false,
                        message: "保存失败",
                        error: error.localizedDescription
                    )
                    isTesting = false
                }
            }
        }
    }
    
    private func testArtistQuery() {
        isTesting = true
        testResults.append(TestResult(
            testName: "查询艺术家测试",
            success: false,
            message: "测试中..."
        ))
        
        Task {
            do {
                if let artist = try await BackendAPIService.shared.findArtistIntroduction(artist: "测试艺术家") {
                    await MainActor.run {
                        testResults[testResults.count - 1] = TestResult(
                            testName: "查询艺术家测试",
                            success: true,
                            message: "找到艺术家: \(artist.name)"
                        )
                        isTesting = false
                    }
                } else {
                    await MainActor.run {
                        testResults[testResults.count - 1] = TestResult(
                            testName: "查询艺术家测试",
                            success: true,
                            message: "未找到艺术家（这是正常的，如果数据库中还没有该艺术家）"
                        )
                        isTesting = false
                    }
                }
            } catch {
                await MainActor.run {
                    testResults[testResults.count - 1] = TestResult(
                        testName: "查询艺术家测试",
                        success: false,
                        message: "查询失败",
                        error: error.localizedDescription
                    )
                    isTesting = false
                }
            }
        }
    }
    
    private func getStatistics() {
        guard AppConfig.isBackendConfigured else {
            print("⚠️ Backend not configured, cannot get statistics")
            return
        }
        
        Task {
            isTesting = true
            await MainActor.run {
                artworkCount = 0
                artistCount = 0
            }
            
            do {
                // Get artwork count
                let artworkCountResult = try await queryCount(table: "artworks")
                await MainActor.run {
                    self.artworkCount = artworkCountResult
                    print("✅ Artwork count: \(artworkCountResult)")
                }
                
                // Get artist count
                let artistCountResult = try await queryCount(table: "artists")
                await MainActor.run {
                    self.artistCount = artistCountResult
                    print("✅ Artist count: \(artistCountResult)")
                }
            } catch {
                print("❌ Failed to get statistics: \(error.localizedDescription)")
                await MainActor.run {
                    testResults.append(TestResult(
                        testName: "获取统计信息",
                        success: false,
                        message: "获取失败",
                        error: error.localizedDescription
                    ))
                }
            }
            
            await MainActor.run {
                isTesting = false
            }
        }
    }
    
    private func queryCount(table: String) async throws -> Int {
        guard let baseURL = AppConfig.backendAPIURL,
              let apiKey = AppConfig.backendAPIKey else {
            throw NSError(domain: "DatabaseTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Backend not configured"])
        }
        
        // Query all records with only id field to get count
        // This is efficient as we only fetch the id field
        guard let url = URL(string: "\(baseURL)/rest/v1/\(table)?select=id") else {
            throw NSError(domain: "DatabaseTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10.0
        
        print("🔍 Querying count for table: \(table)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "DatabaseTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }
        
        print("📡 HTTP Status: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorData = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ HTTP Error \(httpResponse.statusCode): \(errorData)")
            throw NSError(domain: "DatabaseTest", code: 4, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorData)"])
        }
        
        // Try to get count from Content-Range header first (more efficient)
        if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
            print("📊 Content-Range header: \(contentRange)")
            // Parse "0-9/100" or "0-9/*" format
            let parts = contentRange.split(separator: "/")
            if parts.count == 2, let countStr = parts.last, countStr != "*", let count = Int(countStr) {
                print("✅ Got count from Content-Range: \(count)")
                return count
            }
        }
        
        // Fallback: Parse JSON array and count
        do {
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let count = jsonArray.count
                print("✅ Got count from JSON array: \(count)")
                return count
            } else if try JSONSerialization.jsonObject(with: data) is [String: Any] {
                // Single object, count is 1
                print("✅ Got single object, count: 1")
                return 1
            }
        } catch {
            print("⚠️ Failed to parse JSON: \(error)")
            // Try to get count from data size (rough estimate)
            if data.count > 0 {
                // If we got data but can't parse, assume at least 1 record
                print("⚠️ Using fallback: assuming at least 1 record")
                return 1
            }
        }
        
        print("ℹ️ No records found or empty response")
        return 0
    }
    
    private func runQATests() {
        isTesting = true
        testResults.removeAll()
        
        testResults.append(TestResult(
            testName: "QA测试",
            success: false,
            message: "正在运行QA测试..."
        ))
        
        Task {
            let qaResults = await DatabaseQAService.shared.runQATests()
            
            await MainActor.run {
                testResults.removeAll()
                
                for qaResult in qaResults {
                    var detailsMessage = qaResult.message
                    if let details = qaResult.details, !details.isEmpty {
                        detailsMessage += "\n" + details.joined(separator: "\n")
                    }
                    
                    testResults.append(TestResult(
                        testName: qaResult.testName,
                        success: qaResult.passed,
                        message: detailsMessage,
                        error: qaResult.error
                    ))
                }
                
                // Add summary
                let passedCount = qaResults.filter { $0.passed }.count
                let totalCount = qaResults.count
                testResults.append(TestResult(
                    testName: "QA测试总结",
                    success: passedCount == totalCount,
                    message: "通过: \(passedCount)/\(totalCount)"
                ))
                
                isTesting = false
                getStatistics()
            }
        }
    }
}

struct TestResult: Identifiable {
    let id = UUID()
    let testName: String
    let success: Bool
    let message: String?
    let error: String?
    
    init(testName: String, success: Bool, message: String? = nil, error: String? = nil) {
        self.testName = testName
        self.success = success
        self.message = message
        self.error = error
    }
}

#Preview {
    DatabaseTestView()
}

