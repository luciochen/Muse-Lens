# 艺术作品信息准确性改进

## 问题描述
用户反馈 artist、year、style 不准确，像是随意生成的。

## 已完成的改进

### 1. ✅ 加强 NarrationService 的 Prompt 严格性

#### 改进内容：
- **更严格的准确性要求**：
  - 如果不确定标准名称，必须降低 confidence 或使用 null
  - 禁止猜测和模糊表述（如"大约"、"可能"、"约"等）
  - 如果不确定任何信息，必须降低 confidence 值
  - 只有非常确定所有信息时才使用 confidence >= 0.8

#### 关键改进：
```
- 标题必须100%准确：如果不确定标准名称，使用null或降低confidence
- 艺术家名称必须100%准确：如果不确定，使用"未知艺术家"并降低confidence
- 年代必须100%准确：如果不确定则为null，绝对不要猜测
- 风格必须准确：如果不确定则为null，不要猜测风格
- 关键要求：如果对任何一项不确定，必须降低confidence值
```

### 2. ✅ 改进 RetrievalService 的匹配逻辑

#### 改进内容：
- **匹配评分系统**：
  - 标题精确匹配：+3 分
  - 标题部分匹配：+1 分
  - 艺术家精确匹配：+2 分
  - 艺术家部分匹配：+1 分
  - 艺术家不匹配：-1 分
  - 只接受正分匹配（matchScore >= 0）

#### 改进的 API 数据提取：

**Met Museum API**：
- 改进了 artist 提取（尝试多个字段：artistDisplayName, culture, artistAlphaSort）
- 改进了 year 提取（清理常见前缀：ca., c., circa）
- **新增 style 提取**（从 period 或 culture 字段提取）
- 添加了数据清理和标准化

**Art Institute API**：
- 改进了 artist 提取（尝试多个字段）
- 改进了 year 提取（清理前缀）
- **改进了 style 提取**（从 style_title 或 classification_title 提取）
- 添加了数据清理

**Wikipedia**：
- 改进了 artist 提取（从文本中提取）
- **新增 year 提取**（使用正则表达式提取年份）
- **新增 style 提取**（识别常见风格关键词）
- 添加了数据清理

### 3. ✅ 改进 CameraView 的验证逻辑

#### 改进内容：
- **严格验证要求**：
  - 对于高置信度但无法验证的结果，自动降低置信度到 0.65
  - 检测 AI 生成和验证信息的不匹配
  - 优先使用验证信息，只有在验证信息是通用值（如 "Unknown Artist"）时才使用 AI 生成的值
  - 如果存在不匹配，稍微降低置信度

#### 验证流程：
1. 高置信度（>= 0.8）：
   - 尝试从在线源验证
   - 如果找到验证信息：使用验证信息，保留 AI 生成的 narration
   - 如果未找到验证信息：**降低置信度到 0.65**（防止虚假高置信度声明）

2. 中等/低置信度：
   - 仍然尝试验证（如果可能）
   - 如果找到验证信息：使用验证信息，稍微提高置信度

### 4. ✅ 数据清理和标准化

#### Artist 清理：
- 去除多余空格
- 标准化未知艺术家名称（"Unknown" -> "Unknown Artist"）
- 尝试多个字段获取艺术家信息

#### Year 清理：
- 去除常见前缀（ca., c., circa）
- 去除多余空格
- 如果清理后为空，设置为 null

#### Style 提取：
- Met Museum：从 period 或 culture 字段提取
- Art Institute：从 style_title 或 classification_title 提取
- Wikipedia：识别常见风格关键词（Renaissance, Impressionism, Baroque 等）

## 改进效果

### 预期改进：
1. **更准确的 artist**：
   - 优先使用 API 验证的艺术家名称
   - 如果无法验证，降低置信度而不是使用猜测的名称

2. **更准确的 year**：
   - 清理和标准化年份格式
   - 如果不确定，使用 null 而不是猜测

3. **更准确的 style**：
   - 从多个 API 源提取 style
   - 如果不确定，使用 null 而不是猜测

4. **更合理的置信度**：
   - 无法验证的高置信度结果会自动降低置信度
   - 防止虚假的高置信度声明

## 测试建议

### 测试步骤：
1. **测试已知作品**：
   - 拍摄著名艺术作品（如《蒙娜丽莎》、《星夜》等）
   - 验证 artist、year、style 是否准确
   - 检查置信度是否合理

2. **测试未知作品**：
   - 拍摄不确定的作品
   - 验证是否正确标记为中等/低置信度
   - 验证是否正确使用 "未知艺术家" 或 null

3. **查看控制台日志**：
   - 查看验证信息是否找到
   - 查看是否有不匹配警告
   - 查看置信度调整日志

### 关键日志：
```
✅ Found verified information from online sources
📝 Verified info - Title: '...', Artist: '...', Year: '...', Style: '...'
⚠️ Title mismatch: AI='...' vs Verified='...'
⚠️ Confidence lowered to 0.65 due to lack of verification
```

## 技术细节

### 匹配评分系统：
```swift
// 标题匹配
if candidateTitleLower == artworkTitleLower {
    matchScore += 3 // 精确匹配
} else if artworkTitleLower.contains(candidateTitleLower) {
    matchScore += 1 // 部分匹配
}

// 艺术家匹配
if candidateArtistLower == artworkArtistLower {
    matchScore += 2 // 精确匹配
} else if artworkArtistLower.contains(candidateArtistLower) {
    matchScore += 1 // 部分匹配
} else {
    matchScore -= 1 // 不匹配
}
```

### 置信度调整：
```swift
// 如果无法验证高置信度结果，降低置信度
if narrationResponse.confidence >= 0.8 && verifiedInfo == nil {
    confidence = 0.65 // 降低到中等置信度
}
```

## 注意事项

1. **API 限制**：
   - Met Museum API 和 Art Institute API 可能不包含所有作品
   - 如果作品不在这些 API 中，可能无法验证

2. **网络连接**：
   - 验证需要网络连接
   - 如果网络不可用，将使用 AI 生成的信息（但会降低置信度）

3. **数据质量**：
   - API 数据质量可能因作品而异
   - 某些作品的 metadata 可能不完整

## 下一步

1. 测试改进后的准确性
2. 监控控制台日志
3. 根据实际使用情况进一步调整

