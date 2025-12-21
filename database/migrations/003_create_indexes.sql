-- ============================================
-- Additional Indexes
-- ============================================

-- User recognition logs table (optional, for analytics)
CREATE TABLE IF NOT EXISTS user_recognitions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    artwork_id UUID REFERENCES artworks(id) ON DELETE CASCADE,
    user_device_id TEXT, -- 设备ID（不存储个人身份信息）
    recognition_confidence REAL, -- 用户识别的置信度
    recognized_at TIMESTAMP DEFAULT NOW(),
    
    -- 用于统计和分析
    recognition_source TEXT, -- 识别来源（如 'vision_api', 'manual'）
    
    CONSTRAINT fk_artwork FOREIGN KEY (artwork_id) REFERENCES artworks(id)
);

CREATE INDEX IF NOT EXISTS idx_user_recognitions_artwork ON user_recognitions(artwork_id);
CREATE INDEX IF NOT EXISTS idx_user_recognitions_device ON user_recognitions(user_device_id);

