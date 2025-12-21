-- ============================================
-- Row Level Security (RLS) - 公开读取，限制写入
-- ============================================

-- Enable RLS
ALTER TABLE artworks ENABLE ROW LEVEL SECURITY;
ALTER TABLE artists ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_recognitions ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Public read access for artworks" ON artworks;
DROP POLICY IF EXISTS "Public insert access for artworks" ON artworks;
DROP POLICY IF EXISTS "Update view count for artworks" ON artworks;
DROP POLICY IF EXISTS "Public read access for artists" ON artists;
DROP POLICY IF EXISTS "Public insert access for artists" ON artists;

-- Allow everyone to read artworks
CREATE POLICY "Public read access for artworks" ON artworks
    FOR SELECT USING (true);

-- Allow inserting new artworks (but only high-confidence ones)
CREATE POLICY "Public insert access for artworks" ON artworks
    FOR INSERT WITH CHECK (confidence >= 0.8 AND recognized = true);

-- Allow updating artworks (for content updates)
CREATE POLICY "Update artworks" ON artworks
    FOR UPDATE USING (true)
    WITH CHECK (true);

-- Allow updating view count (through function) - kept for backward compatibility
-- Note: The "Update artworks" policy above covers this, but keeping for clarity

-- Allow everyone to read artists
CREATE POLICY "Public read access for artists" ON artists
    FOR SELECT USING (true);

-- Allow inserting new artists
CREATE POLICY "Public insert access for artists" ON artists
    FOR INSERT WITH CHECK (true);

-- Allow updating artists (for biography updates)
CREATE POLICY "Public update access for artists" ON artists
    FOR UPDATE USING (true)
    WITH CHECK (true);

