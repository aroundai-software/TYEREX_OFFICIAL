from __future__ import annotations

import html
import json
import re
import time
from datetime import datetime
from typing import Any
from xml.sax.saxutils import escape as _xml_escape

import requests

from sync.tally_xml import GSTIN_RE, TallyUnavailable, post_xml

# Company + kind + name already accepted by Tally in this process.
# Re-importing existing units/ledgers/voucher types on every bill locks Tally
# (Windows error 32 on trannum) and makes the HTTP server stop.
_MASTER_OK: set[tuple[str, str, str]] = set()


def escape(text: Any) -> str:
    return _xml_escape(str(text or ""), {'"': "&quot;"})


def _master_key(company: str, kind: str, name: str) -> tuple[str, str, str]:
    return ((company or "").casefold(), kind, (name or "").casefold())


def _have_master(company: str, kind: str, name: str) -> bool:
    return _master_key(company, kind, name) in _MASTER_OK


def _remember_masters(company: str, kind: str, names: list[str] | set[str] | None) -> None:
    for name in names or []:
        if name:
            _MASTER_OK.add(_master_key(company, kind, name))


def _is_unknown_request(text: str) -> bool:
    return "UNKNOWN REQUEST" in (text or "").upper()


def _names_collection_xml(company_name: str, object_type: str, col_id: str) -> str:
    safe = escape(company_name)
    return f"""<ENVELOPE>
 <HEADER>
  <VERSION>1</VERSION>
  <TALLYREQUEST>Export</TALLYREQUEST>
  <TYPE>Collection</TYPE>
  <ID>{col_id}</ID>
 </HEADER>
 <BODY>
  <DESC>
   <STATICVARIABLES>
    <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
    <SVCURRENTCOMPANY>{safe}</SVCURRENTCOMPANY>
   </STATICVARIABLES>
   <TDL>
    <TDLMESSAGE>
     <COLLECTION NAME="{col_id}" ISMODIFY="No" ISFIXED="No" ISINITIALIZE="Yes">
      <TYPE>{object_type}</TYPE>
      <NATIVEMETHOD>Name</NATIVEMETHOD>
     </COLLECTION>
    </TDLMESSAGE>
   </TDL>
  </DESC>
 </BODY>
</ENVELOPE>
"""


def _parse_master_names(xml_text: str) -> list[str]:
    names: list[str] = []
    seen: set[str] = set()
    for match in re.findall(r"<NAME(?:\s[^>]*)?>(.*?)</NAME>", xml_text or "", flags=re.I | re.S):
        text = html.unescape(re.sub(r"<[^>]+>", "", match)).strip()
        key = text.casefold()
        if not text or key in seen:
            continue
        seen.add(key)
        names.append(text)
    return names


def prime_existing_masters(company_name: str) -> None:
    if _have_master(company_name, "flag", "primed"):
        return
    print("  checking existing Tally ledgers ...", flush=True)
    try:
        xml = post_xml(
            _names_collection_xml(company_name, "Ledger", "TyrexLedgerCol"),
            timeout=12,
        )
        names = _parse_master_names(xml)
        _remember_masters(company_name, "ledger", names)
        _remember_masters(company_name, "party", names)
        print(f"    Ledger: {len(names)} already in Tally", flush=True)
    except TallyUnavailable:
        raise
    except Exception as exc:  # noqa: BLE001
        print(f"    Ledger list skipped: {exc}", flush=True)
    _remember_masters(company_name, "flag", ["primed"])


VOUCHER_SALES_ORDER = "Job Cards"
VOUCHER_SALES_B2C = "SALES -B2C"
VOUCHER_GST_B2C = "GST SALES (B2C)"
VOUCHER_GST_B2B = "GST SALES (B2B)"
VOUCHER_TYPE = VOUCHER_SALES_ORDER
RECEIPT_TYPE = "Receipt"
VOUCHER_TYPE_ALIASES = {
    "jobcards": VOUCHER_SALES_ORDER,
    "jobcard": VOUCHER_SALES_ORDER,
    "salesorder": VOUCHER_SALES_ORDER,
    "salesorderjobcardapp": VOUCHER_SALES_ORDER,
    "salesb2c": VOUCHER_SALES_B2C,
    "gstsalesb2c": VOUCHER_GST_B2C,
    "gstsalesb2b": VOUCHER_GST_B2B,
}
VOUCHER_TYPE_PRIORITY = {
    VOUCHER_GST_B2B: 4,
    VOUCHER_GST_B2C: 3,
    VOUCHER_SALES_B2C: 2,
    VOUCHER_SALES_ORDER: 1,
}
VOUCHER_TYPE_LABELS = {
    VOUCHER_SALES_ORDER: "JOB CARDS",
    VOUCHER_SALES_B2C: "SALES B2C",
    VOUCHER_GST_B2C: "GST SALES B2C",
    VOUCHER_GST_B2B: "GST SALES B2B",
}
INVENTORY_SALES_LEDGER = "GST SALES"
DEFAULT_SALES_LEDGER = "SERVICE"
DISCOUNT_LEDGER = "Discount Allowed -Sales"
ROUND_OFF_LEDGER = "Round Off"
CGST_LEDGER = "CGST OUTPUT"
SGST_LEDGER = "SGST OUTPUT"
DEFAULT_GST_PERCENT = 18.0
DEFAULT_TYRE_HSN = "40111010"
DEFAULT_COST_CENTRE = "TYREX"
DEFAULT_STATE = "Kerala"
DEFAULT_UNIT = "nos"
DEFAULT_STOCK_GROUP = "R16"
DEFAULT_DUMMY_STOCK_ITEM = "Service Item"
SUNDRY_DEBTORS = "Sundry Debtors"
SALES_LEDGER_PARENT = "Sales Accounts"
TAX_LEDGER_PARENT = "Duties & Taxes"
EXPENSE_LEDGER_PARENT = "Indirect Expenses"

LEDGER_ALIASES = {
    "wheelalignment": "Wheel Alignment",
    "alignment": "Wheel Alignment",
    "wheelbalancing": "Wheel Balancing",
    "balancing": "Wheel Balancing",
    "roadforcebalancing": "Wheel Balancing",
    "tyrefitting": "Tyre Fitting",
    "fitting": "Tyre Fitting",
    "tyrerotation": "Tyre Rotation",
    "rotation": "ROTATION",
    "nitrogentopup": "Nitrogen Topup & Filling",
    "nitrogenfilling": "Nitrogen Topup & Filling",
    "nitrogentopupfilling": "Nitrogen Topup & Filling",
    "puncture": "Punture",
    "punture": "Punture",
    "spacer": "SPACER -Sales",
    "alloybend": "ALLOY BEND / PATCH",
    "alloybendpatch": "ALLOY BEND / PATCH",
    "service": "SERVICE",
    "gstsales": "GST SALES",
}

SERVICE_LEDGERS = {
    "Wheel Alignment",
    "Wheel Balancing",
    "Tyre Fitting",
    "Tyre Rotation",
    "ROTATION",
    "Nitrogen Topup & Filling",
    "Punture",
    "SPACER -Sales",
    "ALLOY BEND / PATCH",
    "SERVICE",
}

COST_CENTRE_BY_BRANCH = {
    "thrissur": "THRISSUR",
    "kochi": "TYREX",
    "tyrex": "TYREX",
    "tyrex 2": "Tyrex 2",
    "tyrex2": "Tyrex 2",
    "palakkad": "Tyrex 2",
    "test": "TYREX",
}

GODOWN_BY_COST_CENTRE = {
    "THRISSUR": "THRISSUR",
}
DEFAULT_GODOWN = "Main Location"

STOCKISH_RE = re.compile(
    r"(\d{2,3}\s*/\s*\d{2})|(\br1[2-9]\b)|alloy|tyre|tire|nut|valve|wheel\s*nut|continental|michelin|bridgestone|goodyear|zeta",
    re.I,
)
SIZE_RE = re.compile(r"(\d{2,3})\s*/\s*(\d{2})\s*R\s*(\d{2})", re.I)
TYRE_PREFIX_RE = re.compile(r"^(tyre|tire)\s*[-:]\s*", re.I)
BRANDS = (
    "bridgestone",
    "goodyear",
    "continental",
    "michelin",
    "ceat",
    "apollo",
    "mrf",
    "jk",
    "yokohama",
    "pirelli",
    "hankook",
    "kumho",
    "falken",
    "zeta",
    "neo",
)


def _norm(value: str | None) -> str:
    text = (value or "").lower().replace("good year", "goodyear")
    return re.sub(r"[^a-z0-9]+", "", text)


def _has_brand(name: str, brand: str) -> bool:
    text = (name or "").lower().replace("good year", "goodyear")
    return brand in text


def _money(value: Any) -> float:
    try:
        return round(float(value or 0) + 1e-9, 2)
    except (TypeError, ValueError):
        return 0.0


def _json_list(raw: Any) -> list[Any]:
    if raw is None or raw == "":
        return []
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except json.JSONDecodeError:
            return []
    if isinstance(raw, dict):
        return [raw]
    if isinstance(raw, list):
        return raw
    return []


def _line_amount(item: dict[str, Any]) -> float:
    qty = _qty(item)
    for key in ("amount", "total", "billing_price", "price", "rate"):
        if item.get(key) not in (None, ""):
            value = _money(item.get(key))
            if key in {"rate", "price", "billing_price"} and qty:
                return _money(value * qty)
            return value
    return 0.0


def _qty(item: dict[str, Any]) -> float:
    for key in ("qty", "quantity", "billed_qty", "nos"):
        if item.get(key) not in (None, ""):
            return _money(item.get(key)) or 1.0
    return 0.0


def _line_text(item: dict[str, Any]) -> str:
    for key in ("text", "name", "stock_item", "item", "service", "ledger", "material"):
        value = item.get(key)
        if value:
            return str(value).strip()
    return ""


def _unit(item: dict[str, Any]) -> str:
    for key in ("unit", "base_unit", "uom"):
        if item.get(key):
            return str(item.get(key)).strip()
    return DEFAULT_UNIT


def sales_ledger_for(name: str) -> str:
    text = " ".join((name or "").split())
    key = _norm(text)
    if key in LEDGER_ALIASES:
        return LEDGER_ALIASES[key]
    for ledger in SERVICE_LEDGERS:
        if _norm(ledger) == key:
            return ledger
    return text or DEFAULT_SALES_LEDGER


def is_stock_line(item: dict[str, Any], name: str, ledger: str) -> bool:
    if ledger in SERVICE_LEDGERS and ledger != DEFAULT_SALES_LEDGER:
        return False
    if item.get("stock_item") or item.get("material"):
        return True
    return bool(STOCKISH_RE.search(name or ""))


def size_label(name: str) -> str | None:
    text = re.sub(r"(\d{2,3}/\d{2})\s*R(\d{2})", r"\1 R\2", name or "", flags=re.I)
    match = SIZE_RE.search(text)
    if not match:
        return None
    return f"{match.group(1)}/{match.group(2)} R{match.group(3)}"


def tally_stock_name(app_name: str) -> str:
    cleaned = TYRE_PREFIX_RE.sub("", (app_name or "").strip())
    size = size_label(cleaned)
    if size:
        rest = SIZE_RE.sub("", re.sub(r"(\d{2,3}/\d{2})\s*R(\d{2})", "", cleaned, flags=re.I))
        rest = " ".join(rest.split())
        return f"{size} {rest}".strip() if rest else size
    return " ".join(cleaned.split())


def match_stock_item(app_name: str, catalog: list[dict[str, Any]]) -> dict[str, Any] | None:
    wanted = _norm(tally_stock_name(app_name))
    raw = _norm(app_name)
    size = size_label(app_name)
    brand = next(
        (item for item in BRANDS if _has_brand(app_name, item)),
        None,
    )
    real_rows = [
        row
        for row in catalog
        if not str(row.get("guid") or "").startswith("TYREX-ITEM-")
    ]
    for row in real_rows:
        name = row.get("name") or ""
        key = _norm(name)
        if key and key in {wanted, raw}:
            return row
    best: dict[str, Any] | None = None
    best_score = 0
    for row in real_rows:
        name = row.get("name") or ""
        key = _norm(name)
        if not key:
            continue
        if size and _norm(size) not in key:
            continue
        if brand and not _has_brand(name, brand):
            continue
        score = 2 if size else 0
        for token in re.findall(r"[a-z0-9]{3,}", (app_name or "").lower()):
            if token in {"tyre", "tire", "nos"}:
                continue
            if token in name.lower():
                score += 1
        if score > best_score:
            best = row
            best_score = score
    if best and best_score >= 4:
        return best
    return None


def party_bank_for(method: str | None) -> str:
    text = (method or "").lower()
    if any(token in text for token in ("gpay", "google", "upi", "phonepe", "paytm")):
        return "Google Pay"
    if "card" in text:
        return "Yes Bank Card Machine"
    if "cash" in text:
        return "Cash"
    return "Google Pay" if text else "Cash"


def cost_centre_for(branch_name: str | None) -> str:
    key = (branch_name or "").strip().lower()
    return COST_CENTRE_BY_BRANCH.get(key, DEFAULT_COST_CENTRE)


def godown_for(cost_centre: str | None, branch_name: str | None = None) -> str:
    if cost_centre and cost_centre in GODOWN_BY_COST_CENTRE:
        return GODOWN_BY_COST_CENTRE[cost_centre]
    key = (branch_name or "").strip().lower()
    if "thrissur" in key:
        return "THRISSUR"
    return DEFAULT_GODOWN


def party_ledger_name(owner: str | None, phone: str | None) -> str:
    name = " ".join(str(owner or "CUSTOMER").split()).upper()
    digits = re.sub(r"\D", "", str(phone or ""))
    if digits:
        return f"{name} {digits}"
    return name


def extract_gstin(*values: Any) -> str:
    for value in values:
        if not value:
            continue
        match = GSTIN_RE.search(str(value))
        if match:
            return match.group(1).upper()
    return ""


def map_voucher_type(raw: str | None) -> str | None:
    if not raw:
        return None
    return VOUCHER_TYPE_ALIASES.get(_norm(raw))


def resolve_voucher_type(
    payments: list[dict[str, Any]] | None = None,
    gstin: str | None = None,
) -> str:
    return VOUCHER_SALES_ORDER


def voucher_type_label(tally_name: str) -> str:
    return VOUCHER_TYPE_LABELS.get(tally_name, tally_name)


ADDRESS_LINE_KEYS = (
    "Address Line1",
    "Address Line2",
    "Address Line3",
    "address_line1",
    "address_line2",
    "address_line3",
    "address",
    "Address",
)


def _first_text(*values: Any) -> str:
    for value in values:
        text = str(value or "").strip()
        if text and text.lower() not in {"none", "null", "n/a", "na"}:
            return text
    return ""


def owner_address_lines(owner: dict[str, Any] | None, report: dict[str, Any] | None = None) -> list[str]:
    source = owner or {}
    report = report or {}
    lines: list[str] = []
    for key in ADDRESS_LINE_KEYS:
        text = _first_text(source.get(key), report.get(key))
        if text and text not in lines:
            lines.append(text)
    pin = owner_pincode(source, report)
    if pin and not any(pin in line for line in lines):
        if lines:
            lines[-1] = f"{lines[-1]} - {pin}"
        else:
            lines.append(pin)
    return lines


def owner_pincode(owner: dict[str, Any] | None, report: dict[str, Any] | None = None) -> str:
    source = owner or {}
    report = report or {}
    return _first_text(
        source.get("pincode"),
        source.get("pin_code"),
        source.get("PIN Code"),
        report.get("pincode"),
        report.get("pin_code"),
    )


def owner_country(owner: dict[str, Any] | None, report: dict[str, Any] | None = None) -> str:
    return _first_text((owner or {}).get("country"), (report or {}).get("country"), "India") or "India"


def owner_address(owner: dict[str, Any] | None, report: dict[str, Any] | None = None) -> str:
    return ", ".join(owner_address_lines(owner, report))


def _kilometer_line(value: Any) -> str:
    if value in (None, "", "none", "null"):
        return ""
    text = str(value).strip()
    if not text or text.lower() in {"none", "null", "n/a", "na"}:
        return ""
    try:
        number = int(float(text.replace(",", "").replace("km", "").replace("KM", "").strip()))
    except ValueError:
        return text if text.upper().endswith("KM") else f"{text} KM"
    if number < 0:
        return ""
    return f"{number} KM"


def party_vehicle_address_lines(
    *,
    vehicle_number: str | None = None,
    brand: str | None = None,
    model: str | None = None,
    kilometer: Any = None,
) -> list[str]:
    lines: list[str] = []
    v_num = _first_text(vehicle_number)
    if v_num:
        lines.append(v_num)
    v_brand = _first_text(brand)
    v_model = _first_text(model)
    if v_brand and v_model:
        if v_brand.casefold() in v_model.casefold():
            lines.append(v_model)
        else:
            lines.append(f"{v_brand} {v_model}")
    elif v_brand or v_model:
        lines.append(v_brand or v_model)
    km = _kilometer_line(kilometer)
    if km:
        lines.append(km)
    return lines


def remote_id_for(report_id: int, alter_id: int | None = None) -> str:
    if alter_id and int(alter_id) > 0:
        return f"TYREX-SALES-R{report_id}-A{int(alter_id)}"
    return f"TYREX-SALES-R{report_id}"


def receipt_remote_id(report_id: int) -> str:
    return f"TYREX-RCPT-R{report_id}"


def _parse_date(raw: Any) -> str | None:
    if not raw:
        return None
    text = str(raw)[:19]
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(text, fmt).strftime("%Y%m%d")
        except ValueError:
            continue
    return None


def _voucher_date(report: dict[str, Any], payments: list[dict[str, Any]]) -> str:
    for key in ("billed_at", "paid_at", "completed_at", "created_at"):
        parsed = _parse_date(report.get(key))
        if parsed:
            return parsed
    for payment in payments:
        parsed = _parse_date(payment.get("paid_at"))
        if parsed:
            return parsed
    return datetime.now().strftime("%Y%m%d")


def _exclusive(inclusive: float, gst_percent: float) -> float:
    if gst_percent <= 0:
        return _money(inclusive)
    return _money(inclusive * 100.0 / (100.0 + gst_percent))


def _collect_raw_lines(report: dict[str, Any]) -> list[dict[str, Any]]:
    lines: list[dict[str, Any]] = []
    seen_texts: set[str] = set()

    # 1. Primary billed lines: complaint (contains actual services/courier items with edited amounts)
    complaints = [item for item in _json_list(report.get("complaint")) if isinstance(item, dict)]
    for item in complaints:
        name = _line_text(item)
        if name:
            seen_texts.add(name.casefold())
        lines.append(item)
        for material in _json_list(item.get("materials")):
            if isinstance(material, dict):
                lines.append(material)

    # 2. Additional suggestions (only non-complaint suggestions not already in complaint list)
    suggested = [item for item in _json_list(report.get("suggested")) if isinstance(item, dict)]
    for item in suggested:
        if str(item.get("type") or "").lower() == "complaint":
            continue
        name = _line_text(item)
        if name and name.casefold() in seen_texts:
            continue
        if name:
            seen_texts.add(name.casefold())
        lines.append(item)
        for material in _json_list(item.get("materials")):
            if isinstance(material, dict):
                lines.append(material)

    # 3. Fallback: if no complaint or suggestion lines exist, check approved
    if not lines:
        for item in [item for item in _json_list(report.get("approved")) if isinstance(item, dict)]:
            lines.append(item)
            for material in _json_list(item.get("materials")):
                if isinstance(material, dict):
                    lines.append(material)

    for material in _json_list(report.get("materials_required")):
        if isinstance(material, dict):
            lines.append(material)
    labour = _money(report.get("labour_cost"))
    if labour > 0:
        lines.append({"text": "Labour", "amount": labour})
    extra = _money(report.get("extra_charge_amount"))
    if extra > 0:
        lines.append({"text": report.get("extra_charge_label") or "Extra charge", "amount": extra})
    return lines


def catalog_groups(catalog: list[dict[str, Any]]) -> list[str]:
    names: list[str] = []
    seen: set[str] = set()
    for row in catalog:
        group = str(row.get("stock_group") or "").strip()
        if group and group not in {"Primary", "General"} and group not in seen:
            seen.add(group)
            names.append(group)
    return names


def fallback_stock_group(name: str, catalog: list[dict[str, Any]]) -> str:
    groups = catalog_groups(catalog)
    size = size_label(name)
    if size:
        for group in groups:
            if _norm(group) == _norm(size) or _norm(size) in _norm(group):
                return group
        match = re.search(r"R\s*(\d{2})", size, flags=re.I)
        if match:
            rim = f"R{match.group(1)}"
            for group in groups:
                if _norm(group) == _norm(rim):
                    return rim
            return rim
        return size
    return DEFAULT_STOCK_GROUP


def bill_lines(
    report: dict[str, Any],
    gst_percent: float,
    stock_catalog: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    catalog = stock_catalog or []
    groups = {row.get("stock_group") for row in catalog if row.get("stock_group")}
    parsed: list[dict[str, Any]] = []
    for item in _collect_raw_lines(report):
        name = _line_text(item)
        if not name:
            continue
        inclusive = _line_amount(item)
        ledger = sales_ledger_for(name)
        qty = _qty(item) or 1.0
        exclusive = _exclusive(inclusive, gst_percent)
        stock = is_stock_line(item, name, ledger)
        tally_name = name
        parent = size_label(name) or "Primary"
        create_stock = False
        create_group = False
        unit = _unit(item)
        hsn = ""
        if stock:
            matched = match_stock_item(name, catalog)
            if matched:
                tally_name = matched.get("name") or name
                parent = matched.get("stock_group") or parent
                unit = matched.get("base_unit") or unit
                hsn = str(matched.get("hsn_code") or matched.get("gst_hsn") or "").strip()
            else:
                stock = False
                tally_name = name
            create_stock = False
            create_group = False
            if not hsn and SIZE_RE.search(name or ""):
                hsn = DEFAULT_TYRE_HSN
        parsed.append(
            {
                "name": tally_name,
                "source_name": name,
                "inclusive": inclusive,
                "amount": exclusive,
                "qty": qty,
                "unit": unit or DEFAULT_UNIT,
                "rate": _money(exclusive / qty) if qty and exclusive else 0.0,
                "kind": "stock" if stock else "service",
                "ledger": INVENTORY_SALES_LEDGER if stock else ledger,
                "stock_group": parent if stock else DEFAULT_STOCK_GROUP,
                "hsn_code": hsn,
                "create_stock": False,
                "create_group": False,
            }
        )
    if not parsed:
        parsed.append(
            {
                "name": DEFAULT_SALES_LEDGER,
                "source_name": DEFAULT_SALES_LEDGER,
                "inclusive": 0.0,
                "amount": 0.0,
                "qty": 1.0,
                "unit": DEFAULT_UNIT,
                "rate": 0.0,
                "kind": "service",
                "ledger": DEFAULT_SALES_LEDGER,
                "stock_group": DEFAULT_STOCK_GROUP,
                "hsn_code": "",
                "create_stock": False,
                "create_group": False,
            }
        )
    return parsed


def _is_buyback_report(report: dict[str, Any]) -> bool:
    if report.get("is_buyback") is True or str(report.get("is_buyback") or "").lower() in ("true", "1", "yes"):
        return True
    marks = report.get("marks")
    if isinstance(marks, str):
        try:
            marks = json.loads(marks)
        except Exception:
            marks = None
    if isinstance(marks, dict) and (marks.get("is_buyback") is True or str(marks.get("is_buyback") or "").lower() in ("true", "1", "yes")):
        return True
    return False


def sale_narration(
    report: dict[str, Any],
    payments: list[dict[str, Any]],
    vehicle_number: str | None,
    jobcard: str,
) -> str:
    parts: list[str] = []
    jc_text = str(report.get("job_card_id") or report.get("jobcard_number") or jobcard or "").strip()
    if jc_text:
        parts.append(jc_text)
    if _is_buyback_report(report):
        parts.append("BUYBACK")
    vehicle = str(vehicle_number or report.get("vehicle_number") or "").strip()
    if vehicle:
        parts.append(vehicle)
    brand = str(report.get("vehicle_brand") or (report.get("vehicle") or {}).get("brand") or (report.get("vehicle") or {}).get("Brand name") or (report.get("vehicle") or {}).get("Brand") or "").strip()
    model = str(report.get("vehicle_model") or (report.get("vehicle") or {}).get("Model name") or (report.get("vehicle") or {}).get("vehicle_name") or (report.get("vehicle") or {}).get("model_name") or "").strip()
    if brand and model:
        if brand.casefold() in model.casefold():
            parts.append(model)
        else:
            parts.append(f"{brand} {model}")
    elif brand or model:
        parts.append(brand or model)
    odo = report.get("odometer_reading")
    if odo in (None, "", "null") and isinstance(report.get("vehicle"), dict):
        odo = report.get("vehicle", {}).get("odometer")
    if odo not in (None, "", "null", 0, "0"):
        parts.append(f"{odo} KM")
    seen: set[str] = set()
    for row in payments:
        text = str(row.get("notes") or "").strip()
        if text and text not in seen:
            seen.add(text)
            parts.append(text)
    report_notes = str(report.get("notes") or "").strip()
    if report_notes and report_notes not in seen:
        parts.append(report_notes)
    return " | ".join(parts) if parts else (jobcard or "Job Card")


def build_sale(
    report: dict[str, Any],
    *,
    stock_catalog: list[dict[str, Any]] | None = None,
    payments: list[dict[str, Any]] | None = None,
    vehicle_number: str | None = None,
) -> dict[str, Any] | None:
    payments = payments or []
    raw_gst = report.get("gst_percent")
    gst_percent = _money(raw_gst) if raw_gst not in (None, "") else DEFAULT_GST_PERCENT
    items = bill_lines(report, gst_percent, stock_catalog=stock_catalog)
    if not items:
        return None
    discount_incl = _money(report.get("discount_amount"))
    if (report.get("discount_type") or "flat").lower() == "percent":
        discount_incl = _money(sum(item["inclusive"] for item in items) * discount_incl / 100)
    discount = _exclusive(discount_incl, gst_percent)
    taxable = max(0.0, _money(sum(item["amount"] for item in items) - discount))
    gst_total = _money(taxable * gst_percent / 100) if gst_percent and taxable > 0 else 0.0
    cgst = _money(gst_total / 2) if gst_percent and taxable > 0 else 0.0
    sgst = _money(gst_total - cgst) if gst_percent and taxable > 0 else 0.0
    inclusive_total = max(0.0, _money(sum(item["inclusive"] for item in items) - discount_incl))
    round_off = _money(inclusive_total - taxable - cgst - sgst) if taxable > 0 else 0.0
    total = _money(taxable + cgst + sgst + round_off)
    report_id = int(report["id"])
    owner_row = report.get("owner") if isinstance(report.get("owner"), dict) else {}
    owner = report.get("Owner name") or report.get("owner_name") or owner_row.get("Owner name") or "Customer"
    phone = report.get("client_phone") or owner_row.get("PhoneNumber") or owner_row.get("MobileNumber") or ""
    gstin = extract_gstin(
        owner_row.get("GST Number"),
        report.get("gst_number"),
        report.get("gstin"),
        report.get("party_gstin"),
    )
    voucher_type = resolve_voucher_type(payments, gstin)
    raw_alter = report.get("alter_id")
    try:
        alter_val = int(raw_alter) if raw_alter not in (None, "") else 0
    except (TypeError, ValueError):
        alter_val = 0
    jobcard_base = report.get("job_card_id") or report.get("jobcard_number") or f"JC-{report_id:06d}"
    jobcard = f"{jobcard_base}-A{alter_val}" if alter_val > 0 else jobcard_base
    latest = max(payments, key=lambda row: str(row.get("paid_at") or ""), default=None)
    paid_total = _money(sum(_money(row.get("amount")) for row in payments))
    if paid_total > total * 1.2:
        paid_total = total
    state = _first_text(owner_row.get("state"), report.get("state"), DEFAULT_STATE) or DEFAULT_STATE
    country = owner_country(owner_row, report)
    vehicle_row = report.get("vehicle") if isinstance(report.get("vehicle"), dict) else {}
    vehicle_number = _first_text(
        vehicle_number,
        report.get("vehicle_number"),
        vehicle_row.get("Vehicle Number"),
    )
    brand = _first_text(
        report.get("vehicle_brand"),
        vehicle_row.get("Brand name"),
        vehicle_row.get("brand"),
        vehicle_row.get("Brand"),
    )
    model = _first_text(
        report.get("vehicle_model"),
        vehicle_row.get("Model name"),
        vehicle_row.get("vehicle_name"),
        vehicle_row.get("model_name"),
    )
    kilometer = report.get("odometer_reading")
    if kilometer in (None, ""):
        kilometer = vehicle_row.get("odometer")
    address_lines = party_vehicle_address_lines(
        vehicle_number=vehicle_number,
        brand=brand,
        model=model,
        kilometer=kilometer,
    )
    return {
        "report_id": report_id,
        "alter_id": alter_val,
        "jobcard_number": jobcard,
        "remote_id": remote_id_for(report_id, alter_val),
        "receipt_remote_id": receipt_remote_id(report_id),
        "date": _voucher_date(report, payments),
        "receipt_date": _parse_date((latest or {}).get("paid_at")) or _voucher_date(report, payments),
        "company": report.get("tally_company") or "",
        "tally_company_id": report.get("tally_company_id"),
        "tally_guid": report.get("tally_guid"),
        "voucher_type": voucher_type,
        "voucher_type_label": voucher_type_label(voucher_type),
        "gst_registration_type": "Regular" if voucher_type == VOUCHER_GST_B2B else "Consumer",
        "party_gstin": gstin,
        "state": state,
        "country": country,
        "pincode": "",
        "buyer_address": " | ".join(address_lines),
        "buyer_address_lines": address_lines,
        "ledger_address_lines": owner_address_lines(owner_row, report),
        "payments": payments,
        "payment_ids": [int(row["id"]) for row in payments if row.get("id") is not None],
        "party_ledger": party_ledger_name(str(owner), str(phone)),
        "buyer_name": str(owner).strip() or "Customer",
        "phone": re.sub(r"\D", "", str(phone)),
        "branch_name": report.get("branch_name") or "",
        "cost_centre": cost_centre_for(report.get("branch_name")),
        "godown": godown_for(cost_centre_for(report.get("branch_name")), report.get("branch_name")),
        "is_alter": any(row.get("alter_id") not in (None, "", 0, "0") for row in payments),
        "alter_ids": [row.get("alter_id") for row in payments if row.get("alter_id") not in (None, "", 0, "0")],
        "vehicle_number": vehicle_number or "",
        "items": items,
        "discount": discount,
        "taxable": taxable,
        "cgst": cgst,
        "sgst": sgst,
        "round_off": round_off,
        "gst_percent": gst_percent,
        "total": total,
        "paid_total": paid_total,
        "receipt_ledger": party_bank_for((latest or {}).get("method") or report.get("payment_method")),
        "notes": " | ".join(
            text
            for text in (
                str(row.get("notes") or "").strip()
                for row in payments
            )
            if text
        ) or str(report.get("notes") or "").strip(),
        "narration": sale_narration(report, payments, vehicle_number, jobcard),
        "fill_report_company": bool(report.get("needs_tally_company_fill")),
    }


def _amt(value: float) -> str:
    return f"{value:.2f}"


def _string_list_xml(list_tag: str, item_tag: str, lines: list[str], indent: str = "      ") -> str:
    items = [str(line).strip() for line in lines if str(line or "").strip()]
    if not items:
        return ""
    inner = "".join(f"\n{indent} <{item_tag}>{escape(line)}</{item_tag}>" for line in items)
    return f"\n{indent}<{list_tag} TYPE=\"String\">{inner}\n{indent}</{list_tag}>"


def _qty_text(qty: float, unit: str) -> str:
    if float(qty).is_integer():
        qty_s = str(int(qty))
    else:
        qty_s = f"{qty:.2f}"
    return f" {qty_s} {unit}"


def _cost_xml(cost_centre: str | None, amount: float) -> str:
    if not cost_centre:
        return ""
    return f"""
      <COSTCENTREALLOCATIONS.LIST>
       <NAME>{escape(cost_centre)}</NAME>
       <AMOUNT>{_amt(abs(amount))}</AMOUNT>
      </COSTCENTREALLOCATIONS.LIST>"""


def _gst_override_xml(
    gst_percent: float,
    *,
    supply: str,
    hsn: str = "",
    indent: str = "     ",
) -> str:
    if gst_percent <= 0:
        return ""
    half = _money(gst_percent / 2)
    hsn_xml = f"\n{indent}<GSTHSNSACCODE>{escape(hsn)}</GSTHSNSACCODE>" if hsn else ""
    return f"""
{indent}<GSTOVRDNTAXABILITY>Taxable</GSTOVRDNTAXABILITY>
{indent}<GSTOVRDNTYPEOFSUPPLY>{escape(supply)}</GSTOVRDNTYPEOFSUPPLY>
{indent}<GSTOVRDNISREVCHARGEAPPL>No</GSTOVRDNISREVCHARGEAPPL>{hsn_xml}
{indent}<GSTOVRDNCGSTRATE>{_amt(half)}</GSTOVRDNCGSTRATE>
{indent}<GSTOVRDNSGSTRATE>{_amt(half)}</GSTOVRDNSGSTRATE>
{indent}<GSTOVRDNIGSTRATE>0</GSTOVRDNIGSTRATE>
{indent}<RATEDETAILS.LIST>
{indent} <GSTRATEDUTYHEAD>CGST</GSTRATEDUTYHEAD>
{indent} <GSTRATEVALUATIONTYPE>Based on Value</GSTRATEVALUATIONTYPE>
{indent} <GSTRATE>{_amt(half)}</GSTRATE>
{indent}</RATEDETAILS.LIST>
{indent}<RATEDETAILS.LIST>
{indent} <GSTRATEDUTYHEAD>SGST/UTGST</GSTRATEDUTYHEAD>
{indent} <GSTRATEVALUATIONTYPE>Based on Value</GSTRATEVALUATIONTYPE>
{indent} <GSTRATE>{_amt(half)}</GSTRATE>
{indent}</RATEDETAILS.LIST>
{indent}<RATEDETAILS.LIST>
{indent} <GSTRATEDUTYHEAD>IGST</GSTRATEDUTYHEAD>
{indent} <GSTRATEVALUATIONTYPE>Based on Value</GSTRATEVALUATIONTYPE>
{indent} <GSTRATE>0</GSTRATE>
{indent}</RATEDETAILS.LIST>"""


def _ledger_entry(
    *,
    name: str,
    amount: float,
    debit: bool,
    is_party: bool = False,
    cost_centre: str | None = None,
    gst_percent: float = 0.0,
    gst_supply: str = "",
) -> str:
    signed = -abs(amount) if debit else abs(amount)
    cost = _cost_xml(cost_centre, amount) if cost_centre and not debit and not is_party else ""
    gst = _gst_override_xml(gst_percent, supply=gst_supply) if gst_supply and not debit and not is_party else ""
    return f"""    <LEDGERENTRIES.LIST>
     <LEDGERNAME>{escape(name)}</LEDGERNAME>
     <ISDEEMEDPOSITIVE>{"Yes" if debit else "No"}</ISDEEMEDPOSITIVE>
     <ISPARTYLEDGER>{"Yes" if is_party else "No"}</ISPARTYLEDGER>
     <AMOUNT>{_amt(signed)}</AMOUNT>{cost}{gst}
    </LEDGERENTRIES.LIST>
"""


def classification_for_item(name: str, kind: str | None = None) -> str:
    if kind == "service":
        return "SERVICE"
    text = (name or "").lower()
    if "alloy" in text:
        return "Alloy 18%"
    if "valve" in text:
        return "Valve"
    if "nut" in text or "bolt" in text:
        return "Nut"
    if "wiper" in text:
        return "Wiper Blade"
    return "TYRE 18%"


def _inventory_entry(
    item: dict[str, Any],
    cost_centre: str | None,
    godown: str | None,
    gst_percent: float = 0.0,
    order_no: str | None = None,
    order_due_date: str | None = None,
) -> str:
    qty = _qty_text(item["qty"], item["unit"])
    location = godown or DEFAULT_GODOWN
    is_dummy = item.get("name") == DEFAULT_DUMMY_STOCK_ITEM or (item.get("amount") or 0) == 0
    is_service = item.get("kind") == "service" or is_dummy
    supply_type = "Services" if is_service else "Goods"
    cls_name = classification_for_item(item.get("name", ""), item.get("kind"))
    gst = _gst_override_xml(
        gst_percent,
        supply=supply_type,
        hsn=str(item.get("hsn_code") or ""),
    )
    order_xml = f"\n      <ORDERNO>{escape(order_no)}</ORDERNO>" if order_no else ""
    due_xml = f"\n      <ORDERDUEDATE>{escape(order_due_date)}</ORDERDUEDATE>" if order_due_date else ""
    order_details_xml = f"\n     <ORDERDETAILS.LIST>\n      <ORDERNO>{escape(order_no)}</ORDERNO>\n     </ORDERDETAILS.LIST>" if order_no else ""
    rate = item.get("rate") if (item.get("rate") is not None and item.get("rate") > 0) else ((item.get("amount") or 0.0) / (item.get("qty") or 1.0))
    alloc_ledger = INVENTORY_SALES_LEDGER
    zero_entry_xml = "\n     <ISZEROVALUED>Yes</ISZEROVALUED>\n     <ZEROVALUEDENTRY>Yes</ZEROVALUEDENTRY>" if is_dummy else ""
    return f"""    <ALLINVENTORYENTRIES.LIST>
     <STOCKITEMNAME>{escape(item["name"])}</STOCKITEMNAME>
     <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>
     <RATE>{_amt(rate)}/{escape(item["unit"])}</RATE>
     <AMOUNT>{_amt(item["amount"])}</AMOUNT>
     <ACTUALQTY>{qty}</ACTUALQTY>
     <BILLEDQTY>{qty}</BILLEDQTY>
     <GODOWNNAME>{escape(location)}</GODOWNNAME>{gst}{order_xml}{zero_entry_xml}
     <BATCHALLOCATIONS.LIST>
      <GODOWNNAME>{escape(location)}</GODOWNNAME>
      <BATCHNAME>Primary Batch</BATCHNAME>{order_xml}{due_xml}
      <AMOUNT>{_amt(item["amount"])}</AMOUNT>
      <ACTUALQTY>{qty}</ACTUALQTY>
      <BILLEDQTY>{qty}</BILLEDQTY>{zero_entry_xml}
     </BATCHALLOCATIONS.LIST>{order_details_xml}
     <ACCOUNTINGALLOCATIONS.LIST>
      <LEDGERNAME>{escape(alloc_ledger)}</LEDGERNAME>
      <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>
      <AMOUNT>{_amt(item["amount"])}</AMOUNT>{_cost_xml(cost_centre, item["amount"])}
     </ACCOUNTINGALLOCATIONS.LIST>
    </ALLINVENTORYENTRIES.LIST>
"""


def stock_group_xml(name: str, parent: str | None = None) -> str:
    parent_xml = f"\n      <PARENT>{escape(parent)}</PARENT>" if parent and parent not in {"Primary", "General", ""} else ""
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <STOCKGROUP NAME="{escape(name)}" ACTION="Create">
      <NAME.LIST TYPE="String">
       <NAME>{escape(name)}</NAME>
      </NAME.LIST>{parent_xml}
     </STOCKGROUP>
    </TALLYMESSAGE>
"""


def stock_item_xml(item: dict[str, Any], action: str = "Create") -> str:
    name = item["name"]
    is_dummy = name == DEFAULT_DUMMY_STOCK_ITEM
    parent = item.get("stock_group") or item.get("fallback_group") or ("Services" if is_dummy else DEFAULT_STOCK_GROUP)
    if parent in {"Primary", "General", ""} and not is_dummy:
        parent = item.get("fallback_group") or DEFAULT_STOCK_GROUP
    parent_xml = f"\n      <PARENT>{escape(parent)}</PARENT>" if parent and parent not in {"Primary", "General", ""} else ""
    unit = item.get("unit") or DEFAULT_UNIT
    is_service = item.get("kind") == "service" or is_dummy
    supply_type = "Services" if is_service else "Goods"
    cls_name = classification_for_item(name, item.get("kind"))
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <STOCKITEM NAME="{escape(name)}" ACTION="{action}">
      <NAME.LIST TYPE="String">
       <NAME>{escape(name)}</NAME>
      </NAME.LIST>{parent_xml}
      <BASEUNITS>{escape(unit)}</BASEUNITS>
      <GSTAPPLICABLE>Applicable</GSTAPPLICABLE>
      <GSTTYPEOFSUPPLY>{supply_type}</GSTTYPEOFSUPPLY>
      <ISZEROVALUEDENTRIES>Yes</ISZEROVALUEDENTRIES>
      <ALLOWZEROVALUEDENTRIES>Yes</ALLOWZEROVALUEDENTRIES>
      <GSTDETAILS.LIST>
       <APPLICABLEFROM>20250401</APPLICABLEFROM>
       <HSNMASTERNAME>{escape(cls_name)}</HSNMASTERNAME>
       <SRCOFGSTDETAILS>Use GST Classification</SRCOFGSTDETAILS>
      </GSTDETAILS.LIST>
      <HSNDETAILS.LIST>
       <APPLICABLEFROM>20250401</APPLICABLEFROM>
       <HSNCLASSIFICATIONNAME>{escape(cls_name)}</HSNCLASSIFICATIONNAME>
       <SRCOFHSNDETAILS>Use GST Classification</SRCOFHSNDETAILS>
      </HSNDETAILS.LIST>
     </STOCKITEM>
    </TALLYMESSAGE>
"""


def ledger_master_xml(sale: dict[str, Any]) -> str:
    name = sale["party_ledger"]
    phone = str(sale.get("phone") or "").strip()
    if phone and not phone.startswith("+"):
        digits = re.sub(r"\D", "", phone)
        if len(digits) == 10:
            phone = f"+91{digits}"
        elif len(digits) == 12 and digits.startswith("91"):
            phone = f"+{digits}"
    gst_type = sale.get("gst_registration_type") or "Consumer"
    gstin = sale.get("party_gstin") or ""
    if not gstin:
        gst_type = "Unregistered/Consumer"
    state = sale.get("state") or DEFAULT_STATE
    country = sale.get("country") or "India"
    pincode = sale.get("ledger_pincode") or ""
    lines = sale.get("ledger_address_lines") or []
    gstin_xml = f"\n      <PARTYGSTIN>{escape(gstin)}</PARTYGSTIN>" if gstin else ""
    pin_xml = f"\n      <PINCODE>{escape(pincode)}</PINCODE>" if pincode else ""
    address_xml = _string_list_xml("ADDRESS.LIST", "ADDRESS", lines)
    mailing = sale.get("buyer_name") or name
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <LEDGER NAME="{escape(name)}" ACTION="Create">
      <NAME.LIST TYPE="String">
       <NAME>{escape(name)}</NAME>
      </NAME.LIST>
      <PARENT>{SUNDRY_DEBTORS}</PARENT>
      <MAILINGNAME>{escape(mailing)}</MAILINGNAME>{address_xml}{pin_xml}
      <ISBILLWISEON>No</ISBILLWISEON>
      <GSTREGISTRATIONTYPE>{escape(gst_type)}</GSTREGISTRATIONTYPE>{gstin_xml}
      <COUNTRYOFRESIDENCE>{escape(country)}</COUNTRYOFRESIDENCE>
      <COUNTRYNAME>{escape(country)}</COUNTRYNAME>
      <LEDSTATENAME>{escape(state)}</LEDSTATENAME>
      <LEDGERMOBILE>{escape(phone)}</LEDGERMOBILE>
     </LEDGER>
    </TALLYMESSAGE>
"""


def godown_xml(name: str) -> str:
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <GODOWN NAME="{escape(name)}" ACTION="Create">
      <NAME>{escape(name)}</NAME>
     </GODOWN>
    </TALLYMESSAGE>
"""


def unit_xml(name: str) -> str:
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <UNIT NAME="{escape(name)}" ACTION="Create">
      <NAME>{escape(name)}</NAME>
      <ISSIMPLEUNIT>Yes</ISSIMPLEUNIT>
     </UNIT>
    </TALLYMESSAGE>
"""


def sales_ledger_xml(name: str, parent: str = SALES_LEDGER_PARENT, action: str = "Create") -> str:
    is_inventory = "Yes" if name == INVENTORY_SALES_LEDGER else "No"
    supply = "Goods" if name == INVENTORY_SALES_LEDGER else "Services"
    cls_name = "TYRE 18%" if name == INVENTORY_SALES_LEDGER else "SERVICE"
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <LEDGER NAME="{escape(name)}" ACTION="{action}">
      <NAME.LIST TYPE="String">
       <NAME>{escape(name)}</NAME>
      </NAME.LIST>
      <PARENT>{escape(parent)}</PARENT>
      <ISBILLWISEON>No</ISBILLWISEON>
      <ISINVENTORYAFFECTED>{is_inventory}</ISINVENTORYAFFECTED>
      <GSTAPPLICABLE>Applicable</GSTAPPLICABLE>
      <GSTTYPEOFSUPPLY>{supply}</GSTTYPEOFSUPPLY>
      <GSTDETAILS.LIST>
       <APPLICABLEFROM>20250401</APPLICABLEFROM>
       <HSNMASTERNAME>{escape(cls_name)}</HSNMASTERNAME>
       <SRCOFGSTDETAILS>Use GST Classification</SRCOFGSTDETAILS>
      </GSTDETAILS.LIST>
      <HSNDETAILS.LIST>
       <APPLICABLEFROM>20250401</APPLICABLEFROM>
       <HSNCLASSIFICATIONNAME>{escape(cls_name)}</HSNCLASSIFICATIONNAME>
       <SRCOFHSNDETAILS>Use GST Classification</SRCOFHSNDETAILS>
      </HSNDETAILS.LIST>
     </LEDGER>
    </TALLYMESSAGE>
"""


def ledger_group_xml(name: str, parent: str | None = None) -> str:
    parent_xml = f"\n      <PARENT>{escape(parent)}</PARENT>" if parent and parent not in {"Primary", "General", ""} else ""
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <GROUP NAME="{escape(name)}" ACTION="Create">
      <NAME.LIST TYPE="String">
       <NAME>{escape(name)}</NAME>
      </NAME.LIST>{parent_xml}
     </GROUP>
    </TALLYMESSAGE>
"""


def tax_ledger_xml(name: str) -> str:
    upper = name.upper()
    if "CGST" in upper:
        head = "CGST"
    elif "SGST" in upper or "UTGST" in upper:
        head = "SGST/UTGST"
    elif "IGST" in upper:
        head = "IGST"
    else:
        head = ""
    head_xml = f"\n      <GSTDUTYHEAD>{head}</GSTDUTYHEAD>" if head else ""
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <LEDGER NAME="{escape(name)}" ACTION="Create">
      <NAME.LIST TYPE="String">
       <NAME>{escape(name)}</NAME>
      </NAME.LIST>
      <PARENT>{TAX_LEDGER_PARENT}</PARENT>
      <TAXTYPE>GST</TAXTYPE>{head_xml}
     </LEDGER>
    </TALLYMESSAGE>
"""


def expense_ledger_xml(name: str) -> str:
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <LEDGER NAME="{escape(name)}" ACTION="Create">
      <NAME.LIST TYPE="String">
       <NAME>{escape(name)}</NAME>
      </NAME.LIST>
      <PARENT>{EXPENSE_LEDGER_PARENT}</PARENT>
     </LEDGER>
    </TALLYMESSAGE>
"""


def cost_centre_xml(name: str, *, with_parent: bool = True) -> str:
    parent_xml = (
        "\n      <CATEGORY>Primary Cost Category</CATEGORY>\n      <PARENT>Primary Cost Category</PARENT>"
        if with_parent
        else ""
    )
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <COSTCENTRE NAME="{escape(name)}" ACTION="Create">
      <NAME.LIST TYPE="String">
       <NAME>{escape(name)}</NAME>
      </NAME.LIST>{parent_xml}
     </COSTCENTRE>
    </TALLYMESSAGE>
"""


def _default_series_name(voucher_type: str) -> str:
    return "Default_" + re.sub(r"\s+", "", voucher_type or "")


def voucher_type_stock_xml(name: str) -> str:
    series = _default_series_name(name)
    parent = "Sales Order" if ("order" in (name or "").lower() or "job" in (name or "").lower() or name == VOUCHER_SALES_ORDER) else "Sales"
    affects_stock = "Yes"
    is_invoice = "Yes"
    allow_zero = "Yes"
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <VOUCHERTYPE NAME="{escape(name)}" ACTION="Create">
      <NAME.LIST TYPE="String">
       <NAME>{escape(name)}</NAME>
      </NAME.LIST>
      <PARENT>{escape(parent)}</PARENT>
      <AFFECTSSTOCK>{affects_stock}</AFFECTSSTOCK>
      <ISINVOICE>{is_invoice}</ISINVOICE>
      <ALLOWZEROVALUEDENTRIES>{allow_zero}</ALLOWZEROVALUEDENTRIES>
      <NUMBERINGMETHOD>Automatic</NUMBERINGMETHOD>
      <VCHNUMBEHAVIOUR>Retain Original Voucher No.</VCHNUMBEHAVIOUR>
      <PREVENTDUPLICATES>No</PREVENTDUPLICATES>
     </VOUCHERTYPE>
    </TALLYMESSAGE>
    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <VOUCHERNUMBERSERIES NAME="{escape(series)}" ACTION="Create">
      <NAME.LIST TYPE="String">
       <NAME>{escape(series)}</NAME>
      </NAME.LIST>
      <NUMBERINGMETHOD>Automatic</NUMBERINGMETHOD>
      <VCHNUMBEHAVIOUR>Retain Original Voucher No.</VCHNUMBEHAVIOUR>
     </VOUCHERNUMBERSERIES>
    </TALLYMESSAGE>
"""


def voucher_type_retain_numbering_xml(name: str) -> str:
    allow_zero = "Yes"
    parent = "Sales Order" if ("order" in (name or "").lower() or "job" in (name or "").lower() or name == VOUCHER_SALES_ORDER) else "Sales"
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <VOUCHERTYPE NAME="{escape(name)}" ACTION="Alter">
      <PARENT>{escape(parent)}</PARENT>
      <AFFECTSSTOCK>Yes</AFFECTSSTOCK>
      <ISINVOICE>Yes</ISINVOICE>
      <VCHNUMBEHAVIOUR>Retain Original Voucher No.</VCHNUMBEHAVIOUR>
      <ALLOWZEROVALUEDENTRIES>{allow_zero}</ALLOWZEROVALUEDENTRIES>
     </VOUCHERTYPE>
    </TALLYMESSAGE>
"""


def numbering_series_retain_xml(name: str) -> str:
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <VOUCHERNUMBERSERIES NAME="{escape(name)}" ACTION="Alter">
      <VCHNUMBEHAVIOUR>Retain Original Voucher No.</VCHNUMBEHAVIOUR>
     </VOUCHERNUMBERSERIES>
    </TALLYMESSAGE>
"""


def ensure_retain_numbering(company_name: str) -> None:
    """Kept for backward compatibility. Does not alter company, voucher types, or existing ledgers."""
    return


def voucher_xml(sale: dict[str, Any], *, use_inventory: bool = True, action: str | None = None) -> str:
    voucher_type = sale.get("voucher_type") or VOUCHER_TYPE
    is_sales_order = (voucher_type == VOUCHER_SALES_ORDER) or ("order" in voucher_type.lower())
    action = action or ("Alter" if sale.get("is_alter") else "Create")
    alter_id = next((str(item).strip() for item in (sale.get("alter_ids") or []) if str(item).strip().isdigit()), "")
    alter_attr = f' ALTERID="{escape(alter_id)}"' if action == "Alter" and alter_id else ""
    jc_num = escape(str(sale.get("jobcard_number") or ""))
    gst_type = sale.get("gst_registration_type") or "Consumer"
    gstin = sale.get("party_gstin") or ""
    state = sale.get("state") or DEFAULT_STATE
    country = sale.get("country") or "India"
    pincode = sale.get("pincode") or ""
    lines = sale.get("buyer_address_lines") or ([sale.get("buyer_address")] if sale.get("buyer_address") else [])
    buyer_name = str(sale.get("buyer_name") or sale["party_ledger"])
    gstin_xml = f"\n      <PARTYGSTIN>{escape(gstin)}</PARTYGSTIN>" if gstin else ""
    consignee_gstin_xml = f"\n      <CONSIGNEEGSTIN>{escape(gstin)}</CONSIGNEEGSTIN>" if gstin else ""
    pin_xml = f"\n      <PINCODE>{escape(pincode)}</PINCODE>" if pincode else ""
    consignee_pin_xml = f"\n      <CONSIGNEEPINCODE>{escape(pincode)}</CONSIGNEEPINCODE>" if pincode else ""
    address_xml = _string_list_xml("ADDRESS.LIST", "ADDRESS", lines)
    buyer_address_xml = _string_list_xml("BASICBUYERADDRESS.LIST", "BASICBUYERADDRESS", lines)
    consignee_address_xml = _string_list_xml("BASICCONSIGNEEADDRESS.LIST", "BASICCONSIGNEEADDRESS", lines)
    narration_text = escape(str(sale.get("narration") or ""))
    v_num = escape(str(sale.get("vehicle_number") or ""))
    order_header_xml = (
        f"\n      <BASICPURCHASEORDERNO>{jc_num}</BASICPURCHASEORDERNO>"
        f"\n      <ORDERDETAILS.LIST>"
        f"\n       <ORDERNO>{jc_num}</ORDERNO>"
        f"\n      </ORDERDETAILS.LIST>"
        f"\n      <BASICORDERREF>{narration_text}</BASICORDERREF>"
        f"\n      <BASICORDERTERMS.LIST TYPE=\"String\">"
        f"\n       <BASICORDERTERMS>{narration_text}</BASICORDERTERMS>"
        f"\n      </BASICORDERTERMS.LIST>"
        f"\n      <BASICSHIPPEDBY>{v_num}</BASICSHIPPEDBY>"
        if jc_num
        else ""
    )

    real_stock_items = [item for item in (sale.get("items") or []) if item.get("kind") == "stock"]
    service_items = [item for item in (sale.get("items") or []) if item.get("kind") == "service"]

    inv_items = real_stock_items

    inventory = use_inventory and bool(inv_items)
    stock_xml = (
        "".join(
            _inventory_entry(
                item,
                sale["cost_centre"],
                sale.get("godown"),
                gst_percent=float(sale.get("gst_percent") or 0),
                order_no=str(sale.get("jobcard_number") or ""),
                order_due_date=str(sale["date"]),
            )
            for item in inv_items
        )
        if inventory
        else ""
    )
    gst_percent = float(sale.get("gst_percent") or 0)
    entries = [
        _ledger_entry(
            name=sale["party_ledger"],
            amount=sale["total"],
            debit=True,
            is_party=True,
        )
    ]
    # Services are ALWAYS placed in the bottom ledger section
    for item in service_items:
        entries.append(
            _ledger_entry(
                name=item["ledger"],
                amount=item["amount"],
                debit=False,
                cost_centre=sale["cost_centre"],
                gst_percent=gst_percent,
                gst_supply="Services",
            )
        )
    if not inventory and real_stock_items:
        for item in real_stock_items:
            entries.append(
                _ledger_entry(
                    name=INVENTORY_SALES_LEDGER,
                    amount=item["amount"],
                    debit=False,
                    cost_centre=sale["cost_centre"],
                    gst_percent=gst_percent,
                    gst_supply="Goods",
                )
            )
    if sale.get("discount") and float(sale["discount"]) > 0:
        entries.append(_ledger_entry(name=DISCOUNT_LEDGER, amount=float(sale["discount"]), debit=True))
    if sale.get("cgst") and float(sale["cgst"]) > 0:
        entries.append(_ledger_entry(name=CGST_LEDGER, amount=float(sale["cgst"]), debit=False))
    if sale.get("sgst") and float(sale["sgst"]) > 0:
        entries.append(_ledger_entry(name=SGST_LEDGER, amount=float(sale["sgst"]), debit=False))
    if sale.get("round_off") is not None and abs(float(sale["round_off"])) >= 0.005:
        entries.append(
            _ledger_entry(
                name=ROUND_OFF_LEDGER,
                amount=abs(float(sale["round_off"])),
                debit=float(sale["round_off"]) < 0,
            )
        )
    has_zero_inventory = any((item.get("amount") or 0) == 0 for item in inv_items)
    view = "Invoice Voucher View" if stock_xml else "Accounting Voucher View"
    is_invoice_val = "Yes" if stock_xml else "No"
    zero_valued_xml = "\n      <ISZEROVALUED>Yes</ISZEROVALUED>" if ((sale.get("total") or 0) == 0 or has_zero_inventory) else ""

    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <VOUCHER REMOTEID="{escape(sale["remote_id"])}" VCHTYPE="{escape(voucher_type)}" ACTION="{action}" OBJVIEW="{view}"{alter_attr}>
      <DATE>{sale["date"]}</DATE>
      <VOUCHERTYPENAME>{escape(voucher_type)}</VOUCHERTYPENAME>
      <VOUCHERNUMBER>{jc_num}</VOUCHERNUMBER>
      <REFERENCE>{jc_num}</REFERENCE>{order_header_xml}
      <NARRATION>{escape(str(sale["narration"]))}</NARRATION>
      <PARTYLEDGERNAME>{escape(sale["party_ledger"])}</PARTYLEDGERNAME>
      <BASICBUYERNAME>{escape(buyer_name)}</BASICBUYERNAME>
      <BASICBASEPARTYNAME>{escape(sale["party_ledger"])}</BASICBASEPARTYNAME>
      <PARTYNAME>{escape(sale["party_ledger"])}</PARTYNAME>
      <PARTYMAILINGNAME>{escape(sale["party_ledger"])}</PARTYMAILINGNAME>{address_xml}{buyer_address_xml}{pin_xml}
      <EFFECTIVEDATE>{sale["date"]}</EFFECTIVEDATE>
      <ISINVOICE>{is_invoice_val}</ISINVOICE>{zero_valued_xml}
      <PERSISTEDVIEW>{view}</PERSISTEDVIEW>
      <PLACEOFSUPPLY>{escape(state)}</PLACEOFSUPPLY>
      <STATENAME>{escape(state)}</STATENAME>
      <COUNTRYOFRESIDENCE>{escape(country)}</COUNTRYOFRESIDENCE>
      <COUNTRYNAME>{escape(country)}</COUNTRYNAME>
      <GSTREGISTRATIONTYPE>{escape(gst_type)}</GSTREGISTRATIONTYPE>{gstin_xml}
      <ISGSTOVERRIDDEN>No</ISGSTOVERRIDDEN>
      <CONSIGNEEMAILINGNAME>{escape(buyer_name)}</CONSIGNEEMAILINGNAME>
      <CONSIGNEESTATENAME>{escape(state)}</CONSIGNEESTATENAME>
      <CONSIGNEECOUNTRYNAME>{escape(country)}</CONSIGNEECOUNTRYNAME>{consignee_pin_xml}{consignee_gstin_xml}{consignee_address_xml}
      <CONSIGNEEGSTREGTYPE>{escape(gst_type)}</CONSIGNEEGSTREGTYPE>
{stock_xml}{''.join(entries)}     </VOUCHER>
    </TALLYMESSAGE>
"""


def receipt_xml(sale: dict[str, Any]) -> str | None:
    amount = _money(sale.get("paid_total"))
    if amount <= 0:
        return None
    return f"""    <TALLYMESSAGE xmlns:UDF="TallyUDF">
     <VOUCHER REMOTEID="{escape(sale["receipt_remote_id"])}" VCHTYPE="{RECEIPT_TYPE}" ACTION="Create" OBJVIEW="Accounting Voucher View">
      <DATE>{sale["receipt_date"]}</DATE>
      <VOUCHERTYPENAME>{RECEIPT_TYPE}</VOUCHERTYPENAME>
      <REFERENCE>{escape(str(sale["jobcard_number"]))}</REFERENCE>
      <NARRATION>{escape(str(sale["narration"]))}</NARRATION>
      <PARTYLEDGERNAME>{escape(sale["party_ledger"])}</PARTYLEDGERNAME>
      <ISINVOICE>No</ISINVOICE>
      <PERSISTEDVIEW>Accounting Voucher View</PERSISTEDVIEW>
{ _ledger_entry(name=sale["receipt_ledger"], amount=amount, debit=True) }{ _ledger_entry(name=sale["party_ledger"], amount=amount, debit=False, is_party=True) }     </VOUCHER>
    </TALLYMESSAGE>
"""


def import_xml(company_name: str, messages: list[str], import_id: str = "Vouchers") -> str:
    body = "".join(messages)
    return f"""<ENVELOPE>
 <HEADER>
  <VERSION>1</VERSION>
  <TALLYREQUEST>Import</TALLYREQUEST>
  <TYPE>Data</TYPE>
  <ID>{escape(import_id)}</ID>
 </HEADER>
 <BODY>
  <DESC>
   <STATICVARIABLES>
    <SVCURRENTCOMPANY>{escape(company_name)}</SVCURRENTCOMPANY>
    <SVPREVENTRENUMBERING>Yes</SVPREVENTRENUMBERING>
   </STATICVARIABLES>
  </DESC>
  <DATA>
{body}  </DATA>
 </BODY>
</ENVELOPE>
"""


def parse_import_result(xml_text: str) -> dict[str, int | str]:
    def _num(*tags: str) -> int:
        for tag in tags:
            match = re.search(rf"<{tag}>(\d+)</{tag}>", xml_text, flags=re.I)
            if match:
                return int(match.group(1))
        return 0

    def _clean_error(chunk: str) -> str:
        text = html.unescape(re.sub(r"<[^>]+>", " ", chunk or ""))
        return " ".join(text.split())

    tagged = re.findall(
        r"<(LINEERROR|ERRORMSG|ERROR|UNKNOWN)>(.*?)</(?:LINEERROR|ERRORMSG|ERROR|UNKNOWN)>",
        xml_text,
        flags=re.I | re.S,
    )
    errors = [_clean_error(body) for _tag, body in tagged]
    detail = "; ".join(item for item in errors if item and item.upper() not in {"0", "1"})
    created = _num("CREATED", "CREATEDVOUCHERS")
    altered = _num("ALTERED", "ALTEREDVOUCHERS", "COMBINED", "COMBINEDVOUCHERS")
    exceptions = _num("EXCEPTIONS")
    last_id = _num("LASTVCHID")
    if not detail and created == 0 and altered == 0 and "CMPINFO" in xml_text.upper() and "CREATED" not in xml_text.upper():
        detail = "Tally did not import the voucher (empty response)"
        exceptions = max(exceptions, 1)
    snippet = re.sub(r"\s+", " ", xml_text).strip()[:400]
    if not detail and _is_unknown_request(xml_text):
        detail = "Unknown Request, cannot be processed"
    if not detail and exceptions:
        if "CMPINFO" in xml_text.upper() and created == 0 and altered == 0:
            detail = "Tally rejected the voucher (check voucher type allows these ledgers; inventory is not enabled on SALES -B2C / GST SALES)"
        else:
            detail = snippet or f"Tally reported {exceptions} exception(s)"
    return {
        "created": created,
        "altered": altered,
        "exceptions": exceptions,
        "last_id": last_id,
        "error": detail,
        "raw": snippet,
    }


def post_messages_to_tally(
    company_name: str,
    messages: list[str],
    import_id: str = "Vouchers",
    timeout: int = 40,
) -> dict[str, int | str]:
    if not messages:
        return {"created": 0, "altered": 0, "exceptions": 0, "last_id": 0, "error": ""}
    try:
        response = post_xml(import_xml(company_name, messages, import_id=import_id), timeout=timeout)
    except TallyUnavailable:
        raise
    except (requests.exceptions.Timeout, requests.exceptions.ConnectionError) as exc:
        raise TallyUnavailable(
            "Tally is not responding. Click OK on Internal Error / Memory Access Violation, "
            "close Tally fully, open the company, wait until Tally is idle, then run sync again."
        ) from exc
    except RuntimeError as exc:
        return {
            "created": 0,
            "altered": 0,
            "exceptions": 1,
            "last_id": 0,
            "error": str(exc),
            "raw": str(exc),
        }
    return parse_import_result(response)


def _needed_ledgers(sale: dict[str, Any]) -> list[tuple[str, str]]:
    names: list[tuple[str, str]] = []
    seen: set[str] = set()

    def add(name: str, kind: str) -> None:
        if name and name not in seen:
            seen.add(name)
            names.append((name, kind))

    for item in sale.get("items") or []:
        if item.get("kind") == "stock":
            add(item.get("ledger") or INVENTORY_SALES_LEDGER, "sales")
        else:
            add(item.get("ledger") or DEFAULT_SALES_LEDGER, "sales")
    if sale.get("discount") and float(sale["discount"]) > 0:
        add(DISCOUNT_LEDGER, "expense")
    if sale.get("cgst") and float(sale["cgst"]) > 0:
        add(CGST_LEDGER, "tax")
    if sale.get("sgst") and float(sale["sgst"]) > 0:
        add(SGST_LEDGER, "tax")
    if sale.get("round_off") is not None and abs(float(sale["round_off"])) >= 0.005:
        add(ROUND_OFF_LEDGER, "expense")
    return names


def post_sales_to_tally(company_name: str, sales: list[dict[str, Any]]) -> dict[str, int | str]:
    prime_existing_masters(company_name)

    parties: list[str] = []
    ledgers: list[str] = []
    seen_ledger: set[str] = set()
    seen_party: set[str] = set()
    pending_parties: list[str] = []
    pending_ledgers: list[str] = []
    has_stock = False

    for sale in sales:
        party = sale["party_ledger"]
        if party not in seen_party:
            seen_party.add(party)
            seen_ledger.add(party)
            if not _have_master(company_name, "party", party) and not _have_master(company_name, "ledger", party):
                parties.append(ledger_master_xml(sale))
                pending_parties.append(party)

        for item in sale.get("items") or []:
            if item.get("kind") == "stock":
                has_stock = True

        for name, kind in _needed_ledgers(sale):
            if name in seen_ledger:
                continue
            seen_ledger.add(name)
            if _have_master(company_name, "ledger", name):
                continue
            pending_ledgers.append(name)
            if kind == "tax":
                ledgers.append(sales_ledger_xml(name))
            elif kind == "expense":
                ledgers.append(expense_ledger_xml(name))
            else:
                ledgers.append(sales_ledger_xml(name))

    combined: dict[str, Any] = {
        "created": 0,
        "altered": 0,
        "exceptions": 0,
        "last_id": 0,
        "error": "",
        "voucher_created": 0,
        "voucher_altered": 0,
        "stock_ok": True,
        "inventory_ok": False,
        "used_inventory": False,
    }

    def _run_masters(
        label: str,
        messages: list[str],
        *,
        kind: str = "",
        names: list[str] | set[str] | None = None,
    ) -> bool:
        if not messages:
            return True
        print(f"  syncing {label} ({len(messages)}) ...", flush=True)
        result = post_messages_to_tally(company_name, messages, import_id="All Masters", timeout=12)
        created = int(result.get("created") or 0)
        altered = int(result.get("altered") or 0)
        exceptions = int(result.get("exceptions") or 0)
        combined["created"] = int(combined["created"]) + created
        combined["altered"] = int(combined["altered"]) + altered
        print(f"    created={created} altered={altered} exceptions={exceptions}", flush=True)
        error = str(result.get("error") or "")
        snippet = str(result.get("raw") or error)
        if snippet == "timeout" or "Tally timeout" in error:
            print(f"  {label}: Tally busy, leaving existing masters and posting the voucher", flush=True)
            _remember_masters(company_name, kind, names)
            return True
        failed = bool(error) or (exceptions and created == 0 and altered == 0) or _is_unknown_request(snippet)
        if failed:
            if error:
                print(f"  {label}: {error}", flush=True)
            elif snippet:
                print(f"  {label}: {snippet[:300]}", flush=True)
            else:
                print(f"  {label}: Tally reported {exceptions} exception(s)", flush=True)
            return False
        _remember_masters(company_name, kind, names)
        return True

    def _create_one(kind: str, name: str) -> bool:
        name = (name or "").strip()
        if not name:
            return False
        if _have_master(company_name, kind, name):
            return True
        xml = ""
        label = kind
        names = [name]
        if kind == "party":
            for sale in sales:
                if sale.get("party_ledger") == name:
                    xml = ledger_master_xml(sale)
                    label = "party ledgers"
                    break
        elif kind == "ledger":
            xml = sales_ledger_xml(name)
            label = "ledgers"
        if not xml:
            return False
        return _run_masters(label, [xml], kind=kind, names=names)

    def _create_missing(err: str) -> bool:
        text = html.unescape(err or "")
        match = re.search(
            r"Ledger\s+'(.+?)'\s+does not exist",
            text,
            flags=re.I,
        )
        if not match:
            return False
        name = match.group(1).strip()
        print(f"  creating missing ledger: {name}", flush=True)
        if any(sale.get("party_ledger") == name for sale in sales):
            return _create_one("party", name)
        return _create_one("ledger", name)

    for sale in sales:
        sale["cost_centre"] = None

    if parties:
        _run_masters("party ledgers", parties, kind="party", names=pending_parties)
    if ledgers:
        _run_masters("ledgers", ledgers, kind="ledger", names=pending_ledgers)

    print("  posting sales voucher ...", flush=True)
    use_inventory = True
    wants_alter = any(sale.get("is_alter") for sale in sales)
    voucher_action = "Alter" if wants_alter else "Create"

    def _post_vouchers(action: str, inventory: bool) -> tuple[dict[str, Any], bool]:
        result = post_messages_to_tally(
            company_name,
            [voucher_xml(sale, use_inventory=inventory, action=action) for sale in sales],
            import_id="Vouchers",
        )
        ok = bool(int(result.get("created") or 0) or int(result.get("altered") or 0)) and not (
            result.get("error") or result.get("exceptions")
        )
        return result, ok

    voucher_result, voucher_ok = _post_vouchers(voucher_action, use_inventory)
    if wants_alter and not voucher_ok:
        print("  retrying voucher as Create ...", flush=True)
        voucher_result, voucher_ok = _post_vouchers("Create", use_inventory)
    elif not wants_alter and not voucher_ok and "duplicate" in str(voucher_result.get("error") or voucher_result.get("raw") or "").lower():
        print("  voucher exists in Tally, updating as Alter ...", flush=True)
        voucher_result, voucher_ok = _post_vouchers("Alter", use_inventory)
    for _attempt in range(5):
        if voucher_ok:
            break
        err = f"{voucher_result.get('error') or ''} {voucher_result.get('raw') or ''}"
        print(f"  voucher not accepted: {html.unescape(err)[:240]}", flush=True)
        if use_inventory and "stock item" in err.lower() and "does not exist" in err.lower():
            print("  stock item not in Tally; accepting job card without stock item ...", flush=True)
            use_inventory = False
            if not _have_master(company_name, "ledger", INVENTORY_SALES_LEDGER):
                _run_masters("ledgers", [sales_ledger_xml(INVENTORY_SALES_LEDGER)], kind="ledger", names=[INVENTORY_SALES_LEDGER])
            voucher_result, voucher_ok = _post_vouchers(voucher_action, use_inventory)
            if voucher_ok:
                break
        if not _create_missing(err):
            break
        print("  retrying sales voucher ...", flush=True)
        voucher_result, voucher_ok = _post_vouchers(voucher_action, use_inventory)
    if use_inventory and not voucher_ok:
        print("  retrying job card without stock item ...", flush=True)
        use_inventory = False
        if not _have_master(company_name, "ledger", INVENTORY_SALES_LEDGER):
            _run_masters("ledgers", [sales_ledger_xml(INVENTORY_SALES_LEDGER)], kind="ledger", names=[INVENTORY_SALES_LEDGER])
        voucher_result, voucher_ok = _post_vouchers("Alter" if "duplicate" in str(voucher_result.get("error") or voucher_result.get("raw") or "").lower() else "Create", False)
    combined["voucher_created"] = int(voucher_result.get("created") or 0)
    combined["voucher_altered"] = int(voucher_result.get("altered") or 0)
    combined["exceptions"] = int(voucher_result.get("exceptions") or 0)
    combined["last_id"] = int(voucher_result.get("last_id") or 0)
    combined["error"] = str(voucher_result.get("error") or "")
    combined["used_inventory"] = bool(use_inventory and voucher_ok)
    combined["inventory_ok"] = bool(has_stock and use_inventory and voucher_ok)
    time.sleep(0.25)
    return combined

