from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Any
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape

from sync.tally_stock import _bool, _clean_tally, _log, _native_methods, _number
from sync.tally_xml import _all_child_text, _child_text, _tag, _text, post_xml, sanitize_xml

# Keep GST nested lists off this export. Party contact fields are enough for owner_master.
LEDGER_METHODS = [
    "Name",
    "GUID",
    "Parent",
    "OpeningBalance",
    "ClosingBalance",
    "MasterID",
    "AlterID",
    "MailingName",
    "LedgerPhone",
    "LedgerMobile",
    "LedgerContact",
    "PhoneNumber",
    "MobileNo",
    "EMail",
    "PartyGSTIN",
    "IncomeTaxNumber",
    "LedStateName",
    "CountryName",
    "Pincode",
    "Address",
    "IsBillWiseOn",
]

PARTY_GROUPS = ("Sundry Debtors", "Sundry Debtor")
DEBTOR_RE = re.compile(r"sundry\s*debtor", re.I)
CREDITOR_RE = re.compile(r"sundry\s*creditor|creditor", re.I)
PHONE_RE = re.compile(r"(\+?\d[\d\s+/()-]{7,}\d)")
TRAILING_PHONE_RE = re.compile(r"(\d{10,12})\s*$")
GSTIN_RE = re.compile(r"\b([0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][A-Z0-9]Z[A-Z0-9])\b", re.I)
SKIP_LEDGER_NAMES = {
    "cash",
    "cgst",
    "sgst",
    "igst",
    "round off",
    "discount",
    "profit and loss",
}


def _collection_xml(company_name: str, col_id: str, child_of: str | None = None) -> str:
    safe = escape(company_name)
    native = _native_methods(LEDGER_METHODS)
    child = ""
    if child_of:
        child = f"\n            <CHILDOF>{escape(child_of)}</CHILDOF>\n            <BELONGSTO>Yes</BELONGSTO>"
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
            <TYPE>Ledger</TYPE>{child}
{native}
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>
"""


def _aliases(element: ET.Element, name: str | None) -> list[str]:
    names = _all_child_text(element, "NAME")
    return [item for item in names if item and item != name]


def _address_lines(element: ET.Element) -> list[str]:
    lines: list[str] = []
    for value in _all_child_text(element, "ADDRESS"):
        cleaned = _clean_tally(value)
        if cleaned and cleaned not in lines:
            lines.append(cleaned)
    return lines[:3]


def _first_phone(*values: Any) -> str:
    for value in values:
        match = PHONE_RE.search(str(value or ""))
        if match:
            digits = re.sub(r"\D", "", match.group(1))
            if len(digits) >= 8:
                return digits[-12:]
    return ""


def _gstin(*values: Any) -> str:
    for value in values:
        match = GSTIN_RE.search(str(value or ""))
        if match:
            return match.group(1).upper()
    return ""


def parse_ledgers(xml_text: str) -> list[dict[str, Any]]:
    root = ET.fromstring(sanitize_xml(xml_text))
    rows: list[dict[str, Any]] = []
    for element in root.iter():
        if _tag(element) != "LEDGER":
            continue
        name = _text(element.get("NAME")) or _child_text(element, "NAME")
        if not name:
            continue
        aliases = _aliases(element, name)
        address = _address_lines(element)
        phone = _first_phone(
            _child_text(element, "LEDGERPHONE"),
            _child_text(element, "PHONENUMBER"),
            _child_text(element, "LEDGERCONTACT"),
            name,
        )
        mobile = _first_phone(
            _child_text(element, "LEDGERMOBILE"),
            _child_text(element, "MOBILENO"),
        ) or phone
        if not phone:
            trailing = TRAILING_PHONE_RE.search(name)
            if trailing:
                phone = trailing.group(1)
                mobile = mobile or phone
        rows.append(
            {
                "name": name,
                "guid": _child_text(element, "GUID"),
                "master_id": int(_number(_child_text(element, "MASTERID")) or 0) or None,
                "alter_id": int(_number(_child_text(element, "ALTERID")) or 0) or None,
                "parent_group": _child_text(element, "PARENT"),
                "mailing_name": _clean_tally(_child_text(element, "MAILINGNAME")),
                "alias": aliases[0] if aliases else None,
                "aliases": aliases or None,
                "address_line1": address[0] if len(address) > 0 else None,
                "address_line2": address[1] if len(address) > 1 else None,
                "address_line3": address[2] if len(address) > 2 else None,
                "state": _clean_tally(_child_text(element, "LEDSTATENAME")),
                "country": _clean_tally(_child_text(element, "COUNTRYNAME")) or "India",
                "pincode": _clean_tally(_child_text(element, "PINCODE")),
                "phone": phone or None,
                "mobile": mobile or None,
                "email": _clean_tally(_child_text(element, "EMAIL")),
                "gstin": _gstin(_child_text(element, "PARTYGSTIN"), name) or None,
                "pan": _clean_tally(_child_text(element, "INCOMETAXNUMBER")),
                "opening_balance_text": _child_text(element, "OPENINGBALANCE"),
                "opening_balance": _number(_child_text(element, "OPENINGBALANCE")),
                "closing_balance_text": _child_text(element, "CLOSINGBALANCE"),
                "closing_balance": _number(_child_text(element, "CLOSINGBALANCE")),
                "is_billwise": _bool(_child_text(element, "ISBILLWISEON")),
            }
        )
    return rows


def is_party_ledger(row: dict[str, Any]) -> bool:
    name = str(row.get("name") or "").strip()
    if not name or name.lower() in SKIP_LEDGER_NAMES:
        return False
    parent = str(row.get("parent_group") or "")
    if CREDITOR_RE.search(parent):
        return False
    return bool(DEBTOR_RE.search(parent) or DEBTOR_RE.search(name))


def fetch_party_ledgers_from_tally(company_name: str) -> list[dict[str, Any]]:
    seen: dict[str, dict[str, Any]] = {}
    for index, group in enumerate(PARTY_GROUPS):
        _log(f"  Requesting party ledgers under {group}.")
        xml_text = post_xml(
            _collection_xml(company_name, f"PartyLedCol{index}", group),
            timeout=45,
        )
        rows = parse_ledgers(xml_text)
        _log(f"  Received {len(rows)} ledger(s) under {group}.")
        for row in rows:
            key = row.get("guid") or row.get("name")
            if key:
                seen[str(key)] = row

    if not seen:
        _log("  No Sundry Debtors group match. Fetching ledgers and keeping debtors only.")
        xml_text = post_xml(_collection_xml(company_name, "AllLedCol"), timeout=60)
        for row in parse_ledgers(xml_text):
            if not is_party_ledger(row):
                continue
            key = row.get("guid") or row.get("name")
            if key:
                seen[str(key)] = row

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows = list(seen.values())
    for row in rows:
        row["tally_company"] = company_name
        row["last_synced_at"] = now
    _log(f"  Using {len(rows)} party ledger(s).")
    return rows
