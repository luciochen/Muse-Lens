# 添加 Info.plist 权限配置

## 问题
应用崩溃，错误信息：缺少 `NSCameraUsageDescription` 权限说明。

## 解决方案

我已经创建了 `Info.plist` 文件，包含所有必要的权限说明。现在需要在 Xcode 项目设置中配置它。

### 步骤 1：在 Xcode 中添加 Info.plist 到项目

1. **在 Xcode 项目导航器中**：
   - 右键点击 "Muse Lens" 组（项目根目录）
   - 选择 "Add Files to 'Muse Lens'..."
   - 导航到 `Muse Lens/Muse Lens/` 目录
   - 选择 `Info.plist` 文件
   - **重要设置**：
     - ✅ 取消选中 "Copy items if needed"（文件已在正确位置）
     - ✅ 选择 "Create groups"
     - ✅ 在 "Add to targets" 中选中 "Muse Lens"
   - 点击 "Add"

### 步骤 2：在项目设置中配置 Info.plist 路径

1. **选择项目**（蓝色图标）→ 选择 **"Muse Lens" target**

2. **点击 "Build Settings" 标签页**

3. **搜索 "Info.plist"** 或 "INFOPLIST_FILE"

4. **找到 "Info.plist File" 设置**：
   - 双击该设置的值
   - 输入：`Muse Lens/Info.plist`
   - 或者点击文件夹图标，选择 `Muse Lens/Info.plist` 文件

5. **或者使用 Info 标签页**（更简单的方法）：
   - 选择项目 → "Muse Lens" target
   - 点击 **"Info"** 标签页
   - 在 "Custom iOS Target Properties" 部分，手动添加以下键值对：
     - **Privacy - Camera Usage Description**
       - 值：`MuseLens需要访问相机来拍摄博物馆艺术品，以便为您提供AI讲解服务。`
     - **Privacy - Photo Library Usage Description**
       - 值：`MuseLens需要访问照片库，以便您可以选择已拍摄的艺术品照片进行识别。`
     - **Privacy - Photo Library Additions Usage Description**
       - 值：`MuseLens需要保存您拍摄的艺术品照片到相册。`
     - **Privacy - Microphone Usage Description**
       - 值：`MuseLens需要访问麦克风以播放音频讲解内容。`

### 步骤 3：验证配置

1. **清理构建**：
   - Product → Clean Build Folder (Shift + Cmd + K)

2. **重新构建**：
   - Product → Build (Cmd + B)

3. **运行应用**：
   - Product → Run (Cmd + R)

## 推荐方法

**推荐使用方法 2（Info 标签页）**，因为：
- 更简单直接
- 不需要手动管理 Info.plist 文件路径
- Xcode 会自动处理

## 验证权限已添加

运行应用后，当首次点击"拍摄艺术品"按钮时，系统应该会弹出权限请求对话框，而不是崩溃。

如果仍有问题，请检查：
1. 权限说明是否已添加到项目设置中
2. 清理并重新构建项目
3. 重新运行应用

