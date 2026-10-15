from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from typing import Any
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape

from sync.tally_xml import (
    _all_child_text,
    _child_text,
    _deep_text,
    _tag,
    _text,
    post_xml,
    sanitize_xml,
)

QTY_RE = re.compile(r"(-?\d+(?:\.\d+)?)")
PART_RE = re.compile(r"[-–]\s*([A-Za-z]{0,3}\d{3,}[A-Za-z0-9]*)\s*$")

# Keep this list free of GSTDetails/HSNDetails. Nested GST lists freeze Tally on a full export.
STOCK_METHODS = [
    "Name",
    "GUID",
    "Parent",
    "Category",
    "BaseUnits",
    "AdditionalUnits",
    "Description",
    "OpeningBalance",
    "ClosingBalance",
    "OpeningValue",
    "ClosingValue",
    "OpeningRate",
    "ClosingRate",
    "StandardPrice",
    "StandardCost",
    "CostingMethod",
    "GSTApplicable",
    "GSTTypeOfSupply",
    "MailingName",
    "IsBatchWiseOn",
    "IgnoreNegativeStock",
    "Conversion",
    "Denominator",
    "MasterID",
    "AlterID",
]

SKIP_EXTRA = {
    "GUID",
    "PARENT",
    "CATEGORY",
    "BASEUNITS",
    "ADDITIONALUNITS",
    "DESCRIPTION",
    "OPENINGBALANCE",
    "CLOSINGBALANCE",
    "OPENINGVALUE",
    "CLOSINGVALUE",
    "OPENINGRATE",
    "CLOSINGRATE",
    "STANDARDPRICE",
    "STANDARDCOST",
    "COSTINGMETHOD",
    "GSTAPPLICABLE",
    "GSTTYPEOFSUPPLY",
    "MASTERID",
    "ALTERID",
    "DENOMINATOR",
    "CONVERSION",
    "ISBATCHWISEON",
    "IGNORENEGATIVESTOCK",
    "NAME",
    "MAILINGNAME",
    "LANGUAGENAME.LIST",
    "GSTDETAILS.LIST",
    "HSNDETAILS.LIST",
    "MAILINGNAME.LIST",
    "NAME.LIST",
}


def _number(value: str | None) -> float | None:
    if not value:
        return None
    match = QTY_RE.search(value.replace(",", ""))
    if not match:
        return None
    try:
        return float(match.group(1))
    except ValueError:
        return None


def _bool(value: str | None) -> bool | None:
    if not value:
        return None
    lowered = value.strip().lower()
    if lowered in {"yes", "true", "1"}:
        return True
    if lowered in {"no", "false", "0"}:
        return False
    return None


def _clean_tally(value: str | None) -> str | None:
    if not value:
        return None
    cleaned = value.replace("\n", " ").strip()
    if not cleaned or "not applicable" in cleaned.lower():
        return None
    return cleaned


def _log(message: str) -> None:
    print(message, flush=True)


def _native_methods(methods: list[str]) -> str:
    return "\n".join(f"            <NATIVEMETHOD>{method}</NATIVEMETHOD>" for method in methods)


def _stock_xml(company_name: str) -> str:
    safe = escape(company_name)
    native = _native_methods(STOCK_METHODS)
    return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>StockLightCol</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
        <SVCURRENTCOMPANY>{safe}</SVCURRENTCOMPANY>
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="StockLightCol" ISMODIFY="No" ISFIXED="No" ISINITIALIZE="Yes">
            <TYPE>Stock Item</TYPE>
{native}
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>
"""


def _gst_class_xml(company_name: str) -> str:
    safe = escape(company_name)
    return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>GstClassCol</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
        <SVCURRENTCOMPANY>{safe}</SVCURRENTCOMPANY>
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="GstClassCol" ISINITIALIZE="Yes">
            <TYPE>GST Classification</TYPE>
            <NATIVEMETHOD>Name</NATIVEMETHOD>
            <NATIVEMETHOD>GUID</NATIVEMETHOD>
            <NATIVEMETHOD>HSNCode</NATIVEMETHOD>
            <NATIVEMETHOD>HSN</NATIVEMETHOD>
            <NATIVEMETHOD>GSTDetails</NATIVEMETHOD>
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>
"""


def _gst_rates(element: ET.Element) -> dict[str, float]:
    rates: dict[str, float] = {}
    for child in element.iter():
        if _tag(child) != "RATEDETAILS.LIST":
            continue
        head = (_child_text(child, "GSTRATEDUTYHEAD") or "").upper()
        rate = _number(_child_text(child, "GSTRATE"))
        if rate is None:
            continue
        if "IGST" in head:
            rates["igst_rate"] = rate
        elif "CGST" in head:
            rates["cgst_rate"] = rate
        elif "SGST" in head:
            rates["sgst_rate"] = rate
        elif head == "CESS":
            rates["cess_rate"] = rate
    if rates.get("igst_rate"):
        rates["gst_rate"] = rates["igst_rate"]
    elif rates.get("cgst_rate") is not None or rates.get("sgst_rate") is not None:
        rates["gst_rate"] = (rates.get("cgst_rate") or 0) + (rates.get("sgst_rate") or 0)
    return rates


def _json_subtree(element: ET.Element) -> dict[str, Any]:
    data: dict[str, Any] = {}
    for child in element:
        tag = _tag(child)
        if tag.endswith(".LIST"):
            nested = _json_subtree(child)
            text = _text(child.text)
            values = data.setdefault(tag, [])
            values.append(nested or text)
        else:
            value = _text(child.text)
            if value:
                data[tag] = value
            elif list(child):
                data[tag] = _json_subtree(child)
    return data


def parse_gst_classifications(xml_text: str) -> dict[str, dict[str, Any]]:
    root = ET.fromstring(sanitize_xml(xml_text))
    classes: dict[str, dict[str, Any]] = {}
    for element in root.iter():
        if _tag(element) != "GSTCLASSIFICATION":
            continue
        name = _text(element.get("NAME")) or _child_text(element, "NAME")
        if not name:
            continue
        rates = _gst_rates(element)
        classes[name] = {
            "name": name,
            "hsn_code": _deep_text(element, "HSNCODE", "HSN"),
            "taxability": _deep_text(element, "TAXABILITY"),
            **rates,
        }
    return classes


def _part_number(element: ET.Element, name: str | None) -> str | None:
    mailing = _deep_text(element, "MAILINGNAME")
    if mailing:
        return mailing
    if name:
        match = PART_RE.search(name)
        if match:
            return match.group(1)
    return None


def _aliases(element: ET.Element, name: str | None) -> list[str]:
    names = _all_child_text(element, "NAME")
    aliases = [item for item in names if item and item != name]
    return aliases


def parse_stock_items(xml_text: str) -> list[dict[str, Any]]:
    root = ET.fromstring(sanitize_xml(xml_text))
    items: list[dict[str, Any]] = []
    for element in root.iter():
        if _tag(element) != "STOCKITEM":
            continue
        name = _text(element.get("NAME")) or _child_text(element, "NAME")
        if not name:
            continue
        aliases = _aliases(element, name)
        rates = _gst_rates(element)
        gst_details = None
        for child in element:
            if _tag(child) == "GSTDETAILS.LIST":
                gst_details = _json_subtree(child)
                break
        extra: dict[str, Any] = {}
        for child in element:
            tag = _tag(child)
            if tag in SKIP_EXTRA or tag.endswith(".LIST"):
                continue
            value = _text(child.text)
            if value:
                extra[tag.lower()] = value
        items.append(
            {
                "name": name,
                "guid": _child_text(element, "GUID"),
                "master_id": int(_number(_child_text(element, "MASTERID")) or 0) or None,
                "alter_id": int(_number(_child_text(element, "ALTERID")) or 0) or None,
                "alias": aliases[0] if aliases else None,
                "aliases": aliases or None,
                "part_number": _part_number(element, name),
                "description": _clean_tally(_child_text(element, "DESCRIPTION")),
                "stock_group": _child_text(element, "PARENT"),
                "category": _clean_tally(_child_text(element, "CATEGORY")),
                "base_unit": _clean_tally(_child_text(element, "BASEUNITS")),
                "additional_unit": _clean_tally(_child_text(element, "ADDITIONALUNITS")),
                "conversion": _number(_child_text(element, "CONVERSION")),
                "denominator": _number(_child_text(element, "DENOMINATOR")),
                "opening_qty_text": _child_text(element, "OPENINGBALANCE"),
                "opening_qty": _number(_child_text(element, "OPENINGBALANCE")),
                "opening_rate": _number(_child_text(element, "OPENINGRATE")),
                "opening_value": _number(_child_text(element, "OPENINGVALUE")),
                "closing_qty_text": _child_text(element, "CLOSINGBALANCE"),
                "closing_qty": _number(_child_text(element, "CLOSINGBALANCE")),
                "closing_rate": _number(_child_text(element, "CLOSINGRATE")),
                "closing_value": _number(_child_text(element, "CLOSINGVALUE")),
                "selling_price": _number(_child_text(element, "STANDARDPRICE")),
                "cost_price": _number(_child_text(element, "STANDARDCOST")),
                "costing_method": _clean_tally(_child_text(element, "COSTINGMETHOD")),
                "hsn_code": _deep_text(element, "HSNCODE", "HSN"),
                "hsn_description": _deep_text(element, "HSNMASTERNAME", "HSNCLASSIFICATIONNAME"),
                "gst_classification": _deep_text(element, "HSNMASTERNAME", "HSNCLASSIFICATIONNAME"),
                "gst_applicable": _clean_tally(_child_text(element, "GSTAPPLICABLE")),
                "gst_type_of_supply": _clean_tally(_child_text(element, "GSTTYPEOFSUPPLY")),
                "gst_taxability": _deep_text(element, "TAXABILITY"),
                "gst_rate": rates.get("gst_rate"),
                "cgst_rate": rates.get("cgst_rate"),
                "sgst_rate": rates.get("sgst_rate"),
                "igst_rate": rates.get("igst_rate"),
                "cess_rate": rates.get("cess_rate"),
                "is_batchwise": _bool(_child_text(element, "ISBATCHWISEON")),
                "ignore_negative_stock": _bool(_child_text(element, "IGNORENEGATIVESTOCK")),
                "gst_details": gst_details,
                "extra": extra or None,
            }
        )
    return items


def apply_gst_classifications(
    items: list[dict[str, Any]], classes: dict[str, dict[str, Any]]
) -> list[dict[str, Any]]:
    for item in items:
        name = item.get("gst_classification")
        klass = classes.get(name or "")
        if not klass:
            continue
        item["hsn_code"] = item.get("hsn_code") or klass.get("hsn_code")
        item["gst_taxability"] = item.get("gst_taxability") or klass.get("taxability")
        if not item.get("gst_rate"):
            for key in ("gst_rate", "cgst_rate", "sgst_rate", "igst_rate", "cess_rate"):
                if klass.get(key) is not None:
                    item[key] = klass[key]
    return items


def fetch_stock_from_tally(company_name: str) -> list[dict[str, Any]]:
    _log("  Requesting stock list from Tally. Keep Tally open; it may pause 2-5 seconds.")
    stock_xml = post_xml(_stock_xml(company_name), timeout=25)
    items = parse_stock_items(stock_xml)
    _log(f"  Received {len(items)} stock item(s).")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for item in items:
        item["tally_company"] = company_name
        item["last_synced_at"] = now
    return items


def dump_sample(items: list[dict[str, Any]], count: int = 3) -> str:
    return json.dumps(items[:count], indent=2, default=str)
