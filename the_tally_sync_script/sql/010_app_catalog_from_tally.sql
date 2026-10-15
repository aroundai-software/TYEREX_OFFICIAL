-- Optional columns so Tally masters can land in the app tables the UI already reads.
-- owner_master.Guid stays the branch identity. Tally ledger GUID goes in tally_guid.
-- Run in Supabase SQL Editor. Safe to re-run.

ALTER TABLE public.owner_master
  ADD COLUMN IF NOT EXISTS tally_guid text;

CREATE UNIQUE INDEX IF NOT EXISTS idx_owner_master_tally_guid
  ON public.owner_master (tally_guid)
  WHERE tally_guid IS NOT NULL AND tally_guid <> '';

ALTER TABLE public.tyre_catalog
  ADD COLUMN IF NOT EXISTS Guid text,
  ADD COLUMN IF NOT EXISTS MasterID bigint,
  ADD COLUMN IF NOT EXISTS tally_name text;

ALTER TABLE public.materials
  ADD COLUMN IF NOT EXISTS Guid text,
  ADD COLUMN IF NOT EXISTS MasterID bigint,
  ADD COLUMN IF NOT EXISTS company_name text;

CREATE TABLE IF NOT EXISTS public.alloy_catalog (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand text NOT NULL,
  model text NOT NULL DEFAULT '',
  size text NOT NULL DEFAULT '',
  company_name text,
  basic_price numeric,
  billing_price numeric,
  Guid text,
  MasterID bigint,
  tally_name text,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.alloy_catalog
  ADD COLUMN IF NOT EXISTS Guid text,
  ADD COLUMN IF NOT EXISTS MasterID bigint,
  ADD COLUMN IF NOT EXISTS tally_name text,
  ADD COLUMN IF NOT EXISTS basic_price numeric,
  ADD COLUMN IF NOT EXISTS billing_price numeric,
  ADD COLUMN IF NOT EXISTS company_name text;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.alloy_catalog
  TO anon, authenticated, service_role;

DO $$
BEGIN
  GRANT USAGE, SELECT ON SEQUENCE public.alloy_catalog_id_seq
    TO anon, authenticated, service_role;
EXCEPTION
  WHEN undefined_table THEN
    NULL;
END $$;

COMMENT ON COLUMN public.owner_master.tally_guid IS
  'Tally party ledger GUID. owner_master.Guid remains the app/branch identity.';
