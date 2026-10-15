-- 1. Add Tally mapping columns to branches table
ALTER TABLE public.branches 
ADD COLUMN IF NOT EXISTS tally_company text,
ADD COLUMN IF NOT EXISTS tally_guid text,
ADD COLUMN IF NOT EXISTS company_number text;

-- 2. Add Tally mapping columns to payments table (and any others identified)
ALTER TABLE public.payments 
ADD COLUMN IF NOT EXISTS tally_company text,
ADD COLUMN IF NOT EXISTS tally_guid text,
ADD COLUMN IF NOT EXISTS company_number text;

-- 3. Google Drive Migration: Create pg_net & pg_cron extensions
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Remove old migration cron jobs if any exist
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (SELECT jobid FROM cron.job WHERE jobname ILIKE '%migrate-photos%' OR jobname ILIKE '%drive%') LOOP
    PERFORM cron.unschedule(r.jobid);
  END LOOP;
END $$;

-- Schedule cron job to run every 5 minutes (every :00, :05, :10, :15, :20... in IST / Kerala time)
SELECT cron.schedule(
  'migrate-photos-to-drive-every-5m',
  '*/5 * * * *',
  $$
    SELECT net.http_post(
      url:='https://nodzljxarvnhwrzakwyz.supabase.co/functions/v1/migrate-photos-to-drive',
      headers:='{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds:=120000
    );
  $$
);
