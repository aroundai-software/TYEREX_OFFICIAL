-- ============================================================================
-- TyreX Tally Sync - Client Live Database Migration
-- Target: Run in Supabase SQL Editor
-- Safe, clean, and 100% idempotent
-- ============================================================================

-- 1. Ensure alter_id, tally_sync_status, and is_converted exist on reports table
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS alter_id INTEGER DEFAULT 0;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS tally_sync_status TEXT DEFAULT 'pending';
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS is_converted BOOLEAN DEFAULT false;

-- 2. Ensure alter_id exists on tally_posted_sales (if table already exists from earlier migrations)
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

-- STEP 3: Create or replace revision trigger function
CREATE OR REPLACE FUNCTION public.handle_jobcard_revision()
RETURNS TRIGGER AS $$
BEGIN
    -- Only trigger when a completed, billed, or previously synced job card is edited:
    IF (OLD.status IN ('completed', 'billed', 'closed') OR OLD.tally_sync_status = 'synced') THEN
        IF (NEW.complaint IS DISTINCT FROM OLD.complaint OR
            NEW.suggested IS DISTINCT FROM OLD.suggested OR
            NEW.approved IS DISTINCT FROM OLD.approved OR
            NEW.materials_required IS DISTINCT FROM OLD.materials_required OR
            NEW.discount_amount IS DISTINCT FROM OLD.discount_amount OR
            NEW.discount_type IS DISTINCT FROM OLD.discount_type OR
            NEW.extra_charge_amount IS DISTINCT FROM OLD.extra_charge_amount OR
            NEW.labour_cost IS DISTINCT FROM OLD.labour_cost OR
            NEW.gst_percent IS DISTINCT FROM OLD.gst_percent) THEN
            
            -- Increment alter revision counter
            NEW.alter_id := COALESCE(OLD.alter_id, 0) + 1;
            -- Flag as pending for Tally sync pickup
            NEW.tally_sync_status := 'pending';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- STEP 4: Attach trigger
DROP TRIGGER IF EXISTS trg_jobcard_revision ON public.reports;
CREATE TRIGGER trg_jobcard_revision
BEFORE UPDATE ON public.reports
FOR EACH ROW
EXECUTE FUNCTION public.handle_jobcard_revision();

-- STEP 5: Index for fast sync pickup
CREATE INDEX IF NOT EXISTS idx_reports_tally_sync_alter 
ON public.reports (tally_sync_status, alter_id) 
WHERE tally_sync_status = 'pending';
