"""Synthetic parser tests and separately opt-in actual-archive comparisons.

No synthetic ZIP is accepted through the real ingest CLI. Actual expectations
come from the independently transcribed, pre-importer source-facts fixture.
"""
from copy import deepcopy
import csv
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("kawo_nasr_v1", ROOT / "tools/ingest/airports/kawo_nasr_v1.py")
INGEST = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INGEST)
FACTS_PATH = Path(__file__).with_name("fixtures") / "expected-source-facts.json"
FACTS_SHA256 = "333bc105f8117cb01218cfab60d9153cbaa7c52b8632a0a87afaf253cbf498b4"


def synthetic_tables():
    """Original minimal rows. Coordinates/dimensions are fake; no FAA contacts."""
    tables = {name: [] for name in INGEST.TABLES}

    def record(fields):
        row = dict.fromkeys(fields, "")
        row.update(INGEST.IDENTITY)
        row["EFF_DATE"] = "2026/10/01"
        return row

    base = record(INGEST.BASE_FIELDS)
    base.update(ICAO_ID="KAWO", ARPT_NAME="ARLINGTON MUNI", LAT_DECIMAL="10", LONG_DECIMAL="20",
                ELEV="141.8", SURVEY_METHOD_CODE="E", ELEV_METHOD_CODE="S", TPA="1000",
                MAG_VARN="17", MAG_HEMIS="E", MAG_VARN_YEAR="2010",
                POSITION_SRC_DATE="2006/05/02", ELEVATION_SRC_DATE="2006/05/02")
    tables["APT_BASE.csv"].append(base)
    for number, (runway_id, ends) in enumerate((("11/29", ("11", "29")), ("16/34", ("16", "34")))):
        runway = record(INGEST.RUNWAY_FIELDS)
        runway.update(RWY_ID=runway_id, RWY_LEN=str(1000 + number * 1000), RWY_WIDTH="100",
                      SURFACE_TYPE_CODE="ASPH", LENGTH_SOURCE_DATE="2006/05/02")
        tables["APT_RWY.csv"].append(runway)
        for index, end_id in enumerate(ends):
            end = record(INGEST.END_FIELDS)
            end.update(RWY_ID=runway_id, RWY_END_ID=end_id, LAT_DECIMAL=str(10 + number),
                       LONG_DECIMAL=str(20 + index), RWY_END_ELEV="100",
                       TRUE_ALIGNMENT=str(123 + number * 10 + index * 180),
                       RIGHT_HAND_TRAFFIC_PAT_FLAG="Y" if index == 0 else "N")
            tables["APT_RWY_END.csv"].append(end)
    return tables


def synthetic_dossier():
    """In-memory source-binding test only; not an acquired real-world dossier."""
    return {"schema": "AirportSourceDossier/v1", "airport_icao": "KAWO", "purpose": "source-record",
            "as_of_utc": "2026-10-19T02:00:00Z", "sources": [{
                "id": "test.nasr", "kind": "faa-nasr", "publisher": "Synthetic parser test",
                "url": INGEST.ARCHIVE_URL, "retrieved_utc": "2026-10-19T01:00:00Z",
                "effective_from": INGEST.EFFECTIVE_FROM, "effective_until": None,
                "capture_state": "captured", "artifact": {"sha256": INGEST.ARCHIVE_SHA256,
                    "bytes": INGEST.ARCHIVE_BYTES, "relative_path": None},
                "rights": {"status": "pending", "license": None, "notice": "Synthetic test only",
                           "reviewed_utc": None}, "note": "Not acquisition evidence"}],
            "conflicts": [], "notes": []}


def csv_bytes(member, rows=None, header=None):
    rows = rows if rows is not None else synthetic_tables()[member]
    header = list(header if header is not None else INGEST.REQUIRED[member])
    text = io.StringIO(newline="")
    writer = csv.writer(text, lineterminator="\r\n")
    writer.writerow(header)
    for row in rows:
        writer.writerow([row.get(key, "") for key in header])
    return text.getvalue().encode("utf-8")


def synthetic_zip(extra=()):
    stream = io.BytesIO()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)  # Deliberate duplicate-member mutant.
        with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for member in INGEST.TABLES:
                archive.writestr(member, csv_bytes(member))
            for name, data in extra:
                archive.writestr(name, data)
    return stream.getvalue()


class SyntheticParserTests(unittest.TestCase):
    def test_minimal_csv_retains_only_consumed_metadata(self):
        name = "APT_BASE.csv"
        rows, count = INGEST._csv_rows(csv_bytes(name), name, INGEST.REQUIRED[name])
        self.assertEqual(count, 1)
        self.assertEqual(rows, synthetic_tables()[name])

    def test_required_displacement_columns_are_exact(self):
        name = "APT_RWY_END.csv"
        for wrong in ("LAT_DISPLACED_THR_DECIMAL", "LONG_DISPLACED_THR_DECIMAL"):
            header = [field if field != wrong else "INCORRECT_ALIAS" for field in INGEST.REQUIRED[name]]
            with self.subTest(column=wrong), self.assertRaises(INGEST.IngestError):
                INGEST._csv_rows(csv_bytes(name, header=header), name, INGEST.REQUIRED[name])

    def test_duplicate_missing_column_shape_encoding_and_field_mutants(self):
        name = "APT_BASE.csv"
        valid = csv_bytes(name)
        duplicate = list(INGEST.REQUIRED[name]) + ["EFF_DATE"]
        mutants = [csv_bytes(name, header=duplicate), b"\xef\xbb\xbf" + valid,
                   valid + b"bad,row\r\n", valid.replace(b"ARLINGTON MUNI", b"\xff"),
                   valid.replace(b"ARLINGTON MUNI", b"\x00"),
                   valid.replace(b"ARLINGTON MUNI", b"a" * (INGEST.MAX_FIELD + 1))]
        for data in mutants:
            with self.subTest(size=len(data)), self.assertRaises(INGEST.IngestError):
                INGEST._csv_rows(data, name, INGEST.REQUIRED[name])

    def test_target_partial_identity_or_cycle_never_silently_drops(self):
        name = "APT_BASE.csv"
        for field, value in (("SITE_NO", "other"), ("ARPT_ID", "BAD"), ("STATE_CODE", "OR"),
                             ("SITE_TYPE_CODE", "H"), ("ICAO_ID", "KBAD"), ("EFF_DATE", "2026/10/29")):
            row = synthetic_tables()[name][0]
            row[field] = value
            with self.subTest(field=field), self.assertRaises(INGEST.IngestError):
                INGEST._csv_rows(csv_bytes(name, [row]), name, INGEST.REQUIRED[name])

    def test_synthetic_zip_has_bounded_named_members(self):
        members, names = INGEST._zip_members(synthetic_zip())
        self.assertEqual(set(names), set(INGEST.TABLES))
        self.assertEqual(set(members), set(INGEST.TABLES))
        for extra in (("../APT_BASE.csv", b"bad"), ("APT_BASE.csv", b"duplicate"),
                      ("apt_base.csv", b"case-alias"), ("unknown.csv", b"bad")):
            with self.subTest(name=extra[0]), self.assertRaises(INGEST.IngestError):
                INGEST._zip_members(synthetic_zip([extra]))

    def test_synthetic_zip_never_qualifies_as_real_archive(self):
        with self.assertRaises(INGEST.IngestError):
            INGEST._actual_tables(synthetic_zip())
        with self.assertRaises(INGEST.IngestError):
            INGEST._zip_members(b"not a ZIP")

    def test_zip_special_unix_types_and_header_crc_size_mutants(self):
        # ZIP central-directory layout is a separately specified container format;
        # these malformed synthetic headers do not modify real archive evidence.
        def central_field(relative, width, value):
            data = bytearray(synthetic_zip())
            start = data.index(b"PK\x01\x02")
            if value is None:
                value = int.from_bytes(data[start + relative:start + relative + width], "little") ^ 1
            data[start + relative:start + relative + width] = value.to_bytes(width, "little")
            return bytes(data)

        regular, _ = INGEST._zip_members(central_field(38, 4, 0o100600 << 16))
        self.assertEqual(set(regular), set(INGEST.TABLES))
        for mode in (0o010000, 0o020000, 0o040000, 0o060000, 0o120000, 0o140000):
            with self.subTest(unix_type=oct(mode)), self.assertRaises(INGEST.IngestError):
                INGEST._zip_members(central_field(38, 4, (mode | 0o600) << 16))
        for data in (central_field(8, 2, 1), central_field(10, 2, 99),
                     central_field(24, 4, INGEST.MAX_MEMBER + 1), central_field(16, 4, None)):
            with self.assertRaises(INGEST.IngestError):
                INGEST._zip_members(data)

    def test_row_and_json_depth_limits(self):
        data = b"SITE_NO\r\n" + b"other\r\n" * (INGEST.MAX_ROWS + 1)
        with self.assertRaises(INGEST.IngestError):
            INGEST._csv_rows(data, "synthetic.csv", ())
        with self.assertRaises(INGEST.IngestError):
            INGEST._strict_json(b"[" * 34 + b"0" + b"]" * 34)

    def test_decimal_feet_before_final_float_and_bad_numeric_inputs(self):
        self.assertEqual(INGEST._number("141.8", "ELEV", -4000, 40000, feet=True), 43.22064)
        self.assertEqual(INGEST._number("3498", "RWY_LEN", 0, 164041, feet=True), 1066.1904)
        for raw in ("NaN", "Infinity", "1e309", " 1", "1 ", "+1", "01", "--1", "1,000", "9" * 65):
            with self.subTest(raw=raw), self.assertRaises(INGEST.IngestError):
                INGEST._number(raw, "test", -4000, 40000, feet=True)

    def test_source_binding_retains_pending_rights_without_upgrading(self):
        dossier = synthetic_dossier()
        before = deepcopy(dossier)
        self.assertEqual(INGEST._source_binding(INGEST._json_bytes(dossier)), "test.nasr")
        self.assertEqual(dossier, before)

    def test_source_binding_refuses_changed_provenance(self):
        mutations = [lambda d: d.update(purpose="synthetic-fixture"),
                     lambda d: d["sources"][0]["artifact"].update(sha256="0" * 64),
                     lambda d: d["sources"][0].update(effective_from="2026-10-29T00:00:00Z"),
                     lambda d: d["sources"][0].update(capture_state="reviewed"),
                     lambda d: d["sources"][0].update(retrieved_utc="2026-10-20T00:00:00Z"),
                     lambda d: d["sources"].append(deepcopy(d["sources"][0]))]
        for mutation in mutations:
            dossier = synthetic_dossier()
            mutation(dossier)
            with self.assertRaises(INGEST.IngestError):
                INGEST._source_binding(INGEST._json_bytes(dossier))
        for data in (b'{"schema":1,"schema":2}', b'{"x":1e9999}', b'{"x":"\\ud800"}',
                     b"{} trailing", b"\xef\xbb\xbf{}", b'{"x":NaN}'):
            with self.assertRaises(INGEST.IngestError):
                INGEST._strict_json(data)


class SyntheticMappingTests(unittest.TestCase):
    def mapped(self, tables=None):
        return INGEST._normalize(tables or synthetic_tables(), "test.nasr", "0" * 64)

    def test_draft_source_datums_unknowns_and_published_heading(self):
        airport = self.mapped()
        self.assertEqual(airport["review_state"], "draft")
        self.assertEqual(airport["field_elevation"]["value"], 43.22064)
        self.assertEqual(airport["field_elevation"]["vertical_datum"], "msl-unspecified")
        crs = airport["reference_point"]["horizontal_crs"]
        self.assertEqual(crs, {"authority": "EPSG", "code": "4269", "realization": None, "epoch_year": None})
        end = airport["runways"][0]["ends"][0]
        self.assertEqual(end["designator"]["value"], "11")
        self.assertEqual(end["true_bearing_deg"]["value"], 123)
        self.assertEqual(end["landing_threshold"]["status"], "unknown")
        self.assertIsNone(end["landing_threshold"]["latitude_deg"])
        for observation in [end["displacement_m"], *end["declared_distances"].values()]:
            self.assertEqual(observation["status"], "unknown")
            self.assertIsNone(observation["value"])
        self.assertIn("ELEV='141.8' ft MSL", airport["field_elevation"]["note"])
        self.assertIn("APT_BASE.csv", airport["field_elevation"]["source_refs"][0]["locator"])

    def test_order_is_deterministic_and_inputs_are_not_modified(self):
        tables = synthetic_tables()
        before = deepcopy(tables)
        expected = INGEST._json_bytes(self.mapped(tables))
        self.assertEqual(tables, before)
        for rows in tables.values():
            rows.reverse()
        self.assertEqual(expected, INGEST._json_bytes(self.mapped(tables)))
        self.assertTrue(expected.endswith(b"\n"))
        self.assertNotIn(b"\r", expected)

    def test_distinct_known_distances_threshold_and_explicit_zero(self):
        tables = synthetic_tables()
        source = tables["APT_RWY_END.csv"][0]
        source.update(TKOF_RUN_AVBL="1000", TKOF_DIST_AVBL="1100",
                      ACLT_STOP_DIST_AVBL="1200", LNDG_DIST_AVBL="900",
                      DISPLACED_THR_LEN="100", LAT_DISPLACED_THR_DECIMAL="10.01",
                      LONG_DISPLACED_THR_DECIMAL="20.01")
        end = self.mapped(tables)["runways"][0]["ends"][0]
        for target, field, expected in (("tora_m", "TKOF_RUN_AVBL", 304.8),
                                        ("toda_m", "TKOF_DIST_AVBL", 335.28),
                                        ("asda_m", "ACLT_STOP_DIST_AVBL", 365.76),
                                        ("lda_m", "LNDG_DIST_AVBL", 274.32)):
            observation = end["declared_distances"][target]
            self.assertEqual(observation["status"], "known")
            self.assertEqual(observation["value"], expected)
            self.assertTrue(observation["source_refs"][0]["locator"].endswith("fields=" + field))
        self.assertEqual(end["displacement_m"]["status"], "known")
        self.assertEqual(end["displacement_m"]["value"], 30.48)
        self.assertEqual(end["landing_threshold"]["status"], "known")
        self.assertEqual(end["landing_threshold"]["latitude_deg"], 10.01)
        self.assertEqual(end["landing_threshold"]["longitude_deg"], 20.01)
        source["DISPLACED_THR_LEN"] = "0"
        zero = self.mapped(tables)["runways"][0]["ends"][0]["displacement_m"]
        self.assertEqual(zero["status"], "known")
        self.assertEqual(zero["value"], 0.0)

    def test_duplicate_missing_and_inconsistent_joins_reject(self):
        def duplicate(tables):
            tables["APT_RWY_END.csv"][1] = deepcopy(tables["APT_RWY_END.csv"][0])

        mutations = [lambda t: t["APT_BASE.csv"].append(t["APT_BASE.csv"][0]),
                     lambda t: t["APT_RWY.csv"].pop(), duplicate,
                     lambda t: t["APT_RWY.csv"][0].update(RWY_ID="10/28"),
                     lambda t: t["APT_RWY_END.csv"][0].update(RWY_ID="16/34"),
                     lambda t: t["APT_RWY.csv"][0].update(SURFACE_TYPE_CODE="TURF")]
        for mutation in mutations:
            tables = synthetic_tables()
            mutation(tables)
            with self.assertRaises(INGEST.IngestError):
                self.mapped(tables)

    def test_coordinate_dimension_displacement_and_bearing_fail_closed(self):
        mutations = [lambda t: t["APT_BASE.csv"][0].update(LAT_DECIMAL="91"),
                     lambda t: t["APT_RWY.csv"][0].update(RWY_LEN="0"),
                     lambda t: t["APT_RWY_END.csv"][0].update(TRUE_ALIGNMENT="360"),
                     lambda t: t["APT_RWY_END.csv"][0].update(LAT_DISPLACED_THR_DECIMAL="10"),
                     lambda t: t["APT_RWY_END.csv"][0].update(DISPLACED_THR_LEN="1001"),
                     lambda t: t["APT_RWY_END.csv"][1].update(LONG_DECIMAL="20")]
        for mutation in mutations:
            tables = synthetic_tables()
            mutation(tables)
            with self.assertRaises(INGEST.IngestError):
                self.mapped(tables)

    def test_production_ingest_rejects_changed_archive_before_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, dossier, output = root / "synthetic.zip", root / "dossier.json", root / "output"
            archive.write_bytes(synthetic_zip())
            dossier.write_bytes(INGEST._json_bytes(synthetic_dossier()))
            with self.assertRaises(INGEST.IngestError):
                INGEST.ingest(archive, dossier, output)
            self.assertFalse(output.exists())


@unittest.skipUnless(os.environ.get("KAWO_TEST_ARCHIVE") and os.environ.get("KAWO_TEST_DOSSIER"),
                     "actual FAA archive/dossier must be explicitly supplied by Root")
class ActualPinnedArchiveTests(unittest.TestCase):
    def test_actual_source_facts_and_repeat_bytes(self):
        facts_bytes = FACTS_PATH.read_bytes()
        self.assertEqual(hashlib.sha256(facts_bytes).hexdigest(), FACTS_SHA256)
        facts = json.loads(facts_bytes)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("first", "repeat"):
                INGEST.ingest(Path(os.environ["KAWO_TEST_ARCHIVE"]), Path(os.environ["KAWO_TEST_DOSSIER"]), root / name)
            for name in ("airport.json", "dossier.json", "ingest-receipt.json", "VALIDATION-REQUIRED.txt"):
                self.assertEqual((root / "first" / name).read_bytes(), (root / "repeat" / name).read_bytes())
            airport = json.loads((root / "first/airport.json").read_bytes())
            self.assertEqual(airport["name"]["value"], facts["identity_raw"]["ARPT_NAME"])
            self.assertEqual(len(airport["runways"]), 2)
            self.assertEqual(sum(len(row["ends"]) for row in airport["runways"]), 4)
            self.assertEqual(airport["field_elevation"]["value"], float(facts["field_elevation"]["exact_si_decimal_m"]))
            self.assertEqual(airport["reference_point"]["latitude_deg"], float(facts["reference_point_raw"]["LAT_DECIMAL"]))
            self.assertEqual(airport["reference_point"]["longitude_deg"], float(facts["reference_point_raw"]["LONG_DECIMAL"]))
            self.assertEqual(airport["review_state"], "draft")
            all_notes = "\n".join(note["text"] for note in airport["notes"])
            for raw in ("SURVEY_METHOD_CODE='E'", "ELEV_METHOD_CODE='S'", "POSITION_SRC_DATE='2006/05/02'",
                        "ELEVATION_SRC_DATE='2006/05/02'", "TPA='1058'", "322.4784 m AGL",
                        "MAG_VARN='17'", "MAG_HEMIS='E'", "MAG_VARN_YEAR='2010'"):
                self.assertIn(raw, all_notes)
            for runway, expected in zip(airport["runways"], facts["runways"], strict=True):
                self.assertEqual(runway["length_m"]["value"], float(expected["exact_length_m"]))
                self.assertEqual(runway["width_m"]["value"], float(expected["exact_width_m"]))
                self.assertEqual(runway["surface"]["value"], expected["SURFACE_TYPE_CODE"])
                for end, designator in zip(runway["ends"], expected["ends"], strict=True):
                    known = next(item for item in facts["ends"] if item["RWY_END_ID"] == designator)
                    self.assertEqual(end["designator"]["value"], designator)
                    self.assertEqual(end["physical_end"]["latitude_deg"], float(known["LAT_DECIMAL"]))
                    self.assertEqual(end["physical_end"]["longitude_deg"], float(known["LONG_DECIMAL"]))
                    self.assertEqual(end["elevation"]["value"], float(known["exact_elevation_m"]))
                    self.assertEqual(end["elevation"]["vertical_datum"], "msl-unspecified")
                    self.assertEqual(end["physical_end"]["horizontal_crs"],
                                     {"authority": "EPSG", "code": "4269", "realization": None, "epoch_year": None})
                    self.assertEqual(end["true_bearing_deg"]["value"], float(known["TRUE_ALIGNMENT_deg"]))
                    self.assertEqual(end["landing_threshold"]["status"], "unknown")
                    self.assertIsNone(end["landing_threshold"]["latitude_deg"])
                    self.assertIsNone(end["landing_threshold"]["longitude_deg"])
                    end_path = "/runways/" + str(airport["runways"].index(runway)) + "/ends/" + str(runway["ends"].index(end))
                    end_notes = "\n".join(item["text"] for item in airport["notes"] if item["field"] == end_path)
                    self.assertIn("RIGHT_HAND_TRAFFIC_PAT_FLAG=" + repr(known["RIGHT_HAND_TRAFFIC_PAT_FLAG"]), end_notes)
                    self.assertIn("RWY_GRAD=''", end_notes)
                    for unknown in [end["displacement_m"], *end["declared_distances"].values()]:
                        self.assertEqual(unknown["status"], "unknown")
                        self.assertIsNone(unknown["value"])
            with self.assertRaises(FileExistsError):
                INGEST.ingest(Path(os.environ["KAWO_TEST_ARCHIVE"]), Path(os.environ["KAWO_TEST_DOSSIER"]), root / "first")


if __name__ == "__main__":
    unittest.main()
