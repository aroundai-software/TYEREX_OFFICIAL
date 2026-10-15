from __future__ import annotations

import argparse
import sys

import requests

from sync.config import tally_url
from sync import alter_cache, supabase_rest, tally_stock, tally_xml


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
        print(f"Fetching stock items for {name} from {tally_url()} ...", flush=True)
        items = tally_stock.fetch_stock_from_tally(name)
        for item in items:
            item["tally_company_id"] = master.get("id")
            item["tally_company_guid"] = master.get("tally_guid")
        new_items, changed_items, seen_items = alter_cache.split_by_alter_id(
            items,
            supabase_rest.list_saved_guids(supabase_rest.STOCK_TABLE, master),
            alter_cache.load(supabase_rest.STOCK_TABLE, master),
        )
        write_items = new_items + changed_items
        print(
            f"  {len(items)} from Tally: {len(new_items)} new, {len(changed_items)} changed (AlterID/Quantity), "
            f"{len(items) - len(new_items) - len(changed_items) - len(seen_items)} unchanged",
            flush=True,
        )
        if dry_run:
            continue
        if seen_items:
            remembered = alter_cache.remember(supabase_rest.STOCK_TABLE, seen_items, master)
            print(f"  remembered Tally AlterID for {remembered} already-synced item(s)", flush=True)
        if not write_items:
            print("  nothing new or AlterID-changed.", flush=True)
            continue
        saved = supabase_rest.upsert_stock_items(write_items)
        print(f"  upserted {saved} row(s) in tally_stock_items", flush=True)
        alter_cache.remember(supabase_rest.STOCK_TABLE, write_items, master)
        total += saved
    if dry_run:
        print("Dry run: nothing written to Supabase.")
        return 0
    print(f"Done. {total} stock row(s) upserted.")
    return 0


def _pause() -> None:
    if not sys.stdin or not sys.stdin.isatty():
        return
    try:
        input("\nPress Enter to close...")
    except EOFError:
        pass


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch Tally stock items into tally_stock_items.")
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
