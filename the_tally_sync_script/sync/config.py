from __future__ import annotations

import os
import sys
from datetime import date, timedelta
from pathlib import Path

from dotenv import load_dotenv

DEFAULT_SUPABASE_URL = "https://nodzljxarvnhwrzakwyz.supabase.co"
DEFAULT_SUPABASE_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5vZHpsanhhcnZuaHdyemFrd3l6Iiwicm9sZSI6ImFub24i"
    "LCJpYXQiOjE3ODk0NDg4MjYsImV4cCI6MjEwNTAyNDgyNn0."
    "ZlnBAoF3MTZUp0xUxArST0w_XgQgIWITfzaynHaGgcg"
)


def app_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


ROOT_DIR = app_dir()

for config_name in ("tally_sync.env", ".env"):
    config_path = ROOT_DIR / config_name
    if config_path.exists():
        load_dotenv(config_path, override=True)
        break
else:
    load_dotenv(ROOT_DIR / ".env")


def _env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


def tally_host() -> str:
    return _env("TALLY_HOST", "127.0.0.1") or "127.0.0.1"


def tally_port() -> int:
    return int(_env("TALLY_PORT", "9000") or "9000")


def tally_url() -> str:
    explicit = _env("TALLY_URL")
    if explicit:
        return explicit.rstrip("/")
    return f"http://{tally_host()}:{tally_port()}"


def tally_timeout() -> int:
    return int(_env("TALLY_TIMEOUT", "30") or "30")


def supabase_url() -> str:
    url = (_env("SUPABASE_URL") or DEFAULT_SUPABASE_URL).rstrip("/")
    if url.endswith("/rest/v1"):
        url = url[: -len("/rest/v1")]
    return url


def supabase_key() -> str:
    return _env("SUPABASE_KEY") or DEFAULT_SUPABASE_KEY


def _parse_iso_date(raw: str, fallback: date) -> date:
    text = (raw or "").strip()[:10]
    try:
        return date.fromisoformat(text)
    except ValueError:
        return fallback


def sync_since_date() -> date:
    return _parse_iso_date(_env("SYNC_SINCE"), date.today())


def sync_until_date() -> date:
    return _parse_iso_date(_env("SYNC_UNTIL"), date.today() + timedelta(days=365))


def sync_interval_seconds() -> int:
    try:
        return max(15, int(_env("SYNC_INTERVAL_SECONDS", "60") or "60"))
    except ValueError:
        return 60
