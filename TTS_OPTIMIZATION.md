# TTS 语音优化指南

## 当前优化配置

### 默认配置（已优化）
- **模型**: `tts-1-hd` (高质量)
- **声音**: `shimmer` (更适合中文，更自然)
- **速度**: `1.15` (优化后的流畅度)

### 为什么选择这些配置？

1. **shimmer 声音**：
   - 更自然、更有表现力
   - 温暖、友好的音色
   - 特别适合中文语音
   - 比 nova 更柔和，不会太生硬

2. **速度 1.15**：
   - 比默认 1.0 稍快
   - 更接近自然对话的节奏
   - 不会太快（>1.3）显得匆忙
   - 不会太慢（<1.0）显得生硬

3. **tts-1-hd 模型**：
   - 高质量语音合成
   - 更自然的声音
   - 推荐用于生产环境

## 可用的声音选项

| 声音 | 特点 | 适用场景 |
|------|------|----------|
| **shimmer** ⭐ | 自然、温暖、有表现力 | **中文语音（推荐）** |
| nova | 清晰、专业 | 新闻、解说 |
| onyx | 深沉、权威 | 正式场合 |
| alloy | 平衡、中性 | 通用场景 |
| echo | 清晰、明亮 | 教育内容 |
| fable | 柔和、友好 | 儿童内容 |

## 速度优化

### 推荐速度范围
- **1.0-1.2**: 自然对话速度（推荐）
- **1.2-1.5**: 稍快，适合新闻播报
- **0.8-1.0**: 较慢，适合强调重点
- **>1.5**: 过快，可能影响理解
- **<0.8**: 过慢，可能显得生硬

### 当前设置：1.15
- 平衡了自然度和清晰度
- 适合中文讲解内容
- 不会显得匆忙或生硬

## 模型选择

### tts-1-hd（当前使用，推荐）
- ✅ **高质量**：更自然的声音
- ✅ **适合生产**：推荐用于正式发布
- ⚠️ **稍慢**：生成时间稍长
- 💰 **成本**：稍高

### tts-1（快速模式）
- ✅ **快速**：生成时间更短
- ✅ **适合测试**：快速验证效果
- ⚠️ **质量稍低**：声音质量略低
- 💰 **成本**：更低

## 如何调整配置

### 方法 1: 在代码中调整（当前设置）

在 `Services/TTSPlayback.swift` 中修改：

```swift
// 更改声音
private var ttsVoice = "shimmer" // 或其他选项

// 更改速度
private var ttsSpeed: Double = 1.15 // 0.25 到 4.0

// 更改模型
private var ttsModel = "tts-1-hd" // 或 "tts-1"
```

### 方法 2: 使用公共方法（运行时调整）

```swift
// 更改声音
TTSPlayback.shared.setVoice("nova")

// 更改速度
TTSPlayback.shared.setSpeed(1.2)

// 更改模型
TTSPlayback.shared.setModel("tts-1") // 快速模式
TTSPlayback.shared.setModel("tts-1-hd") // 质量模式

// 或使用快捷方法
TTSPlayback.shared.enableFastMode() // 使用 tts-1
TTSPlayback.shared.enableQualityMode() // 使用 tts-1-hd
```

## 优化建议

### 如果声音还是生硬

1. **尝试不同的声音**：
   ```swift
   TTSPlayback.shared.setVoice("shimmer") // 最自然
   TTSPlayback.shared.setVoice("nova")    // 清晰专业
   TTSPlayback.shared.setVoice("alloy")   // 平衡中性
   ```

2. **调整速度**：
   ```swift
   TTSPlayback.shared.setSpeed(1.2) // 稍快，更流畅
   TTSPlayback.shared.setSpeed(1.0) // 标准速度
   ```

3. **确保使用高质量模型**：
   ```swift
   TTSPlayback.shared.enableQualityMode() // 使用 tts-1-hd
   ```

### 如果需要更快

1. **使用快速模型**：
   ```swift
   TTSPlayback.shared.enableFastMode() // 使用 tts-1
   ```

2. **注意**：快速模型质量稍低，可能听起来稍生硬

### 最佳实践

1. **生产环境**：使用 `tts-1-hd` + `shimmer` + `1.15`
2. **测试环境**：可以使用 `tts-1` 加快测试
3. **不同场景**：
   - 艺术讲解：`shimmer` + `1.15`（当前设置）
   - 新闻播报：`nova` + `1.2`
   - 正式场合：`onyx` + `1.0`

## 测试不同配置

### 测试脚本

```swift
// 测试不同声音
let voices = ["shimmer", "nova", "alloy", "onyx"]
for voice in voices {
    TTSPlayback.shared.setVoice(voice)
    TTSPlayback.shared.speak(text: "测试文本", language: "zh-CN")
    // 等待播放完成...
}

// 测试不同速度
let speeds = [1.0, 1.1, 1.15, 1.2, 1.3]
for speed in speeds {
    TTSPlayback.shared.setSpeed(speed)
    TTSPlayback.shared.speak(text: "测试文本", language: "zh-CN")
    // 等待播放完成...
}
```

## 当前配置总结

✅ **模型**: `tts-1-hd` (高质量)
✅ **声音**: `shimmer` (最自然，适合中文)
✅ **速度**: `1.15` (优化后的流畅度)

这个配置应该提供：
- 🎯 更自然的声音
- 🚀 流畅的节奏
- 🎨 适合艺术讲解的温暖音色

如果还是觉得生硬，可以尝试：
1. 调整速度到 1.2
2. 尝试其他声音（nova, alloy）
3. 检查网络延迟（可能影响感知）

## 注意事项

1. **声音选择**：不同声音适合不同场景，建议测试后选择
2. **速度调整**：过快或过慢都可能影响自然度
3. **模型选择**：质量模式（tts-1-hd）推荐用于生产
4. **网络影响**：网络延迟可能影响语音的流畅感知

