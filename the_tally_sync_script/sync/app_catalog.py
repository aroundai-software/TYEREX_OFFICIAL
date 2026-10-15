from __future__ import annotations

import re
from typing import Any

from sync.tally_voucher import BRANDS, SIZE_RE, _has_brand, _norm

TYRE_GROUP_RE = re.compile(r"\b(tyre|tire|tube)\b", re.I)
ALLOY_GROUP_RE = re.compile(r"\b(alloy|alloys|rim|rims)\b", re.I)
SIZE_COMPACT_RE = re.compile(r"(\d{2,3})\s*/\s*(\d{2})\s*R?\s*(\d{2})", re.I)


def classify_stock(item: dict[str, Any]) -> str:
    blob = " ".join(
        str(item.get(key) or "")
        for key in ("stock_group", "category", "name", "description")
    )
    if ALLOY_GROUP_RE.search(blob):
        return "alloy"
    if TYRE_GROUP_RE.search(blob) or SIZE_RE.search(blob):
        return "tyre"
    if any(_has_brand(blob, brand) for brand in BRANDS):
        return "tyre"
    return "other"


def parse_size(name: str) -> str:
    match = SIZE_COMPACT_RE.search(name or "")
    if not match:
        return ""
    return f"{match.group(1)}/{match.group(2)}R{match.group(3)}"


def parse_brand(name: str) -> str:
    for brand in BRANDS:
        if _has_brand(name, brand):
            return brand.title().replace("Mrf", "MRF").replace("Jk", "JK")
    return ""


def parse_model(name: str, brand: str, size: str) -> str:
    text = name or ""
    if size:
        text = SIZE_COMPACT_RE.sub(" ", text)
    if brand:
        text = re.sub(re.escape(brand), " ", text, flags=re.I)
        if brand.lower() == "mrf":
            text = re.sub(r"\bmrf\b", " ", text, flags=re.I)
    text = re.sub(r"\b(tyre|tire|alloy|alloys|nos)\b", " ", text, flags=re.I)
    return " ".join(text.split()).strip()


def tyre_catalog_row(item: dict[str, Any], company_name: str | None) -> dict[str, Any] | None:
    name = str(item.get("name") or "").strip()
    if not name:
        return None
    brand = parse_brand(name)
    size = parse_size(name)
    model = parse_model(name, brand, size)
    if not brand:
        brand = str(item.get("stock_group") or "Tally").strip() or "Tally"
    if not model:
        model = name
    return {
        "brand": brand,
        "model": model,
        "size": size or "-",
        "li_si": None,
        "basic_price": item.get("cost_price") or item.get("opening_rate"),
        "billing_price": item.get("selling_price") or item.get("closing_rate"),
        "company_name": company_name,
        "Guid": item.get("guid"),
        "MasterID": item.get("master_id"),
        "tally_name": name,
    }


def alloy_catalog_row(item: dict[str, Any], company_name: str | None) -> dict[str, Any] | None:
    name = str(item.get("name") or "").strip()
    if not name:
        return None
    brand = parse_brand(name) or str(item.get("stock_group") or "Alloy").strip() or "Alloy"
    size = parse_size(name)
    model = parse_model(name, brand, size) or name
    return {
        "brand": brand,
        "model": model,
        "size": size or "-",
        "basic_price": item.get("cost_price") or item.get("opening_rate"),
        "billing_price": item.get("selling_price") or item.get("closing_rate"),
        "company_name": company_name,
        "Guid": item.get("guid"),
        "MasterID": item.get("master_id"),
        "tally_name": name,
    }


def material_row(item: dict[str, Any], kind: str, company_name: str | None) -> dict[str, Any] | None:
    name = str(item.get("name") or "").strip()
    if not name:
        return None
    category = {
        "tyre": "Tyre",
        "alloy": "Alloy",
    }.get(kind) or str(item.get("stock_group") or "Tally").strip() or "Tally"
    return {
        "name": name,
        "category": category,
        "unit": item.get("base_unit") or "Nos",
        "description": item.get("description") or item.get("part_number"),
        "is_active": True,
        "Guid": item.get("guid"),
        "MasterID": item.get("master_id"),
        "company_name": company_name,
    }


def owner_display_name(ledger: dict[str, Any]) -> str:
    mailing = str(ledger.get("mailing_name") or "").strip()
    name = str(ledger.get("name") or "").strip()
    return mailing or name or "CUSTOMER"


def owner_row(ledger: dict[str, Any], branch_guid: str | None, company_name: str | None) -> dict[str, Any]:
    phone = str(ledger.get("phone") or "").strip()
    mobile = str(ledger.get("mobile") or phone).strip()
    row = {
        "Owner name": owner_display_name(ledger),
        "alias": ledger.get("alias") or ledger.get("name"),
        "Address Line1": ledger.get("address_line1"),
        "Address Line2": ledger.get("address_line2"),
        "Address Line3": ledger.get("address_line3"),
        "state": ledger.get("state"),
        "country": ledger.get("country") or "India",
        "pincode": ledger.get("pincode"),
        "PhoneNumber": phone or None,
        "MobileNumber": mobile or None,
        "email": ledger.get("email"),
        "pannumber": ledger.get("pan"),
        "GST Number": ledger.get("gstin"),
        "MasterID": ledger.get("master_id"),
        "tally_guid": ledger.get("guid"),
        "company_name": company_name,
    }
    if branch_guid:
        row["Guid"] = branch_guid
    cleaned = {key: value for key, value in row.items() if value not in (None, "")}
    cleaned["Owner name"] = owner_display_name(ledger)
    return cleaned


def owner_match_key(row: dict[str, Any]) -> str:
    return _norm(str(row.get("Owner name") or row.get("name") or ""))


def digits(value: Any) -> str:
    return re.sub(r"\D", "", str(value or ""))
