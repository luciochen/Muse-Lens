# 数据库测试指南

## 概述

本指南介绍如何设置和测试 Muse Lens 的后端数据库缓存系统。

## 前置要求

1. Supabase 账户（免费版即可）
2. 已创建的 Supabase 项目
3. 项目 URL 和 API Key（anon key）

## 步骤 1: 创建 Supabase 项目

1. 访问 [Supabase](https://supabase.com)
2. 创建新项目
3. 记录项目 URL 和 API Key（anon key）

## 步骤 2: 设置数据库表

### 方法 1: 使用 Supabase SQL Editor

1. 登录 Supabase Dashboard
2. 进入 SQL Editor
3. 按顺序执行以下 SQL 文件：
   - `001_create_artworks_table.sql`
   - `002_create_artists_table.sql`
   - `003_create_indexes.sql`
   - `004_create_functions.sql`
   - `005_create_rls_policies.sql`

### 方法 2: 使用 Supabase CLI

```bash
# 安装 Supabase CLI
npm install -g supabase

# 登录
supabase login

# 链接项目
supabase link --project-ref your-project-ref

# 运行迁移
supabase db push
```

## 步骤 3: 配置应用

### 方法 1: 环境变量（推荐）

在 Xcode Scheme 中设置环境变量：

1. Product → Scheme → Edit Scheme
2. Run → Arguments → Environment Variables
3. 添加以下变量：
   - `BACKEND_API_URL`: 你的 Supabase 项目 URL（例如：`https://xxxxx.supabase.co`）
   - `BACKEND_API_KEY`: 你的 Supabase anon key

### 方法 2: 代码配置（仅开发测试）

在 `AppConfig.swift` 中临时设置：

```swift
AppConfig.setBackendAPIURL("https://xxxxx.supabase.co")
AppConfig.setBackendAPIKey("your-anon-key")
```

## 步骤 4: 测试数据库连接

### 使用 DatabaseTestView

1. 在应用中添加测试视图
2. 运行应用
3. 导航到测试视图
4. 点击"测试连接"按钮

### 手动测试 SQL 查询

在 Supabase SQL Editor 中执行：

```sql
-- 测试查询作品
SELECT * FROM artworks WHERE combined_hash = 'test_hash' LIMIT 1;

-- 测试查询艺术家
SELECT * FROM artists WHERE normalized_name = 'test_artist' LIMIT 1;

-- 测试查看次数统计
SELECT title, artist, view_count, last_viewed_at 
FROM artworks 
WHERE confidence >= 0.8 
ORDER BY view_count DESC 
LIMIT 10;
```

## 步骤 5: 测试 API 端点

### 使用 curl

```bash
# 测试查询作品
curl -X GET \
  'https://your-project.supabase.co/rest/v1/artworks?combined_hash=eq.test_hash' \
  -H 'apikey: your-anon-key' \
  -H 'Content-Type: application/json'

# 测试保存作品
curl -X POST \
  'https://your-project.supabase.co/rest/v1/artworks' \
  -H 'apikey: your-anon-key' \
  -H 'Content-Type: application/json' \
  -H 'Prefer: resolution=merge-duplicates' \
  -d '{
    "combined_hash": "test_hash",
    "normalized_title": "test_title",
    "normalized_artist": "test_artist",
    "title": "测试作品",
    "artist": "测试艺术家",
    "narration": "测试讲解内容",
    "artist_introduction": "测试艺术家介绍",
    "confidence": 0.9,
    "recognized": true
  }'
```

## 步骤 6: 验证数据

### 检查数据是否正确保存

1. 在 Supabase Dashboard 中查看 `artworks` 表
2. 验证以下字段：
   - `combined_hash` 是否唯一
   - `narration` 长度是否为 500-600 字
   - `artist_introduction` 长度是否为 300-400 字
   - `confidence` 是否 >= 0.8
   - `view_count` 是否递增

### 检查索引是否生效

```sql
-- 查看索引使用情况
EXPLAIN ANALYZE 
SELECT * FROM artworks 
WHERE combined_hash = 'test_hash';
```

## 步骤 7: 测试缓存逻辑

### 测试场景 1: 新作品识别

1. 识别一个新作品（高置信度）
2. 检查后端数据库是否有新记录
3. 验证 `combined_hash` 是否正确生成
4. 验证讲解内容和艺术家介绍是否正确保存

### 测试场景 2: 已缓存作品

1. 识别一个已存在的作品
2. 检查是否从后端缓存获取
3. 验证查看次数是否增加
4. 验证响应时间是否更快

### 测试场景 3: 艺术家介绍缓存

1. 识别一个已有艺术家的新作品
2. 检查艺术家介绍是否从缓存获取
3. 验证艺术家介绍是否正确显示

## 常见问题

### 问题 1: 连接失败

**原因**: API URL 或 Key 配置错误

**解决方法**:
1. 检查环境变量是否正确设置
2. 验证 Supabase 项目 URL 和 anon key
3. 检查网络连接

### 问题 2: 权限错误

**原因**: RLS 策略配置错误

**解决方法**:
1. 检查 RLS 策略是否正确创建
2. 验证 anon key 是否有正确的权限
3. 检查数据库函数权限

### 问题 3: 数据未保存

**原因**: 置信度不够高或验证失败

**解决方法**:
1. 检查 `confidence` 是否 >= 0.8
2. 检查 `recognized` 是否为 true
3. 查看应用日志中的错误信息

### 问题 4: 重复数据

**原因**: `combined_hash` 未正确生成

**解决方法**:
1. 检查 `ArtworkIdentifier.generate()` 方法
2. 验证文本标准化逻辑
3. 检查数据库 UNIQUE 约束

## 性能优化

### 查询优化

1. 使用索引加速查询
2. 限制查询结果数量
3. 使用连接池

### 缓存策略

1. 本地缓存作为一级缓存
2. 后端缓存作为二级缓存
3. 异步保存，不阻塞 UI

## 监控和日志

### 查看应用日志

在 Xcode Console 中查看：
- `🔍 Looking up artwork` - 缓存查询
- `✅ Found in backend cache` - 缓存命中
- `💾 Saving new artwork to backend cache` - 保存新作品
- `✅ View count incremented` - 查看次数增加

### 查看数据库日志

在 Supabase Dashboard 中：
1. 进入 Logs → Postgres Logs
2. 查看查询执行情况
3. 检查错误和警告

## 下一步

1. 监控数据库使用情况
2. 优化查询性能
3. 添加更多测试用例
4. 实现热门作品统计
5. 添加多语言支持

