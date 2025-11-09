# OpenAI TTS 测试指南

## 已完成的改进

### 1. 强制使用 OpenAI TTS
- ✅ 添加了 `forceOpenAITTS = true` 标志
- ✅ 强制优先使用 OpenAI TTS，只在失败时回退到本地 TTS

### 2. 改进的 API Key 检查
- ✅ 从多个来源检查 API key（AppConfig、环境变量、UserDefaults）
- ✅ 详细的日志输出，显示 API key 的检查结果

### 3. 详细的错误处理
- ✅ 详细的错误日志
- ✅ 具体的错误信息（401、429、400 等）
- ✅ 网络错误的详细诊断

### 4. 测试方法
- ✅ 添加了 `testOpenAITTS()` 方法用于诊断

## 如何测试

### 步骤 1: 配置 API Key

#### 方法 1: 环境变量（推荐）
1. 在 Xcode 中：Product → Scheme → Edit Scheme
2. 选择 "Run" → "Arguments" → "Environment Variables"
3. 添加：
   - Name: `OPENAI_API_KEY`
   - Value: `你的API密钥`

#### 方法 2: UserDefaults（开发测试）
在代码中临时添加（仅用于测试）：
```swift
// 在 App 启动时调用
AppConfig.setAPIKey("sk-your-api-key-here")
```

#### 方法 3: 直接在 AppConfig.swift 中设置（不推荐，仅测试）
```swift
// 在 AppConfig.swift 中临时取消注释
return "sk-your-api-key-here"
```

### 步骤 2: 运行应用并查看控制台

1. 运行应用
2. 拍摄一张艺术作品照片
3. 等待识别完成
4. 查看 Xcode 控制台输出

### 步骤 3: 查看关键日志

#### 成功使用 OpenAI TTS 的标志：
```
============================================================
🎙️ TTS speak() called
🎙️ API key available: YES (prefix: sk-proj-...)
✅✅✅ FORCING OpenAI TTS (tts-1-hd) ✅✅✅
🚀 Starting OpenAI TTS generation...
🔑 Using OpenAI API key: sk-proj-...
📡 Sending OpenAI TTS API request...
📡 HTTP Status: 200
✅ OpenAI TTS (tts-1-hd) request successful!
✅✅✅ Started streaming playback after X.XXs
✅✅✅ OpenAI TTS SUCCESS! Natural voice is now playing!
```

#### API Key 未配置的标志：
```
🎙️ API key available: NO ❌
🎙️ Checking API key sources:
   - AppConfig.openAIApiKey: not found
   - Environment OPENAI_API_KEY: not found
   - UserDefaults OPENAI_API_KEY: not found
❌❌❌ CRITICAL: OpenAI API key not available or empty!
❌ TTS will fallback to local TTS (robotic voice)
```

#### API Key 无效的标志：
```
❌❌❌ OpenAI TTS API error: HTTP 401
❌ Authentication failed - check your API key is valid
❌ Make sure API key starts with 'sk-' and has TTS access
```

### 步骤 4: 使用测试方法（可选）

在代码中调用测试方法：
```swift
Task {
    let result = await TTSPlayback.shared.testOpenAITTS()
    print(result)
}
```

## 常见问题排查

### 问题 1: API Key 未找到
**症状**: 控制台显示 "API key available: NO"

**解决方案**:
1. 检查环境变量是否正确配置
2. 确保 API key 格式正确（应该以 `sk-` 开头）
3. 尝试使用 UserDefaults 方法

### 问题 2: API Key 无效
**症状**: 控制台显示 "HTTP 401" 错误

**解决方案**:
1. 检查 API key 是否正确
2. 确保 API key 有 TTS 访问权限
3. 检查 API key 是否过期

### 问题 3: 网络错误
**症状**: 控制台显示网络连接错误

**解决方案**:
1. 检查网络连接
2. 检查是否可以使用 OpenAI API
3. 检查防火墙设置

### 问题 4: 仍然使用本地 TTS
**症状**: 语音仍然生硬

**可能原因**:
1. API key 未配置
2. API 请求失败
3. 网络问题

**检查方法**:
- 查看控制台日志
- 查找 `❌` 错误标记
- 使用测试方法诊断

## 验证 OpenAI TTS 是否工作

### 方法 1: 听语音质量
- ✅ OpenAI TTS: 自然、流畅、有情感
- ❌ 本地 TTS: 生硬、机械、无情感

### 方法 2: 查看控制台日志
- ✅ 看到 "✅✅✅ OpenAI TTS SUCCESS!"
- ❌ 看到 "📢 Using local TTS"

### 方法 3: 检查播放时间
- OpenAI TTS 通常需要 1-3 秒开始播放（流式传输）
- 本地 TTS 几乎立即开始播放

## 下一步

如果 OpenAI TTS 仍然没有工作：

1. **检查控制台日志** - 查看具体的错误信息
2. **验证 API Key** - 确保 API key 正确配置
3. **测试网络连接** - 确保可以访问 OpenAI API
4. **使用测试方法** - 调用 `testOpenAITTS()` 进行诊断

## 技术支持

如果问题仍然存在，请提供：
1. 控制台完整日志
2. API key 配置方法
3. 错误信息详情

