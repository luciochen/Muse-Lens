//
//  DatabaseQAService.swift
//  Muse Lens
//
//  QA testing service for database verification
//

import Foundation

/// QA Test Result
struct QATestResult {
    let testName: String
    let passed: Bool
    let message: String
    let details: [String]?
    let error: String?
    
    init(testName: String, passed: Bool, message: String, details: [String]? = nil, error: String? = nil) {
        self.testName = testName
        self.passed = passed
        self.message = message
        self.details = details
        self.error = error
    }
}

/// Database QA Testing Service
class DatabaseQAService {
    static let shared = DatabaseQAService()
    private let backendAPI = BackendAPIService.shared
    
    private init() {}
    
    /// Run comprehensive QA tests on the database
    func runQATests() async -> [QATestResult] {
        var results: [QATestResult] = []
        
        print("🧪 Starting Database QA Tests...")
        
        // Test 1: Backend Configuration
        results.append(await testBackendConfiguration())
        
        // Test 2: Database Connection
        results.append(await testDatabaseConnection())
        
        // Test 3: Verify Artwork Data Structure
        results.append(await testArtworkDataStructure())
        
        // Test 4: Verify Narration Content
        results.append(await testNarrationContent())
        
        // Test 5: Verify Artist Introduction Content
        results.append(await testArtistIntroductionContent())
        
        // Test 6: Data Statistics
        results.append(await testDataStatistics())
        
        // Test 7: Sample Artwork Verification
        results.append(await testSampleArtworkVerification())
        
        // Test 8: Content Quality Checks
        results.append(await testContentQuality())
        
        print("✅ QA Tests Completed: \(results.filter { $0.passed }.count)/\(results.count) passed")
        
        return results
    }
    
    // MARK: - Individual Test Methods
    
    private func testBackendConfiguration() async -> QATestResult {
        let isConfigured = backendAPI.isConfigured
        let url = AppConfig.backendAPIURL ?? "Not configured"
        let hasKey = AppConfig.backendAPIKey != nil
        
        if isConfigured {
            return QATestResult(
                testName: "后端配置检查",
                passed: true,
                message: "后端已正确配置",
                details: [
                    "URL: \(url)",
                    "API Key: \(hasKey ? "已配置" : "未配置")"
                ]
            )
        } else {
            return QATestResult(
                testName: "后端配置检查",
                passed: false,
                message: "后端未配置",
                details: [
                    "请设置 BACKEND_API_URL 和 BACKEND_API_KEY"
                ]
            )
        }
    }
    
    private func testDatabaseConnection() async -> QATestResult {
        guard backendAPI.isConfigured else {
            return QATestResult(
                testName: "数据库连接测试",
                passed: false,
                message: "跳过测试（后端未配置）"
            )
        }
        
        do {
            // Try a simple query to test connection
            let identifier = ArtworkIdentifier.generate(
                title: "测试连接",
                artist: "测试"
            )
            let _ = try await backendAPI.findArtwork(identifier: identifier)
            
            return QATestResult(
                testName: "数据库连接测试",
                passed: true,
                message: "数据库连接成功"
            )
        } catch {
            return QATestResult(
                testName: "数据库连接测试",
                passed: false,
                message: "数据库连接失败",
                error: error.localizedDescription
            )
        }
    }
    
    private func testArtworkDataStructure() async -> QATestResult {
        guard backendAPI.isConfigured else {
            return QATestResult(
                testName: "作品数据结构验证",
                passed: false,
                message: "跳过测试（后端未配置）"
            )
        }
        
        // Try to find a known artwork or create a test one
        let testTitle = "蒙娜丽莎"
        let testArtist = "列奥纳多·达·芬奇"
        let identifier = ArtworkIdentifier.generate(
            title: testTitle,
            artist: testArtist
        )
        
        do {
            if let artwork = try await backendAPI.findArtwork(identifier: identifier) {
                var details: [String] = []
                details.append("标题: \(artwork.title)")
                details.append("艺术家: \(artwork.artist)")
                details.append("年份: \(artwork.year ?? "N/A")")
                details.append("风格: \(artwork.style ?? "N/A")")
                details.append("讲解长度: \(artwork.narration.count) 字符")
                // Get artist introduction from artists table
                var artistIntroLength = 0
                if let backendArtist = try? await backendAPI.findArtistIntroduction(artist: artwork.artist) {
                    artistIntroLength = backendArtist.artistIntroduction?.count ?? 0
                }
                details.append("艺术家介绍: \(artistIntroLength > 0 ? "\(artistIntroLength) 字符" : "无")")
                details.append("置信度: \(artwork.confidence)")
                details.append("已识别: \(artwork.recognized ? "是" : "否")")
                
                // Verify required fields
                var issues: [String] = []
                if artwork.narration.isEmpty {
                    issues.append("讲解内容为空")
                }
                if artwork.title.isEmpty {
                    issues.append("标题为空")
                }
                if artwork.artist.isEmpty {
                    issues.append("艺术家为空")
                }
                
                let passed = issues.isEmpty
                return QATestResult(
                    testName: "作品数据结构验证",
                    passed: passed,
                    message: passed ? "数据结构正确" : "发现数据问题",
                    details: details,
                    error: issues.isEmpty ? nil : issues.joined(separator: ", ")
                )
            } else {
                return QATestResult(
                    testName: "作品数据结构验证",
                    passed: true,
                    message: "未找到测试作品（这是正常的）",
                    details: ["数据库中可能还没有该作品"]
                )
            }
        } catch {
            return QATestResult(
                testName: "作品数据结构验证",
                passed: false,
                message: "查询失败",
                error: error.localizedDescription
            )
        }
    }
    
    private func testNarrationContent() async -> QATestResult {
        guard backendAPI.isConfigured else {
            return QATestResult(
                testName: "讲解内容验证",
                passed: false,
                message: "跳过测试（后端未配置）"
            )
        }
        
        // Search for artworks with narration
        var artworksWithNarration: [BackendArtwork] = []
        var totalArtworks = 0
        
        // Try to find some sample artworks
        let testArtworks = [
            ("蒙娜丽莎", "列奥纳多·达·芬奇"),
            ("星夜", "文森特·梵高"),
            ("向日葵", "文森特·梵高"),
            ("睡莲", "克劳德·莫奈")
        ]
        
        for (title, artist) in testArtworks {
            let identifier = ArtworkIdentifier.generate(
                title: title,
                artist: artist
            )
            
            do {
                if let artwork = try await backendAPI.findArtwork(identifier: identifier) {
                    totalArtworks += 1
                    if !artwork.narration.isEmpty {
                        artworksWithNarration.append(artwork)
                    }
                }
            } catch {
                // Continue with next artwork
            }
        }
        
        var details: [String] = []
        details.append("检查的作品数: \(testArtworks.count)")
        details.append("找到的作品数: \(totalArtworks)")
        details.append("有讲解的作品数: \(artworksWithNarration.count)")
        
        if !artworksWithNarration.isEmpty {
            for artwork in artworksWithNarration.prefix(3) {
                let narrationLength = artwork.narration.count
                // 500-600 words in Chinese ≈ 500-600 characters (each word is typically 1-2 characters)
                let expectedMinLength = 500
                let hasGoodLength = narrationLength >= expectedMinLength
                
                details.append("  - \(artwork.title): \(narrationLength) 字符 (\(hasGoodLength ? "✓ 长度符合" : "⚠️ 长度不足，期望≥\(expectedMinLength)字符"))")
            }
        }
        
        let passed = !artworksWithNarration.isEmpty
        return QATestResult(
            testName: "讲解内容验证",
            passed: passed,
            message: passed ? "找到 \(artworksWithNarration.count) 个有讲解的作品" : "未找到有讲解的作品",
            details: details
        )
    }
    
    private func testArtistIntroductionContent() async -> QATestResult {
        guard backendAPI.isConfigured else {
            return QATestResult(
                testName: "艺术家介绍验证",
                passed: false,
                message: "跳过测试（后端未配置）"
            )
        }
        
        // Test known artists
        let testArtists = [
            "列奥纳多·达·芬奇",
            "文森特·梵高",
            "克劳德·莫奈",
            "巴勃罗·毕加索"
        ]
        
        var artistsWithIntroduction: [BackendArtist] = []
        var details: [String] = []
        
        for artistName in testArtists {
            do {
                if let artist = try await backendAPI.findArtistIntroduction(artist: artistName) {
                    if let artistIntro = artist.artistIntroduction, !artistIntro.isEmpty {
                        artistsWithIntroduction.append(artist)
                        let bioLength = artistIntro.count
                        // 300-400 words in Chinese ≈ 300-400 characters
                        let expectedMinLength = 300
                        let hasGoodLength = bioLength >= expectedMinLength
                        
                        details.append("  - \(artist.name): \(bioLength) 字符 (\(hasGoodLength ? "✓ 长度符合" : "⚠️ 长度不足，期望≥\(expectedMinLength)字符"))")
                    }
                }
            } catch {
                // Continue with next artist
            }
        }
        
        details.insert("检查的艺术家数: \(testArtists.count)", at: 0)
        details.insert("有介绍的艺术家数: \(artistsWithIntroduction.count)", at: 1)
        
        let passed = !artistsWithIntroduction.isEmpty
        return QATestResult(
            testName: "艺术家介绍验证",
            passed: passed,
            message: passed ? "找到 \(artistsWithIntroduction.count) 个有介绍的艺术家" : "未找到有介绍的艺术家",
            details: details
        )
    }
    
    private func testDataStatistics() async -> QATestResult {
        guard backendAPI.isConfigured else {
            return QATestResult(
                testName: "数据统计",
                passed: false,
                message: "跳过测试（后端未配置）"
            )
        }
        
        // Try to find multiple artworks to estimate statistics
        var foundArtworks = 0
        var foundArtists = 0
        var totalNarrationLength = 0
        var artworksWithNarration = 0
        
        let testArtworks = [
            ("蒙娜丽莎", "列奥纳多·达·芬奇"),
            ("星夜", "文森特·梵高"),
            ("向日葵", "文森特·梵高"),
            ("睡莲", "克劳德·莫奈"),
            ("记忆的永恒", "萨尔瓦多·达利"),
            ("呐喊", "爱德华·蒙克")
        ]
        
        var foundArtistNames = Set<String>()
        
        for (title, artist) in testArtworks {
            let identifier = ArtworkIdentifier.generate(
                title: title,
                artist: artist
            )
            
            do {
                if let artwork = try await backendAPI.findArtwork(identifier: identifier) {
                    foundArtworks += 1
                    if !artwork.narration.isEmpty {
                        artworksWithNarration += 1
                        totalNarrationLength += artwork.narration.count
                    }
                    if !artwork.artist.isEmpty {
                        foundArtistNames.insert(artwork.artist)
                    }
                }
            } catch {
                // Continue
            }
        }
        
        // Check artists
        for artistName in foundArtistNames {
            do {
                if let _ = try await backendAPI.findArtistIntroduction(artist: artistName) {
                    foundArtists += 1
                }
            } catch {
                // Continue
            }
        }
        
        var details: [String] = []
        details.append("检查的测试作品数: \(testArtworks.count)")
        details.append("找到的作品数: \(foundArtworks)")
        details.append("有讲解的作品数: \(artworksWithNarration)")
        if artworksWithNarration > 0 {
            let avgLength = totalNarrationLength / artworksWithNarration
            details.append("平均讲解长度: \(avgLength) 字符")
        }
        details.append("找到的艺术家数: \(foundArtists)")
        
        return QATestResult(
            testName: "数据统计",
            passed: foundArtworks > 0,
            message: "找到 \(foundArtworks) 个作品，\(foundArtists) 个艺术家",
            details: details
        )
    }
    
    private func testSampleArtworkVerification() async -> QATestResult {
        guard backendAPI.isConfigured else {
            return QATestResult(
                testName: "示例作品验证",
                passed: false,
                message: "跳过测试（后端未配置）"
            )
        }
        
        // Create and save a test artwork
        let testNarration = NarrationResponse(
            title: "QA测试作品",
            artist: "QA测试艺术家",
            year: "2024年",
            style: "测试风格",
            summary: "这是一个QA测试作品的摘要",
            narration: """
            这是一个QA测试作品的详细讲解内容。讲解内容应该足够长，以验证数据库能够正确存储500-600字的讲解内容。
            
            讲解内容应该包含多个段落，每个段落2-4句话，使用双换行符分隔。这样可以测试数据库是否正确存储了格式化的文本内容。
            
            这个测试作品用于验证：
            1. 讲解内容是否正确保存到数据库
            2. 讲解内容的长度是否符合要求（500-600字）
            3. 讲解内容的格式是否正确
            4. 数据库查询功能是否正常
            
            通过这个测试，我们可以确保艺术指南内容已经正确上传到数据库中，并且可以被正确检索和使用。
            """,
            artistIntroduction: """
            这是一个QA测试艺术家的详细介绍。介绍内容应该足够长，以验证数据库能够正确存储300-400字的艺术家介绍内容。
            
            艺术家介绍应该包含多个段落，每个段落2-4句话，使用双换行符分隔。这样可以测试数据库是否正确存储了格式化的文本内容。
            
            这个测试艺术家用于验证：
            1. 艺术家介绍是否正确保存到数据库
            2. 艺术家介绍的长度是否符合要求（300-400字）
            3. 艺术家介绍的格式是否正确
            4. 数据库查询功能是否正常
            """,
            sources: ["https://qa-test.example.com"],
            confidence: 0.95
        )
        
        let identifier = ArtworkIdentifier.generate(
            title: testNarration.title,
            artist: testNarration.artist,
            year: testNarration.year
        )
        
        do {
            // Try to save
            let backendArtwork = BackendArtwork.from(
                narrationResponse: testNarration,
                identifier: identifier
            )
            
            try await backendAPI.saveArtwork(backendArtwork)
            
            // Verify it was saved by querying
            if let savedArtwork = try await backendAPI.findArtwork(identifier: identifier) {
                var details: [String] = []
                details.append("作品已保存并验证")
                details.append("标题: \(savedArtwork.title)")
                details.append("艺术家: \(savedArtwork.artist)")
                details.append("讲解长度: \(savedArtwork.narration.count) 字符")
                // Get artist introduction from artists table
                var artistIntroLength = 0
                if let backendArtist = try? await backendAPI.findArtistIntroduction(artist: savedArtwork.artist) {
                    artistIntroLength = backendArtist.artistIntroduction?.count ?? 0
                }
                details.append("艺术家介绍长度: \(artistIntroLength) 字符")
                
                let narrationOK = savedArtwork.narration.count > 500
                let introOK = artistIntroLength > 300
                
                return QATestResult(
                    testName: "示例作品验证",
                    passed: narrationOK && introOK,
                    message: "测试作品保存成功",
                    details: details
                )
            } else {
                return QATestResult(
                    testName: "示例作品验证",
                    passed: false,
                    message: "作品保存后无法查询到",
                    error: "数据可能未正确保存"
                )
            }
        } catch {
            return QATestResult(
                testName: "示例作品验证",
                passed: false,
                message: "保存测试作品失败",
                error: error.localizedDescription
            )
        }
    }
    
    private func testContentQuality() async -> QATestResult {
        guard backendAPI.isConfigured else {
            return QATestResult(
                testName: "内容质量检查",
                passed: false,
                message: "跳过测试（后端未配置）"
            )
        }
        
        var details: [String] = []
        var issues: [String] = []
        
        // Check sample artworks for quality
        let testArtworks = [
            ("蒙娜丽莎", "列奥纳多·达·芬奇"),
            ("星夜", "文森特·梵高")
        ]
        
        for (title, artist) in testArtworks {
            let identifier = ArtworkIdentifier.generate(
                title: title,
                artist: artist
            )
            
            do {
                if let artwork = try await backendAPI.findArtwork(identifier: identifier) {
                    // Check narration quality
                    if artwork.narration.count < 500 {
                        issues.append("\(title) 的讲解内容过短 (\(artwork.narration.count) 字符)")
                    } else {
                        details.append("✓ \(title) 讲解内容长度符合要求 (\(artwork.narration.count) 字符)")
                    }
                    
                    // Check artist introduction quality (from artists table)
                    if let backendArtist = try? await backendAPI.findArtistIntroduction(artist: artist),
                       let intro = backendArtist.artistIntroduction, !intro.isEmpty {
                        if intro.count < 300 {
                            issues.append("\(artist) 的介绍内容过短 (\(intro.count) 字符)")
                        } else {
                            details.append("✓ \(artist) 介绍内容长度符合要求 (\(intro.count) 字符)")
                        }
                    } else {
                        details.append("⚠️ \(artist) 没有介绍内容")
                    }
                }
            } catch {
                // Continue
            }
        }
        
        if details.isEmpty {
            details.append("未找到测试作品进行质量检查")
        }
        
        let passed = issues.isEmpty
        return QATestResult(
            testName: "内容质量检查",
            passed: passed,
            message: passed ? "内容质量符合要求" : "发现 \(issues.count) 个质量问题",
            details: details,
            error: issues.isEmpty ? nil : issues.joined(separator: "; ")
        )
    }
}

