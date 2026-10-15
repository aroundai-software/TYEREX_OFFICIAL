-- Tally stock items (does not change public.materials).
-- Run in Supabase SQL Editor. Safe to re-run.

CREATE TABLE IF NOT EXISTS public.tally_stock_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tally_company_id uuid REFERENCES public.tally_company_master(id),
  tally_company text,
  tally_company_guid text,
  name text NOT NULL,
  guid text,
  master_id bigint,
  alias text,
  aliases jsonb,
  part_number text,
  description text,
  stock_group text,
  category text,
  base_unit text,
  additional_unit text,
  conversion numeric,
  denominator numeric,
  opening_qty numeric,
  opening_qty_text text,
  opening_rate numeric,
  opening_value numeric,
  closing_qty numeric,
  closing_qty_text text,
  closing_rate numeric,
  closing_value numeric,
  selling_price numeric,
  cost_price numeric,
  costing_method text,
  hsn_code text,
  hsn_description text,
  gst_classification text,
  gst_applicable text,
  gst_type_of_supply text,
  gst_taxability text,
  gst_rate numeric,
  cgst_rate numeric,
  sgst_rate numeric,
  igst_rate numeric,
  cess_rate numeric,
  is_batchwise boolean,
  ignore_negative_stock boolean,
  gst_details jsonb,
  extra jsonb,
  last_synced_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT tally_stock_items_company_guid_key UNIQUE (tally_company_id, guid)
);

CREATE INDEX IF NOT EXISTS idx_tally_stock_items_company
  ON public.tally_stock_items (tally_company_id);

CREATE INDEX IF NOT EXISTS idx_tally_stock_items_name
  ON public.tally_stock_items (name);

CREATE INDEX IF NOT EXISTS idx_tally_stock_items_group
  ON public.tally_stock_items (stock_group);

CREATE INDEX IF NOT EXISTS idx_tally_stock_items_part
  ON public.tally_stock_items (part_number);

COMMENT ON TABLE public.tally_stock_items IS
  'Stock items imported from Tally. App materials table is unchanged.';

GRANT SELECT, INSERT, UPDATE, DELETE ON public.tally_stock_items
  TO anon, authenticated, service_role;
