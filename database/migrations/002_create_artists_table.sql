-- ============================================
-- Artists Table (艺术家表，用于快速检索)
-- ============================================
CREATE TABLE IF NOT EXISTS artists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL, -- 艺术家名称（中文）
    name_en TEXT, -- 英文名称
    normalized_name TEXT NOT NULL, -- 标准化名称（用于匹配）
    artist_introduction TEXT, -- 艺术家介绍（300-400字）
    artworks_count INTEGER DEFAULT 0, -- 作品数量
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_artists_normalized_name ON artists(normalized_name);

