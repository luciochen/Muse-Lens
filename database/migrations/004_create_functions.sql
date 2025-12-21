-- ============================================
-- Database Functions
-- ============================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger for artworks table
DROP TRIGGER IF EXISTS update_artworks_updated_at ON artworks;
CREATE TRIGGER update_artworks_updated_at BEFORE UPDATE ON artworks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Trigger for artists table
DROP TRIGGER IF EXISTS update_artists_updated_at ON artists;
CREATE TRIGGER update_artists_updated_at BEFORE UPDATE ON artists
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Increment view count function
CREATE OR REPLACE FUNCTION increment_artwork_view_count(artwork_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE artworks 
    SET view_count = view_count + 1,
        last_viewed_at = NOW()
    WHERE id = artwork_id;
END;
$$ language 'plpgsql';

