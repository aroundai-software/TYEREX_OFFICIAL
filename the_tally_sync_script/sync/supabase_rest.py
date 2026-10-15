from __future__ import annotations

import time
from datetime import date, datetime, timezone
from typing import Any

import requests

from sync.config import supabase_key, supabase_url, sync_since_date, sync_until_date

TABLE = "tally_company_master"
STOCK_TABLE = "tally_stock_items"
SALES_TABLE = "tally_sales_accounts"
LEDGER_TABLE = "tally_ledgers"
LEDGER_SQL = "sql/009_tally_ledgers.sql"
APP_CATALOG_SQL = "sql/010_app_catalog_from_tally.sql"

# In-memory caches to prevent redundant duplicate queries on periodic sync cycles
_VEHICLES_CACHE: dict[int, dict[str, Any]] = {}
_OWNERS_CACHE: dict[str, dict[str, Any]] = {}
_MODELS_CACHE: dict[int, dict[str, Any]] = {}
_STOCK_CATALOG_CACHE: list[dict[str, Any]] = []
_STOCK_CATALOG_CACHED_AT: float = 0.0
_BRANCHES_CACHE: list[dict[str, Any]] = []
_BRANCHES_CACHED_AT: float = 0.0


def _headers() -> dict[str, str]:
    key = supabase_key()
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def _rest(path: str) -> str:
    return f"{supabase_url()}/rest/v1/{path.lstrip('/')}"


def _raise_for_rest(response: requests.Response, action: str) -> None:
    if response.ok:
        return
    raise RuntimeError(
        f"Supabase {action} failed ({response.status_code}): {response.text[:800]}"
    )


# PostgREST / Cloudflare reject long query strings (400 Bad Request).
# UUID `in.(...)` filters blow past that around a few hundred ids.
_IN_FILTER_CHUNK = 80


def _select_in(
    table: str,
    ids: list[str],
    *,
    action: str,
    limit: int = 20000,
    select: str = "*",
) -> list[dict[str, Any]]:
    unique = [str(item) for item in dict.fromkeys(ids) if item]
    if not unique:
        return []
    rows: list[dict[str, Any]] = []
    for start in range(0, len(unique), _IN_FILTER_CHUNK):
        chunk = unique[start : start + _IN_FILTER_CHUNK]
        response = requests.get(
            _rest(table),
            headers=_headers(),
            params={
                "select": select,
                "id": f"in.({','.join(chunk)})",
                "limit": str(limit),
            },
            timeout=30,
        )
        if response.status_code == 400 and select != "*":
            response = requests.get(
                _rest(table),
                headers=_headers(),
                params={
                    "select": "*",
                    "id": f"in.({','.join(chunk)})",
                    "limit": str(limit),
                },
                timeout=30,
            )
        _raise_for_rest(response, action)
        rows.extend(response.json())
    return rows


def find_company(*, tally_guid: str | None = None, name: str | None = None) -> dict[str, Any] | None:
    params: dict[str, str] = {"select": "id,tally_company_name,tally_guid", "limit": "1"}
    if tally_guid:
        params["tally_guid"] = f"eq.{tally_guid}"
    elif name:
        params["tally_company_name"] = f"eq.{name}"
    else:
        return None

    response = requests.get(_rest(TABLE), headers=_headers(), params=params, timeout=30)
    _raise_for_rest(response, "select")
    rows = response.json()
    return rows[0] if rows else None


def upsert_company(row: dict[str, Any]) -> dict[str, Any]:
    existing = None
    if row.get("tally_guid"):
        existing = find_company(tally_guid=row["tally_guid"])
    if existing is None:
        existing = find_company(name=row["tally_company_name"])

    payload = {key: value for key, value in row.items() if value is not None}
    payload["updated_at"] = datetime.now(timezone.utc).isoformat()

    if existing:
        response = requests.patch(
            _rest(TABLE),
            headers=_headers(),
            params={"id": f"eq.{existing['id']}"},
            json=payload,
            timeout=30,
        )
        _raise_for_rest(response, "update")
        data = response.json()
        return data[0] if data else {**existing, **payload}

    response = requests.post(_rest(TABLE), headers=_headers(), json=payload, timeout=30)
    _raise_for_rest(response, "insert")
    data = response.json()
    return data[0] if data else payload


def upsert_companies(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [upsert_company(row) for row in rows]


def list_company_masters() -> list[dict[str, Any]]:
    response = requests.get(
        _rest(TABLE),
        headers=_headers(),
        params={
            "select": "id,tally_company_name,tally_guid,company_number,financial_year_start_date,financial_year_end_date",
            "order": "tally_company_name",
        },
        timeout=30,
    )
    _raise_for_rest(response, "select companies")
    return response.json()


# PostgREST bulk insert requires every object to have the exact same keys (PGRST102).
STOCK_COLUMNS = (
    "tally_company_id",
    "tally_company",
    "tally_company_guid",
    "name",
    "guid",
    "master_id",
    "alias",
    "aliases",
    "part_number",
    "description",
    "stock_group",
    "category",
    "base_unit",
    "additional_unit",
    "conversion",
    "denominator",
    "opening_qty",
    "opening_qty_text",
    "opening_rate",
    "opening_value",
    "closing_qty",
    "closing_qty_text",
    "closing_rate",
    "closing_value",
    "selling_price",
    "cost_price",
    "costing_method",
    "hsn_code",
    "hsn_description",
    "gst_classification",
    "gst_applicable",
    "gst_type_of_supply",
    "gst_taxability",
    "gst_rate",
    "cgst_rate",
    "sgst_rate",
    "igst_rate",
    "cess_rate",
    "is_batchwise",
    "ignore_negative_stock",
    "gst_details",
    "extra",
    "last_synced_at",
)


SALES_COLUMNS = (
    "tally_company_id",
    "tally_company",
    "tally_company_guid",
    "name",
    "guid",
    "master_id",
    "account_type",
    "alias",
    "aliases",
    "parent_group",
    "description",
    "mailing_name",
    "opening_balance",
    "opening_balance_text",
    "closing_balance",
    "closing_balance_text",
    "tax_type",
    "gst_applicable",
    "gst_type_of_supply",
    "gst_taxability",
    "hsn_code",
    "hsn_description",
    "gst_rate",
    "cgst_rate",
    "sgst_rate",
    "igst_rate",
    "cess_rate",
    "affects_stock",
    "is_billwise",
    "is_cost_centre",
    "is_revenue",
    "is_subledger",
    "gst_details",
    "extra",
    "last_synced_at",
)


def _row_payload(row: dict[str, Any], columns: tuple[str, ...]) -> dict[str, Any]:
    payload = {key: row.get(key) for key in columns}
    payload["updated_at"] = datetime.now(timezone.utc).isoformat()
    return payload


def _upsert_by_guid(
    table: str,
    columns: tuple[str, ...],
    rows: list[dict[str, Any]],
    chunk_size: int = 200,
    sql_hint: str = "",
) -> int:
    by_guid: dict[str, dict[str, Any]] = {}
    skipped_no_guid = 0
    for row in rows:
        guid = row.get("guid")
        if not guid:
            skipped_no_guid += 1
            continue
        by_guid[guid] = _row_payload(row, columns)
    payload = list(by_guid.values())
    if skipped_no_guid:
        print(f"  skipped {skipped_no_guid} item(s) with no GUID", flush=True)
    if not payload:
        return 0

    session = requests.Session()
    headers = {
        "apikey": supabase_key(),
        "Authorization": f"Bearer {supabase_key()}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }
    saved = 0
    conflict_targets = ("guid", "tally_company_id,guid")
    last_error = ""
    for start in range(0, len(payload), chunk_size):
        chunk = payload[start : start + chunk_size]
        ok = False
        for conflict in conflict_targets:
            response = session.post(
                _rest(table),
                headers=headers,
                params={"on_conflict": conflict},
                json=chunk,
                timeout=60,
            )
            if response.ok:
                saved += len(chunk)
                ok = True
                break
            last_error = response.text[:500]
        if not ok:
            hint = f" Run {sql_hint}." if sql_hint else ""
            raise RuntimeError(
                f"{table} upsert failed (need unique guid).{hint} {last_error}"
            )
        print(f"  saved {saved}/{len(payload)} ...", flush=True)
    return saved


def upsert_stock_items(rows: list[dict[str, Any]], chunk_size: int = 200) -> int:
    return _upsert_by_guid(
        STOCK_TABLE,
        STOCK_COLUMNS,
        rows,
        chunk_size,
        sql_hint="sql/004_stock_upsert_guid.sql",
    )


def upsert_sales_accounts(rows: list[dict[str, Any]], chunk_size: int = 200) -> int:
    return _upsert_by_guid(
        SALES_TABLE,
        SALES_COLUMNS,
        rows,
        chunk_size,
        sql_hint="sql/005_tally_sales_accounts.sql",
    )


LEDGER_COLUMNS = (
    "tally_company_id",
    "tally_company",
    "tally_company_guid",
    "name",
    "guid",
    "master_id",
    "parent_group",
    "mailing_name",
    "alias",
    "aliases",
    "address_line1",
    "address_line2",
    "address_line3",
    "state",
    "country",
    "pincode",
    "phone",
    "mobile",
    "email",
    "gstin",
    "pan",
    "opening_balance",
    "opening_balance_text",
    "closing_balance",
    "closing_balance_text",
    "is_billwise",
    "extra",
    "last_synced_at",
)


def upsert_ledgers(rows: list[dict[str, Any]], chunk_size: int = 200) -> int:
    return _upsert_by_guid(
        LEDGER_TABLE,
        LEDGER_COLUMNS,
        rows,
        chunk_size,
        sql_hint=LEDGER_SQL,
    )


def list_saved_guids(table: str, master: dict[str, Any] | None = None) -> set[str]:
    extra: dict[str, str] = {}
    if master and master.get("id"):
        extra["tally_company_id"] = f"eq.{master['id']}"
    rows = _select_all(table, "guid", extra=extra)
    return {str(row.get("guid") or "").strip() for row in rows if row.get("guid")}


def _select_all(
    table: str,
    select: str = "*",
    page: int = 1000,
    extra: dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    offset = 0
    current_select = select
    while True:
        params = {"select": current_select, "limit": str(page), "offset": str(offset)}
        if extra:
            params.update(extra)
        response = requests.get(
            _rest(table),
            headers=_headers(),
            params=params,
            timeout=45,
        )
        if response.status_code == 404 or "PGRST205" in (response.text or ""):
            return rows
        if response.status_code == 400 and current_select != "*":
            current_select = "*"
            offset = 0
            rows = []
            continue
        _raise_for_rest(response, f"select {table}")
        chunk = response.json()
        rows.extend(chunk)
        if len(chunk) < page:
            break
        offset += page
    return rows


def list_branches_for_company(master: dict[str, Any] | None) -> list[dict[str, Any]]:
    master = master or {}
    rows = _select_all(
        "branches",
        "id,branch_name,Guid,tally_company_id,tally_company,tally_guid,is_active",
    )
    company_id = str(master.get("id") or "").strip()
    company_name = _company_name_key(master.get("tally_company_name") or master.get("tally_company"))
    company_guid = str(master.get("tally_guid") or "").strip().casefold()
    matched = []
    for row in rows:
        if company_id and str(row.get("tally_company_id") or "") == company_id:
            matched.append(row)
            continue
        if company_guid and str(row.get("tally_guid") or "").strip().casefold() == company_guid:
            matched.append(row)
            continue
        if company_name and _company_name_key(row.get("tally_company")) == company_name:
            matched.append(row)
    return [row for row in matched if is_branch_guid(row.get("Guid"))]


def list_saved_stock_items(master: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    extra: dict[str, str] = {}
    if master and master.get("id"):
        extra["tally_company_id"] = f"eq.{master['id']}"
    return _select_all(STOCK_TABLE, "*", extra=extra)


def list_saved_ledgers(master: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    extra: dict[str, str] = {}
    if master and master.get("id"):
        extra["tally_company_id"] = f"eq.{master['id']}"
    return _select_all(LEDGER_TABLE, "*", extra=extra)


def _missing_column(error_text: str, keys: list[str]) -> str | None:
    text = error_text or ""
    if "schema cache" not in text and "Could not find" not in text:
        return None
    for key in keys:
        if key and key in text:
            return key
    return None


def _same_keys(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    keys: list[str] = []
    seen: set[str] = set()
    for row in rows:
        for key in row:
            if key not in seen:
                seen.add(key)
                keys.append(key)
    return [{key: row.get(key) for key in keys} for row in rows]


def _bulk_insert(table: str, rows: list[dict[str, Any]], chunk_size: int = 150) -> int:
    if not rows:
        return 0
    headers = {
        "apikey": supabase_key(),
        "Authorization": f"Bearer {supabase_key()}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    dropped: set[str] = set()
    saved = 0
    payload = [dict(row) for row in rows]
    index = 0
    while index < len(payload):
        chunk = []
        for row in payload[index : index + chunk_size]:
            cleaned = {key: value for key, value in row.items() if key not in dropped and value not in (None, "")}
            if table == "owner_master" and not cleaned.get("Owner name"):
                continue
            chunk.append(cleaned)
        if not chunk:
            index += chunk_size
            continue
        aligned = _same_keys(chunk)
        response = requests.post(_rest(table), headers=headers, json=aligned, timeout=60)
        if response.ok or response.status_code == 409:
            saved += len(aligned)
            index += chunk_size
            print(f"  {table}: saved {saved}/{len(payload)} ...", flush=True)
            continue
        missing = _missing_column(response.text or "", [key for row in aligned for key in row])
        if missing:
            dropped.add(missing)
            print(f"  {table} has no {missing}; continuing without it.", flush=True)
            continue
        if response.status_code == 400 and len(aligned) > 1:
            half = max(1, len(aligned) // 2)
            if chunk_size > 1:
                chunk_size = half
                continue
        print(f"  {table} chunk skipped: {(response.text or '')[:240]}", flush=True)
        index += max(1, len(aligned))
    return saved


def upsert_owners_from_ledgers(ledgers: list[dict[str, Any]], master: dict[str, Any] | None) -> int:
    from sync.app_catalog import owner_match_key, owner_row

    if not ledgers:
        return 0
    branches = list_branches_for_company(master)
    branch_guid = next((str(row.get("Guid") or "").strip() for row in branches if row.get("Guid")), "")
    existing = _select_all("owner_master", 'id,"Owner name",tally_guid')
    by_tally = {
        str(row.get("tally_guid") or "").strip(): row
        for row in existing
        if row.get("tally_guid")
    }
    known_names = {owner_match_key(row) for row in existing if owner_match_key(row)}
    company_name = (master or {}).get("tally_company_name")
    to_insert: list[dict[str, Any]] = []
    updated = 0
    seen: set[str] = set()
    headers = {
        "apikey": supabase_key(),
        "Authorization": f"Bearer {supabase_key()}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    for ledger in ledgers:
        tally_guid = str(ledger.get("guid") or "").strip()
        name_key = owner_match_key({"Owner name": ledger.get("mailing_name") or ledger.get("name")})
        payload = owner_row(ledger, branch_guid or None, company_name)
        if not payload.get("Owner name"):
            continue
        existing_row = by_tally.get(tally_guid) if tally_guid else None
        if existing_row and existing_row.get("id"):
            body = dict(payload)
            body.pop("Guid", None)
            response = requests.patch(
                _rest("owner_master"),
                headers=headers,
                params={"id": f"eq.{existing_row['id']}"},
                json=body,
                timeout=30,
            )
            if response.ok:
                updated += 1
            continue
        if tally_guid and tally_guid in seen:
            continue
        if not tally_guid and name_key and name_key in known_names:
            continue
        to_insert.append(payload)
        if tally_guid:
            seen.add(tally_guid)
        if name_key:
            known_names.add(name_key)
    return updated + _bulk_insert("owner_master", to_insert)


def upsert_app_stock_from_tally(
    items: list[dict[str, Any]],
    master: dict[str, Any] | None,
) -> tuple[int, int, int]:
    from sync.app_catalog import alloy_catalog_row, classify_stock, material_row, tyre_catalog_row

    company_name = (master or {}).get("tally_company_name")
    tyres: list[dict[str, Any]] = []
    alloys: list[dict[str, Any]] = []
    materials: list[dict[str, Any]] = []
    seen_material: set[str] = set()
    for item in items:
        kind = classify_stock(item)
        material = material_row(item, kind, company_name)
        if material:
            key = str(material.get("name") or "").casefold()
            if key and key not in seen_material:
                seen_material.add(key)
                materials.append(material)
        if kind == "tyre":
            row = tyre_catalog_row(item, company_name)
            if row:
                tyres.append(row)
        elif kind == "alloy":
            row = alloy_catalog_row(item, company_name)
            if row:
                alloys.append(row)

    return (
        _upsert_catalog_rows(
            "tyre_catalog",
            tyres,
            _select_all("tyre_catalog", "id,brand,model,size,Guid"),
            ("brand", "model", "size"),
        ),
        _upsert_catalog_rows(
            "alloy_catalog",
            alloys,
            _select_all("alloy_catalog", "id,brand,model,size,Guid"),
            ("brand", "model", "size"),
        ),
        _upsert_catalog_rows(
            "materials",
            materials,
            _select_all("materials", "id,name,Guid"),
            ("name",),
        ),
    )


def _catalog_key(row: dict[str, Any], keys: tuple[str, ...]) -> tuple[str, ...]:
    return tuple(str(row.get(key) or "").casefold() for key in keys)


def _upsert_catalog_rows(
    table: str,
    incoming: list[dict[str, Any]],
    existing: list[dict[str, Any]],
    match_keys: tuple[str, ...],
) -> int:
    """Insert new catalog rows; PATCH existing when Tally AlterID changed."""
    if not incoming:
        return 0
    by_guid = {str(row.get("Guid") or "").strip(): row for row in existing if row.get("Guid")}
    by_key = {_catalog_key(row, match_keys): row for row in existing}
    to_insert: list[dict[str, Any]] = []
    updated = 0
    headers = {
        "apikey": supabase_key(),
        "Authorization": f"Bearer {supabase_key()}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    for row in incoming:
        guid = str(row.get("Guid") or "").strip()
        match = (by_guid.get(guid) if guid else None) or by_key.get(_catalog_key(row, match_keys))
        if match and match.get("id"):
            body = {key: value for key, value in row.items() if value not in (None, "")}
            body.pop("Guid", None)
            response = requests.patch(
                _rest(table),
                headers=headers,
                params={"id": f"eq.{match['id']}"},
                json=body,
                timeout=30,
            )
            if response.ok:
                updated += 1
            continue
        to_insert.append(row)
        if guid:
            by_guid[guid] = row
        by_key[_catalog_key(row, match_keys)] = row
    return updated + _bulk_insert(table, to_insert)


def list_stock_catalog() -> list[dict[str, Any]]:
    global _STOCK_CATALOG_CACHE, _STOCK_CATALOG_CACHED_AT
    now = time.time()
    if _STOCK_CATALOG_CACHE and (now - _STOCK_CATALOG_CACHED_AT < 300):
        return _STOCK_CATALOG_CACHE
    response = requests.get(
        _rest(STOCK_TABLE),
        headers=_headers(),
        params={"select": "name,stock_group,base_unit,part_number,guid", "limit": "5000"},
        timeout=30,
    )
    if response.status_code == 404 or "PGRST205" in (response.text or ""):
        return []
    _raise_for_rest(response, "select stock catalog")
    _STOCK_CATALOG_CACHE = response.json()
    _STOCK_CATALOG_CACHED_AT = now
    return _STOCK_CATALOG_CACHE


SYNC_STATUS_SQL = "sql/007_tally_sync_status.sql"
_FAKE_GUID_PREFIXES = ("TYREX-SALES-", "TYREX-RCPT-", "TYREX-ITEM-")


def is_branch_guid(value: Any) -> bool:
    text = str(value or "").strip()
    if not text:
        return False
    upper = text.upper()
    return not any(upper.startswith(prefix) for prefix in _FAKE_GUID_PREFIXES)


def row_branch_guid(row: dict[str, Any] | None) -> str:
    text = str((row or {}).get("Guid") or "").strip()
    return text if is_branch_guid(text) else ""


def report_has_branch_guid(report: dict[str, Any] | None) -> bool:
    report = report or {}
    if row_branch_guid(report):
        return True
    return any(row_branch_guid(payment) for payment in report.get("payments") or [])


def payments_with_branch_guid(payments: list[dict[str, Any]] | None) -> list[dict[str, Any]]:
    return [row for row in (payments or []) if row_branch_guid(row)]


def restore_payment_branch_guids() -> int:
    """Undo TYREX-SALES-* written onto payments.Guid; put back reports.Guid (branch)."""
    payments = list_payments()
    damaged = [row for row in payments if str(row.get("Guid") or "").upper().startswith("TYREX-SALES-")]
    if not damaged:
        return 0
    report_ids = sorted({int(row["report_id"]) for row in damaged if row.get("report_id") is not None})
    reports = _select_in(
        "reports",
        [str(item) for item in report_ids],
        action="select report branch Guid",
        select="id,Guid",
    )
    guid_by_report = {
        int(row["id"]): str(row.get("Guid") or "").strip()
        for row in reports
        if row.get("id") is not None and is_branch_guid(row.get("Guid"))
    }
    grouped: dict[str, list[int]] = {}
    for row in damaged:
        rid = row.get("report_id")
        guid = guid_by_report.get(int(rid)) if rid is not None else ""
        if not guid or not row.get("id"):
            continue
        grouped.setdefault(guid, []).append(int(row["id"]))
    headers = {
        "apikey": supabase_key(),
        "Authorization": f"Bearer {supabase_key()}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    restored = 0
    print(f"Restoring {sum(len(v) for v in grouped.values())} payment Guid(s) from reports.Guid ...", flush=True)
    for guid, payment_ids in grouped.items():
        for start in range(0, len(payment_ids), _IN_FILTER_CHUNK):
            chunk = payment_ids[start : start + _IN_FILTER_CHUNK]
            response = requests.patch(
                _rest("payments"),
                headers=headers,
                params={"id": f"in.({','.join(str(item) for item in chunk)})"},
                json={"Guid": guid},
                timeout=30,
            )
            _raise_for_rest(response, "restore payment branch Guid")
            restored += len(chunk)
    if restored:
        print(f"  restored {restored} payment branch Guid(s).", flush=True)
    return restored


def list_payments() -> list[dict[str, Any]]:
    params = {
        "select": (
            "id,report_id,method,amount,paid_at,transaction_id,Guid,voucher_type,"
            "tally_guid,tally_company,tally_company_id,branch_id,branch_name,"
            "tally_sync_status,tally_synced_at,alter_id,notes"
        ),
        "order": "id.desc",
        "limit": "20000",
    }
    response = requests.get(_rest("payments"), headers=_headers(), params=params, timeout=30)
    if response.status_code == 400 and (
        "tally_sync_status" in (response.text or "") or "alter_id" in (response.text or "") or "notes" in (response.text or "")
    ):
        print(f"  Run {SYNC_STATUS_SQL} in the Supabase SQL Editor to add tally_sync_status.", flush=True)
        params["select"] = (
            "id,report_id,method,amount,paid_at,transaction_id,Guid,voucher_type,"
            "tally_guid,tally_company,tally_company_id,branch_id,branch_name"
        )
        if "alter_id" not in (response.text or ""):
            params["select"] += ",alter_id"
        if "tally_sync_status" not in (response.text or ""):
            params["select"] += ",tally_sync_status,tally_synced_at"
        if "notes" not in (response.text or ""):
            params["select"] += ",notes"
        response = requests.get(_rest("payments"), headers=_headers(), params=params, timeout=30)
    _raise_for_rest(response, "select payments")
    return response.json()


def list_owners(ids: list[str]) -> dict[str, dict[str, Any]]:
    unique = [str(item) for item in sorted({item for item in ids if item})]
    missing = [item for item in unique if item not in _OWNERS_CACHE]
    if missing:
        rows = _select_in(
            "owner_master",
            missing,
            action="select owners",
            select='id,"Owner name",PhoneNumber,MobileNumber,"GST Number",pannumber,state,pincode,"Address Line1",Guid',
        )
        for row in rows:
            if row.get("id"):
                _OWNERS_CACHE[str(row["id"])] = row
    return {item: _OWNERS_CACHE[item] for item in unique if item in _OWNERS_CACHE}


def list_vehicles(ids: list[int]) -> dict[int, dict[str, Any]]:
    unique = [int(item) for item in sorted({int(item) for item in ids if item is not None})]
    missing = [str(item) for item in unique if item not in _VEHICLES_CACHE]
    if missing:
        rows = _select_in(
            "vehicles",
            missing,
            action="select vehicles",
            select='id,"Vehicle Number",model_id,odometer,owner_id,"Model name",company_name,Guid',
        )
        for row in rows:
            if row.get("id") is not None:
                _VEHICLES_CACHE[int(row["id"])] = row
    return {item: _VEHICLES_CACHE[item] for item in unique if item in _VEHICLES_CACHE}


def list_vehicle_models(ids: list[int]) -> dict[int, dict[str, Any]]:
    unique = [int(item) for item in sorted({int(item) for item in ids if item is not None})]
    missing = [str(item) for item in unique if item not in _MODELS_CACHE]
    if missing:
        rows = _select_in(
            "vehicle_models",
            missing,
            action="select vehicle models",
            select='id,brand,"Model name"',
        )
        for row in rows:
            if row.get("id") is not None:
                _MODELS_CACHE[int(row["id"])] = row
    return {item: _MODELS_CACHE[item] for item in unique if item in _MODELS_CACHE}


def _parse_row_date(raw: Any) -> date | None:
    text = str(raw or "").strip()[:10]
    try:
        return date.fromisoformat(text)
    except ValueError:
        return None


def report_in_sync_window(report: dict[str, Any] | None) -> bool:
    report = report or {}
    since = sync_since_date()
    until = sync_until_date()
    found: list[date] = []
    for key in ("billed_at", "paid_at", "completed_at", "created_at"):
        parsed = _parse_row_date(report.get(key))
        if parsed:
            found.append(parsed)
    for payment in report.get("payments") or []:
        parsed = _parse_row_date(payment.get("paid_at"))
        if parsed:
            found.append(parsed)
    if not found:
        return True
    return any(since <= item <= until for item in found)


def list_sales_reports(limit: int | None = None, current_company: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    global _BRANCHES_CACHE, _BRANCHES_CACHED_AT
    payments = list_payments()
    paid_ids = {int(row["report_id"]) for row in payments if row.get("report_id") is not None}
    
    report_select = (
        "id,vehicle_id,complaint,suggested,approved,status,created_at,expected_delivery,"
        "odometer_reading,Owner name,client_phone,materials_required,labour_cost,branch_id,"
        "branch_name,company_name,Guid,jobcard_number,bill_status,job_card_id,billing_status,"
        "billed_at,paid_at,payment_method,payment_notes,gst_percent,discount_amount,discount_type,"
        "extra_charge_amount,extra_charge_label,tally_sync_status,tally_synced_at,tally_guid,tally_company,alter_id"
    )
    
    params: dict[str, str] = {
        "select": report_select,
        "or": "(billing_status.eq.Paid,billing_status.eq.Billed,billed_at.not.is.null,status.eq.Completed,status.ilike.%complete%)",
        "order": "id.desc",
        "limit": str(limit or 1000),
    }
    response = requests.get(_rest("reports"), headers=_headers(), params=params, timeout=30)
    if response.status_code == 400:
        # If columns like alter_id/tally_sync_status don't exist yet, retry with universal *
        params["select"] = "*"
        response = requests.get(_rest("reports"), headers=_headers(), params=params, timeout=30)
    _raise_for_rest(response, "select completed/billed reports")
    rows = response.json()
    have = {int(row["id"]) for row in rows if row.get("id") is not None}
    missing = paid_ids - have
    if missing:
        extra_rows = _select_in(
            "reports",
            [str(item) for item in sorted(missing)],
            action="select paid reports",
            select=params.get("select", "*"),
            limit=1000,
        )
        rows.extend(extra_rows)
    vehicles = list_vehicles([int(row["vehicle_id"]) for row in rows if row.get("vehicle_id")])
    model_ids = [int(v["model_id"]) for v in vehicles.values() if v.get("model_id")]
    models_map = list_vehicle_models(model_ids)
    payments_by_report: dict[int, list[dict[str, Any]]] = {}
    for payment in payments:
        rid = payment.get("report_id")
        if rid is None:
            continue
        payments_by_report.setdefault(int(rid), []).append(payment)
    cleaned: list[dict[str, Any]] = []
    for row in rows:
        row.pop("photo_urls", None)
        row.pop("after_photo_urls", None)
        row.pop("customer_feedback_audio", None)
        row.pop("gdrive_folder_url", None)
        vehicle = vehicles.get(int(row["vehicle_id"])) if row.get("vehicle_id") else None
        v_model = models_map.get(int(vehicle["model_id"])) if (vehicle and vehicle.get("model_id")) else {}
        brand = (v_model or {}).get("brand") or (vehicle or {}).get("Brand name") or (vehicle or {}).get("brand") or (vehicle or {}).get("Brand")
        model_name = (v_model or {}).get("Model name") or (vehicle or {}).get("Model name") or (vehicle or {}).get("model_name") or (vehicle or {}).get("vehicle_name")
        row["vehicle"] = vehicle
        row["vehicle_number"] = (vehicle or {}).get("Vehicle Number")
        row["vehicle_brand"] = brand
        row["vehicle_model"] = model_name
        if row.get("odometer_reading") in (None, ""):
            row["odometer_reading"] = (vehicle or {}).get("odometer")
        row["owner_id"] = (vehicle or {}).get("owner_id")
        row["payments"] = payments_by_report.get(int(row["id"]), [])
        cleaned.append(row)
    owners = list_owners([str(row.get("owner_id") or "") for row in cleaned])
    cleaned.sort(key=lambda item: int(item.get("id") or 0))
    now = time.time()
    if not _BRANCHES_CACHE or (now - _BRANCHES_CACHED_AT >= 300):
        _BRANCHES_CACHE = _select_all("branches", "id,branch_name,Guid,tally_company_id,tally_company,tally_guid")
        _BRANCHES_CACHED_AT = now
    branches = _BRANCHES_CACHE
    branches_map = {}
    for b in branches:
        if b.get("id"):
            branches_map[str(b["id"]).strip().lower()] = b
        if b.get("Guid"):
            branches_map[str(b["Guid"]).strip().lower()] = b
        if b.get("branch_name"):
            branches_map[_company_name_key(b["branch_name"])] = b

    for row in cleaned:
        row["owner"] = owners.get(str(row.get("owner_id") or ""))
        if not report_has_branch_guid(row):
            row["needs_tally_company_fill"] = False
            continue
        r_bid = str(row.get("branch_id") or "").strip().lower()
        r_bguid = str(row.get("Guid") or "").strip().lower()
        r_bname = _company_name_key(row.get("branch_name") or row.get("company_name"))
        branch = branches_map.get(r_bid) or branches_map.get(r_bguid) or branches_map.get(r_bname)
        if branch and branch.get("tally_company_id"):
            row["tally_company_id"] = branch.get("tally_company_id")
            row["tally_company"] = branch.get("tally_company")
            row["tally_guid"] = branch.get("tally_guid")
            row["needs_tally_company_fill"] = True
        elif branch:
            row["tally_company_id"] = None
            row["tally_company"] = None
            row["tally_guid"] = None
            row["needs_tally_company_fill"] = False
        else:
            row["needs_tally_company_fill"] = False
    cleaned = [row for row in cleaned if report_in_sync_window(row)]
    if limit:
        return cleaned[:limit]
    return cleaned


def _company_name_key(value: Any) -> str:
    return " ".join(str(value or "").split()).casefold()


def report_matches_open_company(report: dict[str, Any] | None, company: dict[str, Any] | None) -> bool:
    report = report or {}
    if not payments_with_branch_guid(report.get("payments")) and not row_branch_guid(report):
        return False
    if not company:
        return True
    company_id = str(company.get("id") or "").strip()
    company_guid = str(company.get("tally_guid") or "").strip().casefold()
    company_name = _company_name_key(company.get("tally_company_name"))
    report_id = str(report.get("tally_company_id") or "").strip()
    report_guid = str(report.get("tally_guid") or "").strip().casefold()
    report_name = _company_name_key(report.get("tally_company"))
    assigned = bool(report_id or report_guid or report_name)
    if not assigned:
        return False
    if company_id and report_id and company_id == report_id:
        return True
    if company_guid and report_guid and company_guid == report_guid:
        return True
    if company_name and report_name and company_name == report_name:
        return True
    return False


def payment_has_alter(row: dict[str, Any] | None) -> bool:
    value = (row or {}).get("alter_id")
    return value not in (None, "", 0, "0")


def payment_is_synced(row: dict[str, Any] | None) -> bool:
    if payment_has_alter(row):
        return False
    status = str((row or {}).get("tally_sync_status") or "").strip().lower()
    if status:
        return status == "synced"
    return False


def posted_sales_report_ids(payments: list[dict[str, Any]] | None = None) -> set[int]:
    rows = payments if payments is not None else list_payments()
    by_report: dict[int, list[dict[str, Any]]] = {}
    for row in rows:
        if row.get("report_id") is None:
            continue
        by_report.setdefault(int(row["report_id"]), []).append(row)
    posted: set[int] = set()
    for report_id, group in by_report.items():
        if group and all(payment_is_synced(item) for item in group):
            posted.add(report_id)
    return posted


def mark_tally_sync(sale: dict[str, Any], status: str) -> int:
    now = datetime.now(timezone.utc).isoformat() if status == "synced" else None
    payload = {
        "tally_sync_status": status,
        "tally_synced_at": now,
        "tally_company": sale.get("company"),
        "tally_company_id": sale.get("tally_company_id"),
        "tally_guid": sale.get("tally_guid"),
    }
    if status == "synced":
        payload["alter_id"] = None
    saved = 0
    headers = {
        "apikey": supabase_key(),
        "Authorization": f"Bearer {supabase_key()}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    missing_column = False
    for payment in sale.get("payments") or []:
        payment_id = payment.get("id")
        if payment_id is None:
            continue
        if not row_branch_guid(payment):
            continue
        body = dict(payload)
        if not str(payment.get("voucher_type") or "").strip():
            body["voucher_type"] = sale.get("voucher_type_label") or sale.get("voucher_type")
        response = requests.patch(
            _rest("payments"),
            headers=headers,
            params={"id": f"eq.{int(payment_id)}"},
            json=body,
            timeout=30,
        )
        if response.status_code == 400 and "alter_id" in (response.text or "") and "alter_id" in body:
            body.pop("alter_id", None)
            response = requests.patch(
                _rest("payments"),
                headers=headers,
                params={"id": f"eq.{int(payment_id)}"},
                json=body,
                timeout=30,
            )
        if response.status_code == 400 and "tally_sync_status" in (response.text or ""):
            missing_column = True
            break
        _raise_for_rest(response, f"stamp payment {payment_id} {status}")
        saved += 1
    report_body = {
        "tally_sync_status": status,
        "tally_synced_at": now,
    }
    if sale.get("fill_report_company"):
        for key in ("tally_company", "tally_company_id", "tally_guid"):
            if payload.get(key):
                report_body[key] = payload[key]
    response = requests.patch(
        _rest("reports"),
        headers=headers,
        params={"id": f"eq.{int(sale['report_id'])}"},
        json=report_body,
        timeout=30,
    )
    if response.status_code == 400 and "tally_sync_status" in (response.text or ""):
        missing_column = True
    elif response.ok:
        saved += 1
    else:
        _raise_for_rest(response, f"stamp report {sale['report_id']} {status}")
    if missing_column:
        print(f"  Run {SYNC_STATUS_SQL} in the Supabase SQL Editor to store pending/synced.", flush=True)
    return saved


def mark_sales_posted(sales: list[dict[str, Any]]) -> int:
    return sum(mark_tally_sync(sale, "synced") for sale in sales)


_LAST_CONVERTED_SYNC: float = 0.0


def sync_converted_sales_from_tally(company_name: str) -> int:
    """Fetch all Sales Invoices from Tally and update is_converted = True on Supabase reports."""
    global _LAST_CONVERTED_SYNC
    from sync.tally_xml import post_xml, escape
    import re

    if not company_name:
        return 0
    now_ts = time.time()
    if now_ts - _LAST_CONVERTED_SYNC < 600:
        return 0
    _LAST_CONVERTED_SYNC = now_ts

    from datetime import datetime, timedelta
    today = datetime.now()
    from_date = (today - timedelta(days=60)).strftime("%Y%m%d")
    to_date = (today + timedelta(days=1)).strftime("%Y%m%d")

    xml = f"""<ENVELOPE>
 <HEADER>
  <VERSION>1</VERSION>
  <TALLYREQUEST>Export</TALLYREQUEST>
  <TYPE>Collection</TYPE>
  <ID>TyrexSalesVouchersCol</ID>
 </HEADER>
 <BODY>
  <DESC>
   <STATICVARIABLES>
    <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
    <SVCURRENTCOMPANY>{escape(company_name)}</SVCURRENTCOMPANY>
    <SVFROMDATE>{from_date}</SVFROMDATE>
    <SVTODATE>{to_date}</SVTODATE>
   </STATICVARIABLES>
   <TDL>
    <TDLMESSAGE>
     <COLLECTION NAME="TyrexSalesVouchersCol" ISMODIFY="No" ISFIXED="No" ISINITIALIZE="Yes">
      <TYPE>Voucher</TYPE>
      <FETCH>VOUCHERNUMBER,VOUCHERTYPENAME,DATE,BASICPURCHASEORDERNO,INVOICEORDERLIST.BASICPURCHASEORDERNO,REFERENCE,NARRATION</FETCH>
      <FILTER>IsSalesFilter</FILTER>
     </COLLECTION>
     <SYSTEM TYPE="Formulae" NAME="IsSalesFilter">
      $$IsSales:$VoucherTypeName
     </SYSTEM>
    </TDLMESSAGE>
   </TDL>
  </DESC>
 </BODY>
</ENVELOPE>"""
    try:
        res = post_xml(xml, timeout=10)
    except Exception as exc:  # noqa: BLE001
        print(f"  check converted sales skipped: {exc}", flush=True)
        return 0

    vouchers = re.findall(r'<VOUCHER(?:\s[^>]*)?>(.*?)</VOUCHER>', res, flags=re.I | re.S)
    jc_regex = re.compile(r'(TYX\d{4,10}(?:-A\d+)?|JC-\d{4,8}(?:-A\d+)?|TES\d{4,10}(?:-A\d+)?)', re.I)

    found_orders: set[str] = set()
    for v_text in vouchers:
        vtype_m = re.search(r'<VOUCHERTYPENAME[^>]*>(.*?)</VOUCHERTYPENAME>', v_text, flags=re.I)
        vtype = vtype_m.group(1).strip() if vtype_m else ""
        if "order" in vtype.lower() or vtype.lower() == "job cards":
            continue
        matches = jc_regex.findall(v_text)
        for m in matches:
            found_orders.add(m.strip().upper())

    if not found_orders:
        return 0

    # Only patch reports that are not already marked is_converted = True in Supabase
    try:
        unconverted_rows = _select_all("reports", "id,jobcard_number,job_card_id", extra={"is_converted": "neq.true"})
    except Exception as e:
        print(f"  error querying unconverted rows: {e}", flush=True)
        unconverted_rows = []

    target_ids = set()
    for row in unconverted_rows:
        jc1 = str(row.get("jobcard_number") or "").strip().upper()
        jc2 = str(row.get("job_card_id") or "").strip().upper()
        jc1_base = re.sub(r'-A\d+$', '', jc1)
        jc2_base = re.sub(r'-A\d+$', '', jc2)
        if any(code in found_orders for code in (jc1, jc2, jc1_base, jc2_base) if code):
            if row.get("id"):
                target_ids.add(str(row["id"]))

    if not target_ids:
        return 0

    print(f"  found {len(target_ids)} newly converted sales invoice voucher(s) in Tally", flush=True)
    headers = _headers()
    headers["Prefer"] = "return=minimal"
    target_list = list(target_ids)
    updated_count = 0
    now_iso = datetime.now().isoformat()
    for start in range(0, len(target_list), 50):
        chunk = target_list[start : start + 50]
        params = {"id": f"in.({','.join(chunk)})"}
        try:
            resp = requests.patch(
                _rest("reports"),
                headers=headers,
                params=params,
                json={"is_converted": True, "billing_status": "Billed", "billed_at": now_iso},
                timeout=10,
            )
            if resp.ok:
                updated_count += len(chunk)
        except Exception:
            pass

    return updated_count
