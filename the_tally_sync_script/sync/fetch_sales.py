from __future__ import annotations

import argparse
import sys

import requests

from sync.config import tally_url
from sync import supabase_rest, tally_sales, tally_xml


def run(dry_run: bool = False) -> int:
    masters = supabase_rest.list_company_masters()
    if not masters:
        print("No rows in tally_company_master. Fetching companies from Tally first...")
        companies = tally_xml.fetch_companies_from_tally()
        if not companies:
            print("No Tally companies found.")
            return 1
        supabase_rest.upsert_companies(companies)
        masters = supabase_rest.list_company_masters()
    if not masters:
        print("tally_company_master is still empty.")
        return 1

    total = 0
    for master in masters:
        name = master.get("tally_company_name")
        if not name:
            continue
        print(f"Fetching sales accounts for {name} from {tally_url()} ...", flush=True)
        rows = tally_sales.fetch_sales_from_tally(name)
        for row in rows:
            row["tally_company_id"] = master.get("id")
            row["tally_company_guid"] = master.get("tally_guid")
        print(f"  {len(rows)} account(s). Saving to database (update if exists, insert if new)...", flush=True)
        if dry_run:
            continue
        saved = supabase_rest.upsert_sales_accounts(rows)
        print(f"  upserted {saved} row(s) in tally_sales_accounts", flush=True)
        total += saved
    if dry_run:
        print("Dry run: nothing written to Supabase.")
        return 0
    print(f"Done. {total} sales account row(s) upserted.")
    return 0


def _pause() -> None:
    if not sys.stdin or not sys.stdin.isatty():
        return
    try:
        input("\nPress Enter to close...")
    except EOFError:
        pass


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch Tally sales accounts into tally_sales_accounts.")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-pause", action="store_true")
    args = parser.parse_args()
    exit_code = 0
    try:
        exit_code = run(dry_run=args.dry_run)
    except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
        print(
            f"Sync failed: cannot reach Tally at {tally_url()}. "
            "Enable the Tally HTTP server (port 9000) and keep the company open.",
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
