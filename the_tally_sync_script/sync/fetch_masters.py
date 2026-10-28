from __future__ import annotations

import argparse
import sys

import requests

from sync.config import tally_url
from sync import alter_cache, app_catalog, supabase_rest, tally_ledgers, tally_sales, tally_stock, tally_xml


def _ensure_companies() -> list[dict]:
    masters = supabase_rest.list_company_masters()
    if masters:
        return masters
    print("No rows in tally_company_master. Fetching companies from Tally first...")
    companies = tally_xml.fetch_companies_from_tally()
    if not companies:
        print("No Tally companies found.")
        return []
    supabase_rest.upsert_companies(companies)
    return supabase_rest.list_company_masters()


def _project_app_tables(
    items: list[dict],
    ledgers: list[dict],
    sales_rows: list[dict] | None,
    master: dict,
) -> tuple[int, int, int, int, int]:
    owners = 0
    tyres = alloys = materials = 0
    services = 0
    try:
        owners = supabase_rest.upsert_owners_from_ledgers(ledgers, master)
        print(f"  owner_master: {owners} owner(s) created/updated", flush=True)
    except Exception as exc:  # noqa: BLE001
        print(f"  owner_master save failed: {exc}", flush=True)
    try:
        tyres, alloys, materials = supabase_rest.upsert_app_stock_from_tally(items, master)
        print(
            f"  app catalogs: {tyres} tyre_catalog, {alloys} alloy_catalog, {materials} materials",
            flush=True,
        )
    except Exception as exc:  # noqa: BLE001
        print(f"  app catalog save failed: {exc}", flush=True)
    if sales_rows:
        try:
            services = supabase_rest.upsert_service_catalog_from_sales(sales_rows, master)
            print(f"  service_catalog: {services} service(s) saved", flush=True)
        except Exception as exc:  # noqa: BLE001
            print(f"  service_catalog save failed: {exc}", flush=True)
    return owners, tyres, alloys, materials, services


def project_saved(company_name: str | None = None) -> int:
    masters = supabase_rest.list_company_masters()
    if company_name:
        masters = [row for row in masters if row.get("tally_company_name") == company_name]
    if not masters:
        print("No tally_company_master rows to project.")
        return 1
    for master in masters:
        name = master.get("tally_company_name") or "?"
        items = supabase_rest.list_saved_stock_items(master)
        ledgers = supabase_rest.list_saved_ledgers(master)
        sales_rows = supabase_rest.list_saved_sales_accounts(master)
        print(
            f"Filling app tables from saved Tally data for {name}: "
            f"{len(items)} stock, {len(ledgers)} ledgers, {len(sales_rows)} sales accounts ...",
            flush=True,
        )
        if not items and not ledgers and not sales_rows:
            print("  nothing saved for this company.", flush=True)
            continue
        _project_app_tables(items, ledgers, sales_rows, master)
    return 0


def run(dry_run: bool = False, company_name: str | None = None) -> int:
    masters = _ensure_companies()
    if company_name:
        matched = [row for row in masters if row.get("tally_company_name") == company_name]
        masters = matched or masters
    if not masters:
        print("tally_company_master is still empty.")
        return 1

    total_stock = 0
    total_ledgers = 0
    total_sales = 0
    total_owners = 0
    total_tyres = 0
    total_alloys = 0
    total_materials = 0
    total_services = 0

    for master in masters:
        name = master.get("tally_company_name")
        if not name:
            continue
        print(f"Fetching Tally masters for {name} from {tally_url()} ...", flush=True)

        print("  Stock items (tyres / alloys / parts)...", flush=True)
        items = tally_stock.fetch_stock_from_tally(name)
        for item in items:
            item["tally_company_id"] = master.get("id")
            item["tally_company_guid"] = master.get("tally_guid")
        print(f"  {len(items)} stock item(s).", flush=True)

        print("  Party ledgers (Sundry Debtors → owner name)...", flush=True)
        ledgers = tally_ledgers.fetch_party_ledgers_from_tally(name)
        for row in ledgers:
            row["tally_company_id"] = master.get("id")
            row["tally_company_guid"] = master.get("tally_guid")
        print(f"  {len(ledgers)} party ledger(s).", flush=True)

        print("  Sales & service accounts (Sales Accounts / Service Income)...", flush=True)
        sales = tally_sales.fetch_sales_from_tally(name)
        for row in sales:
            row["tally_company_id"] = master.get("id")
            row["tally_company_guid"] = master.get("tally_guid")
        print(f"  {len(sales)} sales/service account(s).", flush=True)

        if not items and not ledgers and not sales:
            print("  Tally returned no stock/ledgers/sales for this company; skipping.", flush=True)
            continue

        if not dry_run and sales:
            try:
                saved_sales = supabase_rest.upsert_sales_accounts(sales)
                print(f"  upserted {saved_sales} row(s) in tally_sales_accounts", flush=True)
                total_sales += saved_sales
            except Exception as exc:  # noqa: BLE001
                print(f"  tally_sales_accounts save failed: {exc}", flush=True)
                print("  Run sql/005_tally_sales_accounts.sql.", flush=True)

        stock_guids = supabase_rest.list_saved_guids(supabase_rest.STOCK_TABLE, master)
        ledger_guids = supabase_rest.list_saved_guids(supabase_rest.LEDGER_TABLE, master)
        new_items, changed_items, seen_items = alter_cache.split_by_alter_id(
            items, stock_guids, alter_cache.load(supabase_rest.STOCK_TABLE, master)
        )
        new_ledgers, changed_ledgers, seen_ledgers = alter_cache.split_by_alter_id(
            ledgers, ledger_guids, alter_cache.load(supabase_rest.LEDGER_TABLE, master)
        )
        write_items = new_items + changed_items
        write_ledgers = new_ledgers + changed_ledgers
        print(
            f"  stock: {len(new_items)} new, {len(changed_items)} changed (AlterID/Quantity), "
            f"{len(items) - len(new_items) - len(changed_items) - len(seen_items)} unchanged",
            flush=True,
        )
        print(
            f"  ledgers: {len(new_ledgers)} new, {len(changed_ledgers)} Tally AlterID changed, "
            f"{len(ledgers) - len(new_ledgers) - len(changed_ledgers) - len(seen_ledgers)} unchanged",
            flush=True,
        )

        if dry_run:
            kinds = {"tyre": 0, "alloy": 0, "other": 0}
            for item in write_items:
                kinds[app_catalog.classify_stock(item)] += 1
            print(
                f"  dry-run write: {kinds['tyre']} tyre, {kinds['alloy']} alloy, "
                f"{kinds['other']} other, {len(write_ledgers)} owners, {len(sales)} services"
            )
            continue

        if seen_items:
            remembered = alter_cache.remember(supabase_rest.STOCK_TABLE, seen_items, master)
            print(f"  remembered Tally AlterID for {remembered} already-synced stock item(s)", flush=True)
        if seen_ledgers:
            remembered = alter_cache.remember(supabase_rest.LEDGER_TABLE, seen_ledgers, master)
            print(f"  remembered Tally AlterID for {remembered} already-synced ledger(s)", flush=True)

        if write_items:
            try:
                saved = supabase_rest.upsert_stock_items(write_items)
                print(f"  upserted {saved} row(s) in tally_stock_items", flush=True)
                total_stock += saved
                alter_cache.remember(supabase_rest.STOCK_TABLE, write_items, master)
            except Exception as exc:  # noqa: BLE001
                print(f"  tally_stock_items save failed: {exc}", flush=True)
                print("  Run sql/003_tally_stock_items.sql and sql/004_stock_upsert_guid.sql.", flush=True)

        if write_ledgers:
            try:
                saved = supabase_rest.upsert_ledgers(write_ledgers)
                print(f"  upserted {saved} row(s) in tally_ledgers", flush=True)
                total_ledgers += saved
                alter_cache.remember(supabase_rest.LEDGER_TABLE, write_ledgers, master)
            except Exception as exc:  # noqa: BLE001
                print(f"  tally_ledgers save failed: {exc}", flush=True)
                print("  Run sql/009_tally_ledgers.sql.", flush=True)

        owners, tyres, alloys, materials, services = _project_app_tables(write_items, write_ledgers, sales, master)
        total_owners += owners
        total_tyres += tyres
        total_alloys += alloys
        total_materials += materials
        total_services += services

    if dry_run:
        print("Dry run: nothing written to Supabase.")
        return 0
    print(
        f"Done. stock={total_stock} ledgers={total_ledgers} sales_accounts={total_sales} "
        f"owners={total_owners} tyres={total_tyres} alloys={total_alloys} "
        f"materials={total_materials} services={total_services}"
    )
    return 0


def _pause() -> None:
    if not sys.stdin or not sys.stdin.isatty():
        return
    try:
        input("\nPress Enter to close...")
    except EOFError:
        pass


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch Tally stock items and party ledgers into the app database."
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--from-db", action="store_true", help="Fill app tables from already-saved Tally rows")
    parser.add_argument("--no-pause", action="store_true")
    args = parser.parse_args()
    exit_code = 0
    try:
        exit_code = project_saved() if args.from_db else run(dry_run=args.dry_run)
    except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
        print(
            f"Sync failed: cannot reach Tally at {tally_url()}. "
            "Enable the Tally HTTP server and keep the company open.",
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
