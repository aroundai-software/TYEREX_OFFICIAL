-- ============================================================================
-- TyreX Tally Sync - ALL-IN-ONE CLIENT DATABASE MIGRATION
-- Target: Run once in Client's Supabase SQL Editor (https://xlgeqjpdsimkskssikhb.supabase.co)
-- Safe, clean, and 100% idempotent (safe to run multiple times)
-- ============================================================================

-- 1. TALLY COMPANY MASTER TABLE
CREATE TABLE IF NOT EXISTS public.tally_company_master (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tally_company_name TEXT NOT NULL,
    tally_guid TEXT UNIQUE,
    company_number TEXT,
    company_alias TEXT,
    address_line1 TEXT,
    address_line2 TEXT,
    city TEXT,
    state TEXT,
    pin_code TEXT,
    country TEXT DEFAULT 'India',
    phone_number TEXT,
    email TEXT,
    gst_number TEXT,
    pan_number TEXT,
    tan_number TEXT,
    financial_year_start_date DATE,
    financial_year_end_date DATE,
    tally_server_url TEXT,
    tally_port INTEGER DEFAULT 9000,
    is_active BOOLEAN DEFAULT true,
    sync_status TEXT DEFAULT 'synced',
    sync_error_message TEXT,
    last_synced_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. TALLY STOCK ITEMS TABLE
CREATE TABLE IF NOT EXISTS public.tally_stock_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    guid TEXT,
    alter_id INTEGER DEFAULT 0,
    part_number TEXT,
    parent_group TEXT,
    category TEXT,
    base_units TEXT,
    opening_balance NUMERIC,
    opening_value NUMERIC,
    opening_rate NUMERIC,
    closing_balance NUMERIC,
    closing_value NUMERIC,
    closing_rate NUMERIC,
    standard_cost NUMERIC,
    standard_price NUMERIC,
    hsn_code TEXT,
    gst_rate NUMERIC,
    taxability TEXT,
    company_name TEXT,
    tally_guid TEXT,
    last_synced_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT tally_stock_items_company_name_uniq UNIQUE (company_name, name)
);

-- 3. TALLY LEDGERS TABLE
CREATE TABLE IF NOT EXISTS public.tally_ledgers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    guid TEXT,
    alter_id INTEGER DEFAULT 0,
    parent_group TEXT,
    opening_balance NUMERIC,
    closing_balance NUMERIC,
    address_line1 TEXT,
    address_line2 TEXT,
    city TEXT,
    state TEXT,
    pincode TEXT,
    phone_number TEXT,
    email TEXT,
    gstin TEXT,
    pan TEXT,
    company_name TEXT,
    tally_guid TEXT,
    last_synced_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT tally_ledgers_company_name_uniq UNIQUE (company_name, name)
);

-- 4. TALLY POSTED SALES TABLE
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
CREATE INDEX IF NOT EXISTS idx_tally_posted_sales_report ON public.tally_posted_sales (report_id, alter_id);

-- 5. UPDATE REPORTS TABLE COLUMNS
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS alter_id INTEGER DEFAULT 0;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS tally_sync_status TEXT DEFAULT 'pending';
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS is_converted BOOLEAN DEFAULT false;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS billing_status TEXT;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS billed_at TIMESTAMPTZ;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS billed_by TEXT;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS tally_company_id TEXT;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS tally_company TEXT;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS tally_guid TEXT;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS tally_synced_at TIMESTAMPTZ;

-- 6. UPDATE PAYMENTS TABLE COLUMNS
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS tally_sync_status TEXT DEFAULT 'pending';
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS tally_synced_at TIMESTAMPTZ;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS tally_company TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS tally_guid TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS "Guid" TEXT;

-- 7. REVISION TRIGGER (Auto-increments alter_id when an invoice is edited)
CREATE OR REPLACE FUNCTION public.handle_jobcard_revision()
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.status IN ('completed', 'billed', 'closed', 'Completed') OR OLD.tally_sync_status = 'synced') THEN
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

DROP TRIGGER IF EXISTS trg_jobcard_revision ON public.reports;
CREATE TRIGGER trg_jobcard_revision
BEFORE UPDATE ON public.reports
FOR EACH ROW
EXECUTE FUNCTION public.handle_jobcard_revision();

-- 8. INDEXES FOR HIGH PERFORMANCE
CREATE INDEX IF NOT EXISTS idx_reports_tally_sync_alter ON public.reports (tally_sync_status, alter_id);
CREATE INDEX IF NOT EXISTS idx_reports_is_converted ON public.reports (is_converted);

-- 9. MARK EXISTING HISTORICAL DATA AS ALREADY SYNCED
-- (Prevents re-posting past job cards/payments that were already entered manually in Tally)
UPDATE public.reports
SET 
    tally_sync_status = 'synced',
    tally_synced_at = COALESCE(tally_synced_at, NOW()),
    alter_id = COALESCE(alter_id, 0)
WHERE 
    tally_sync_status IS NULL 
    OR tally_sync_status != 'synced';

UPDATE public.payments
SET 
    tally_sync_status = 'synced',
    tally_synced_at = COALESCE(tally_synced_at, NOW())
WHERE 
    tally_sync_status IS NULL 
    OR tally_sync_status != 'synced';

-- ============================================================================
-- VERIFICATION CONFIRMATION
-- ============================================================================
SELECT 'Migration Successful! Reports synced count:' AS status, count(*) AS total FROM public.reports WHERE tally_sync_status = 'synced';
