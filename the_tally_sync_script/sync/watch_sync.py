from __future__ import annotations

import ctypes
import subprocess
import sys
import time
from datetime import date

import requests

from sync.config import sync_interval_seconds, sync_since_date, sync_until_date, tally_url
from sync.fetch_companies import run as run_companies
from sync.fetch_masters import run as run_masters
from sync.push_sales import run as run_sales
from sync.tally_xml import TallyUnavailable, fetch_current_company

MUTEX_NAME = "Local\\TyrexTallySyncWatch"
TALLY_PROCESS_NAMES = {"tally.exe", "tallyprime.exe", "tallyprimegold.exe"}
CREATE_NO_WINDOW = 0x08000000
ERROR_ALREADY_EXISTS = 183


def _acquire_mutex() -> bool:
    if sys.platform != "win32":
        return True
    handle = ctypes.windll.kernel32.CreateMutexW(None, False, MUTEX_NAME)
    if not handle:
        return True
    return ctypes.windll.kernel32.GetLastError() != ERROR_ALREADY_EXISTS


def tally_process_running() -> bool:
    if sys.platform != "win32":
        return True
    try:
        result = subprocess.run(
            ["tasklist", "/FO", "CSV", "/NH"],
            capture_output=True,
            text=True,
            timeout=10,
            creationflags=CREATE_NO_WINDOW,
        )
    except Exception:
        return False
    names: set[str] = set()
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        names.add(line.split(",")[0].strip().strip('"').lower())
    return bool(names & TALLY_PROCESS_NAMES)


def tally_company_open() -> bool:
    try:
        return fetch_current_company() is not None
    except TallyUnavailable:
        return False
    except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
        return False
    except Exception:
        return False


def tally_ready() -> bool:
    return tally_company_open()


def run_watch() -> int:
    if not _acquire_mutex():
        print("Tyrex Tally Sync watcher is already running.", flush=True)
        return 0
    until = sync_until_date()
    since = sync_since_date()
    interval = sync_interval_seconds()
    print(
        f"Watch mode: fetch stock/ledgers when Tally opens, then sync job cards "
        f"from {since} to {until}, every {interval} seconds while Tally is open.",
        flush=True,
    )
    if date.today() > until:
        print(f"Sync window ended on {until}. Run Install-TyrexTallySync.bat to renew.", flush=True)
        return 0
    waiting = False
    fetched_masters_for = ""
    while date.today() <= until:
        if tally_ready():
            waiting = False
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Tally is open. Syncing ...", flush=True)
            try:
                current = fetch_current_company() or {}
                company_name = str(current.get("tally_company_name") or "").strip()
                company_code = run_companies()
                if company_code == 0 and company_name and company_name != fetched_masters_for:
                    print(
                        f"  Fetching Tally stock items and party ledgers for {company_name} ...",
                        flush=True,
                    )
                    run_masters(company_name=company_name)
                    fetched_masters_for = company_name
                if company_code == 0:
                    run_sales()
            except TallyUnavailable as exc:
                print(f"  Tally closed or crashed during sync: {exc}", flush=True)
                fetched_masters_for = ""
            except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
                print(f"  Tally is not answering at {tally_url()}.", flush=True)
                fetched_masters_for = ""
            except Exception as exc:  # noqa: BLE001
                print(f"  Sync cycle failed: {exc}", flush=True)
        else:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Tally is not answering at {tally_url()} or no company is opened. Waiting {interval}s...", flush=True)
            fetched_masters_for = ""
        time.sleep(interval)
    print(f"Watch window ended on {until}. Uninstall or reinstall to continue.", flush=True)
    return 0
