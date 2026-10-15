from __future__ import annotations

import os
import sys
from datetime import datetime
from pathlib import Path

from sync.config import app_dir

LOG_NAME = "tally_sync.log"
_log_fp = None


class _Tee:
    def __init__(self, fp, also=None) -> None:
        self.fp = fp
        self.also = also

    def write(self, data: str) -> int:
        if not data:
            return 0
        self.fp.write(data)
        self.fp.flush()
        if self.also:
            try:
                self.also.write(data)
                self.also.flush()
            except Exception:
                pass
        return len(data)

    def flush(self) -> None:
        self.fp.flush()
        if self.also:
            try:
                self.also.flush()
            except Exception:
                pass

    def isatty(self) -> bool:
        return False


def log_path() -> Path:
    return app_dir() / LOG_NAME


def start_logging() -> Path:
    global _log_fp
    path = log_path()
    _log_fp = path.open("a", encoding="utf-8")
    _log_fp.write("\n" + "=" * 72 + "\n")
    _log_fp.write(f"Tyrex Tally Sync  {datetime.now():%Y-%m-%d %H:%M:%S}\n")
    _log_fp.write(
        "Watch: fetch stock items and party ledgers when Tally first opens, "
        "then post sales vouchers every minute. Existing Tally masters are not altered.\n"
    )
    _log_fp.write("=" * 72 + "\n")
    _log_fp.flush()
    console = None
    if sys.stdout and not getattr(sys, "frozen", False):
        try:
            if sys.stdout.isatty():
                console = sys.stdout
        except Exception:
            console = None
    sys.stdout = _Tee(_log_fp, console)
    sys.stderr = _Tee(_log_fp, console)
    return path


def notify(title: str, message: str, *, error: bool = False) -> None:
    if sys.platform != "win32":
        return
    try:
        import ctypes

        ctypes.windll.user32.MessageBoxW(0, message, title, 0x10 if error else 0x40)
    except Exception:
        pass


def show_log() -> None:
    path = log_path()
    if sys.platform == "win32" and path.exists():
        os.startfile(str(path))
