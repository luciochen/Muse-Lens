# 修复构建错误："Multiple commands produce"

## 问题原因

这个错误通常是因为：
1. **Info.plist 文件冲突**：现代 Xcode 项目可能使用自动生成的 Info.plist，不需要单独的文件
2. **文件被重复添加**：同一个文件被添加到项目中多次

## 解决方案

### 方法 1：删除手动创建的 Info.plist 文件（推荐）

现代 Xcode 项目（iOS 14+）通常不需要单独的 Info.plist 文件，权限可以直接在项目设置中配置。

**步骤：**

1. **在 Xcode 中删除 Info.plist 文件引用**：
   - 在项目导航器中找到 `Info.plist`
   - 右键点击 → 选择 "Delete"
   - 选择 "Remove Reference"（不要选择 "Move to Trash"）

2. **在项目设置中添加权限**：
   - 选择项目 → 选择 "Muse Lens" target
   - 点击 "Info" 标签页
   - 在 "Custom iOS Target Properties" 部分，点击 "+" 按钮添加以下键值对：

   ```
   Privacy - Camera Usage Description
   值: MuseLens需要访问相机来拍摄博物馆艺术品，以便为您提供AI讲解服务。

   Privacy - Photo Library Usage Description  
   值: MuseLens需要访问照片库，以便您可以选择已拍摄的艺术品照片进行识别。

   Privacy - Photo Library Additions Usage Description
   值: MuseLens需要保存您拍摄的艺术品照片到相册。

   Privacy - Microphone Usage Description
   值: MuseLens需要访问麦克风以播放音频讲解内容。
   ```

3. **清理并重新构建**：
   - Product → Clean Build Folder (Shift + Cmd + K)
   - Product → Build (Cmd + B)

### 方法 2：检查是否有重复的文件引用

如果方法 1 不行，检查是否有文件被重复添加：

1. **在项目导航器中检查**：
   - 查看是否有同一个文件出现多次
   - 特别是 `.swift` 文件

2. **检查文件成员关系**：
   - 选择每个有问题的文件
   - 在右侧的 "File Inspector" 中查看 "Target Membership"
   - 确保每个文件只属于一个 target，且只被选中一次

3. **删除 Derived Data**：
   - Xcode → Settings → Locations
   - 点击 Derived Data 路径旁边的箭头
   - 删除整个 DerivedData 文件夹
   - 重新构建项目

### 方法 3：如果必须使用 Info.plist 文件

如果项目确实需要 Info.plist 文件：

1. **确保项目设置正确**：
   - 选择项目 → "Muse Lens" target
   - 在 "Build Settings" 中搜索 "Info.plist"
   - 确保 "INFOPLIST_FILE" 指向正确的路径：`Muse Lens/Info.plist`

2. **确保文件只被引用一次**：
   - 在项目导航器中，确保 Info.plist 只出现一次
   - 如果出现多次，删除多余的引用

## 快速修复步骤（推荐顺序）

1. ✅ **删除 Info.plist 文件引用**（如果存在）
2. ✅ **在项目 Info 标签页添加权限说明**
3. ✅ **清理 Derived Data**
4. ✅ **清理构建文件夹**（Shift + Cmd + K）
5. ✅ **重新构建**（Cmd + B）

## 如果问题仍然存在

请提供：
1. Xcode 错误面板中的完整错误信息
2. 哪些文件被标记为重复
3. 项目设置中 "INFOPLIST_FILE" 的值

