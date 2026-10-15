-- Party ledgers imported from Tally (Sundry Debtors only).
-- Does not change owner_master.Guid (that column is the app/branch identity).
-- Run in Supabase SQL Editor. Safe to re-run.

CREATE TABLE IF NOT EXISTS public.tally_ledgers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tally_company_id uuid REFERENCES public.tally_company_master(id),
  tally_company text,
  tally_company_guid text,
  name text NOT NULL,
  guid text,
  master_id bigint,
  parent_group text,
  mailing_name text,
  alias text,
  aliases jsonb,
  address_line1 text,
  address_line2 text,
  address_line3 text,
  state text,
  country text,
  pincode text,
  phone text,
  mobile text,
  email text,
  gstin text,
  pan text,
  opening_balance numeric,
  opening_balance_text text,
  closing_balance numeric,
  closing_balance_text text,
  is_billwise boolean,
  extra jsonb,
  last_synced_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT tally_ledgers_guid_unique UNIQUE (guid),
  CONSTRAINT tally_ledgers_company_guid_key UNIQUE (tally_company_id, guid)
);

CREATE INDEX IF NOT EXISTS idx_tally_ledgers_company
  ON public.tally_ledgers (tally_company_id);

CREATE INDEX IF NOT EXISTS idx_tally_ledgers_name
  ON public.tally_ledgers (name);

CREATE INDEX IF NOT EXISTS idx_tally_ledgers_parent
  ON public.tally_ledgers (parent_group);

CREATE INDEX IF NOT EXISTS idx_tally_ledgers_phone
  ON public.tally_ledgers (phone);

CREATE INDEX IF NOT EXISTS idx_tally_ledgers_gstin
  ON public.tally_ledgers (gstin);

COMMENT ON TABLE public.tally_ledgers IS
  'Sundry Debtors party ledgers imported from Tally. owner_master.Guid stays the branch identity.';

GRANT SELECT, INSERT, UPDATE, DELETE ON public.tally_ledgers
  TO anon, authenticated, service_role;
