-- Tally company master + non-breaking columns on existing tables
-- Run in Supabase SQL Editor. Safe to re-run (IF NOT EXISTS / ADD COLUMN IF NOT EXISTS).
-- Does NOT rename tally_companies, company_id, branch_id, or row Guid.
-- App keeps using branch_id / Guid. Sync uses tally_company + tally_guid.

-- ---------------------------------------------------------------------------
-- 1. Real Tally company (the Tally books / company file)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tally_company_master (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tally_company_name text NOT NULL,
  tally_guid text UNIQUE,
  company_number text,
  company_alias text,
  address_line1 text,
  address_line2 text,
  city text,
  state text,
  pin_code text,
  country text DEFAULT 'India'::text,
  phone_number text,
  email text,
  gst_number text,
  pan_number text,
  tan_number text,
  financial_year_start_date date,
  financial_year_end_date date,
  tally_server_url text,
  tally_port integer DEFAULT 9000,
  tally_username text,
  tally_password text,
  is_active boolean DEFAULT true,
  last_synced_at timestamp with time zone,
  sync_status text DEFAULT 'pending'::text,
  sync_error_message text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tally_company_master_guid
  ON public.tally_company_master (tally_guid);

CREATE INDEX IF NOT EXISTS idx_tally_company_master_name
  ON public.tally_company_master (tally_company_name);

COMMENT ON TABLE public.tally_company_master IS
  'Original Tally company file (name + company GUID). Branches belong to this. Not used by the app UI.';

COMMENT ON COLUMN public.tally_company_master.tally_guid IS
  'Tally company GUID (CMPGUID). Used by sync as SVCurrentCompany identity.';

GRANT SELECT, INSERT, UPDATE, DELETE ON public.tally_company_master
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Branch is owned by a Tally company (source of truth)
--    Adds name/guid/number if this database never had them (new app DBs).
-- ---------------------------------------------------------------------------
ALTER TABLE public.branches
  ADD COLUMN IF NOT EXISTS tally_company_id uuid,
  ADD COLUMN IF NOT EXISTS tally_company text,
  ADD COLUMN IF NOT EXISTS tally_guid text,
  ADD COLUMN IF NOT EXISTS company_number text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'branches_tally_company_id_fkey'
  ) THEN
    ALTER TABLE public.branches
      ADD CONSTRAINT branches_tally_company_id_fkey
      FOREIGN KEY (tally_company_id)
      REFERENCES public.tally_company_master(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_branches_tally_company_id
  ON public.branches (tally_company_id);

COMMENT ON COLUMN public.branches.tally_company_id IS
  'FK to real Tally company. App continues to use branches.Guid.';

-- ---------------------------------------------------------------------------
-- 3. Transaction tables: copy Tally company name + guid for sync
--    Nullable. App does not read these columns.
-- ---------------------------------------------------------------------------
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS tally_company_id uuid,
  ADD COLUMN IF NOT EXISTS tally_company text,
  ADD COLUMN IF NOT EXISTS tally_guid text;

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS tally_company_id uuid,
  ADD COLUMN IF NOT EXISTS tally_company text,
  ADD COLUMN IF NOT EXISTS tally_guid text;

ALTER TABLE public.service_reminders
  ADD COLUMN IF NOT EXISTS tally_company_id uuid,
  ADD COLUMN IF NOT EXISTS tally_company text,
  ADD COLUMN IF NOT EXISTS tally_guid text;

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS tally_company_id uuid,
  ADD COLUMN IF NOT EXISTS tally_company text,
  ADD COLUMN IF NOT EXISTS tally_guid text,
  ADD COLUMN IF NOT EXISTS company_number text,
  ADD COLUMN IF NOT EXISTS alter_id text,
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS voucher_type text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'bookings_tally_company_id_fkey'
  ) THEN
    ALTER TABLE public.bookings
      ADD CONSTRAINT bookings_tally_company_id_fkey
      FOREIGN KEY (tally_company_id) REFERENCES public.tally_company_master(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reports_tally_company_id_fkey'
  ) THEN
    ALTER TABLE public.reports
      ADD CONSTRAINT reports_tally_company_id_fkey
      FOREIGN KEY (tally_company_id) REFERENCES public.tally_company_master(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'payments_tally_company_id_fkey'
  ) THEN
    ALTER TABLE public.payments
      ADD CONSTRAINT payments_tally_company_id_fkey
      FOREIGN KEY (tally_company_id) REFERENCES public.tally_company_master(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'service_reminders_tally_company_id_fkey'
  ) THEN
    ALTER TABLE public.service_reminders
      ADD CONSTRAINT service_reminders_tally_company_id_fkey
      FOREIGN KEY (tally_company_id) REFERENCES public.tally_company_master(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_bookings_tally_company_id
  ON public.bookings (tally_company_id);
CREATE INDEX IF NOT EXISTS idx_reports_tally_company_id
  ON public.reports (tally_company_id);
CREATE INDEX IF NOT EXISTS idx_payments_tally_company_id
  ON public.payments (tally_company_id);
CREATE INDEX IF NOT EXISTS idx_service_reminders_tally_company_id
  ON public.service_reminders (tally_company_id);

-- ---------------------------------------------------------------------------
-- 4. Auto-copy Tally company from branch on insert/update
--    App keeps writing only branch_id. Sync columns fill themselves.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fill_tally_company_from_branch()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
  v_name text;
  v_guid text;
BEGIN
  IF NEW.branch_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT b.tally_company_id, b.tally_company, b.tally_guid
    INTO v_id, v_name, v_guid
  FROM public.branches b
  WHERE b.id = NEW.branch_id;

  IF v_id IS NULL AND v_name IS NULL AND v_guid IS NULL THEN
    RETURN NEW;
  END IF;

  NEW.tally_company_id := COALESCE(NEW.tally_company_id, v_id);
  NEW.tally_company := COALESCE(NEW.tally_company, v_name);
  NEW.tally_guid := COALESCE(NEW.tally_guid, v_guid);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bookings_fill_tally_company ON public.bookings;
CREATE TRIGGER trg_bookings_fill_tally_company
  BEFORE INSERT OR UPDATE OF branch_id
  ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.fill_tally_company_from_branch();

DROP TRIGGER IF EXISTS trg_reports_fill_tally_company ON public.reports;
CREATE TRIGGER trg_reports_fill_tally_company
  BEFORE INSERT OR UPDATE OF branch_id
  ON public.reports
  FOR EACH ROW
  EXECUTE FUNCTION public.fill_tally_company_from_branch();

DROP TRIGGER IF EXISTS trg_payments_fill_tally_company ON public.payments;
CREATE TRIGGER trg_payments_fill_tally_company
  BEFORE INSERT OR UPDATE OF branch_id
  ON public.payments
  FOR EACH ROW
  EXECUTE FUNCTION public.fill_tally_company_from_branch();

DROP TRIGGER IF EXISTS trg_service_reminders_fill_tally_company ON public.service_reminders;
CREATE TRIGGER trg_service_reminders_fill_tally_company
  BEFORE INSERT OR UPDATE OF branch_id
  ON public.service_reminders
  FOR EACH ROW
  EXECUTE FUNCTION public.fill_tally_company_from_branch();

-- When a branch is linked to a Tally company, push name/guid onto the branch row
CREATE OR REPLACE FUNCTION public.fill_branch_tally_company_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_name text;
  v_guid text;
  v_number text;
BEGIN
  IF NEW.tally_company_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT m.tally_company_name, m.tally_guid, m.company_number
    INTO v_name, v_guid, v_number
  FROM public.tally_company_master m
  WHERE m.id = NEW.tally_company_id;

  NEW.tally_company := COALESCE(NEW.tally_company, v_name);
  NEW.tally_guid := COALESCE(NEW.tally_guid, v_guid);
  NEW.company_number := COALESCE(NEW.company_number, v_number);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_branches_fill_tally_company ON public.branches;
CREATE TRIGGER trg_branches_fill_tally_company
  BEFORE INSERT OR UPDATE OF tally_company_id
  ON public.branches
  FOR EACH ROW
  EXECUTE FUNCTION public.fill_branch_tally_company_fields();

-- ---------------------------------------------------------------------------
-- 5. Seed master from existing branch tally fields (if already filled)
-- ---------------------------------------------------------------------------
INSERT INTO public.tally_company_master (tally_company_name, tally_guid, company_number)
SELECT DISTINCT ON (COALESCE(b.tally_guid, b.tally_company))
  COALESCE(NULLIF(b.tally_company, ''), 'Unknown Tally Company'),
  NULLIF(b.tally_guid, ''),
  NULLIF(b.company_number, '')
FROM public.branches b
WHERE (NULLIF(b.tally_company, '') IS NOT NULL OR NULLIF(b.tally_guid, '') IS NOT NULL)
  AND NOT EXISTS (
    SELECT 1
    FROM public.tally_company_master m
    WHERE (NULLIF(b.tally_guid, '') IS NOT NULL AND m.tally_guid = b.tally_guid)
       OR (
         NULLIF(b.tally_guid, '') IS NULL
         AND m.tally_company_name = b.tally_company
       )
  );

-- Link branches to the seeded master
UPDATE public.branches b
SET tally_company_id = m.id
FROM public.tally_company_master m
WHERE b.tally_company_id IS NULL
  AND (
    (NULLIF(b.tally_guid, '') IS NOT NULL AND b.tally_guid = m.tally_guid)
    OR (
      NULLIF(b.tally_guid, '') IS NULL
      AND NULLIF(b.tally_company, '') IS NOT NULL
      AND b.tally_company = m.tally_company_name
    )
  );

-- Backfill transaction rows from their branch
UPDATE public.bookings x
SET
  tally_company_id = b.tally_company_id,
  tally_company = b.tally_company,
  tally_guid = b.tally_guid
FROM public.branches b
WHERE x.branch_id = b.id
  AND x.tally_company_id IS NULL
  AND b.tally_company_id IS NOT NULL;

UPDATE public.reports x
SET
  tally_company_id = b.tally_company_id,
  tally_company = b.tally_company,
  tally_guid = b.tally_guid
FROM public.branches b
WHERE x.branch_id = b.id
  AND x.tally_company_id IS NULL
  AND b.tally_company_id IS NOT NULL;

UPDATE public.payments x
SET
  tally_company_id = COALESCE(x.tally_company_id, b.tally_company_id),
  tally_company = COALESCE(NULLIF(x.tally_company, ''), b.tally_company),
  tally_guid = COALESCE(NULLIF(x.tally_guid, ''), b.tally_guid)
FROM public.branches b
WHERE x.branch_id = b.id
  AND (
    x.tally_company_id IS NULL
    OR NULLIF(x.tally_company, '') IS NULL
    OR NULLIF(x.tally_guid, '') IS NULL
  )
  AND b.tally_company_id IS NOT NULL;

UPDATE public.service_reminders x
SET
  tally_company_id = b.tally_company_id,
  tally_company = b.tally_company,
  tally_guid = b.tally_guid
FROM public.branches b
WHERE x.branch_id = b.id
  AND x.tally_company_id IS NULL
  AND b.tally_company_id IS NOT NULL;
