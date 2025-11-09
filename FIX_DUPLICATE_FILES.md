# 修复 "Multiple commands produce" 错误

## 问题原因

错误显示多个 Swift 文件被重复添加到项目中，导致 Xcode 尝试为同一个文件生成多个 `.stringsdata` 文件。

## 解决方案

### 步骤 1：检查并删除重复的文件引用

1. **打开 Xcode 项目**

2. **在项目导航器中检查每个文件**：
   - 查看以下文件是否出现**多次**：
     - `AppConfig.swift`
     - `ArtworkInfo.swift`
     - `RecognitionService.swift`
     - `RetrievalService.swift`
     - `NarrationService.swift`
     - `TTSPlayback.swift`
     - `HistoryService.swift`
     - `CameraView.swift`
     - `PlaybackView.swift`
     - `HistoryView.swift`

3. **如果发现重复引用**：
   - 右键点击**重复的文件**（不是第一个）
   - 选择 **"Delete"**
   - 选择 **"Remove Reference"**（不要选择 "Move to Trash"）

### 步骤 2：检查 Build Phases

1. **选择项目**（蓝色图标）→ 选择 **"Muse Lens" target**

2. **点击 "Build Phases" 标签页**

3. **展开 "Compile Sources"**
   - 检查是否有同一个文件出现**多次**
   - 如果发现重复，选中重复的文件，点击 **"-"** 按钮删除

4. **展开 "Copy Bundle Resources"**（如果有）
   - 同样检查是否有重复的文件

### 步骤 3：清理构建产物

1. **清理 DerivedData**：
   ```
   Xcode → Settings → Locations
   点击 Derived Data 路径旁边的箭头
   删除整个 DerivedData 文件夹
   ```

2. **或者使用命令行**：
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/Muse_Lens-*
   ```

3. **清理构建文件夹**：
   - Product → Clean Build Folder (Shift + Cmd + K)

### 步骤 4：重新添加文件（如果必要）

如果文件引用很混乱，可以：

1. **删除所有新文件的引用**（不是删除文件本身）：
   - 在项目导航器中，选中这些文件
   - Delete → Remove Reference

2. **重新添加文件**：
   - 右键点击 "Muse Lens" 组
   - 选择 "Add Files to 'Muse Lens'..."
   - 选择以下文件夹：
     - `Configuration` 文件夹
     - `Models` 文件夹
     - `Services` 文件夹
     - `Views` 文件夹
   - ✅ 确保 **"Copy items if needed"** **未选中**
   - ✅ 选择 **"Create groups"**
   - ✅ 在 "Add to targets" 中**只选中 "Muse Lens"**（确保只选中一次）
   - 点击 "Add"

### 步骤 5：验证文件只被添加一次

1. **选择项目** → **"Muse Lens" target** → **"Build Phases"**

2. **展开 "Compile Sources"**

3. **确认每个文件只出现一次**：
   - AppConfig.swift
   - ArtworkInfo.swift
   - RecognitionService.swift
   - RetrievalService.swift
   - NarrationService.swift
   - TTSPlayback.swift
   - HistoryService.swift
   - CameraView.swift
   - PlaybackView.swift
   - HistoryView.swift

### 步骤 6：重新构建

1. **Product → Clean Build Folder** (Shift + Cmd + K)
2. **Product → Build** (Cmd + B)

## 快速检查清单

- [ ] 项目导航器中每个文件只出现一次
- [ ] Build Phases → Compile Sources 中每个文件只出现一次
- [ ] 每个文件的 Target Membership 中只选中 "Muse Lens" 一次
- [ ] 已清理 DerivedData
- [ ] 已清理构建文件夹
- [ ] 重新构建成功

如果完成以上步骤后仍有问题，请提供具体的错误信息。

