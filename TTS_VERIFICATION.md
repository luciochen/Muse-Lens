# TTS Playback 验证指南

## 确保使用 OpenAI TTS

### 当前配置

1. **强制使用 OpenAI TTS**：
   - `useOpenAITTS = true` ✅
   - `forceOpenAITTS = true` ✅
   - 代码路径：`speak()` 方法总是尝试 OpenAI TTS 首先

2. **API Key 检查**：
   - 优先级 1: `AppConfig.openAIApiKey`（环境变量）
   - 优先级 2: 环境变量 `OPENAI_API_KEY`
   - 优先级 3: `UserDefaults` 中的 `OPENAI_API_KEY`

### 验证步骤

#### 1. 检查控制台日志

当调用 `speak()` 时，应该看到以下日志：

```
============================================================
🎙️ TTS speak() called
🎙️ Text length: XXX characters
🎙️ useOpenAITTS: true, forceOpenAITTS: true
============================================================
✅✅✅ FORCING OpenAI TTS (tts-1-hd) ✅✅✅
✅ useOpenAITTS: true, forceOpenAITTS: true
🚀 Starting OpenAI TTS generation task...
============================================================
🚀🚀🚀 Starting OpenAI TTS generation 🚀🚀🚀
✅✅✅ OpenAI API key found! ✅✅✅
🔑 Using OpenAI API key: sk-xxxxx...
📡 Sending OpenAI TTS API request...
📡 Model: tts-1-hd
✅ OpenAI TTS (tts-1-hd) request successful!
✅✅✅ OpenAI TTS (tts-1-hd) SUCCESS! Natural voice is now playing!
```

#### 2. 如果看到本地 TTS 日志

如果看到以下日志，说明 OpenAI TTS 失败并回退到本地 TTS：

```
❌❌❌ OpenAI TTS FAILED - Falling back to local TTS ❌❌❌
📢 Using local TTS (AVSpeechSynthesizer)
```

**可能的原因**：
1. API key 未配置
2. 网络连接问题
3. API key 无效或没有 TTS 访问权限

#### 3. API Key 配置

##### 方法 1: 环境变量（推荐）
在 Xcode Scheme 中设置：
1. Product → Scheme → Edit Scheme
2. Run → Arguments → Environment Variables
3. 添加：`OPENAI_API_KEY` = `your-api-key-here`

##### 方法 2: UserDefaults（开发测试）
在代码中临时设置：
```swift
AppConfig.setAPIKey("your-api-key-here")
```

##### 方法 3: 环境变量（终端）
```bash
export OPENAI_API_KEY=your-api-key-here
```

### 代码流程

```
speak(text:)
  ↓
检查 API key
  ↓
✅✅✅ FORCING OpenAI TTS (gpt-4o-mini-tts)
  ↓
Task { generateAndPlayOpenAITTS(text) }
  ↓
检查 API key（再次检查）
  ↓
发送 OpenAI API 请求 (gpt-4o-mini-tts)
  ↓
成功？ → ✅ 播放 OpenAI TTS 音频
失败？ → ❌ 回退到本地 TTS
```

### 关键代码位置

1. **强制 OpenAI TTS**：
   ```swift
   // Services/TTSPlayback.swift:95-129
   // ALWAYS FORCE OpenAI TTS - never use local TTS unless OpenAI TTS completely fails
   print("✅✅✅ FORCING OpenAI TTS (gpt-4o-mini-tts) ✅✅✅")
   Task {
       let success = await generateAndPlayOpenAITTS(text: text)
       // ...
   }
   ```

2. **API Key 检查**：
   ```swift
   // Services/TTSPlayback.swift:132-151
   private func getOpenAIApiKey() -> String? {
       // Priority 1: AppConfig
       // Priority 2: Environment variable
       // Priority 3: UserDefaults
   }
   ```

3. **OpenAI TTS 生成**：
   ```swift
   // Services/TTSPlayback.swift:155-365
   private func generateAndPlayOpenAITTS(text: String) async -> Bool {
       // 使用 gpt-4o-mini-tts 模型
       // 流式播放音频
   }
   ```

### 故障排除

#### 问题 1: 总是使用本地 TTS
**检查**：
1. 查看控制台日志，确认是否看到 "FORCING OpenAI TTS"
2. 检查 API key 是否配置
3. 检查网络连接

#### 问题 2: API key 未找到
**解决**：
1. 确认环境变量已设置
2. 重启 Xcode 和模拟器
3. 检查 API key 格式（应该以 `sk-` 开头）

#### 问题 3: OpenAI TTS 请求失败
**检查**：
1. API key 是否有效
2. API key 是否有 TTS 访问权限
3. 网络连接是否正常
4. 查看错误日志中的 HTTP 状态码

### 预期行为

✅ **正确**：总是尝试 OpenAI TTS 首先
✅ **正确**：如果 OpenAI TTS 成功，使用自然语音播放
✅ **正确**：如果 OpenAI TTS 失败，回退到本地 TTS（但会显示警告）
❌ **错误**：直接使用本地 TTS，不尝试 OpenAI TTS

### 验证清单

- [ ] `useOpenAITTS = true`
- [ ] `forceOpenAITTS = true`
- [ ] API key 已配置
- [ ] 控制台显示 "FORCING OpenAI TTS"
- [ ] 控制台显示 "OpenAI TTS (gpt-4o-mini-tts) SUCCESS"
- [ ] 听到自然语音（不是机器人声音）

