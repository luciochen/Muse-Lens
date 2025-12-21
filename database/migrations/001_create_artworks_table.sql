-- ============================================
-- Artworks Table (主表)
-- ============================================
CREATE TABLE IF NOT EXISTS artworks (
    -- Primary Key
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Combined Identifier (唯一标识)
    combined_hash TEXT UNIQUE NOT NULL, -- SHA256(title|artist)
    normalized_title TEXT NOT NULL,
    normalized_artist TEXT NOT NULL,
    
    -- Artwork Information
    title TEXT NOT NULL, -- 原始标题（中文）
    title_en TEXT, -- 英文标题（可选）
    artist TEXT NOT NULL, -- 艺术家名称（中文）
    artist_en TEXT, -- 英文艺术家名称（可选）
    year TEXT, -- 创作年份
    style TEXT, -- 艺术风格
    medium TEXT, -- 创作媒介
    museum TEXT, -- 收藏博物馆
    image_url TEXT, -- 作品图片URL
    sources TEXT[], -- 信息来源数组
    
    -- Narration Content
    narration TEXT NOT NULL, -- 作品讲解（中文，500-600字）
    narration_en TEXT, -- 英文讲解（可选，为多语言支持做准备）
    summary TEXT, -- 摘要
    
    -- Metadata
    confidence REAL NOT NULL DEFAULT 0.0, -- 识别置信度 (0.0-1.0)
    recognized BOOLEAN NOT NULL DEFAULT true, -- 是否为具体作品（true）还是风格描述（false）
    
    -- Statistics
    view_count INTEGER DEFAULT 0, -- 查看次数（热门作品统计）
    last_viewed_at TIMESTAMP, -- 最后查看时间
    
    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT confidence_range CHECK (confidence >= 0.0 AND confidence <= 1.0),
    CONSTRAINT high_confidence_required CHECK (
        (confidence >= 0.8 AND recognized = true) OR 
        (confidence < 0.8)
    )
);

-- ============================================
-- Indexes (索引优化)
-- ============================================
-- 主查询索引：combined_hash (唯一标识查询)
CREATE UNIQUE INDEX IF NOT EXISTS idx_artworks_combined_hash ON artworks(combined_hash);

-- 标题和艺术家查询索引
CREATE INDEX IF NOT EXISTS idx_artworks_title_artist ON artworks(normalized_title, normalized_artist);

-- 置信度索引（只索引高置信度作品，用于快速检索）
CREATE INDEX IF NOT EXISTS idx_artworks_high_confidence ON artworks(combined_hash) 
WHERE confidence >= 0.8 AND recognized = true;

-- 热门作品索引（按查看次数排序）
CREATE INDEX IF NOT EXISTS idx_artworks_popular ON artworks(view_count DESC, last_viewed_at DESC) 
WHERE confidence >= 0.8;

-- 全文搜索索引（用于后续的搜索功能）
CREATE INDEX IF NOT EXISTS idx_artworks_search ON artworks USING gin(
    to_tsvector('english', coalesce(title, '') || ' ' || coalesce(artist, '') || ' ' || coalesce(style, ''))
);

