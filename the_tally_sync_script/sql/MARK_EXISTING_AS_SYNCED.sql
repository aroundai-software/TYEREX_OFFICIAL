-- =========================================================================
-- TyreX: Mark Existing Historical Job Cards & Payments as Already Synced
-- Run this in Client Supabase SQL Editor BEFORE starting sync daemon.
-- =========================================================================

-- 1. Mark all existing job cards in 'reports' as already synced
UPDATE public.reports
SET 
    tally_sync_status = 'synced',
    tally_synced_at = COALESCE(tally_synced_at, NOW()),
    alter_id = COALESCE(alter_id, 0)
WHERE 
    tally_sync_status IS NULL 
    OR tally_sync_status != 'synced';

-- 2. Mark all existing payments as already synced
UPDATE public.payments
SET 
    tally_sync_status = 'synced',
    tally_synced_at = COALESCE(tally_synced_at, NOW())
WHERE 
    tally_sync_status IS NULL 
    OR tally_sync_status != 'synced';

-- Verification Query (Run this to verify)
SELECT 
    'reports' AS table_name,
    tally_sync_status,
    COUNT(*) AS total_count
FROM public.reports
GROUP BY tally_sync_status

UNION ALL

SELECT 
    'payments' AS table_name,
    tally_sync_status,
    COUNT(*) AS total_count
FROM public.payments
GROUP BY tally_sync_status;
