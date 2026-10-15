from __future__ import annotations

import argparse
import sys

import requests

from sync.config import tally_url
from sync import supabase_rest, tally_voucher
from sync.tally_xml import TallyUnavailable, fetch_current_company


def run(dry_run: bool = False, limit: int | None = None, force: bool = False) -> int:
    current = fetch_current_company()
    if not current:
        print("No company is open in Tally. Open the company, then run sync.")
        return 1
    current_saved = supabase_rest.find_company(
        tally_guid=current.get("tally_guid")
    ) or supabase_rest.find_company(name=current.get("tally_company_name"))
    if current_saved:
        current = {**current, **current_saved}
    print(
        f"Open Tally company: {current.get('tally_company_name')} "
        f"(guid={current.get('tally_guid') or '-'})",
        flush=True,
    )
    print("Checking converted sales vouchers in Tally ...", flush=True)
    try:
        updated_converted = supabase_rest.sync_converted_sales_from_tally(current.get("tally_company_name") or "")
        if updated_converted > 0:
            print(f"  stamped is_converted=true on {updated_converted} job card(s) in database", flush=True)
    except Exception as exc:  # noqa: BLE001
        print(f"  converted sales check skipped: {exc}", flush=True)

    print("Loading billed/paid job cards from reports + payments ...", flush=True)
    try:
        supabase_rest.restore_payment_branch_guids()
    except Exception as exc:  # noqa: BLE001
        print(f"  payment Guid restore skipped: {exc}", flush=True)
    reports = supabase_rest.list_sales_reports(limit=limit, current_company=current)
    all_payments = [row for report in reports for row in (report.get("payments") or [])]
    posted_ids = supabase_rest.posted_sales_report_ids(all_payments)
    catalog = supabase_rest.list_stock_catalog()
    sales: list[dict] = []
    skipped = 0
    skipped_no_guid = 0
    restamp = 0
    other_company = 0
    for report in reports:
        eligible_payments = supabase_rest.payments_with_branch_guid(report.get("payments") or [])
        if not eligible_payments and not supabase_rest.report_has_branch_guid(report):
            skipped_no_guid += 1
            continue
        if not supabase_rest.report_matches_open_company(report, current):
            other_company += 1
            continue
        sale = tally_voucher.build_sale(
            report,
            stock_catalog=catalog,
            payments=eligible_payments,
            vehicle_number=report.get("vehicle_number"),
        )
        if not sale:
            skipped += 1
            continue
        sale["company"] = current.get("tally_company_name") or sale.get("company")
        sale["tally_company_id"] = current.get("id") or sale.get("tally_company_id")
        sale["tally_guid"] = current.get("tally_guid") or sale.get("tally_guid")
        already = report.get("id") in posted_ids
        report_status = str(report.get("tally_sync_status") or "").lower()
        pay_status = {(p.get("tally_sync_status") or "").lower() for p in (report.get("payments") or [])}
        synced_here = (
            str(report.get("tally_company") or "").strip().casefold()
            == str(current.get("tally_company_name") or "").strip().casefold()
            and report_status == "synced"
        ) or any(
            str(p.get("tally_company") or "").strip().casefold()
            == str(current.get("tally_company_name") or "").strip().casefold()
            and str(p.get("tally_sync_status") or "").lower() == "synced"
            for p in (report.get("payments") or [])
        )
        is_pending = report_status == "pending"
        has_revision = int(sale.get("alter_id") or 0) > 0
        sale["is_alter"] = False  # Always create distinct voucher in Tally
        synced = (report_status == "synced" or (already and bool(pay_status) and pay_status <= {"synced"})) and synced_here and not is_pending
        if synced and not force:
            continue
        if has_revision:
            restamp += 1
        sales.append(sale)
    print(
        f"  {len(reports)} completed/billed job card(s), {len(posted_ids)} already posted, "
        f"{other_company} for other Tally companies, "
        f"{skipped_no_guid} skipped (no branch Guid), "
        f"{len(sales)} to send to {current.get('tally_company_name')} ({restamp} alter), "
        f"{len(catalog)} Tally stock name(s)."
    )
    print(
        f"  {len(sales)} sale order / voucher(s) ready "
        f"({tally_voucher.VOUCHER_TYPE}), {skipped} skipped (no billable lines)."
    )
    if not sales:
        print("Nothing to send to this Tally company.")
        return 0
    for sale in sales[:8]:
        print(
            f"  - {sale['jobcard_number']} {sale['voucher_type']} {sale['date']} {sale['party_ledger']} "
            f"veh={sale['vehicle_number'] or '-'} taxable={sale['taxable']:.2f} "
            f"gst={sale['cgst']+sale['sgst']:.2f} round={sale['round_off']:.2f} total={sale['total']:.2f}"
        )
        for item in sale["items"]:
            ledger = tally_voucher.INVENTORY_SALES_LEDGER if item["kind"] == "stock" else item["ledger"]
            src = f" (from {item.get('source_name')})" if item.get("source_name") and item.get("source_name") != item["name"] else ""
            print(
                f"      {ledger}: {item['amount']:.2f} ({item['name']}{src})"
            )
        if sale.get("narration"):
            print(f"      narration: {sale['narration']}")
        if sale.get("buyer_address"):
            print(f"      party address: {sale.get('buyer_address')}")
    print(
        "Posting one voucher at a time. Numbering stays in Tally without the popup.",
        flush=True,
    )
    if dry_run:
        print("Dry run: nothing sent to Tally.")
        return 0

    def _mark_ok(sale: dict) -> None:
        nonlocal total_ok
        saved = supabase_rest.mark_tally_sync(sale, "synced")
        total_ok += 1
        print(f"  synced {sale['jobcard_number']} ({saved} row(s))")

    def _send_one(sale: dict) -> None:
        nonlocal failed
        company = sale.get("company") or ""
        print(f"Sending {sale['jobcard_number']} as {sale['voucher_type']} ...", flush=True)
        try:
            result = tally_voucher.post_sales_to_tally(company, [sale])
        except TallyUnavailable:
            raise
        except Exception as exc:  # noqa: BLE001
            print(f"  Tally error: {exc}")
            try:
                supabase_rest.mark_tally_sync(sale, "failed")
            except Exception:
                pass
            failed += 1
            return
        created = int(result.get("voucher_created") or 0)
        altered = int(result.get("voucher_altered") or 0)
        exceptions = int(result.get("exceptions") or 0)
        error = str(result.get("error") or "")
        print(f"  Tally created={created} altered={altered} exceptions={exceptions} last_id={result.get('last_id')}")
        if error:
            print(f"  Tally error: {error}")
        voucher_ok = (created > 0 or altered > 0) and exceptions == 0
        if not voucher_ok:
            if "duplicate entry" in error.lower():
                print(f"  {sale['jobcard_number']} already recorded in Tally.")
                _mark_ok(sale)
                return
            supabase_rest.mark_tally_sync(sale, "failed")
            print(f"  not recorded: {sale['jobcard_number']}")
            failed += 1
            return
        _mark_ok(sale)

    total_ok = 0
    failed = 0
    company_name = str(current.get("tally_company_name") or sales[0].get("company") or "")
    if company_name:
        tally_voucher.ensure_retain_numbering(company_name)
    for sale in sales:
        company = sale.get("company") or ""
        if not company:
            print(f"  skip {sale['jobcard_number']}: empty tally_company")
            failed += 1
            continue
        try:
            _send_one(sale)
        except TallyUnavailable:
            print(
                "Stopped: Tally closed or crashed (Internal Error / Memory Access Violation). "
                "Click OK, close Tally fully, open the company, then run sync again. "
                f"Remaining bills will sync next time. Posted {total_ok}, failed {failed}."
            )
            raise
    print(f"Done. {total_ok} Tally document(s) recorded, {failed} failed.")
    return 1 if failed else 0


def _pause() -> None:
    if not sys.stdin or not sys.stdin.isatty():
        return
    try:
        input("\nPress Enter to close...")
    except EOFError:
        pass


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Post job-card sales to Tally from reports and payments (SALES -B2C, GST SALES (B2C), GST SALES (B2B))."
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--force", "-f", action="store_true", help="Force re-sync all completed/billed job cards to Tally")
    parser.add_argument("--no-pause", action="store_true")
    args = parser.parse_args()
    exit_code = 0
    try:
        exit_code = run(dry_run=args.dry_run, limit=args.limit or None, force=args.force)
    except TallyUnavailable as exc:
        print(f"Sync stopped: {exc}", file=sys.stderr)
        exit_code = 1
    except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
        print(
            f"Sync failed: cannot reach Tally at {tally_url()}. "
            "Click OK on any Tally Internal Error, close Tally fully, open the company, then run sync again.",
            file=sys.stderr,
        )
        exit_code = 1
    except Exception as exc:  # noqa: BLE001
        print(f"Sync failed: {exc}", file=sys.stderr)
        exit_code = 1
    finally:
        if not args.no_pause:
            _pause()
    raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
