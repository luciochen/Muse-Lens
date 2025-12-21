# 修复 Schema Cache 错误

## 问题描述

如果遇到以下错误：
- `Could not find the 'artist_introduction' column of 'artists' in the schema cache`
- `Could not find the 'last_viewed_at' column of 'artworks' in the schema cache`

这表示 Supabase 的 schema cache 没有更新，需要执行迁移脚本并刷新 cache。

**注意**：代码已经更新，在 POST 请求时会自动排除 `last_viewed_at` 字段，以避免 schema cache 错误。但为了完整功能，仍建议执行迁移脚本添加该列。

## 解决步骤

### 步骤 1: 执行迁移脚本

1. 登录 Supabase Dashboard
2. 进入 **SQL Editor**
3. 执行以下迁移脚本（按顺序）：

```sql
-- 006_rename_biography_to_artist_introduction.sql
-- Step 1: Rename biography to artist_introduction in artists table
ALTER TABLE artists RENAME COLUMN biography TO artist_introduction;

-- Step 2: Remove artist_introduction columns from artworks table (if they exist)
ALTER TABLE artworks DROP COLUMN IF EXISTS artist_introduction;
ALTER TABLE artworks DROP COLUMN IF EXISTS artist_introduction_en;

-- 007_add_last_viewed_at_if_missing.sql
-- Step 3: Add last_viewed_at column if missing
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'artworks' 
        AND column_name = 'last_viewed_at'
    ) THEN
        ALTER TABLE artworks ADD COLUMN last_viewed_at TIMESTAMP;
    END IF;
END $$;
```

### 步骤 2: 验证表结构

在 SQL Editor 中执行以下查询，确认列已正确创建/重命名：

```sql
-- 检查 artists 表结构
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'artists' 
ORDER BY ordinal_position;

-- 检查 artworks 表结构
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'artworks' 
ORDER BY ordinal_position;
```

应该看到：
- `artists` 表有 `artist_introduction` 列（不是 `biography`）
- `artworks` 表有 `last_viewed_at` 列
- `artworks` 表**没有** `artist_introduction` 列

### 步骤 3: 刷新 Schema Cache

Supabase 的 PostgREST 会自动刷新 schema cache，但有时需要手动触发：

#### 方法 1: 通过 API 刷新（推荐）

在终端执行：

```bash
curl -X POST "https://YOUR_PROJECT_REF.supabase.co/rest/v1/rpc/refresh_schema_cache" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_ANON_KEY"
```

#### 方法 2: 等待自动刷新

PostgREST 通常会在几分钟内自动刷新。等待 2-5 分钟后重试。

#### 方法 3: 重启 Supabase 项目

1. 在 Supabase Dashboard 中进入 **Settings** → **General**
2. 点击 **Restart Project**（如果可用）
3. 等待项目重启完成

### 步骤 4: 验证修复

1. 重新运行应用
2. 尝试识别一个作品
3. 检查日志，应该不再出现 schema cache 错误

## 如果问题仍然存在

### 检查 RLS 策略

确保 RLS 策略允许访问这些列：

```sql
-- 检查 artists 表的 RLS 策略
SELECT * FROM pg_policies WHERE tablename = 'artists';

-- 检查 artworks 表的 RLS 策略
SELECT * FROM pg_policies WHERE tablename = 'artworks';
```

### 检查列权限

确保 anon key 有权限访问这些列：

```sql
-- 检查 artists 表的权限
SELECT grantee, privilege_type 
FROM information_schema.role_table_grants 
WHERE table_name = 'artists';

-- 检查 artworks 表的权限
SELECT grantee, privilege_type 
FROM information_schema.role_table_grants 
WHERE table_name = 'artworks';
```

## 常见问题

### Q: 迁移脚本执行失败

**A**: 检查：
1. 是否已经执行过部分迁移（例如，`biography` 列可能已经不存在）
2. 使用 `IF EXISTS` 或 `IF NOT EXISTS` 来避免错误
3. 检查是否有其他依赖关系

### Q: Schema cache 刷新后仍然报错

**A**: 
1. 等待更长时间（最多 10 分钟）
2. 检查列名是否正确（大小写敏感）
3. 确认使用的是正确的项目 URL 和 API Key

### Q: 如何确认 schema cache 已刷新

**A**: 
1. 在 Supabase Dashboard → **API** → **REST** 中查看表结构
2. 如果看到正确的列名，说明 cache 已更新
3. 或者通过 API 查询表结构：

```bash
curl "https://YOUR_PROJECT_REF.supabase.co/rest/v1/artists?limit=0" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_ANON_KEY"
```

如果返回 200 且没有 schema 错误，说明 cache 已更新。

