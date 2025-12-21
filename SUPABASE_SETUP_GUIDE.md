# Supabase 设置指南

本指南将帮助你一步步设置 Supabase 数据库并配置到 Muse Lens 应用中。

## 步骤 1: 创建 Supabase 账户

1. 访问 [Supabase官网](https://supabase.com)
2. 点击右上角 **"Sign In"** 或 **"Start your project"**
3. 使用 GitHub 账户登录（推荐）或创建新账户
4. 完成账户验证

## 步骤 2: 创建新项目

1. 登录后，点击 **"New Project"** 按钮
2. 填写项目信息：
   - **Name**: 项目名称（例如：`muse-lens`）
   - **Database Password**: 设置数据库密码（**重要：请保存此密码**）
   - **Region**: 选择离你最近的地域（例如：`Southeast Asia (Singapore)` 或 `West US (N. California)`）
   - **Pricing Plan**: 选择 **Free** 计划（免费版足够使用）
3. 点击 **"Create new project"**
4. 等待项目创建完成（约 2-3 分钟）

## 步骤 3: 获取项目配置信息

项目创建完成后，你需要获取以下信息：

### 3.1 获取 Project URL

1. 在项目 Dashboard 中，点击左侧菜单的 **"Settings"**（设置）
2. 点击 **"API"**
3. 在 **"Project URL"** 部分，复制 URL（格式：`https://xxxxx.supabase.co`）
   - 例如：`https://abcdefghijklmnop.supabase.co`

### 3.2 获取 API Key (anon key)

1. 在同一页面（Settings → API）
2. 在 **"Project API keys"** 部分
3. 找到 **"anon"** 或 **"public"** key
4. 点击 **"Reveal"** 按钮显示密钥
5. 复制 **anon key**（格式：`eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`）

**重要提示**：
- 使用 **anon key**（公开密钥），不要使用 `service_role` key（服务密钥）
- anon key 是安全的，因为我们已经设置了 Row Level Security (RLS) 策略

## 步骤 4: 设置数据库表

### 方法 1: 使用 Supabase SQL Editor（推荐）

1. 在 Supabase Dashboard 中，点击左侧菜单的 **"SQL Editor"**
2. 点击 **"New query"** 按钮
3. 打开项目中的 SQL 文件，按顺序执行：

#### 4.1 创建 Artworks 表

复制 `database/migrations/001_create_artworks_table.sql` 的内容，粘贴到 SQL Editor，然后点击 **"Run"** 按钮。

#### 4.2 创建 Artists 表

复制 `database/migrations/002_create_artists_table.sql` 的内容，粘贴到 SQL Editor，然后点击 **"Run"** 按钮。

#### 4.3 创建索引和用户识别日志表

复制 `database/migrations/003_create_indexes.sql` 的内容，粘贴到 SQL Editor，然后点击 **"Run"** 按钮。

#### 4.4 创建数据库函数

复制 `database/migrations/004_create_functions.sql` 的内容，粘贴到 SQL Editor，然后点击 **"Run"** 按钮。

#### 4.5 创建 RLS 策略

复制 `database/migrations/005_create_rls_policies.sql` 的内容，粘贴到 SQL Editor，然后点击 **"Run"** 按钮。

### 方法 2: 使用 Supabase CLI（高级用户）

如果你熟悉命令行工具，可以使用 Supabase CLI：

```bash
# 安装 Supabase CLI
npm install -g supabase

# 登录 Supabase
supabase login

# 链接到你的项目
supabase link --project-ref your-project-ref

# 运行迁移脚本
supabase db push
```

**注意**：项目 ref 可以在项目 Settings → General 中找到。

## 步骤 5: 验证数据库设置

### 5.1 检查表是否创建成功

1. 在 Supabase Dashboard 中，点击左侧菜单的 **"Table Editor"**
2. 你应该看到以下表：
   - `artworks` - 作品表
   - `artists` - 艺术家表
   - `user_recognitions` - 用户识别记录表（可选）

### 5.2 检查 RLS 策略

1. 在 Supabase Dashboard 中，点击左侧菜单的 **"Authentication"**
2. 点击 **"Policies"**
3. 确认 `artworks` 和 `artists` 表有正确的策略

### 5.3 测试数据库连接

在 SQL Editor 中运行以下查询，确认表结构正确：

```sql
-- 检查 artworks 表结构
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'artworks';

-- 检查 artists 表结构
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'artists';
```

## 步骤 6: 配置应用到 Xcode

### 方法 1: 使用环境变量（推荐）

1. 在 Xcode 中打开项目
2. 点击菜单 **Product** → **Scheme** → **Edit Scheme...**
3. 选择 **Run** → **Arguments**
4. 在 **Environment Variables** 部分，点击 **+** 按钮添加以下变量：

   | Name | Value |
   |------|-------|
   | `BACKEND_API_URL` | 你的 Supabase Project URL（例如：`https://abcdefghijklmnop.supabase.co`）|
   | `BACKEND_API_KEY` | 你的 Supabase anon key |

5. 确保两个变量都被勾选（Enabled）
6. 点击 **Close** 保存

**示例**：
```
BACKEND_API_URL = https://abcdefghijklmnop.supabase.co
BACKEND_API_KEY = eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFiY2RlZmdoaWprbG1ub3AiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTYxNjIzOTAyMiwiZXhwIjoxOTMxODE1MDIyfQ.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 方法 2: 在代码中临时配置（仅开发测试）

如果你不想使用环境变量，可以在 `AppConfig.swift` 中临时设置：

```swift
// 在 AppConfig.swift 的 init() 方法中添加
static func configureBackend() {
    setBackendAPIURL("https://your-project.supabase.co")
    setBackendAPIKey("your-anon-key")
}
```

**注意**：这种方法不适合生产环境，因为 API key 会暴露在代码中。

## 步骤 7: 测试连接

### 7.1 使用 DatabaseTestView

1. 在 Xcode 中运行应用
2. 导航到 `DatabaseTestView`（如果已添加到应用中）
3. 输入 Supabase URL 和 API Key
4. 点击 **"保存配置"**
5. 点击 **"测试连接"** 按钮
6. 如果看到 ✅ **"连接成功"**，说明配置正确

### 7.2 使用 curl 命令行测试

在终端中运行以下命令（替换为你的实际值）：

```bash
# 测试查询作品（应该返回空数组或已有作品）
curl -X GET \
  'https://your-project.supabase.co/rest/v1/artworks?limit=1' \
  -H 'apikey: your-anon-key' \
  -H 'Content-Type: application/json'
```

如果返回 `[]` 或 JSON 数据，说明连接成功。

## 步骤 8: 验证功能

### 8.1 测试保存作品

1. 在应用中识别一个作品（高置信度，confidence >= 0.8）
2. 查看 Xcode Console 日志，应该看到：
   - `💾 Saving new artwork to backend cache...`
   - `✅ Saved to backend cache successfully`
3. 在 Supabase Dashboard → Table Editor → artworks 表中查看新记录

### 8.2 测试查询作品

1. 识别同一个作品第二次
2. 查看 Xcode Console 日志，应该看到：
   - `✅ Found in backend cache (shared with other users)`
3. 响应时间应该更快（因为使用了缓存）

### 8.3 测试艺术家介绍

1. 识别一个已有艺术家的新作品
2. 查看艺术家介绍是否从缓存获取
3. 在 Supabase Dashboard → Table Editor → artists 表中查看艺术家记录

## 常见问题

### 问题 1: 连接失败，返回 401 Unauthorized

**原因**：API Key 错误或未设置

**解决方法**：
1. 检查环境变量是否正确设置
2. 确认使用的是 **anon key**，不是 service_role key
3. 在 Xcode 中重新设置环境变量

### 问题 2: 连接失败，返回 404 Not Found

**原因**：Project URL 错误

**解决方法**：
1. 检查 Project URL 是否正确（应该以 `https://` 开头，以 `.supabase.co` 结尾）
2. 确认 URL 中没有多余的空格或字符
3. 在 Supabase Dashboard 中重新复制 URL

### 问题 3: 表不存在错误

**原因**：数据库迁移脚本未执行

**解决方法**：
1. 检查 SQL Editor 中是否有错误
2. 重新执行迁移脚本
3. 在 Table Editor 中确认表是否存在

### 问题 4: 插入数据失败，返回权限错误

**原因**：RLS 策略未正确设置

**解决方法**：
1. 检查 RLS 策略是否已创建
2. 确认策略允许 INSERT 操作
3. 重新执行 `005_create_rls_policies.sql` 脚本

### 问题 5: 数据未保存到数据库

**原因**：置信度不够高

**解决方法**：
1. 检查作品的 `confidence` 是否 >= 0.8
2. 检查 `recognized` 是否为 `true`
3. 查看 Xcode Console 日志中的错误信息

## 安全注意事项

1. **不要提交 API Key 到 Git**
   - 使用环境变量，不要硬编码在代码中
   - 将 `.xcconfig` 文件添加到 `.gitignore`

2. **使用 anon key，不要使用 service_role key**
   - anon key 是安全的，因为我们已经设置了 RLS 策略
   - service_role key 有完整权限，不应该在客户端使用

3. **定期轮换 API Key**
   - 在 Supabase Dashboard → Settings → API 中可以生成新 key
   - 更新环境变量后重新部署应用

## 监控和日志

### 查看应用日志

在 Xcode Console 中查看：
- `🔍 Looking up artwork` - 缓存查询
- `✅ Found in backend cache` - 缓存命中
- `💾 Saving new artwork to backend cache` - 保存新作品
- `⚠️ Backend lookup failed` - 连接失败

### 查看数据库日志

在 Supabase Dashboard 中：
1. 点击左侧菜单的 **"Logs"**
2. 选择 **"Postgres Logs"** 查看数据库日志
3. 选择 **"API Logs"** 查看 API 请求日志

### 查看数据库使用情况

在 Supabase Dashboard → Settings → Usage 中查看：
- 数据库大小
- API 请求数量
- 存储使用情况

## 下一步

设置完成后，你可以：

1. ✅ 测试作品识别和缓存功能
2. ✅ 查看数据库中的作品记录
3. ✅ 监控 API 使用情况
4. ⏳ 实现本地 SQLite 缓存（一级缓存）
5. ⏳ 添加热门作品统计功能
6. ⏳ 实现多语言支持

## 参考资源

- [Supabase 官方文档](https://supabase.com/docs)
- [Supabase API 文档](https://supabase.com/docs/reference/javascript/introduction)
- [PostgreSQL 文档](https://www.postgresql.org/docs/)
- [DATABASE_TEST_GUIDE.md](./DATABASE_TEST_GUIDE.md) - 数据库测试指南
- [BACKEND_CACHE_IMPLEMENTATION.md](./BACKEND_CACHE_IMPLEMENTATION.md) - 后端缓存实施总结

## 需要帮助？

如果遇到问题，可以：

1. 查看 [DATABASE_TEST_GUIDE.md](./DATABASE_TEST_GUIDE.md) 中的常见问题部分
2. 检查 Supabase Dashboard 中的日志
3. 查看 Xcode Console 中的错误信息
4. 参考 Supabase 官方文档

