from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape

from sync.tally_stock import (
    SKIP_EXTRA,
    _bool,
    _clean_tally,
    _gst_rates,
    _json_subtree,
    _log,
    _native_methods,
    _number,
)
from sync.tally_xml import _all_child_text, _child_text, _deep_text, _tag, _text, post_xml, sanitize_xml

# Nested GST lists are safe here: Sales Accounts is a small ledger set, not 900+ stock items.
LEDGER_METHODS = [
    "Name",
    "GUID",
    "Parent",
    "OpeningBalance",
    "ClosingBalance",
    "GSTApplicable",
    "GSTTypeOfSupply",
    "GSTHSNCode",
    "Description",
    "MailingName",
    "MasterID",
    "IsBillWiseOn",
    "IsCostCentresOn",
    "AffectsStock",
    "TaxType",
    "GSTDetails",
    "HSNDetails",
]

GROUP_METHODS = [
    "Name",
    "GUID",
    "Parent",
    "MasterID",
    "IsSubledger",
    "IsRevenue",
    "GSTApplicable",
    "GSTTypeOfSupply",
    "GSTHSNCode",
]


def _collection_xml(company_name: str, col_id: str, object_type: str, methods: list[str]) -> str:
    safe = escape(company_name)
    native = _native_methods(methods)
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
            <CHILDOF>Sales Accounts</CHILDOF>
            <BELONGSTO>Yes</BELONGSTO>
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


def _hsn(element: ET.Element) -> str | None:
    value = _clean_tally(_child_text(element, "GSTHSNCODE", "HSNCODE") or _deep_text(element, "HSNCODE", "HSN"))
    if not value or value.lower() in {"not found", "not available"}:
        return None
    return value


def _extra(element: ET.Element) -> dict[str, Any] | None:
    extra: dict[str, Any] = {}
    skip = SKIP_EXTRA | {
        "TAXTYPE",
        "GSTHSNCODE",
        "HSNCODE",
        "HSN",
        "OPENINGBALANCE",
        "CLOSINGBALANCE",
        "ISBILLWISEON",
        "ISCOSTCENTRESON",
        "AFFECTSSTOCK",
        "ISSUBLEDGER",
        "ISREVENUE",
        "TAXABILITY",
    }
    for child in element:
        tag = _tag(child)
        if tag in skip or tag.endswith(".LIST"):
            continue
        value = _text(child.text)
        if value:
            extra[tag.lower()] = value
    return extra or None


def _base_row(element: ET.Element, name: str, account_type: str) -> dict[str, Any]:
    aliases = _aliases(element, name)
    rates = _gst_rates(element)
    gst_details = None
    for child in element:
        if _tag(child) == "GSTDETAILS.LIST":
            gst_details = _json_subtree(child)
            break
    return {
        "name": name,
        "guid": _child_text(element, "GUID"),
        "master_id": int(_number(_child_text(element, "MASTERID")) or 0) or None,
        "account_type": account_type,
        "alias": aliases[0] if aliases else None,
        "aliases": aliases or None,
        "parent_group": _child_text(element, "PARENT"),
        "description": _clean_tally(_child_text(element, "DESCRIPTION")),
        "mailing_name": _clean_tally(_child_text(element, "MAILINGNAME")),
        "opening_balance_text": _child_text(element, "OPENINGBALANCE"),
        "opening_balance": _number(_child_text(element, "OPENINGBALANCE")),
        "closing_balance_text": _child_text(element, "CLOSINGBALANCE"),
        "closing_balance": _number(_child_text(element, "CLOSINGBALANCE")),
        "tax_type": _clean_tally(_child_text(element, "TAXTYPE")),
        "gst_applicable": _clean_tally(_child_text(element, "GSTAPPLICABLE")),
        "gst_type_of_supply": _clean_tally(_child_text(element, "GSTTYPEOFSUPPLY")),
        "gst_taxability": _clean_tally(_deep_text(element, "TAXABILITY")),
        "hsn_code": _hsn(element),
        "hsn_description": _clean_tally(_deep_text(element, "HSNMASTERNAME", "HSNCLASSIFICATIONNAME")),
        "gst_rate": rates.get("gst_rate"),
        "cgst_rate": rates.get("cgst_rate"),
        "sgst_rate": rates.get("sgst_rate"),
        "igst_rate": rates.get("igst_rate"),
        "cess_rate": rates.get("cess_rate"),
        "affects_stock": _bool(_child_text(element, "AFFECTSSTOCK")),
        "is_billwise": _bool(_child_text(element, "ISBILLWISEON")),
        "is_cost_centre": _bool(_child_text(element, "ISCOSTCENTRESON")),
        "is_revenue": _bool(_child_text(element, "ISREVENUE")),
        "is_subledger": _bool(_child_text(element, "ISSUBLEDGER")),
        "gst_details": gst_details,
        "extra": _extra(element),
    }


def parse_sales_accounts(xml_text: str, account_type: str, tag_name: str) -> list[dict[str, Any]]:
    root = ET.fromstring(sanitize_xml(xml_text))
    rows: list[dict[str, Any]] = []
    for element in root.iter():
        if _tag(element) != tag_name:
            continue
        name = _text(element.get("NAME")) or _child_text(element, "NAME")
        if not name:
            continue
        rows.append(_base_row(element, name, account_type))
    return rows


def fetch_sales_from_tally(company_name: str) -> list[dict[str, Any]]:
    _log("  Requesting sales groups from Tally.")
    groups_xml = post_xml(_collection_xml(company_name, "SalesGrpCol", "Group", GROUP_METHODS), timeout=15)
    groups = parse_sales_accounts(groups_xml, "group", "GROUP")
    _log(f"  Received {len(groups)} sales group(s).")

    _log("  Requesting sales ledgers from Tally.")
    ledgers_xml = post_xml(_collection_xml(company_name, "SalesLedCol", "Ledger", LEDGER_METHODS), timeout=20)
    ledgers = parse_sales_accounts(ledgers_xml, "ledger", "LEDGER")
    _log(f"  Received {len(ledgers)} sales ledger(s).")

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows = groups + ledgers
    for row in rows:
        row["tally_company"] = company_name
        row["last_synced_at"] = now
    return rows
