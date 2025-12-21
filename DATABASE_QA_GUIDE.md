# 数据库QA测试指南

## 概述

本指南说明如何运行QA测试来验证艺术指南内容已正确上传到数据库。

## 快速开始

### 1. 访问数据库测试界面

在应用中，可以通过以下方式访问数据库测试界面：
- 在开发模式下，可以通过代码导航到 `DatabaseTestView`
- 或者添加一个测试入口按钮（开发模式）

### 2. 配置后端连接

1. 打开数据库测试界面
2. 输入后端URL（Supabase项目URL）
3. 输入后端API Key（Supabase anon key）
4. 点击"保存配置"

### 3. 运行QA测试

点击"运行完整QA测试"按钮，系统将自动执行以下测试：

## QA测试项目

### 1. 后端配置检查 ✅
- 验证后端URL和API Key是否已配置
- 显示配置状态

### 2. 数据库连接测试 ✅
- 测试与Supabase数据库的连接
- 验证网络连接和认证

### 3. 作品数据结构验证 ✅
- 检查作品数据是否包含所有必需字段
- 验证字段完整性：
  - 标题 (title)
  - 艺术家 (artist)
  - 年份 (year)
  - 风格 (style)
  - 讲解内容 (narration)
  - 艺术家介绍 (artistIntroduction)
  - 置信度 (confidence)

### 4. 讲解内容验证 ✅
- 检查数据库中是否有讲解内容
- 验证讲解内容长度（应≥500字符，对应500-600字）
- 检查多个知名作品（蒙娜丽莎、星夜、向日葵、睡莲等）

### 5. 艺术家介绍验证 ✅
- 检查数据库中是否有艺术家介绍
- 验证介绍内容长度（应≥300字符，对应300-400字）
- 检查多个知名艺术家（达芬奇、梵高、莫奈、毕加索等）

### 6. 数据统计 ✅
- 统计数据库中的作品数量
- 统计艺术家数量
- 计算平均讲解长度

### 7. 示例作品验证 ✅
- 创建并保存一个测试作品
- 验证保存功能
- 验证查询功能
- 检查讲解和艺术家介绍是否正确保存

### 8. 内容质量检查 ✅
- 检查讲解内容长度是否符合要求（≥500字符）
- 检查艺术家介绍长度是否符合要求（≥300字符）
- 识别质量问题

## 测试结果解读

### ✅ 通过 (绿色)
- 测试项目通过
- 数据符合要求

### ❌ 失败 (红色)
- 测试项目失败
- 查看错误信息了解原因

### 测试结果详情
每个测试结果包含：
- **测试名称**：测试项目名称
- **状态**：通过/失败
- **消息**：测试结果摘要
- **详情**：详细的测试信息
- **错误**：错误信息（如果有）

## 常见问题

### Q: 测试显示"后端未配置"
**A:** 需要在测试界面中配置后端URL和API Key。

### Q: 连接测试失败
**A:** 检查：
1. 网络连接
2. 后端URL是否正确
3. API Key是否正确
4. Supabase项目是否正常运行

### Q: 未找到作品/艺术家
**A:** 这是正常的，如果数据库中还没有该作品/艺术家。测试会继续检查其他项目。

### Q: 讲解内容长度不足
**A:** 检查：
1. 生成讲解时是否使用了正确的prompt（要求500-600字）
2. `max_tokens` 是否设置为3000
3. 讲解内容是否被正确保存到数据库

## 验证艺术指南内容已上传

运行QA测试后，检查以下项目：

1. **讲解内容验证**：应显示找到有讲解的作品
2. **艺术家介绍验证**：应显示找到有介绍的艺术家
3. **示例作品验证**：测试作品应能成功保存和查询
4. **内容质量检查**：讲解长度应≥500字符，介绍长度应≥300字符

如果所有测试通过，说明艺术指南内容已正确上传到数据库。

## 手动验证

除了运行QA测试，您也可以：

1. **在Supabase Dashboard中查看**：
   - 打开Supabase项目
   - 进入Table Editor
   - 查看 `artworks` 表
   - 检查 `narration` 字段是否有内容
   - 查看 `artists` 表
   - 检查 `biography` 字段是否有内容

2. **使用SQL查询**：
```sql
-- 查看所有有讲解的作品
SELECT title, artist, LENGTH(narration) as narration_length 
FROM artworks 
WHERE narration IS NOT NULL AND narration != ''
ORDER BY narration_length DESC;

-- 查看所有有介绍的艺术家
SELECT name, LENGTH(biography) as bio_length 
FROM artists 
WHERE biography IS NOT NULL AND biography != ''
ORDER BY bio_length DESC;

-- 统计信息
SELECT 
  COUNT(*) as total_artworks,
  COUNT(CASE WHEN narration IS NOT NULL AND narration != '' THEN 1 END) as artworks_with_narration,
  AVG(LENGTH(narration)) as avg_narration_length
FROM artworks;
```

## 下一步

如果QA测试通过：
- ✅ 艺术指南内容已正确上传
- ✅ 数据库结构正确
- ✅ 内容质量符合要求

如果QA测试失败：
- 检查错误信息
- 验证后端配置
- 检查网络连接
- 查看应用日志获取详细信息

