# 配置 OpenAI API Key

## 问题
应用显示错误："API Key 未配置。请在 Xcode Scheme 中设置 OPENAI_API_KEY 环境变量。"

## 解决方案：在 Xcode 中设置环境变量

### 方法 1：通过 Xcode Scheme 设置（推荐）

1. **打开 Xcode Scheme 设置**：
   - 在 Xcode 顶部工具栏，点击项目名称旁边的 Scheme 选择器（显示 "Muse Lens" 的地方）
   - 选择 **"Edit Scheme..."**

2. **添加环境变量**：
   - 在左侧选择 **"Run"**
   - 点击 **"Arguments"** 标签页
   - 在 **"Environment Variables"** 部分，点击 **"+"** 按钮
   - 添加以下环境变量：
     - **Name**: `OPENAI_API_KEY`
     - **Value**: 你的 OpenAI API Key（例如：`sk-...`）
     - ✅ 确保 **"Show"** 复选框已选中（这样在调试时可以看到）

3. **保存设置**：
   - 点击 **"Close"** 按钮保存

4. **重新运行应用**：
   - Product → Run (Cmd + R)

### 方法 2：临时在代码中设置（仅用于测试，不推荐用于生产）

如果只是快速测试，可以临时在 `AppConfig.swift` 中设置：

```swift
static var openAIApiKey: String? {
    // Priority 1: Environment variable (recommended)
    if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
        return key
    }
    
    // Priority 2: UserDefaults (for development/testing only)
    if let key = UserDefaults.standard.string(forKey: "OPENAI_API_KEY"), !key.isEmpty {
        return key
    }
    
    // Priority 3: Hardcoded (NOT RECOMMENDED for production)
    // 仅用于快速测试，发布前必须删除！
    return "your-api-key-here"  // 替换为你的实际 API Key
    
    // return nil
}
```

⚠️ **警告**：方法 2 仅用于开发测试，发布到 App Store 前必须删除硬编码的 API Key！

## 获取 OpenAI API Key

如果你还没有 API Key：

1. 访问 [OpenAI Platform](https://platform.openai.com/)
2. 登录或注册账户
3. 进入 **API Keys** 页面
4. 点击 **"Create new secret key"**
5. 复制生成的 API Key（格式类似：`sk-...`）
6. ⚠️ **重要**：API Key 只显示一次，请妥善保存

## 验证配置

配置完成后：

1. **清理构建**：
   - Product → Clean Build Folder (Shift + Cmd + K)

2. **重新运行应用**：
   - Product → Run (Cmd + R)

3. **测试**：
   - 点击"拍摄艺术品"按钮
   - 选择一张照片
   - 应该不再显示 API Key 错误
   - 应用会开始识别和处理照片

## 安全提示

- ✅ **推荐**：使用环境变量（方法 1）
- ✅ **开发测试**：可以使用 UserDefaults 临时存储
- ❌ **禁止**：不要在代码中硬编码 API Key
- ❌ **禁止**：不要将 API Key 提交到 Git 仓库

## 如果仍有问题

1. 确认环境变量名称拼写正确：`OPENAI_API_KEY`
2. 确认 API Key 格式正确（以 `sk-` 开头）
3. 清理并重新构建项目
4. 重启 Xcode（有时需要）

