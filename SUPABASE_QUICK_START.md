# Supabase 快速开始指南

## 5分钟快速设置

### 1. 创建 Supabase 项目（2分钟）

1. 访问 https://supabase.com 并登录
2. 点击 **"New Project"**
3. 填写项目信息：
   - Name: `muse-lens`
   - Database Password: （设置一个强密码并保存）
   - Region: 选择最近的地域
   - Plan: Free
4. 点击 **"Create new project"** 并等待创建完成

### 2. 获取配置信息（1分钟）

1. 进入项目 → Settings → API
2. 复制 **Project URL**（例如：`https://xxxxx.supabase.co`）
3. 复制 **anon key**（点击 Reveal 显示）

### 3. 执行数据库迁移（1分钟）

1. 进入项目 → SQL Editor
2. 按顺序执行以下 SQL 文件：

**文件 1: 创建 artworks 表**
```sql
-- 复制 database/migrations/001_create_artworks_table.sql 的内容并执行
```

**文件 2: 创建 artists 表**
```sql
-- 复制 database/migrations/002_create_artists_table.sql 的内容并执行
```

**文件 3: 创建索引**
```sql
-- 复制 database/migrations/003_create_indexes.sql 的内容并执行
```

**文件 4: 创建函数**
```sql
-- 复制 database/migrations/004_create_functions.sql 的内容并执行
```

**文件 5: 创建 RLS 策略**
```sql
-- 复制 database/migrations/005_create_rls_policies.sql 的内容并执行
```

### 4. 配置 Xcode（1分钟）

1. 在 Xcode 中：Product → Scheme → Edit Scheme
2. Run → Arguments → Environment Variables
3. 添加两个环境变量：

```
BACKEND_API_URL = https://your-project.supabase.co
BACKEND_API_KEY = your-anon-key
```

4. 点击 Close 保存

### 5. 测试连接

运行应用，在 `DatabaseTestView` 中测试连接。

## 完成！

现在你的应用已经配置好 Supabase 后端缓存了。

详细步骤请参考 [SUPABASE_SETUP_GUIDE.md](./SUPABASE_SETUP_GUIDE.md)

