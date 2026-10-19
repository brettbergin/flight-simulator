"""Pinned, offline KAWO NASR source ingestion; no terrain or runtime admission.

The accepted JavaScript validateSourcePair remains the final pair validator.
This module never launches it (or any other process). Outputs require that check.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime
from decimal import Decimal, localcontext
import hashlib
import io
import json
import math
from pathlib import Path
import re
import sys
import zipfile


ARCHIVE_SHA256 = "aba48ea877f249d9b8cd63988b14b3432a6a09ad1fbe9561a5e6443c99c03dd0"
ARCHIVE_BYTES = 8030968
ARCHIVE_URL = "https://nfdc.faa.gov/webContent/28DaySub/extra/01_Oct_2026_APT_CSV.zip"
CYCLE = "2026/10/01"
EFFECTIVE_FROM = "2026-10-01T00:00:00Z"
EFFECTIVE_UNTIL = "2026-10-29T00:00:00Z"
MAX_JSON = 4194304
MAX_MEMBER = 32 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
MAX_ROWS = 100000
MAX_FIELD = 8192
MEMBERS = ("APT DATA LAYOUT.pdf", "APT_ARS.csv", "APT_ATT.csv", "APT_BASE.csv",
           "APT_CON.csv", "APT_CSV_DATA_STRUCTURE.csv", "APT_RMK.csv", "APT_RWY.csv",
           "APT_RWY_END.csv", "CSV_README.pdf")
TABLES = {
    "APT_BASE.csv": (9837278, 90, 19427),
    "APT_RWY.csv": (3094505, 26, 23191),
    "APT_RWY_END.csv": (11561739, 80, 39829),
}
IDENTITY = {"SITE_NO": "26099.", "SITE_TYPE_CODE": "A", "STATE_CODE": "WA",
            "ARPT_ID": "AWO", "COUNTRY_CODE": "US"}
BASE_FIELDS = tuple(IDENTITY) + (
    "EFF_DATE", "ICAO_ID", "ARPT_NAME", "LAT_DECIMAL", "LONG_DECIMAL", "ELEV",
    "SURVEY_METHOD_CODE", "ELEV_METHOD_CODE", "ARPT_PSN_SOURCE", "POSITION_SRC_DATE",
    "ARPT_ELEV_SOURCE", "ELEVATION_SRC_DATE", "TPA", "MAG_VARN", "MAG_HEMIS", "MAG_VARN_YEAR")
RUNWAY_FIELDS = tuple(IDENTITY) + (
    "EFF_DATE", "RWY_ID", "RWY_LEN", "RWY_WIDTH", "SURFACE_TYPE_CODE", "RWY_LEN_SOURCE",
    "LENGTH_SOURCE_DATE")
END_FIELDS = tuple(IDENTITY) + (
    "EFF_DATE", "RWY_ID", "RWY_END_ID", "LAT_DECIMAL", "LONG_DECIMAL", "RWY_END_ELEV",
    "TRUE_ALIGNMENT", "RIGHT_HAND_TRAFFIC_PAT_FLAG", "LAT_DISPLACED_THR_DECIMAL",
    "LONG_DISPLACED_THR_DECIMAL", "DISPLACED_THR_ELEV", "DISPLACED_THR_LEN", "TKOF_RUN_AVBL",
    "TKOF_DIST_AVBL", "ACLT_STOP_DIST_AVBL", "LNDG_DIST_AVBL", "RWY_GRAD", "RWY_GRAD_DIRECTION",
    "RWY_END_PSN_SOURCE", "RWY_END_PSN_DATE", "RWY_END_ELEV_SOURCE", "RWY_END_ELEV_DATE")
REQUIRED = dict(zip(TABLES, (BASE_FIELDS, RUNWAY_FIELDS, END_FIELDS)))
RUNWAY_IDS = {"11/29": ("11", "29"), "16/34": ("16", "34")}
DECIMAL_TEXT = re.compile(r"-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\Z", re.ASCII)
STABLE_ID = re.compile(r"[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\Z", re.ASCII)


class IngestError(ValueError):
    """Closed source/format mismatch. No repaired or partially accepted record."""


def _require(condition, message):
    if not condition:
        raise IngestError(message)


def _digest(data):
    return hashlib.sha256(data).hexdigest()


def _read_bounded(path, maximum):
    with Path(path).open("rb") as stream:
        data = stream.read(maximum + 1)
    _require(0 < len(data) <= maximum, "input byte limit exceeded or empty input")
    return data


def _json_bytes(value):
    data = (json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True,
                       indent=2) + "\n").encode("utf-8", errors="strict")
    _require(len(data) <= MAX_JSON, "output JSON byte limit exceeded")
    return data


def _strict_json(data):
    _require(0 < len(data) <= MAX_JSON and not data.startswith(b"\xef\xbb\xbf"),
             "dossier must be bounded UTF-8 without BOM")

    def pairs(items):
        result = {}
        for key, value in items:
            _require(key not in result, "duplicate dossier JSON key")
            result[key] = value
        return result

    def nonfinite(_):
        raise IngestError("nonfinite dossier number")

    try:
        value = json.loads(data.decode("utf-8", errors="strict"), object_pairs_hook=pairs,
                           parse_float=Decimal, parse_constant=nonfinite)
    except (UnicodeError, json.JSONDecodeError, RecursionError, ValueError) as error:
        raise IngestError("invalid dossier JSON") from error
    count = 0
    stack = [(value, 0)]
    while stack:
        node, depth = stack.pop()
        count += 1
        _require(depth <= 32 and count <= 200000, "dossier structure limit exceeded")
        if isinstance(node, dict):
            stack.extend((key, depth + 1) for key in node)
            stack.extend((child, depth + 1) for child in node.values())
        elif isinstance(node, list):
            stack.extend((child, depth + 1) for child in node)
        elif isinstance(node, str):
            _require(not any(0xD800 <= ord(ch) <= 0xDFFF for ch in node), "unpaired dossier surrogate")
        elif isinstance(node, (Decimal, int)) and not isinstance(node, bool):
            try:
                _require(math.isfinite(float(node)), "overflow dossier number")
            except (OverflowError, ValueError) as error:
                raise IngestError("overflow dossier number") from error
    return value


def _utc(value):
    _require(isinstance(value, str) and len(value) == 20, "invalid dossier UTC")
    try:
        result = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise IngestError("invalid dossier UTC") from error
    _require(result.strftime("%Y-%m-%dT%H:%M:%SZ") == value, "invalid dossier UTC")
    return result


def _source_binding(dossier_bytes):
    """Narrow source preflight; final full schema/semantics are external JS."""
    dossier = _strict_json(dossier_bytes)
    _require(isinstance(dossier, dict), "dossier must be an object")
    _require(set(dossier) == {"schema", "airport_icao", "purpose", "as_of_utc", "sources", "conflicts", "notes"},
             "unexpected dossier keys")
    _require(dossier["schema"] == "AirportSourceDossier/v1" and dossier["airport_icao"] == "KAWO"
             and dossier["purpose"] == "source-record", "not a KAWO source-record dossier")
    snapshot = _utc(dossier["as_of_utc"])
    _require(isinstance(dossier["sources"], list) and 1 <= len(dossier["sources"]) <= 64,
             "invalid dossier sources")
    seen = set()
    matches = []
    for source in dossier["sources"]:
        _require(isinstance(source, dict), "invalid dossier source")
        source_id = source.get("id")
        _require(isinstance(source_id, str) and len(source_id) <= 128 and STABLE_ID.fullmatch(source_id),
                 "invalid dossier source ID")
        _require(source_id not in seen, "duplicate dossier source ID")
        seen.add(source_id)
        _require(source.get("kind") != "original-fixture", "synthetic source in real dossier")
        if source.get("kind") == "faa-nasr" and source.get("url") == ARCHIVE_URL:
            matches.append(source)
    _require(len(matches) == 1, "require one exact FAA archive source in dossier")
    source = matches[0]
    _require(source.get("capture_state") in ("captured", "reviewed"), "FAA source not captured")
    _require(_utc(source.get("retrieved_utc")) <= snapshot, "FAA retrieval after dossier snapshot")
    _require(source.get("effective_from") == EFFECTIVE_FROM
             and source.get("effective_until") in (None, EFFECTIVE_UNTIL), "FAA effective cycle mismatch")
    artifact = source.get("artifact")
    _require(isinstance(artifact, dict) and set(artifact) == {"sha256", "bytes", "relative_path"},
             "invalid FAA artifact identity")
    _require(artifact["sha256"] == ARCHIVE_SHA256 and type(artifact["bytes"]) is int
             and artifact["bytes"] == ARCHIVE_BYTES, "FAA artifact does not bind exact archive")
    rights = source.get("rights")
    _require(isinstance(rights, dict) and set(rights) == {"status", "license", "notice", "reviewed_utc"},
             "invalid FAA rights declaration")
    _require(rights["status"] in ("pending", "redistributable", "reference-only"), "invalid FAA rights status")
    if rights["status"] == "pending":
        _require(rights["reviewed_utc"] is None and source["capture_state"] != "reviewed",
                 "pending rights cannot claim reviewed source")
    else:
        _require(isinstance(rights["license"], str) and bool(rights["license"])
                 and _utc(rights["reviewed_utc"]) <= snapshot, "invalid FAA rights review")
    _require(artifact["relative_path"] is None, "raw ZIP must remain an external source reference")
    return source["id"]


def _decimal(raw, field, minimum, maximum):
    _require(isinstance(raw, str) and len(raw) <= 64 and DECIMAL_TEXT.fullmatch(raw),
             "malformed numeric field: " + field)
    value = Decimal(raw)
    _require(value.is_finite() and Decimal(str(minimum)) <= value <= Decimal(str(maximum)),
             "numeric range exceeded: " + field)
    return value


def _number(raw, field, minimum, maximum, feet=False):
    with localcontext() as context:
        context.prec = 96  # More than the bounded 64-character decimal input.
        value = _decimal(raw, field, minimum, maximum)
        if feet:
            value *= Decimal("0.3048")
        result = float(value)
    _require(math.isfinite(result), "nonfinite converted value")
    return result


def _csv_rows(data, member, required, expected_columns=None):
    """Private bounded parser; synthetic tests do not bypass CLI archive pins."""
    _require(0 < len(data) <= MAX_MEMBER and not data.startswith(b"\xef\xbb\xbf"), "CSV byte limit/BOM")
    try:
        text = data.decode("utf-8", errors="strict")
        _require("\x00" not in text, "NUL in CSV")
        reader = csv.reader(io.StringIO(text, newline=""), strict=True)
        header = next(reader, None)
        _require(header is not None and 1 <= len(header) <= 128 and len(set(header)) == len(header),
                 "missing or duplicate CSV columns")
        _require(all(re.fullmatch(r"[A-Z][A-Z0-9_]{0,79}", field, re.ASCII) for field in header),
                 "invalid CSV column name")
        _require(set(required) <= set(header), "missing required CSV column in " + member)
        _require(expected_columns is None or len(header) == expected_columns, "unexpected source column count")
        count = 0
        selected = []
        for fields in reader:
            count += 1
            _require(count <= MAX_ROWS and len(fields) == len(header), "CSV row count/shape limit")
            _require(all(len(field) <= MAX_FIELD for field in fields), "CSV field size exceeded")
            record = dict(zip(header, fields))
            if (record.get("SITE_NO") == "26099." or record.get("ARPT_ID") == "AWO"
                    or record.get("ICAO_ID") == "KAWO"):
                _require(all(record.get(key) == value for key, value in IDENTITY.items())
                         and record.get("EFF_DATE") == CYCLE, "inconsistent target identity/cycle join")
                if member == "APT_BASE.csv":
                    _require(record.get("ICAO_ID") == "KAWO", "target ICAO mismatch")
                # Retain only consumed source fields. No unrelated contact details.
                selected.append({key: record[key] for key in required})
        return selected, count
    except (UnicodeError, csv.Error) as error:
        raise IngestError("invalid CSV encoding/grammar in " + member) from error


def _zip_members(data):
    """Read named CSV members only; never extract or follow archive paths."""
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            infos = archive.infolist()
            _require(1 <= len(infos) <= 32, "ZIP member count exceeded")
            names = [info.filename for info in infos]
            _require(len(set(name.casefold() for name in names)) == len(names), "duplicate ZIP member")
            total = 0
            for info in infos:
                _require(info.filename in MEMBERS and not info.is_dir(), "unexpected ZIP member")
                _require(not (info.flag_bits & 1) and info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED),
                         "encrypted/unsupported ZIP member")
                unix_type = (info.external_attr >> 16) & 0o170000
                _require(unix_type in (0, 0o100000), "ZIP special Unix member type unsupported")
                _require(0 < info.file_size <= MAX_MEMBER and info.compress_size <= ARCHIVE_BYTES,
                         "ZIP member size exceeded")
                total += info.file_size
                _require(total <= MAX_TOTAL, "ZIP total size exceeded")
            _require(set(TABLES) <= set(names), "required CSV ZIP member absent")
            result = {}
            for member in TABLES:
                with archive.open(member, "r") as stream:
                    contents = stream.read(MAX_MEMBER + 1)  # Complete read verifies CRC.
                _require(len(contents) == archive.getinfo(member).file_size
                         and len(contents) <= MAX_MEMBER, "ZIP member length mismatch")
                result[member] = contents
            return result, tuple(names)
    except (zipfile.BadZipFile, NotImplementedError, RuntimeError, EOFError, OSError) as error:
        raise IngestError("invalid ZIP input") from error


def _actual_tables(archive_bytes):
    _require(len(archive_bytes) == ARCHIVE_BYTES and _digest(archive_bytes) == ARCHIVE_SHA256,
             "archive exact byte identity mismatch")
    members, names = _zip_members(archive_bytes)
    _require(set(names) == set(MEMBERS), "pinned ZIP member roster mismatch")
    tables = {}
    for member, (size, columns, national_rows) in TABLES.items():
        _require(len(members[member]) == size, "pinned CSV byte size mismatch")
        rows, count = _csv_rows(members[member], member, REQUIRED[member], columns)
        _require(count == national_rows, "pinned national CSV row count mismatch")
        tables[member] = rows
    return tables


def _locator(member, row, fields):
    keys = ["SITE_NO", "ARPT_ID", "EFF_DATE"] + (["RWY_ID"] if "RWY_ID" in row else [])
    if "RWY_END_ID" in row:
        keys.append("RWY_END_ID")
    return member + "; " + "; ".join(key + "=" + row[key] for key in keys) + "; fields=" + ",".join(fields)


class _Observations:
    def __init__(self, source_id):
        self.source_id = source_id

    def refs(self, member, row, fields):
        return [{"source_id": self.source_id, "locator": _locator(member, row, fields)}]

    def scalar(self, member, row, field, unit, kind="length", required=False):
        raw = row[field]
        refs = self.refs(member, row, [field])
        note = field + "=" + repr(raw) + " " + unit + "; "
        if not raw:
            _require(not required, "missing required value: " + field)
            result = {"status": "unknown", "value": None, "source_refs": refs,
                      "note": note + "blank source value; no zero/full-runway substitution"}
        else:
            if kind == "elevation":
                value = _number(raw, field, -4000, 40000, feet=True)
                _require(-1000 <= value <= 10000, "converted elevation exceeds schema range")
            elif kind == "bearing":
                value = _number(raw, field, 0, 360)
                _require(value < 360, "true bearing must be below 360")
            elif kind == "text":
                _require(len(raw) <= 256 and not any(ord(ch) < 32 for ch in raw), "invalid source text")
                value = raw
            else:
                value = _number(raw, field, 0, 164041, feet=True)
                _require(value <= 50000, "converted length exceeds schema range")
            result = {"status": "known", "value": value, "source_refs": refs,
                      "note": note + ("exact Decimal feet*0.3048 before JSON number" if unit.startswith("ft")
                                      else "captured source value; no operational validation")}
        if kind == "elevation":
            result["vertical_datum"] = "msl-unspecified"
            result["note"] += "; MSL does not establish a specific vertical realization"
        return result

    def point(self, member, row, latitude, longitude, required=False):
        lat, lon = row[latitude], row[longitude]
        _require(bool(lat) == bool(lon), "incomplete coordinate pair")
        _require(not required or bool(lat), "missing required coordinate pair")
        refs = self.refs(member, row, [latitude, longitude])
        refs.append({"source_id": self.source_id, "locator": "CSV_README.pdf; DATUM; all US coordinate information references NAD83"})
        return {"status": "known" if lat else "unknown",
                "latitude_deg": _number(lat, latitude, -90, 90) if lat else None,
                "longitude_deg": _number(lon, longitude, -180, 180) if lon else None,
                "horizontal_crs": {"authority": "EPSG", "code": "4269", "realization": None, "epoch_year": None},
                "source_refs": refs,
                "note": latitude + "=" + repr(lat) + " deg; " + longitude + "=" + repr(lon)
                        + " deg; generic NAD83, realization/epoch unknown; "
                        + ("no datum conversion" if lat else "blank displacement coordinates do not prove threshold coincidence")}


def _normalize(tables, source_id, dossier_sha256):
    """Pure selected-row mapping, independently testable with synthetic rows."""
    bases, runways, ends = (tables[name] for name in TABLES)
    _require(len(bases) == 1 and len(runways) == 2 and len(ends) == 4, "KAWO selected record counts mismatch")
    base = bases[0]
    _require(base["ICAO_ID"] == "KAWO" and base["ARPT_NAME"] == "ARLINGTON MUNI", "KAWO airport identity mismatch")
    runway_by_id = {}
    for row in runways:
        _require(row["RWY_ID"] in RUNWAY_IDS and row["RWY_ID"] not in runway_by_id,
                 "duplicate/unexpected runway")
        _require(row["SURFACE_TYPE_CODE"] == "ASPH", "expected two paved ASPH source runways")
        runway_by_id[row["RWY_ID"]] = row
    end_by_id = {}
    for row in ends:
        key = (row["RWY_ID"], row["RWY_END_ID"])
        _require(key[0] in RUNWAY_IDS and key[1] in RUNWAY_IDS[key[0]] and key not in end_by_id,
                 "duplicate/inconsistent runway-end join")
        end_by_id[key] = row
    obs = _Observations(source_id)
    notes = []

    def note(field, member, row, fields, explanation):
        text = "; ".join(key + "=" + repr(row[key]) for key in fields) + "; " + explanation
        _require(len(text) <= 4096, "source note exceeded")
        notes.append({"field": field, "text": text, "source_refs": obs.refs(member, row, fields)})

    note("/", "APT_BASE.csv", base, list(IDENTITY) + ["ICAO_ID", "EFF_DATE"],
         "exact target identity/cycle used for joins; no other airport or cycle is substituted")
    note("/reference_point", "APT_BASE.csv", base,
         ["SURVEY_METHOD_CODE", "ARPT_PSN_SOURCE", "POSITION_SRC_DATE"],
         "E is the estimated airport-position method; retain source attribution/date independently of elevation survey")
    note("/field_elevation", "APT_BASE.csv", base,
         ["ELEV_METHOD_CODE", "ARPT_ELEV_SOURCE", "ELEVATION_SRC_DATE"],
         "S is the surveyed elevation method; feet MSL is not NAVD88 or ellipsoid height")
    if base["TPA"]:
        tpa = _number(base["TPA"], "TPA", 0, 50000, feet=True)
        tpa_note = "published whole feet AGL; exact SI value " + str(tpa) + " m AGL, not an MSL procedure"
    else:
        tpa_note = "pattern altitude remains unknown"
    note("/", "APT_BASE.csv", base, ["TPA"], tpa_note)
    if base["MAG_VARN"]:
        _decimal(base["MAG_VARN"], "MAG_VARN", 0, 180)
        _require(base["MAG_HEMIS"] in ("E", "W"), "invalid magnetic hemisphere")
    if base["MAG_VARN_YEAR"]:
        _decimal(base["MAG_VARN_YEAR"], "MAG_VARN_YEAR", 1800, 2200)
    note("/", "APT_BASE.csv", base, ["MAG_VARN", "MAG_HEMIS", "MAG_VARN_YEAR"],
         "MAG_VARN is degrees with published hemisphere/year; never a contemporary transform or runway-number recalculation")
    output_runways = []
    for runway_index, runway_id in enumerate(sorted(RUNWAY_IDS)):
        row = runway_by_id[runway_id]
        output_ends = []
        note("/runways/" + str(runway_index), "APT_RWY.csv", row,
             ["RWY_LEN_SOURCE", "LENGTH_SOURCE_DATE"], "published dimensions retain their source date")
        for end_index, end_id in enumerate(RUNWAY_IDS[runway_id]):
            end = end_by_id[(runway_id, end_id)]
            path = "/runways/" + str(runway_index) + "/ends/" + str(end_index)
            physical = obs.point("APT_RWY_END.csv", end, "LAT_DECIMAL", "LONG_DECIMAL", required=True)
            threshold = obs.point("APT_RWY_END.csv", end, "LAT_DISPLACED_THR_DECIMAL", "LONG_DISPLACED_THR_DECIMAL")
            displacement = obs.scalar("APT_RWY_END.csv", end, "DISPLACED_THR_LEN", "ft")
            length = _number(row["RWY_LEN"], "RWY_LEN", 0, 164041, feet=True)
            _require(displacement["value"] is None or displacement["value"] <= length, "displacement exceeds runway length")
            declared = {target: obs.scalar("APT_RWY_END.csv", end, field, "ft") for target, field in
                        (("tora_m", "TKOF_RUN_AVBL"), ("toda_m", "TKOF_DIST_AVBL"),
                         ("asda_m", "ACLT_STOP_DIST_AVBL"), ("lda_m", "LNDG_DIST_AVBL"))}
            _require(end["RIGHT_HAND_TRAFFIC_PAT_FLAG"] in ("Y", "N", ""), "invalid source traffic-pattern flag")
            if end["RWY_GRAD"]:
                _decimal(end["RWY_GRAD"], "RWY_GRAD", 0, 100)
            if end["DISPLACED_THR_ELEV"]:
                _number(end["DISPLACED_THR_ELEV"], "DISPLACED_THR_ELEV", -3281, 32809, feet=True)
            note(path, "APT_RWY_END.csv", end,
                 ["RIGHT_HAND_TRAFFIC_PAT_FLAG", "RWY_GRAD", "RWY_GRAD_DIRECTION", "DISPLACED_THR_ELEV"],
                 "source flags, gradient percent/direction, displaced-threshold elevation ft MSL only; blanks remain unknown, not flat/zero; no executable procedure")
            note(path + "/physical_end", "APT_RWY_END.csv", end,
                 ["RWY_END_PSN_SOURCE", "RWY_END_PSN_DATE", "RWY_END_ELEV_SOURCE", "RWY_END_ELEV_DATE"],
                 "position/elevation source attribution retained separately")
            output_ends.append({"id": "kawo.end." + end_id,
                                "designator": obs.scalar("APT_RWY_END.csv", end, "RWY_END_ID", "published designator", "text", True),
                                "physical_end": physical, "landing_threshold": threshold,
                                "elevation": obs.scalar("APT_RWY_END.csv", end, "RWY_END_ELEV", "ft MSL", "elevation", True),
                                "displacement_m": displacement,
                                "true_bearing_deg": obs.scalar("APT_RWY_END.csv", end, "TRUE_ALIGNMENT", "degrees true", "bearing", True),
                                "declared_distances": declared})
        _require((output_ends[0]["physical_end"]["latitude_deg"], output_ends[0]["physical_end"]["longitude_deg"])
                 != (output_ends[1]["physical_end"]["latitude_deg"], output_ends[1]["physical_end"]["longitude_deg"]),
                 "coincident physical endpoints")
        length_obs = obs.scalar("APT_RWY.csv", row, "RWY_LEN", "ft", required=True)
        width_obs = obs.scalar("APT_RWY.csv", row, "RWY_WIDTH", "ft", required=True)
        _require(length_obs["value"] > 0 and width_obs["value"] > 0, "nonpositive runway dimensions")
        output_runways.append({"id": "kawo.runway." + runway_id.replace("/", "-"), "ends": output_ends,
                               "length_m": length_obs, "width_m": width_obs,
                               "surface": obs.scalar("APT_RWY.csv", row, "SURFACE_TYPE_CODE", "FAA surface code", "text", True),
                               "note": "Pinned NASR paved subset only; physical ends are not inferred landing thresholds."})
    notes.append({"field": "/", "text": "Bounded 1-airport/2-paved-runway/4-physical-end NASR subset. Turf/glider facilities, taxi graph, lighting, frequencies, closures, obstacles and operational procedures are not established by omission. No terrain, geoid or canonical ellipsoid coordinates are produced.",
                  "source_refs": [{"source_id": source_id, "locator": "APT_BASE.csv/APT_RWY.csv/APT_RWY_END.csv; AWO/site26099.; pinned cycle 2026/10/01"}]})
    return {"schema": "NormalizedAirport/v1", "airport_icao": "KAWO", "purpose": "source-record",
            "dossier_sha256": dossier_sha256, "review_state": "draft",
            "name": obs.scalar("APT_BASE.csv", base, "ARPT_NAME", "source name", "text", True),
            "reference_point": obs.point("APT_BASE.csv", base, "LAT_DECIMAL", "LONG_DECIMAL", required=True),
            "field_elevation": obs.scalar("APT_BASE.csv", base, "ELEV", "ft MSL", "elevation", True),
            "runways": output_runways, "notes": notes}


def ingest(archive_path, dossier_path, output_path):
    """Create a new directory of draft bytes; never overwrite or mark JS accepted."""
    dossier_bytes = _read_bounded(dossier_path, MAX_JSON)
    source_id = _source_binding(dossier_bytes)
    archive_bytes = _read_bounded(archive_path, ARCHIVE_BYTES)
    airport = _normalize(_actual_tables(archive_bytes), source_id, _digest(dossier_bytes))
    airport_bytes = _json_bytes(airport)
    receipt = {"schema": "KawoNasrIngestReceipt/v1", "tool_version": 1,
               "tool_sha256": _digest(Path(__file__).read_bytes()),
               "archive_sha256": ARCHIVE_SHA256, "archive_bytes": ARCHIVE_BYTES,
               "effective_cycle": CYCLE, "selected_counts": {"airport": 1, "runways": 2, "physical_ends": 4},
               "dossier_sha256": _digest(dossier_bytes), "dossier_bytes": len(dossier_bytes),
               "airport_sha256": _digest(airport_bytes), "airport_bytes": len(airport_bytes),
               "review_state": "draft", "final_pair_validation": "required-external-validateSourcePair"}
    receipt_bytes = _json_bytes(receipt)
    output = Path(output_path)
    output.mkdir()  # Parent must exist; existing directory/file/symlink rejects.
    for filename, data in (("dossier.json", dossier_bytes), ("airport.json", airport_bytes),
                           ("ingest-receipt.json", receipt_bytes),
                           ("VALIDATION-REQUIRED.txt", b"Draft source output. Root must validate the exact dossier.json/airport.json bytes with accepted validateSourcePair before acceptance. Not a world/runtime pack.\n")):
        with (output / filename).open("xb") as stream:
            stream.write(data)
    return receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--dossier", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        ingest(args.archive, args.dossier, args.output)
    except (IngestError, OSError) as error:
        # Bounded diagnostics; do not dump arbitrary source records or caller paths.
        print("KAWO ingestion refused: " + (str(error)[:160] if isinstance(error, IngestError)
                                             else "input/output filesystem operation failed"), file=sys.stderr)
        return 2
    print("Draft source bytes written; external validateSourcePair is required.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
