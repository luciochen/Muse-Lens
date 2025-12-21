-- ============================================
-- Migration: Add missing columns if they don't exist
-- ============================================

-- Add last_viewed_at column to artworks table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'artworks' 
        AND column_name = 'last_viewed_at'
    ) THEN
        ALTER TABLE artworks ADD COLUMN last_viewed_at TIMESTAMP;
        RAISE NOTICE 'Added last_viewed_at column to artworks table';
    ELSE
        RAISE NOTICE 'last_viewed_at column already exists in artworks table';
    END IF;
END $$;

-- Add view_count column to artworks table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'artworks' 
        AND column_name = 'view_count'
    ) THEN
        ALTER TABLE artworks ADD COLUMN view_count INTEGER DEFAULT 0;
        RAISE NOTICE 'Added view_count column to artworks table';
    ELSE
        RAISE NOTICE 'view_count column already exists in artworks table';
    END IF;
END $$;

