-- Restore payments."Guid" after sync wrote TYREX-SALES-R* over the branch Guid.
-- Source of truth is reports."Guid" (branch identity). Safe to re-run.

UPDATE public.payments p
SET "Guid" = r."Guid"
FROM public.reports r
WHERE p.report_id = r.id
  AND p."Guid" IS NOT NULL
  AND p."Guid" LIKE 'TYREX-SALES-%'
  AND r."Guid" IS NOT NULL
  AND BTRIM(r."Guid") <> ''
  AND r."Guid" NOT LIKE 'TYREX-%';

COMMENT ON COLUMN public.payments."Guid" IS
  'Branch identity (same as reports."Guid" / branches."Guid"). Sync never overwrites this.';
