# API Key 验证指南

## 功能概述

应用现在包含完整的 API key 验证和连接测试功能，确保 OpenAI TTS 能够正常工作。

## 验证功能

### 1. 自动验证（应用启动时）

应用启动时会自动验证 API key：
- 检查 API key 是否存在
- 测试 API key 格式（是否以 `sk-` 开头）
- 测试与 OpenAI API 的连接
- 在控制台输出详细结果

### 2. 手动验证

可以在代码中随时调用验证：

```swift
// 获取详细验证结果
let result = await TTSPlayback.shared.verifyAPIKey()
print(result.summary)

// 或使用简化的诊断方法
let diagnostics = await TTSPlayback.shared.testOpenAITTS()
print(diagnostics)
```

## 验证结果

### APIKeyVerificationResult 结构

```swift
struct APIKeyVerificationResult {
    var hasKey: Bool              // API key 是否存在
    var keyLength: Int            // API key 长度
    var keyPrefix: String         // API key 前缀（前10个字符）
    var keyStartsWithSK: Bool     // 是否以 'sk-' 开头
    var connectionTestStarted: Bool  // 是否开始连接测试
    var connectionSuccessful: Bool   // 连接是否成功
    var httpStatusCode: Int?      // HTTP 状态码
    var connectionError: String?  // 错误信息
    
    var isValid: Bool             // 综合验证结果
    var summary: String            // 摘要信息
}
```

## 使用示例

### 示例 1: 在应用启动时验证

```swift
// 在 App 的 init() 中
init() {
    Task {
        let result = await TTSPlayback.shared.verifyAPIKey()
        if !result.isValid {
            // 显示警告或提示用户配置 API key
        }
    }
}
```

### 示例 2: 在设置页面验证

```swift
// 在设置页面添加验证按钮
Button("验证 API Key") {
    Task {
        let result = await TTSPlayback.shared.verifyAPIKey()
        // 显示结果给用户
        showAlert(result.summary)
    }
}
```

### 示例 3: 在 TTS 使用前验证

```swift
// 在使用 TTS 前验证
func playNarration(_ text: String) {
    Task {
        let result = await TTSPlayback.shared.verifyAPIKey()
        if result.isValid {
            TTSPlayback.shared.speak(text: text)
        } else {
            // 显示错误提示
            showError("API key 未配置或无效")
        }
    }
}
```

## 验证流程

```
1. 检查 API key 是否存在
   ├─ 检查 AppConfig.openAIApiKey
   ├─ 检查环境变量 OPENAI_API_KEY
   └─ 检查 UserDefaults OPENAI_API_KEY

2. 验证 API key 格式
   └─ 检查是否以 'sk-' 开头

3. 测试 API 连接
   ├─ 发送测试请求到 OpenAI TTS API
   ├─ 使用 gpt-4o-mini-tts 模型
   └─ 检查响应状态码

4. 返回验证结果
   └─ 包含所有验证信息
```

## 控制台输出示例

### 成功情况

```
============================================================
🔍 Starting API Key Verification...
============================================================
✅ API Key found
   - Length: 51 characters
   - Prefix: sk-proj-xxx...
   - Starts with 'sk-': true
🔄 Testing API connectivity...
📡 Sending test request to OpenAI TTS API...
📡 Response received in 1.23s
📡 HTTP Status: 200
✅ Received audio data (at least 100 bytes)
✅✅✅ API connection test PASSED!
✅ HTTP Status: 200
✅ OpenAI TTS API is accessible and working
============================================================
🔍 API Key Verification Complete
============================================================
```

### 失败情况

```
============================================================
🔍 Starting API Key Verification...
============================================================
❌ API Key not found
❌ Checking all sources:
   - AppConfig.openAIApiKey: ❌ not found
   - Environment OPENAI_API_KEY: ❌ not found
   - UserDefaults OPENAI_API_KEY: ❌ not found
============================================================
🔍 API Key Verification Complete
============================================================
```

### API Key 无效

```
============================================================
🔍 Starting API Key Verification...
============================================================
✅ API Key found
   - Length: 51 characters
   - Prefix: sk-proj-xxx...
   - Starts with 'sk-': true
🔄 Testing API connectivity...
📡 Sending test request to OpenAI TTS API...
📡 Response received in 0.45s
📡 HTTP Status: 401
❌ API connection test FAILED
❌ HTTP Status: 401
❌ Error: Invalid API key
============================================================
🔍 API Key Verification Complete
============================================================
```

## 错误处理

### 常见错误

1. **API Key 未找到**
   - 原因：未配置 OPENAI_API_KEY
   - 解决：在 Xcode Scheme 中设置环境变量

2. **API Key 无效 (401)**
   - 原因：API key 错误或已过期
   - 解决：检查 API key 是否正确

3. **网络连接失败**
   - 原因：无网络连接或网络问题
   - 解决：检查网络连接

4. **请求超时**
   - 原因：网络延迟或 OpenAI API 响应慢
   - 解决：检查网络连接，稍后重试

5. **模型不可用 (400)**
   - 原因：tts-1-hd 可能不可用或请求参数错误
   - 解决：检查 OpenAI API 状态和请求参数

## 配置 API Key

### 方法 1: 环境变量（推荐）

在 Xcode Scheme 中设置：
1. Product → Scheme → Edit Scheme
2. Run → Arguments → Environment Variables
3. 添加：`OPENAI_API_KEY` = `your-api-key-here`

### 方法 2: UserDefaults（开发测试）

```swift
AppConfig.setAPIKey("your-api-key-here")
```

### 方法 3: 环境变量（终端）

```bash
export OPENAI_API_KEY=your-api-key-here
```

## 最佳实践

1. **应用启动时验证**：在 `App.init()` 中自动验证
2. **设置页面验证**：提供手动验证按钮
3. **使用前验证**：在关键功能使用前验证
4. **错误提示**：向用户显示清晰的错误信息
5. **定期验证**：定期检查 API key 状态

## 注意事项

- 验证是异步操作，不会阻塞 UI
- 验证会发送一个测试请求到 OpenAI API
- 验证结果会缓存在 `APIKeyVerificationResult` 中
- 建议在应用启动时验证一次，避免频繁验证

