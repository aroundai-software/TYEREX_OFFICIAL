from __future__ import annotations

import re
import time
from datetime import datetime, timezone
from typing import Any
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape

import requests

from sync.config import tally_host, tally_port, tally_timeout, tally_url

TALLY_SEPARATOR = "\x04"


class TallyUnavailable(RuntimeError):
    """Tally HTTP is down: crash, company closed, or Internal Error c0000005."""
GSTIN_RE = re.compile(r"\b([0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][A-Z0-9]Z[A-Z0-9])\b", re.I)
PHONE_LINE_RE = re.compile(r"^[\d\s+/()\\-]{8,}$")
CIN_LINE_RE = re.compile(r"^CIN\s*:", re.I)
CITY_PIN_RE = re.compile(r"^(?P<city>.+?)\s*[-,]?\s*(?P<pin>\d{6})\s*$")
ILLEGAL_CHARREF_RE = re.compile(r"&#0*(?:[1-8]|1[0-9]|2[0-9]|3[01]);")

# Only Company-object methods. GSTRegNumber / GSTRegistrationDetails belong to Tax Unit
# and trigger Tally "Incorrect Object Type!" if requested here.
COMPANY_METHODS = [
    "Name",
    "GUID",
    "CompanyNumber",
    "StartingFrom",
    "EndingAt",
    "BooksFrom",
    "StateName",
    "CountryName",
    "Pincode",
    "PhoneNumber",
    "MobileNo",
    "EMail",
    "IncomeTaxNumber",
    "GSTRegistrationNumber",
]


def _collection_xml(name: str, methods: list[str]) -> str:
    native = "\n".join(f"            <NATIVEMETHOD>{method}</NATIVEMETHOD>" for method in methods)
    return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>{name}</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="{name}" ISMODIFY="No" ISFIXED="No" ISINITIALIZE="Yes" ISOPTION="No" ISINTERNAL="No">
            <TYPE>Company</TYPE>
{native}
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>
"""


def _company_object_xml(company_name: str) -> str:
    safe = escape(company_name)
    return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Object</TYPE>
    <SUBTYPE>Company</SUBTYPE>
    <ID TYPE="Name">{safe}</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
      </STATICVARIABLES>
      <FETCHLIST>
        <FETCH>Name</FETCH>
        <FETCH>GUID</FETCH>
        <FETCH>Address</FETCH>
        <FETCH>StateName</FETCH>
        <FETCH>CountryName</FETCH>
        <FETCH>Pincode</FETCH>
        <FETCH>PhoneNumber</FETCH>
        <FETCH>EMail</FETCH>
        <FETCH>Website</FETCH>
        <FETCH>GSTRegistrationNumber</FETCH>
        <FETCH>IncomeTaxNumber</FETCH>
        <FETCH>CompanyNumber</FETCH>
        <FETCH>StartingFrom</FETCH>
        <FETCH>BooksFrom</FETCH>
      </FETCHLIST>
    </DESC>
  </BODY>
</ENVELOPE>
"""


def _tax_unit_xml(company_name: str) -> str:
    safe = escape(company_name)
    return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>TaxUnitCol</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
        <SVCURRENTCOMPANY>{safe}</SVCURRENTCOMPANY>
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="TaxUnitCol" ISINITIALIZE="Yes">
            <TYPE>Tax Unit</TYPE>
            <NATIVEMETHOD>Name</NATIVEMETHOD>
            <NATIVEMETHOD>GSTRegNumber</NATIVEMETHOD>
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>
"""


LIST_OF_COMPANIES_XML = """<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>List of Companies</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
      </STATICVARIABLES>
    </DESC>
  </BODY>
</ENVELOPE>
"""

CURRENT_COMPANY_XML = """<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>TyrexCurrentCompany</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="TyrexCurrentCompany" ISINITIALIZE="Yes">
            <TYPE>Company</TYPE>
            <FILTER>TyrexIsCurrentCompany</FILTER>
            <NATIVEMETHOD>Name</NATIVEMETHOD>
            <NATIVEMETHOD>GUID</NATIVEMETHOD>
            <NATIVEMETHOD>CompanyNumber</NATIVEMETHOD>
            <NATIVEMETHOD>StartingFrom</NATIVEMETHOD>
            <NATIVEMETHOD>EndingAt</NATIVEMETHOD>
          </COLLECTION>
          <SYSTEM TYPE="Formulae" NAME="TyrexIsCurrentCompany">$Name = ##SVCurrentCompany</SYSTEM>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>
"""


def sanitize_xml(xml_text: str) -> str:
    text = ILLEGAL_CHARREF_RE.sub(" ", xml_text.lstrip("\ufeff"))
    return "".join(ch if ord(ch) >= 32 or ch in "\t\n\r" else " " for ch in text)


def decode_tally_bytes(data: bytes) -> str:
    if data.startswith(b"\xff\xfe") or data.startswith(b"\xfe\xff"):
        return data.decode("utf-16")
    if data.startswith(b"\xef\xbb\xbf"):
        return data.decode("utf-8-sig")
    for encoding in ("utf-8", "utf-16", "utf-16-le", "cp1252"):
        try:
            text = data.decode(encoding)
            if "<" in text:
                return text
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def _tag(element: ET.Element) -> str:
    return element.tag.split("}")[-1].upper()


def _text(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.replace(TALLY_SEPARATOR, "\n").strip()
    return cleaned or None


def _child_text(element: ET.Element, *names: str) -> str | None:
    wanted = {name.upper() for name in names}
    for child in element:
        if _tag(child) in wanted:
            return _text(child.text) or _text("".join(child.itertext()))
    return None


def _deep_text(element: ET.Element, *names: str) -> str | None:
    wanted = {name.upper() for name in names}
    for child in element.iter():
        if _tag(child) in wanted:
            value = _text(child.text)
            if value:
                return value
    return None


def _all_child_text(element: ET.Element, *names: str) -> list[str]:
    wanted = {name.upper() for name in names}
    values: list[str] = []
    for child in element.iter():
        if _tag(child) in wanted:
            value = _text(child.text)
            if value:
                values.append(value)
    return values


def _parse_date(value: str | None) -> str | None:
    if not value:
        return None
    raw = value.strip()
    for fmt in ("%Y%m%d", "%Y-%m-%d", "%d-%b-%Y", "%d-%B-%Y", "%d/%m/%Y"):
        try:
            return datetime.strptime(raw, fmt).date().isoformat()
        except ValueError:
            continue
    match = re.search(r"(\d{4})(\d{2})(\d{2})", raw)
    if match:
        try:
            return datetime.strptime(match.group(0), "%Y%m%d").date().isoformat()
        except ValueError:
            return None
    return None


def _company_name(element: ET.Element) -> str | None:
    attr = _text(element.get("NAME"))
    if attr:
        return attr
    direct = _child_text(element, "NAME")
    if direct:
        return direct
    names = _all_child_text(element, "NAME")
    return names[0] if names else None


def _split_address(element: ET.Element) -> tuple[str | None, str | None, str | None, str | None]:
    lines = _all_child_text(element, "ADDRESS")
    if not lines:
        blob = _child_text(element, "ADDRESS")
        if blob:
            lines = [part.strip() for part in re.split(r"[\n|]", blob) if part.strip()]

    city = None
    pin = None
    kept: list[str] = []
    for line in lines:
        if PHONE_LINE_RE.match(line) or CIN_LINE_RE.match(line):
            continue
        city_pin = CITY_PIN_RE.match(line)
        if city_pin:
            city = city_pin.group("city").strip(" ,-") or city
            pin = city_pin.group("pin")
            continue
        kept.append(line.strip(" ,"))

    line1 = kept[0] if kept else None
    line2 = ", ".join(kept[1:]) if len(kept) > 1 else None
    return line1, line2, city, pin


def _gst_number(element: ET.Element) -> str | None:
    attr = _text(element.get("TAXREGISTRATION"))
    if attr and GSTIN_RE.search(attr):
        return GSTIN_RE.search(attr).group(1).upper()
    value = _deep_text(
        element,
        "GSTREGNUMBER",
        "GSTIN",
        "GSTREGISTRATIONNUMBER",
        "CMPGSTIN",
        "GSTREGISTRATION",
    )
    if value:
        match = GSTIN_RE.search(value)
        return (match.group(1) if match else value).upper()
    blob = " ".join(element.itertext())
    match = GSTIN_RE.search(blob)
    return match.group(1).upper() if match else None


def _phone_number(element: ET.Element) -> str | None:
    return _child_text(element, "MOBILENO", "MOBILENUMBER", "PHONENUMBER", "PHONE")


def parse_companies(xml_text: str) -> list[dict[str, Any]]:
    xml_text = sanitize_xml(xml_text)
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as exc:
        raise RuntimeError(f"Tally returned invalid XML: {exc}") from exc

    companies: list[dict[str, Any]] = []
    seen: set[tuple[str | None, str | None]] = set()

    for element in root.iter():
        if _tag(element) != "COMPANY":
            continue
        name = _company_name(element)
        guid = _child_text(element, "GUID")
        if guid:
            guid = guid.strip() or None
        if not name and not guid:
            continue
        key = (guid, name)
        if key in seen:
            continue
        seen.add(key)
        companies.append(_company_row(element, name, guid))

    if not companies:
        for element in root.iter():
            if _tag(element) not in {"COMPANYNAME", "CMPNAME"}:
                continue
            name = _text(element.text)
            if not name or (None, name) in seen:
                continue
            seen.add((None, name))
            companies.append(_company_row(element, name, None))
    return companies


def parse_gstin(xml_text: str) -> str | None:
    xml_text = sanitize_xml(xml_text)
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        match = GSTIN_RE.search(xml_text)
        return match.group(1).upper() if match else None

    for element in root.iter():
        if _tag(element) != "TAXUNIT":
            continue
        tax_type = (_text(element.get("TAXTYPE")) or _child_text(element, "USEDFOR") or "").upper()
        gstin = _gst_number(element)
        if gstin and (not tax_type or tax_type == "GST"):
            return gstin
    match = GSTIN_RE.search(" ".join(root.itertext()))
    return match.group(1).upper() if match else None


def _company_row(element: ET.Element, name: str | None, guid: str | None) -> dict[str, Any]:
    address1, address2, city, pin_from_address = _split_address(element)
    alias = _child_text(element, "FORMALNAME", "BASICCOMPANYFORMALNAME")
    if alias and (alias.upper() == "INR" or alias == name):
        alias = None
    gstin = _gst_number(element)
    pan = _child_text(element, "INCOMETAXNUMBER")
    if not pan and gstin and len(gstin) == 15:
        pan = gstin[2:12]
    return {
        "tally_company_name": name or "Unknown Tally Company",
        "tally_guid": guid,
        "company_number": _child_text(element, "COMPANYNUMBER"),
        "company_alias": alias,
        "address_line1": address1,
        "address_line2": address2,
        "city": city,
        "state": _child_text(element, "STATENAME", "STATE"),
        "pin_code": _child_text(element, "PINCODE") or pin_from_address,
        "country": _child_text(element, "COUNTRYNAME", "COUNTRY") or "India",
        "phone_number": _phone_number(element),
        "email": _child_text(element, "EMAIL"),
        "gst_number": gstin,
        "pan_number": pan,
        "tan_number": _child_text(element, "TANUMBER"),
        "financial_year_start_date": _parse_date(_child_text(element, "STARTINGFROM", "BOOKSFROM")),
        "financial_year_end_date": _parse_date(_child_text(element, "ENDINGAT")),
    }


def _fill_missing(target: dict[str, Any], source: dict[str, Any]) -> None:
    for key, value in source.items():
        if value and not target.get(key):
            target[key] = value


def _is_failure(xml_text: str) -> str | None:
    upper = xml_text.upper()
    if "<STATUS>0</STATUS>" in upper or re.search(r"<STATUS>\s*0\s*</STATUS>", upper):
        messages = re.findall(r"<LINEERROR>(.*?)</LINEERROR>", xml_text, flags=re.I | re.S)
        if not messages:
            messages = re.findall(r"<ERRORMSG>(.*?)</ERRORMSG>", xml_text, flags=re.I | re.S)
        if not messages:
            messages = re.findall(r"<DESC>(.*?)</DESC>", xml_text, flags=re.I | re.S)
        detail = "; ".join(item.strip() for item in messages if item.strip())
        return detail or "Tally export failed"
    return None


def post_xml(xml_body: str, timeout: int | None = None, url: str | None = None) -> str:
    target_url = (url or tally_url()).rstrip("/")
    try:
        response = requests.post(
            target_url,
            data=xml_body.encode("utf-8"),
            headers={"Content-Type": "application/xml"},
            timeout=timeout or tally_timeout(),
        )
    except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as exc:
        raise TallyUnavailable(
            f"Tally is not responding at {target_url}."
        ) from exc
    response.raise_for_status()
    text = decode_tally_bytes(response.content)
    text = sanitize_xml(text)
    error = _is_failure(text)
    if error:
        raise RuntimeError(f"Tally error from {target_url}: {error}")
    return text


_COMPANY_ENRICH_CACHE: dict[str, tuple[float, dict[str, Any]]] = {}
_CURRENT_COMPANY_CACHE: tuple[float, dict[str, Any] | None] | None = None


def _enrich_company(company: dict[str, Any], url: str | None = None) -> dict[str, Any]:
    name = company.get("tally_company_name")
    if not name:
        return company

    now = time.time()
    cached = _COMPANY_ENRICH_CACHE.get(name)
    if cached and (now - cached[0]) < 1800:  # 30-minute cache for company details
        _fill_missing(company, cached[1])
        return company

    try:
        details = parse_companies(post_xml(_company_object_xml(name), url=url))
        if details:
            _fill_missing(company, details[0])
    except TallyUnavailable:
        raise
    except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
        raise
    except Exception as exc:  # noqa: BLE001
        print(f"Address fetch failed for {name}: {exc}")
    try:
        gstin = parse_gstin(post_xml(_tax_unit_xml(name), url=url))
        if gstin:
            company["gst_number"] = company.get("gst_number") or gstin
            if not company.get("pan_number") and len(gstin) == 15:
                company["pan_number"] = gstin[2:12]
    except TallyUnavailable:
        raise
    except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
        raise
    except Exception as exc:  # noqa: BLE001
        print(f"GST fetch failed for {name}: {exc}")

    _COMPANY_ENRICH_CACHE[name] = (now, dict(company))
    return company


def fetch_companies_from_tally(url: str | None = None, timeout: int | None = None) -> list[dict[str, Any]]:
    xml_text = post_xml(_collection_xml("CompanyMasterCol", COMPANY_METHODS), timeout=timeout, url=url)
    companies = parse_companies(xml_text)
    if not companies:
        xml_text = post_xml(LIST_OF_COMPANIES_XML, timeout=timeout, url=url)
        companies = parse_companies(xml_text)
    if not companies:
        return []
    return _with_connection([_enrich_company(company, url=url) for company in companies], url=url)


def fetch_current_company(url: str | None = None, timeout: int | None = None, force_fresh: bool = False) -> dict[str, Any] | None:
    global _CURRENT_COMPANY_CACHE
    now = time.time()
    if not force_fresh and _CURRENT_COMPANY_CACHE and (now - _CURRENT_COMPANY_CACHE[0]) < 5:
        return dict(_CURRENT_COMPANY_CACHE[1]) if _CURRENT_COMPANY_CACHE[1] else None

    try:
        current = parse_companies(post_xml(CURRENT_COMPANY_XML, timeout=timeout, url=url))
        if len(current) == 1:
            res = _with_connection([_enrich_company(current[0], url=url)], url=url)[0]
            _CURRENT_COMPANY_CACHE = (now, res)
            return res
    except TallyUnavailable:
        _CURRENT_COMPANY_CACHE = None
        raise
    except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
        _CURRENT_COMPANY_CACHE = None
        raise
    except Exception as exc:  # noqa: BLE001
        print(f"Current company detect: {exc}")

    companies = fetch_companies_from_tally(url=url, timeout=timeout)
    if len(companies) == 1:
        _CURRENT_COMPANY_CACHE = (now, companies[0])
        return companies[0]
    if companies:
        print(
            "  Multiple Tally companies are loaded; using the first loaded company. "
            "Keep only the target company open for a precise sync."
        )
        _CURRENT_COMPANY_CACHE = (now, companies[0])
        return companies[0]
    _CURRENT_COMPANY_CACHE = (now, None)
    return None


def _with_connection(companies: list[dict[str, Any]], url: str | None = None) -> list[dict[str, Any]]:
    target_url = (url or tally_url()).rstrip("/")
    port = tally_port()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for row in companies:
        row["tally_server_url"] = target_url
        row["tally_port"] = port
        row["is_active"] = True
        row["sync_status"] = "synced"
        row["sync_error_message"] = None
        row["last_synced_at"] = now
    return companies
