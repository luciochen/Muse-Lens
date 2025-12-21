-- ============================================
-- Migration: Rename biography to artist_introduction in artists table
-- Remove artist_introduction from artworks table
-- ============================================

-- Step 1: Rename biography column to artist_introduction in artists table
ALTER TABLE artists RENAME COLUMN biography TO artist_introduction;

-- Step 2: Remove artist_introduction columns from artworks table
ALTER TABLE artworks DROP COLUMN IF EXISTS artist_introduction;
ALTER TABLE artworks DROP COLUMN IF EXISTS artist_introduction_en;

-- Step 3: Update RLS policy comment (if needed)
-- The policy itself doesn't need to change, just the column name reference

