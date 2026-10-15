-- Unique GUID so stock sync updates existing rows instead of inserting duplicates.
-- Run in Supabase SQL Editor.

DELETE FROM public.tally_stock_items a
USING public.tally_stock_items b
WHERE a.guid IS NOT NULL
  AND a.guid = b.guid
  AND a.ctid < b.ctid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'tally_stock_items_guid_unique'
  ) THEN
    ALTER TABLE public.tally_stock_items
      ADD CONSTRAINT tally_stock_items_guid_unique UNIQUE (guid);
  END IF;
END $$;
