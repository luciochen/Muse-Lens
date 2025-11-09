# MuseLens

**拍一眼，就懂艺术**

MuseLens 是一款面向普通观众的 AI 导览 App，帮助用户在博物馆快速了解艺术品背后的故事。

## 功能特性

### P0 核心功能
- ✅ **拍照识别**：拍摄艺术品后 3 秒内返回识别结果
- ✅ **作品识别与检索**：从可靠的公开来源（Met Museum、Art Institute、Wikipedia）获取艺术品信息
- ✅ **AI 讲解生成**：基于检索资料生成 1-2 分钟的中文讲解（250-350 字）
- ✅ **讲解播放**：支持播放、暂停、快进 15 秒，文字与语音切换

### P1 功能
- ✅ **未识别降级**：识别失败时讲解画风
- ✅ **历史记录**：本地存储最近 10 条记录
- ⏳ **多语言支持**：中英切换（待实现）

## 技术架构

### 模块化设计
- **CameraView**：相机界面和照片捕获
- **RecognitionService**：使用 OpenAI Vision API 识别艺术品
- **RetrievalService**：从博物馆 API 和 Wikipedia 检索信息
- **NarrationService**：基于事实生成讲解脚本
- **TTSPlayback**：文本转语音播放服务
- **HistoryService**：本地历史记录管理

### 数据源
- The Metropolitan Museum of Art Collection API
- The Art Institute of Chicago API
- Wikipedia / Wikidata API
- OpenAI GPT-4o (Vision & Text)

## 配置要求

### 1. API Key 配置

在 Xcode 中设置环境变量或通过 Scheme 配置：

1. 打开 Xcode 项目
2. 选择 Product → Scheme → Edit Scheme
3. 在 Run → Arguments → Environment Variables 中添加：
   - Key: `OPENAI_API_KEY`
   - Value: 你的 OpenAI API Key

**或者**在代码中直接设置（不推荐用于生产环境）：

```swift
// Services/RecognitionService.swift
private init() {
    self.apiKey = "your-api-key-here" // 临时方案
}
```

### 2. Info.plist 权限

项目已包含 `Info.plist` 文件，包含以下权限说明：
- 相机访问权限
- 照片库访问权限
- 网络访问配置

如果 Xcode 项目使用 Build Settings 中的 Info.plist 路径，请确保将权限添加到项目的 Info 标签页。

### 3. 网络配置

项目已配置 App Transport Security (ATS)，允许访问：
- `api.openai.com`
- `collectionapi.metmuseum.org`
- `api.artic.edu`
- `en.wikipedia.org`

## 项目结构

```
Muse Lens/
├── Models/
│   └── ArtworkInfo.swift          # 数据模型
├── Services/
│   ├── RecognitionService.swift   # 艺术品识别服务
│   ├── RetrievalService.swift     # 信息检索服务
│   ├── NarrationService.swift     # 讲解生成服务
│   ├── TTSPlayback.swift          # 语音播放服务
│   └── HistoryService.swift       # 历史记录服务
├── Views/
│   ├── CameraView.swift           # 相机界面
│   ├── PlaybackView.swift         # 播放界面
│   └── HistoryView.swift          # 历史记录界面
├── ContentView.swift              # 主视图
├── Muse_LensApp.swift             # 应用入口
└── Info.plist                     # 权限配置
```

## 使用流程

1. **打开应用**：进入相机界面
2. **拍摄艺术品**：点击相机按钮拍摄展品
3. **自动识别**：系统识别艺术品（约 3 秒）
4. **信息检索**：从可靠来源获取作品信息
5. **生成讲解**：AI 生成 1-2 分钟讲解
6. **播放讲解**：自动播放语音，可切换文字显示

## App Store 合规性

### 隐私保护
- ✅ 不收集个人数据、人脸或用户标识
- ✅ 照片本地处理，仅传输最小特征用于识别
- ✅ 无登录、无广告、无隐藏追踪
- ✅ 仅教育用途

### 权限说明
- 相机：用于拍摄艺术品
- 照片库：用于选择已拍摄照片（可选）
- 网络：用于 API 调用和信息检索

### 数据来源
- 所有讲解内容严格基于可引用来源
- 不编造或推断信息
- 提供来源链接

## 错误处理

- **网络中断**：提示用户检查网络连接，缓存最近记录
- **未识别**：降级到画风讲解，不会出现空白界面
- **数据不足**：提示基于有限信息的说明
- **播放错误**：提示用户稍后重试

## 性能目标

- 识别 + 讲解生成总耗时 ≤ 8 秒
- 拍照到讲解全过程成功率 ≥ 80%
- 内容真实性满意度 ≥ 90%

## 开发环境

- Xcode 15.0+
- iOS 16.0+
- Swift 5.9+
- SwiftUI

## 待实现功能

- [ ] 多语言支持（中英切换）
- [ ] 更好的音频进度控制（精确跳转）
- [ ] 离线模式支持
- [ ] 更多博物馆 API 集成

## 注意事项

1. **API Key 安全**：生产环境请使用 Keychain 或环境变量，不要硬编码
2. **网络请求**：所有 API 调用需要网络连接
3. **识别准确性**：取决于艺术品知名度和照片质量
4. **内容真实性**：讲解严格基于检索到的信息，不会编造

## 许可证

Copyright © 2025 MuseLens. All rights reserved.

