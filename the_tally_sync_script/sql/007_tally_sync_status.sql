-- Track whether a job-card sale was posted to Tally.
-- reports."Guid" stays the app/branch identity and is not used for this.
-- Run in Supabase SQL Editor. Safe to re-run.

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS tally_sync_status text;

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS tally_synced_at timestamp with time zone;

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS tally_sync_status text;

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS tally_synced_at timestamp with time zone;

UPDATE public.payments
SET tally_sync_status = COALESCE(NULLIF(tally_sync_status, ''), 'pending')
WHERE tally_sync_status IS NULL;

UPDATE public.reports
SET tally_sync_status = COALESCE(NULLIF(tally_sync_status, ''), 'pending')
WHERE tally_sync_status IS NULL;

ALTER TABLE public.payments
  ALTER COLUMN tally_sync_status SET DEFAULT 'pending';

ALTER TABLE public.reports
  ALTER COLUMN tally_sync_status SET DEFAULT 'pending';

COMMENT ON COLUMN public.payments.tally_sync_status IS
  'pending | synced | failed. Sync retries pending and failed.';

COMMENT ON COLUMN public.reports.tally_sync_status IS
  'pending | synced | failed. reports."Guid" is not modified.';

CREATE INDEX IF NOT EXISTS idx_payments_tally_sync_status
  ON public.payments (tally_sync_status);

CREATE INDEX IF NOT EXISTS idx_reports_tally_sync_status
  ON public.reports (tally_sync_status);
