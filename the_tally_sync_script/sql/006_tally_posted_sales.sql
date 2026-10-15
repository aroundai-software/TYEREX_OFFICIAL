-- Sales posted to Tally are tracked on payments + reports.
-- Do not use tally_posted_sales.
-- Do not overwrite reports."Guid" or payments."Guid".
-- Both stay the app/branch identity (UUID or BR-xxxxxx).
-- Rows with no branch Guid are not synced.
--
-- payments.voucher_type (app labels -> Tally voucher types):
--   SALES B2C        -> SALES -B2C
--   GST SALES B2C    -> GST SALES (B2C)
--   GST SALES B2B    -> GST SALES (B2B)
-- payments.tally_*   = Tally company from tally_company_master
--
-- If voucher_type is empty, the sync infers GST SALES (B2B) when
-- owner_master."GST Number" is set, otherwise SALES -B2C.
--
-- Optional: drop the unused tracking table if you created it earlier.
-- DROP TABLE IF EXISTS public.tally_posted_sales;

COMMENT ON COLUMN public.payments."Guid" IS
  'Branch identity (same as reports."Guid" / branches."Guid"). Sync never overwrites this.';

COMMENT ON COLUMN public.payments.voucher_type IS
  'App sales type: SALES B2C, GST SALES B2C, or GST SALES B2B.';
