-- Link app tally_companies + branches to the real Tally company.
-- Does NOT change Guid, company_id, or app behaviour.
-- Run in Supabase SQL Editor.

-- ---------------------------------------------------------------------------
-- 1. App "company" rows point at the real Tally company
-- ---------------------------------------------------------------------------
ALTER TABLE public.tally_companies
  ADD COLUMN IF NOT EXISTS tally_company_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'tally_companies_tally_company_id_fkey'
  ) THEN
    ALTER TABLE public.tally_companies
      ADD CONSTRAINT tally_companies_tally_company_id_fkey
      FOREIGN KEY (tally_company_id)
      REFERENCES public.tally_company_master(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_tally_companies_tally_company_id
  ON public.tally_companies (tally_company_id);

COMMENT ON COLUMN public.tally_companies.tally_company_id IS
  'FK to real Tally company (tally_company_master). Guid on this table stays the app/branch identity.';

-- ---------------------------------------------------------------------------
-- 2. If you have ONLY one Tally company file, attach every app company + branch.
--    Comment this block out if Mumbai/Thrissur use a different Tally company.
-- ---------------------------------------------------------------------------
UPDATE public.tally_companies c
SET tally_company_id = m.id
FROM public.tally_company_master m
WHERE c.tally_company_id IS NULL
  AND (SELECT count(*) FROM public.tally_company_master) = 1;

UPDATE public.branches b
SET tally_company_id = m.id
FROM public.tally_company_master m
WHERE b.tally_company_id IS NULL
  AND (SELECT count(*) FROM public.tally_company_master) = 1;

-- Name/guid on branches are filled by trigger trg_branches_fill_tally_company.
-- Force-fill existing rows too:
UPDATE public.branches b
SET
  tally_company = COALESCE(NULLIF(b.tally_company, ''), m.tally_company_name),
  tally_guid = COALESCE(NULLIF(b.tally_guid, ''), m.tally_guid),
  company_number = COALESCE(NULLIF(b.company_number, ''), m.company_number)
FROM public.tally_company_master m
WHERE b.tally_company_id = m.id;

-- ---------------------------------------------------------------------------
-- 3. To link only some locations, use this instead of block 2:
--
-- UPDATE public.tally_companies
-- SET tally_company_id = 'cf465a50-f11d-44e2-8907-03f773fc2581'
-- WHERE company_name IN ('Kochi', 'thrissur', 'palakkad');
--
-- UPDATE public.branches
-- SET tally_company_id = 'cf465a50-f11d-44e2-8907-03f773fc2581'
-- WHERE branch_name IN ('Kochi', 'thrissur', 'palakkad');
-- ---------------------------------------------------------------------------
