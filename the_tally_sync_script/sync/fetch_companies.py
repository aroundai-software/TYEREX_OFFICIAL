from __future__ import annotations

import argparse
import sys

import requests

from sync.config import tally_url
from sync import supabase_rest, tally_xml
from sync.tally_xml import TallyUnavailable


def run(dry_run: bool = False) -> int:
    print(f"Fetching companies from Tally at {tally_url()} ...", flush=True)
    current = None
    try:
        current = tally_xml.fetch_current_company()
    except TallyUnavailable:
        raise
    except Exception as exc:  # noqa: BLE001
        print(f"  Could not detect the open company: {exc}")
        print(
            "  Tally is not answering. Close any Tally error popup, "
            "exit Tally fully, reopen the company, then run sync again."
        )
    companies = tally_xml.fetch_companies_from_tally()
    if current and not any(
        (row.get("tally_guid") and row.get("tally_guid") == current.get("tally_guid"))
        or row.get("tally_company_name") == current.get("tally_company_name")
        for row in companies
    ):
        companies.insert(0, current)
    if not companies:
        print("No company is open in Tally. Open the company, then run sync.")
        return 1

    if current:
        print(
            f"Open Tally company: {current.get('tally_company_name')} "
            f"| guid={current.get('tally_guid') or '-'} "
            f"| no={current.get('company_number') or '-'}"
        )
    print(f"Fetched {len(companies)} company(ies):")
    for company in companies:
        guid = company.get("tally_guid") or "-"
        number = company.get("company_number") or "-"
        phone = company.get("phone_number") or "-"
        gst = company.get("gst_number") or "-"
        address = company.get("address_line1") or "-"
        marker = " [open]" if current and company.get("tally_company_name") == current.get("tally_company_name") else ""
        print(f"  - {company['tally_company_name']}{marker} | guid={guid} | no={number}")
        print(f"    address={address} | phone={phone} | gst={gst} | email={company.get('email') or '-'}")

    if dry_run:
        print("Dry run: nothing written to Supabase.")
        return 0

    saved = supabase_rest.upsert_companies(companies)
    print(f"Saved {len(saved)} row(s) to tally_company_master.")
    return 0


def _pause() -> None:
    if not sys.stdin or not sys.stdin.isatty():
        return
    try:
        input("\nPress Enter to close...")
    except EOFError:
        pass


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch Tally companies into tally_company_master.")
    parser.add_argument("--dry-run", action="store_true", help="Print companies without writing to Supabase")
    parser.add_argument("--no-pause", action="store_true", help="Do not wait for Enter after finishing")
    args = parser.parse_args()
    exit_code = 0
    try:
        exit_code = run(dry_run=args.dry_run)
    except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
        print(
            f"Sync failed: cannot reach Tally at {tally_url()}. "
            "In TallyPrime open F1 → Settings → Advanced Configuration and enable the HTTP server (port 9000).",
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
