from __future__ import annotations

import argparse
import sys

import requests

from sync.config import tally_url
from sync.fetch_companies import run as run_companies
from sync.fetch_masters import run as run_masters
from sync.logutil import log_path, start_logging
from sync.push_sales import run as run_sales
from sync.tally_xml import TallyUnavailable
from sync.watch_sync import run_watch


def main() -> None:
    parser = argparse.ArgumentParser(description="Tyrex Tally sync background daemon")
    parser.add_argument(
        "job",
        nargs="?",
        default="watch",
        choices=["companies", "sales", "masters", "all", "watch"],
        help="companies | sales | masters | all | watch (default)",
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--force", "-f", action="store_true", help="Force re-sync all completed/billed job cards to Tally")
    parser.add_argument("--no-pause", action="store_true")
    parser.add_argument(
        "--watch",
        action="store_true",
        help="Run continuously in background mode",
    )
    args = parser.parse_args()

    log_file = start_logging()
    print(f"Status log: {log_file}", flush=True)

    def pause() -> None:
        if args.watch or args.job == "watch" or getattr(sys, "frozen", False) or args.no_pause:
            return
        if not sys.stdin or not sys.stdin.isatty():
            return
        try:
            input("\nPress Enter to close...")
        except EOFError:
            pass

    exit_code = 0
    try:
        if args.watch or args.job == "watch":
            exit_code = run_watch()
        else:
            if args.job in {"companies", "all"}:
                exit_code = run_companies(dry_run=args.dry_run) or exit_code
            if args.job in {"masters", "all"} and exit_code == 0:
                exit_code = run_masters(dry_run=args.dry_run) or exit_code
            if args.job in {"sales", "all"} and exit_code == 0:
                exit_code = run_sales(dry_run=args.dry_run, limit=args.limit or None, force=args.force) or exit_code
    except TallyUnavailable as exc:
        print(f"Sync stopped: {exc}", file=sys.stderr)
        exit_code = 1
    except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
        print(
            f"Sync failed: cannot reach Tally at {tally_url()}. "
            "Click OK on Internal Error, close Tally fully, open the company, then run sync again.",
            file=sys.stderr,
        )
        exit_code = 1
    except Exception as exc:  # noqa: BLE001
        print(f"Sync failed: {exc}", file=sys.stderr)
        exit_code = 1
    finally:
        print(f"Log file: {log_path()}", flush=True)
        pause()
    raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
