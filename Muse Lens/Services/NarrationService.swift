//
//  NarrationService.swift
//  Muse Lens
//
//  Created by Lucio Chen on 2025-11-05.
//

import Foundation

/// Service for generating narration based on retrieved artwork information
class NarrationService {
    static let shared = NarrationService()
    
    private let apiKey: String? // Should be set from environment or config
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    private init() {
        // Load API key from AppConfig
        self.apiKey = AppConfig.openAIApiKey
    }
    
    /// Generate narration directly from image using ChatGPT API
    func generateNarrationFromImage(imageBase64: String) async throws -> NarrationResponse {
        // Verify API key is present first
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            print("❌ API key is missing or empty")
            throw NarrationError.apiKeyMissing
        }
        
        print("🔑 API key present: \(apiKey.prefix(7))...")
        
        // Build request messages - directly analyze image
        var messages: [[String: Any]] = [
            [
                "role": "system",
                "content": "你是一位专业的博物馆导游和艺术史专家。你拥有深厚的艺术史知识，能够识别著名艺术作品、艺术家及其创作背景。请用中文提供专业、深入、引人入胜的艺术品讲解。\n\n重要原则：\n1. **严禁编造**：如果无法确定作品信息，不要编造标题、艺术家或历史背景。\n2. **避免明显事实**：不要讲述过于明显或常识性的内容。\n3. **诚实描述**：如果识别不出具体作品，只描述你看到的视觉风格和特征，不要编造作品信息。\n4. **识别确定性评估**：根据你的识别把握程度，给出confidence值（0.0-1.0）。\n   - 高确定性（>=0.8）：能明确识别出具体作品和艺术家\n   - 中等确定性（0.5-0.8）：能识别风格但不确定具体作品\n   - 低确定性（<0.5）：无法识别作品或风格"
            ]
        ]
        
        // Build user message with image and prompt
        let userContent: [Any] = [
            [
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(imageBase64)"
                ]
            ],
            [
                "type": "text",
                "text": """
                作为一个专业的博物馆导游，请分析这个收藏品并根据识别确定性提供相应的讲解。请用中文生成讲解内容。
                
                **识别确定性评估**：
                请根据你的识别把握程度，给出confidence值（0.0-1.0）：
                - **高确定性（>=0.8）**：能明确识别出具体作品和艺术家（如《蒙娜丽莎》、达芬奇）
                - **中等确定性（0.5-0.8）**：能识别艺术风格但不确定具体作品（如印象派风格）
                - **低确定性（<0.5）**：无法识别作品或风格
                
                **根据确定性提供内容**：
                
                **1. 高确定性（confidence >= 0.8）- 识别成功**：
                   - 提供完整的作品讲解（300-400字）
                   - 包含：作品识别、背景故事（基于事实）、视觉分析、艺术价值
                   - 提供艺术家介绍（如果识别出艺术家）
                   - **标题必须100%准确，并使用中文**：只能使用作品的最常见、最准确的中文名称（如《蒙娜丽莎》、《星夜》、《向日葵》），必须是世界公认的标准中文名称。如果不确定标准中文名称，使用null或降低confidence
                   - **艺术家名称必须100%准确，并使用中文**：必须使用艺术家的完整、准确、标准中文姓名（如"列奥纳多·达·芬奇"、"文森特·梵高"、"克劳德·莫奈"），不要使用英文名，不要简写、不要错误拼写、不要使用别名。如果不确定艺术家姓名，使用"未知艺术家"并降低confidence
                   - **年代必须100%准确，并使用中文格式**：如果能确定创作年代，必须提供准确的年份或年代范围（如"1503-1519年"或"1889年"），格式要一致；如果不确定则为null，绝对不要猜测或使用模糊表述（如"大约"、"可能"、"约"等）。如果只有大概时间范围但不确切，使用null
                   - **风格必须准确，并使用中文**：如果能确定艺术风格或流派，使用标准中文名称（如"文艺复兴"、"印象派"、"后印象派"、"巴洛克"、"新古典主义"等），不要使用英文。如果不确定则为null。不要猜测风格
                   - **关键要求**：title, artist, year, style 这些字段的值必须与讲解内容（narration）中提到的信息完全一致。讲解内容中提到的作品名称、艺术家、年代、风格，必须与这些字段的值一致。如果对标题、艺术家、年代、风格中的任何一项不确定，必须降低confidence值。只有当你非常确定所有信息时才使用confidence >= 0.8
                
                **2. 中等确定性（0.5 <= confidence < 0.8）- 识别模糊**：
                   - 讲解内容开头明确说明："我们无法确定这幅作品的具体信息，但可以分析它的风格特征。"
                   - 简短描述艺术风格（100-200字）
                   - 分析视觉元素：构图、色彩、技法
                   - 说明风格特点和代表性
                   - 不要编造作品标题、艺术家或历史背景
                   - artistIntroduction必须为null
                
                **3. 低确定性（confidence < 0.5）- 无法识别**：
                   - narration字段提供友好的提示信息（50-100字）
                   - 说明无法识别，鼓励用户重试或扫描其他作品
                   - 不要编造任何作品信息
                   - artistIntroduction必须为null
                
                **重要要求**：
                - 严禁编造信息：无法确定时明确说明，不要编造
                - 避免明显事实：不要讲述过于明显的内容
                - 诚实评估：根据实际识别把握给出准确的confidence值
                
                请返回JSON格式：
                {
                    "title": "作品标题（高确定性：必须使用世界公认的标准中文作品名称，如《蒙娜丽莎》、《星夜》、《向日葵》等，必须是准确的标准中文名称，不要使用英文，不要编造、猜测或使用变体。如果不确定标准中文名称，宁愿降低confidence也不要用猜测的标题；中等确定性：描述性标题如'一幅印象派风格的作品'；低确定性：'无法识别的作品'）",
                    "artist": "艺术家姓名（高确定性：必须使用完整、准确、标准的中文艺术家姓名，如'列奥纳多·达·芬奇'、'文森特·梵高'、'克劳德·莫奈'等，必须是标准全名，不要使用英文名，不要简写、不要错误拼写、不要使用别名。如果不确定艺术家，使用'未知艺术家'并降低confidence；中等/低确定性：'未知艺术家'）",
                    "year": "创作年份（高确定性：如果能确定，必须提供准确年份，如'1503-1519年'或'1889年'，格式要一致；如果不确定则为null，绝对不要猜测或使用模糊表述（如'大约'、'可能'、'约'等）。如果只有大概时间范围但不确切，使用null；中等/低确定性：null）",
                    "style": "艺术风格或流派（高确定性：如果能确定，使用标准中文名称如'文艺复兴'、'印象派'、'后印象派'、'巴洛克'、'新古典主义'等，不要使用英文；如果不确定则为null，不要猜测风格；中等/低确定性：基于视觉分析，如无法确定则为null）",
                    "summary": "摘要（高确定性：作品核心信息；中等确定性：风格特征；低确定性：无法识别提示）",
                    "narration": "讲解内容（根据确定性：高确定性300-400字完整讲解；中等确定性100-200字风格描述，开头说明不确定；低确定性50-100字友好提示）。重要：将文本分成逻辑短段落，每段2-4句话，使用双换行符（\\n\\n）分隔段落，以提高可读性。**关键**：讲解内容中提到的作品名称、艺术家、年代、风格，必须与title、artist、year、style字段的值完全一致。",
                    "artistIntroduction": "艺术家介绍（仅在高确定性且识别出艺术家时提供200-300字，否则为null）。重要：将文本分成逻辑短段落，每段2-4句话，使用双换行符（\\n\\n）分隔段落。**关键**：艺术家介绍中提到的艺术家姓名必须与artist字段的值完全一致。",
                    "confidence": 0.85,
                    "sources": []
                }
                """
            ]
        ]
        
        messages.append([
            "role": "user",
            "content": userContent
        ])
        
        let responseFormat: [String: Any] = ["type": "json_object"]
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 2000, // Increased for more detailed narration with background story and artist introduction
            "temperature": 0.7, // Slightly higher for more engaging narration
            "response_format": responseFormat
        ]
        
        guard let url = URL(string: baseURL) else {
            throw NarrationError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30.0 // 30 second timeout for image analysis
        
        print("📡 Sending image analysis request...")
        let startTime = Date()
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsed = Date().timeIntervalSince(startTime)
            print("📡 Request completed in \(String(format: "%.2f", elapsed))s")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid HTTP response")
                throw NarrationError.apiRequestFailed("Invalid HTTP response")
            }
            
            print("📡 HTTP Status: \(httpResponse.statusCode)")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                print("❌ HTTP Error: \(httpResponse.statusCode)")
                var errorMessage: String?
                if let errorData = String(data: data, encoding: .utf8) {
                    print("📄 Error response: \(errorData.prefix(500))")
                    errorMessage = errorData
                    
                    // Try to parse OpenAI error format
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        errorMessage = message
                        print("📝 OpenAI error message: \(message)")
                    }
                }
                
                // Handle specific HTTP status codes
                switch httpResponse.statusCode {
                case 401:
                    throw NarrationError.apiError(401, "Invalid API key. Please check your OPENAI_API_KEY.")
                case 429:
                    throw NarrationError.apiError(429, "Rate limit exceeded. Please try again later.")
                case 500...599:
                    throw NarrationError.apiError(httpResponse.statusCode, "Server error. Please try again later.")
                default:
                    throw NarrationError.apiError(httpResponse.statusCode, errorMessage)
                }
            }
            
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = jsonResponse["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                print("❌ Invalid response structure")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 Response: \(jsonString.prefix(500))")
                }
                throw NarrationError.invalidResponse
            }
            
            print("📝 Received response content: \(content.count) characters")
            
            // Parse JSON from response
            var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Remove markdown code blocks if present
            jsonString = jsonString
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Extract JSON object
            if let firstBrace = jsonString.firstIndex(of: "{"),
               let lastBrace = jsonString.lastIndex(of: "}"),
               firstBrace < lastBrace {
                jsonString = String(jsonString[firstBrace...lastBrace])
            }
            
            guard let jsonData = jsonString.data(using: .utf8) else {
                print("❌ Failed to convert JSON string to data")
                print("📄 JSON string: \(jsonString)")
                throw NarrationError.invalidResponse
            }
            
            do {
                let narrationResponse = try JSONDecoder().decode(NarrationResponse.self, from: jsonData)
                
                // Validate narration is not empty
                if narrationResponse.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("⚠️ Narration is empty")
                    throw NarrationError.invalidResponse
                }
                
                print("✅ Narration parsed successfully")
                print("📝 Title: \(narrationResponse.title)")
                print("📝 Artist: \(narrationResponse.artist)")
                print("📝 Narration length: \(narrationResponse.narration.count) characters")
                return narrationResponse
            } catch let decodingError as DecodingError {
                print("❌ JSON decode error: \(decodingError)")
                print("📄 JSON string (first 500 chars): \(String(jsonString.prefix(500)))")
                
                // Try to extract manually
                if let jsonDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let narration = jsonDict["narration"] as? String, !narration.isEmpty {
                    print("⚠️ Using manually extracted narration")
                    return NarrationResponse(
                        title: jsonDict["title"] as? String ?? "未知作品",
                        artist: jsonDict["artist"] as? String ?? "未知艺术家",
                        year: jsonDict["year"] as? String,
                        style: jsonDict["style"] as? String,
                        summary: jsonDict["summary"] as? String ?? "",
                        narration: narration,
                        artistIntroduction: jsonDict["artistIntroduction"] as? String,
                        sources: jsonDict["sources"] as? [String] ?? [],
                        confidence: (jsonDict["confidence"] as? Double) ?? 0.3
                    )
                }
                
                throw NarrationError.invalidResponse
            } catch {
                print("❌ JSON decode error: \(error)")
                print("📄 JSON string: \(String(jsonString.prefix(500)))")
                throw NarrationError.invalidResponse
            }
        } catch let error as URLError {
            print("❌ URL Error: \(error.localizedDescription)")
            print("❌ Error code: \(error.code.rawValue)")
            
            switch error.code {
            case .timedOut:
                print("❌ Request timed out after 30 seconds")
                throw NarrationError.networkTimeout
            case .notConnectedToInternet, .networkConnectionLost:
                print("❌ Network connection unavailable")
                throw NarrationError.networkUnavailable
            default:
                print("❌ Network error: \(error.localizedDescription)")
                throw NarrationError.apiRequestFailed(error.localizedDescription)
            }
        } catch let narrationError as NarrationError {
            // Re-throw NarrationError as-is
            throw narrationError
        } catch {
            print("❌ Unexpected error: \(error)")
            print("❌ Error type: \(type(of: error))")
            throw NarrationError.apiRequestFailed(error.localizedDescription)
        }
    }
    
    /// Generate narration script based on artwork information (kept for backward compatibility)
    func generateNarration(artworkInfo: ArtworkInfo, imageBase64: String? = nil, additionalContext: String? = nil, isRetry: Bool = false) async throws -> NarrationResponse {
        guard let apiKey = apiKey else {
            throw NarrationError.apiKeyMissing
        }
        
        var context = """
        Title: \(artworkInfo.title)
        Artist: \(artworkInfo.artist)
        """
        
        if let year = artworkInfo.year {
            context += "\nYear: \(year)"
        }
        if let style = artworkInfo.style {
            context += "\nStyle: \(style)"
        }
        if let medium = artworkInfo.medium {
            context += "\nMedium: \(medium)"
        }
        if let museum = artworkInfo.museum {
            context += "\nMuseum: \(museum)"
        }
        
        if let additional = additionalContext {
            context += "\n\nAdditional Context: \(additional)"
        }
        
        context += "\n\nSources: \(artworkInfo.sources.joined(separator: ", "))"
        
        // Build request messages
        var messages: [[String: Any]] = [
            [
                "role": "system",
                "content": "You are a professional museum guide. You provide accurate, engaging, and educational narrations about artworks. Always use the EXACT artist name and artwork title provided in the context."
            ]
        ]
        
        // Build user message content
        var userContentArray: [Any] = []
        
        // Add image if available (for better description, especially for unrecognized artworks)
        if let imageBase64 = imageBase64 {
            print("🖼️ Adding image to narration request for AI analysis")
            userContentArray.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(imageBase64)"
                ]
            ])
        }
        
        // Build text prompt
        let prompt: String
        if artworkInfo.recognized && !artworkInfo.sources.isEmpty {
            // Recognized artwork with sources - use provided info, but also analyze image if available
            if imageBase64 != nil {
                prompt = """
                Analyze this artwork image and create a 1-2 min narration (250-350 words) in Chinese.
                
                CRITICAL: Use EXACT title "\(artworkInfo.title)" and artist "\(artworkInfo.artist)". Do NOT change them.
                
                Requirements:
                1. Describe what you see in the image (colors, composition, details, mood)
                2. Combine visual observations with provided facts
                3. Include: what it depicts, historical context, techniques, significance
                4. Conversational, engaging tone (250-350 words Chinese)
                
                Artwork: \(context)
                
                Return JSON:
                {
                    "title": "\(artworkInfo.title)",
                    "artist": "\(artworkInfo.artist)",
                    "year": "\(artworkInfo.year ?? "null")",
                    "style": "\(artworkInfo.style ?? "null")",
                    "summary": "2-3 sentence summary in Chinese",
                    "narration": "full narration in Chinese (250-350 words)",
                    "sources": \(artworkInfo.sources.isEmpty ? "[]" : "[\"" + artworkInfo.sources.joined(separator: "\", \"") + "\"]")
                }
                """
            } else {
                prompt = """
                Create a 1-2 min narration (250-350 words) in Chinese based on the artwork info.
                
                CRITICAL: Use EXACT title "\(artworkInfo.title)" and artist "\(artworkInfo.artist)". Do NOT change.
                
                Requirements:
                1. Base on provided facts - DO NOT fabricate
                2. Include: what it depicts, historical context, techniques, significance
                3. Conversational, engaging tone (250-350 words Chinese)
                
                Artwork: \(context)
                
                Return JSON:
                {
                    "title": "\(artworkInfo.title)",
                    "artist": "\(artworkInfo.artist)",
                    "year": "\(artworkInfo.year ?? "null")",
                    "style": "\(artworkInfo.style ?? "null")",
                    "summary": "2-3 sentence summary in Chinese",
                    "narration": "full narration in Chinese (250-350 words)",
                    "sources": \(artworkInfo.sources.isEmpty ? "[]" : "[\"" + artworkInfo.sources.joined(separator: "\", \"") + "\"]")
                }
                """
            }
        } else if artworkInfo.title == "这张图片" || artworkInfo.title.lowercased().contains("unknown") || !artworkInfo.recognized || isRetry {
            // Recognition failed or artwork not recognized - generate description based on image
            // Also use this path for retries to force AI-based description
            if imageBase64 != nil {
                let retryNote = isRetry ? "\n\nNOTE: This is a retry attempt. Please provide a detailed, unique description based on what you actually see in the image. Do NOT use generic placeholder text." : ""
                
                prompt = """
                Analyze this image carefully and create a unique, detailed 1-2 min narration (250-350 words) in Chinese describing what you see.
                
                CRITICAL: This must be a UNIQUE description based on THIS SPECIFIC IMAGE. Do NOT use generic placeholder text.
                
                Requirements:
                1. Look at the image and describe EXACTLY what you see: colors, composition, subjects, style, mood, lighting, brushstrokes, details
                2. If it appears to be an artwork: describe the specific subjects, scenes, objects, possible artistic style/movement, visible techniques, emotional impact
                3. If it's a photo: describe what is shown in detail - people, objects, setting, atmosphere
                4. Be SPECIFIC and UNIQUE - mention actual visual details from THIS image
                5. Warm, conversational tone
                6. 250-350 words in Chinese
                7. Make it interesting and informative based on what you actually observe
                \(retryNote)
                
                Info: \(context)
                
                Return JSON:
                {
                    "title": "\(artworkInfo.title)",
                    "artist": "\(artworkInfo.artist)",
                    "year": null,
                    "style": null,
                    "summary": "2-3 sentence summary in Chinese about what is visible in THIS specific image",
                    "narration": "full narration in Chinese (250-350 words) with SPECIFIC visual observations from THIS image - must be unique, not generic",
                    "sources": []
                }
                """
            } else {
                prompt = """
                Create a 1-2 minute audio narration (250-350 words) in Chinese about appreciating art when we don't know its exact identity.
                
                Focus on the value of visual observation and personal interpretation in art appreciation.
                
                Return a JSON object with this exact structure:
                {
                    "title": "这张图片",
                    "artist": "未知",
                    "year": null,
                    "style": null,
                    "summary": "2-3 sentence summary in Chinese",
                    "narration": "full narration text in Chinese (250-350 words)",
                    "sources": []
                }
                """
            }
        } else {
            prompt = """
            This artwork was not specifically identified, but it appears to be in the \(artworkInfo.style ?? "unknown") style.
            
            Create a 1-2 minute audio narration (250-350 words) in Chinese explaining this art style or movement.
            
            Requirements:
            1. Base content on verified information from Wikipedia or other reliable sources
            2. Explain the characteristics, origins, and notable artists of this style
            3. Write in a conversational, engaging tone
            4. Keep it accessible and interesting
            
            Style Information:
            \(context)
            
            Return a JSON object with this exact structure:
            {
                "title": "Art Style Name",
                "artist": "Various Artists",
                "year": null,
                "style": "style name",
                "summary": "2-3 sentence summary",
                "narration": "full narration text (250-350 words)",
                "sources": ["source URL 1"]
            }
            """
        }
        
        // Add text prompt to user content
        userContentArray.append([
            "type": "text",
            "text": prompt
        ])
        
        let userContent = userContentArray
        
        messages.append([
            "role": "user",
            "content": userContent
        ])
        
        let responseFormat: [String: Any] = ["type": "json_object"]
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 800, // Reduced for faster response
            "temperature": 0.6, // Slightly lower for more consistent, faster responses
            "response_format": responseFormat
        ]
        
        guard let url = URL(string: baseURL) else {
            throw NarrationError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 10.0 // 10 second timeout (optimized for speed)
        
        print("📡 Sending narration request...")
        let startTime = Date()
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsed = Date().timeIntervalSince(startTime)
            print("📡 Request completed in \(String(format: "%.2f", elapsed))s")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid HTTP response")
                throw NarrationError.apiRequestFailed("Invalid HTTP response")
            }
            
            print("📡 HTTP Status: \(httpResponse.statusCode)")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                print("❌ HTTP Error: \(httpResponse.statusCode)")
                var errorMessage: String?
                if let errorData = String(data: data, encoding: .utf8) {
                    print("📄 Error response: \(errorData.prefix(200))")
                    errorMessage = errorData
                }
                throw NarrationError.apiRequestFailed(errorMessage ?? "HTTP error \(httpResponse.statusCode)")
            }
        
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = jsonResponse["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                print("❌ Invalid response structure")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 Response: \(jsonString.prefix(500))")
                }
                throw NarrationError.invalidResponse
            }
            
            print("📝 Received response content: \(content.count) characters")
        
        // Parse JSON from response
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        jsonString = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Extract JSON object
        if let firstBrace = jsonString.firstIndex(of: "{"),
           let lastBrace = jsonString.lastIndex(of: "}"),
           firstBrace < lastBrace {
            jsonString = String(jsonString[firstBrace...lastBrace])
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ Failed to convert JSON string to data")
            print("📄 JSON string: \(jsonString)")
            throw NarrationError.invalidResponse
        }
        
            do {
                let narrationResponse = try JSONDecoder().decode(NarrationResponse.self, from: jsonData)
                
                // Validate narration is not empty
                if narrationResponse.narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("⚠️ Narration is empty, trying manual extraction")
                    throw NarrationError.invalidResponse
                }
                
                print("✅ Narration parsed successfully: \(narrationResponse.narration.prefix(50))...")
                print("📝 Full narration length: \(narrationResponse.narration.count) characters")
                return narrationResponse
            } catch let decodingError as DecodingError {
                print("❌ JSON decode error: \(decodingError)")
                print("📄 JSON string (first 500 chars): \(String(jsonString.prefix(500)))")
                
                // Try to extract at least the narration field manually
                if let jsonDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    print("⚠️ Attempting manual extraction from JSON dict")
                    if let narration = jsonDict["narration"] as? String, !narration.isEmpty {
                        print("✅ Using manually extracted narration")
                        return NarrationResponse(
                            title: jsonDict["title"] as? String ?? artworkInfo.title,
                            artist: jsonDict["artist"] as? String ?? artworkInfo.artist,
                            year: jsonDict["year"] as? String,
                            style: jsonDict["style"] as? String,
                            summary: jsonDict["summary"] as? String ?? "",
                            narration: narration,
                            artistIntroduction: jsonDict["artistIntroduction"] as? String,
                            sources: jsonDict["sources"] as? [String] ?? [],
                            confidence: (jsonDict["confidence"] as? Double) ?? 0.3
                        )
                    }
                }
                
                throw NarrationError.invalidResponse
            } catch {
                print("❌ JSON decode error: \(error)")
                print("📄 JSON string: \(String(jsonString.prefix(500)))")
                throw NarrationError.invalidResponse
            }
        } catch let error as URLError {
            print("❌ URL Error: \(error.localizedDescription)")
            print("❌ Error code: \(error.code.rawValue)")
            
            switch error.code {
            case .timedOut:
                print("❌ Request timed out after 30 seconds")
                throw NarrationError.networkTimeout
            case .notConnectedToInternet, .networkConnectionLost:
                print("❌ Network connection unavailable")
                throw NarrationError.networkUnavailable
            default:
                print("❌ Network error: \(error.localizedDescription)")
                throw NarrationError.apiRequestFailed(error.localizedDescription)
            }
        } catch let narrationError as NarrationError {
            // Re-throw NarrationError as-is
            throw narrationError
        } catch {
            print("❌ Unexpected error: \(error)")
            print("❌ Error type: \(type(of: error))")
            throw NarrationError.apiRequestFailed(error.localizedDescription)
        }
    }
    
    enum NarrationError: LocalizedError {
        case apiKeyMissing
        case invalidURL
        case apiRequestFailed(String?) // Include error details
        case invalidResponse
        case imageProcessingFailed
        case networkTimeout
        case networkUnavailable
        case apiError(Int, String?) // HTTP status code and error message
        
        var errorDescription: String? {
            switch self {
            case .apiKeyMissing:
                return "API key not configured"
            case .invalidURL:
                return "Invalid API URL"
            case .apiRequestFailed(let details):
                if let details = details, !details.isEmpty {
                    return "API request failed: \(details)"
                }
                return "Failed to generate narration. Please check your network connection."
            case .invalidResponse:
                return "Invalid response from narration service"
            case .imageProcessingFailed:
                return "Failed to process image"
            case .networkTimeout:
                return "Request timed out. Please check your network connection and try again."
            case .networkUnavailable:
                return "Network unavailable. Please check your internet connection."
            case .apiError(let code, let message):
                if let message = message, !message.isEmpty {
                    return "API error (\(code)): \(message)"
                }
                return "API error (\(code)). Please check your API key and try again."
            }
        }
    }
}

