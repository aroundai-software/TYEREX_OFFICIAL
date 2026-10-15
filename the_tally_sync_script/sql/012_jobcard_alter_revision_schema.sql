-- ============================================================================
-- Migration 012: Job Card Alteration & Revision Schema
-- 
-- Description:
-- When a completed or billed job card is edited by an executive:
-- 1. `alter_id` is incremented (revision counter: 1, 2, 3...).
-- 2. `tally_sync_status` resets to 'pending' so the sync script picks it up.
-- 3. In Tally, the Python sync script creates a NEW Job Card revision
--    (e.g., TYX2026005-A1) while preserving the original Job Card completely.
-- ============================================================================

-- 1. Add alter_id column to reports table if not already present
ALTER TABLE public.reports 
ADD COLUMN IF NOT EXISTS alter_id INTEGER DEFAULT 0;

-- 2. Ensure tally_sync_status column exists on reports table
ALTER TABLE public.reports 
ADD COLUMN IF NOT EXISTS tally_sync_status TEXT DEFAULT 'pending';

-- 3. Ensure alter_id exists on tally_posted_sales
CREATE TABLE IF NOT EXISTS public.tally_posted_sales (
    id BIGSERIAL PRIMARY KEY,
    report_id BIGINT,
    jobcard_number TEXT,
    company_guid TEXT,
    voucher_type TEXT,
    remote_id TEXT UNIQUE,
    alter_id INTEGER DEFAULT 0,
    synced_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.tally_posted_sales ADD COLUMN IF NOT EXISTS alter_id INTEGER DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_tally_posted_sales_report 
ON public.tally_posted_sales (report_id, alter_id);

-- 4. Create or replace trigger function to auto-track revisions on completed/billed reports
CREATE OR REPLACE FUNCTION public.handle_jobcard_revision()
RETURNS TRIGGER AS $$
BEGIN
    -- If the report was already completed, billed, or synced and its billable data changed
    IF (OLD.status IN ('completed', 'billed', 'closed') OR OLD.tally_sync_status = 'synced') THEN
        -- Only increment if billable items, amounts, or complaints actually changed
        IF (NEW.complaint IS DISTINCT FROM OLD.complaint OR
            NEW.suggested IS DISTINCT FROM OLD.suggested OR
            NEW.approved IS DISTINCT FROM OLD.approved OR
            NEW.materials_required IS DISTINCT FROM OLD.materials_required OR
            NEW.discount_amount IS DISTINCT FROM OLD.discount_amount OR
            NEW.discount_type IS DISTINCT FROM OLD.discount_type OR
            NEW.extra_charge_amount IS DISTINCT FROM OLD.extra_charge_amount OR
            NEW.labour_cost IS DISTINCT FROM OLD.labour_cost OR
            NEW.gst_percent IS DISTINCT FROM OLD.gst_percent) THEN
            
            NEW.alter_id := COALESCE(OLD.alter_id, 0) + 1;
            NEW.tally_sync_status := 'pending';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Drop trigger if already exists and re-create
DROP TRIGGER IF EXISTS trg_jobcard_revision ON public.reports;
CREATE TRIGGER trg_jobcard_revision
BEFORE UPDATE ON public.reports
FOR EACH ROW
EXECUTE FUNCTION public.handle_jobcard_revision();

-- 5. Index for fast sync querying
CREATE INDEX IF NOT EXISTS idx_reports_tally_sync_alter 
ON public.reports (tally_sync_status, alter_id) 
WHERE tally_sync_status = 'pending';
