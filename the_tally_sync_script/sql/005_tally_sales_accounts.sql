-- Tally sales accounts (ledgers/groups under Sales Accounts).
-- Does not change public.service_catalog. Run in Supabase SQL Editor. Safe to re-run.

CREATE TABLE IF NOT EXISTS public.tally_sales_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tally_company_id uuid REFERENCES public.tally_company_master(id),
  tally_company text,
  tally_company_guid text,
  name text NOT NULL,
  guid text,
  master_id bigint,
  account_type text NOT NULL DEFAULT 'ledger',
  alias text,
  aliases jsonb,
  parent_group text,
  description text,
  mailing_name text,
  opening_balance numeric,
  opening_balance_text text,
  closing_balance numeric,
  closing_balance_text text,
  tax_type text,
  gst_applicable text,
  gst_type_of_supply text,
  gst_taxability text,
  hsn_code text,
  hsn_description text,
  gst_rate numeric,
  cgst_rate numeric,
  sgst_rate numeric,
  igst_rate numeric,
  cess_rate numeric,
  affects_stock boolean,
  is_billwise boolean,
  is_cost_centre boolean,
  is_revenue boolean,
  is_subledger boolean,
  gst_details jsonb,
  extra jsonb,
  last_synced_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT tally_sales_accounts_guid_unique UNIQUE (guid),
  CONSTRAINT tally_sales_accounts_company_guid_key UNIQUE (tally_company_id, guid)
);

CREATE INDEX IF NOT EXISTS idx_tally_sales_accounts_company
  ON public.tally_sales_accounts (tally_company_id);

CREATE INDEX IF NOT EXISTS idx_tally_sales_accounts_name
  ON public.tally_sales_accounts (name);

CREATE INDEX IF NOT EXISTS idx_tally_sales_accounts_parent
  ON public.tally_sales_accounts (parent_group);

CREATE INDEX IF NOT EXISTS idx_tally_sales_accounts_type
  ON public.tally_sales_accounts (account_type);

COMMENT ON TABLE public.tally_sales_accounts IS
  'Sales ledgers and groups imported from Tally (under Sales Accounts). App service_catalog is unchanged.';

GRANT SELECT, INSERT, UPDATE, DELETE ON public.tally_sales_accounts
  TO anon, authenticated, service_role;
