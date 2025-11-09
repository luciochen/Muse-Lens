# 构建失败故障排除指南

## 问题：Failed to build the scheme "Muse Lens"

### 最可能的原因：新文件未添加到 Xcode 项目

我创建的新 Swift 文件需要手动添加到 Xcode 项目中。

### 解决方案

#### 方法 1：在 Xcode 中添加文件（推荐）

1. **打开 Xcode 项目**
   - 打开 `Muse Lens.xcodeproj`

2. **在项目导航器中右键点击项目根目录**
   - 选择 "Add Files to 'Muse Lens'..."

3. **选择以下文件夹和文件**：
   - `Muse Lens/Configuration/` 文件夹 → 选择 `AppConfig.swift`
   - `Muse Lens/Models/` 文件夹 → 选择 `ArtworkInfo.swift`
   - `Muse Lens/Services/` 文件夹 → 选择所有 `.swift` 文件：
     - `RecognitionService.swift`
     - `RetrievalService.swift`
     - `NarrationService.swift`
     - `TTSPlayback.swift`
     - `HistoryService.swift`
   - `Muse Lens/Views/` 文件夹 → 选择所有 `.swift` 文件：
     - `CameraView.swift`
     - `PlaybackView.swift`
     - `HistoryView.swift`

4. **重要设置**：
   - ✅ 确保 "Copy items if needed" **未选中**（文件已在正确位置）
   - ✅ 确保 "Create groups" 已选中
   - ✅ 在 "Add to targets" 中选中 "Muse Lens"

5. **点击 "Add"**

#### 方法 2：拖拽文件到 Xcode

1. 打开 Finder，导航到 `Muse Lens/Muse Lens/` 目录
2. 在 Xcode 项目导航器中，找到 "Muse Lens" 组
3. 将以下文件夹拖拽到 Xcode：
   - `Configuration` 文件夹
   - `Models` 文件夹
   - `Services` 文件夹
   - `Views` 文件夹
4. 在弹出的对话框中：
   - ✅ 确保 "Copy items if needed" **未选中**
   - ✅ 选择 "Create groups"
   - ✅ 选中 "Muse Lens" target
   - 点击 "Finish"

### 验证文件已添加

1. 在 Xcode 项目导航器中，你应该能看到：
   ```
   Muse Lens
   ├── Configuration
   │   └── AppConfig.swift
   ├── Models
   │   └── ArtworkInfo.swift
   ├── Services
   │   ├── RecognitionService.swift
   │   ├── RetrievalService.swift
   │   ├── NarrationService.swift
   │   ├── TTSPlayback.swift
   │   └── HistoryService.swift
   ├── Views
   │   ├── CameraView.swift
   │   ├── PlaybackView.swift
   │   └── HistoryView.swift
   ├── ContentView.swift
   ├── Muse_LensApp.swift
   └── Assets.xcassets
   ```

2. 点击每个文件，在右侧的 "File Inspector" 中确认：
   - "Target Membership" 中 "Muse Lens" 已选中 ✅

### 其他可能的问题

#### 1. Info.plist 未添加到项目

如果 `Info.plist` 文件未在项目中：
1. 按照上述方法将 `Info.plist` 添加到项目
2. 在项目设置中：
   - 选择项目 → "Muse Lens" target
   - 在 "Info" 标签页，将 "Custom iOS Target Properties" 指向 `Info.plist`

#### 2. 编译错误检查

添加文件后，如果仍有错误：

1. **清理构建**：
   - Product → Clean Build Folder (Shift + Cmd + K)

2. **检查编译错误**：
   - 查看 Xcode 左侧的错误面板
   - 常见错误：
     - "Cannot find type 'AppConfig'" → 文件未添加到项目
     - "Use of undeclared type" → 导入缺失或文件未添加
     - "Missing import" → 添加相应的 import 语句

3. **重新构建**：
   - Product → Build (Cmd + B)

### 如果问题仍然存在

1. **删除 Derived Data**：
   - Xcode → Settings → Locations
   - 点击 Derived Data 路径旁边的箭头
   - 删除 "Muse Lens" 相关的文件夹
   - 重新构建

2. **检查项目设置**：
   - 确保 iOS Deployment Target ≥ 16.0
   - 确保 Swift Language Version 正确

3. **查看详细错误信息**：
   - 在 Xcode 的错误面板中点击错误
   - 查看完整的错误描述

### 快速验证

添加所有文件后，尝试构建：
- Product → Build (Cmd + B)

如果成功，你应该看到 "Build Succeeded" ✅

如果仍有错误，请查看 Xcode 的错误面板并告诉我具体的错误信息。

