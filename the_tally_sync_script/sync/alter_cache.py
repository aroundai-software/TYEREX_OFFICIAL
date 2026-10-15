from __future__ import annotations

import json
from typing import Any

from sync.config import app_dir

CACHE_NAME = "tally_alter_ids.json"


def _as_alter_id(value: Any) -> int | None:
    if value in (None, ""):
        return None
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


def _as_qty(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def cache_path():
    return app_dir() / CACHE_NAME


def _company_key(master: dict[str, Any] | None) -> str:
    master = master or {}
    return str(master.get("id") or master.get("tally_company_name") or "default").strip() or "default"


def _section_key(table: str, master: dict[str, Any] | None) -> str:
    return f"{table}:{_company_key(master)}"


def _load_file() -> dict[str, Any]:
    path = cache_path()
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _save_file(data: dict[str, Any]) -> None:
    path = cache_path()
    path.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")


def load(table: str, master: dict[str, Any] | None = None) -> dict[str, dict[str, Any]]:
    section = _load_file().get(_section_key(table, master)) or {}
    if not isinstance(section, dict):
        return {}
    out: dict[str, dict[str, Any]] = {}
    for guid, value in section.items():
        if not guid:
            continue
        if isinstance(value, dict):
            alter_id = _as_alter_id(value.get("alter_id"))
            closing_qty = _as_qty(value.get("closing_qty"))
            out[str(guid)] = {"alter_id": alter_id, "closing_qty": closing_qty}
        else:
            alter_id = _as_alter_id(value)
            out[str(guid)] = {"alter_id": alter_id, "closing_qty": None}
    return out


def remember(table: str, rows: list[dict[str, Any]], master: dict[str, Any] | None = None) -> int:
    if not rows:
        return 0
    data = _load_file()
    key = _section_key(table, master)
    section = data.get(key)
    if not isinstance(section, dict):
        section = {}
    saved = 0
    for row in rows:
        guid = str(row.get("guid") or "").strip()
        if not guid:
            continue
        alter_id = _as_alter_id(row.get("alter_id"))
        closing_qty = _as_qty(row.get("closing_qty"))
        if "closing_qty" in row:
            section[guid] = {"alter_id": alter_id, "closing_qty": closing_qty}
        else:
            section[guid] = alter_id
        saved += 1
    data[key] = section
    _save_file(data)
    return saved


def split_by_alter_id(
    incoming: list[dict[str, Any]],
    db_guids: set[str],
    last_seen: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    """Return (new_rows, changed_rows, remember_only).
    
    Detects if either Tally AlterID or stock quantity (closing_qty) changed.
    """
    new_rows: list[dict[str, Any]] = []
    changed_rows: list[dict[str, Any]] = []
    remember_only: list[dict[str, Any]] = []
    for row in incoming:
        guid = str(row.get("guid") or "").strip()
        if not guid:
            continue
        tally_alter = _as_alter_id(row.get("alter_id"))
        tally_qty = _as_qty(row.get("closing_qty"))
        if guid not in db_guids:
            new_rows.append(row)
            continue
        stored = last_seen.get(guid)
        if stored is None:
            remember_only.append(row)
            continue

        if isinstance(stored, dict):
            stored_alter = stored.get("alter_id")
            stored_qty = stored.get("closing_qty")
        else:
            stored_alter = _as_alter_id(stored)
            stored_qty = None

        alter_changed = tally_alter is not None and stored_alter is not None and tally_alter != stored_alter
        qty_changed = (
            tally_qty is not None
            and stored_qty is not None
            and abs(tally_qty - stored_qty) > 1e-5
        )
        qty_newly_tracked = (
            tally_qty is not None
            and stored_qty is None
            and "closing_qty" in row
        )

        if alter_changed or qty_changed or qty_newly_tracked:
            changed_rows.append(row)

    return new_rows, changed_rows, remember_only
