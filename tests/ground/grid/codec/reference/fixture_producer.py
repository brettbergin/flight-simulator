"""Independent literal resident-grid byte fixtures; no production imports/decoder.

Source only until Root review/qualification. Normal mode prints JSON; --check
compares an existing expected JSON artifact without writing any file.
"""
import hashlib
import json
from pathlib import Path
import struct
import sys

MAX_CHECK_BYTES = 1048576
MAGIC = b"FGRDLE1\x00"


def golden_a():
    # These literal blocks follow the hand-authored offset table. This function
    # deliberately is not an encoder accepting arbitrary Definition values.
    header = (
        struct.pack("<8sIIQ", MAGIC, 1, 0x01020304, 195)
        + struct.pack("<8I", 3, 2, 6, 1, 1, 1, 3, 0)
        + struct.pack("<BBHI", 2, 2, 0, 0)
        + struct.pack("<5Q", 0, 0, 0x4059000000000000,
                      0xC000000000000000, 0xC000000000000000)
    )
    heights = struct.pack("<6I", 0, 0x3F800000, 0x7FC00000,
                          0, 0x3F800000, 0x7FC00000)
    validity = struct.pack("<Q", 0x1B)
    material = b"\x05grass" + struct.pack("<2Q", 0x3FE0000000000000,
                                         0x3FD0000000000000)
    polygon = (b"\x03pad" + struct.pack("<IBI", 0, 7, 3)
               + struct.pack("<6i", -1000, -1000, -1000, 1000, 1000, -1000))
    result = header + heights + validity + material + polygon
    if (len(header), len(heights), len(validity), len(material), len(polygon),
            len(result)) != (104, 24, 8, 22, 37, 195):
        raise AssertionError("literal golden-a block lengths changed")
    return result


def signed_zero_b():
    header = (
        struct.pack("<8sIIQ", MAGIC, 1, 0x01020304, 146)
        + struct.pack("<8I", 2, 2, 4, 1, 1, 0, 0, 0)
        + struct.pack("<BBHI", 2, 0, 0, 0)
        + struct.pack("<5Q", 0x8000000000000000, 0x8000000000000000,
                      0x8000000000000000, 0x8000000000000000,
                      0xC000000000000000)
    )
    heights = struct.pack("<4I", 0x80000000, 0, 0x80000000, 0)
    validity = struct.pack("<Q", 0x0F)
    material = b"\x01z" + struct.pack("<2Q", 0x8000000000000000, 0)
    result = header + heights + validity + material
    if (len(header), len(heights), len(validity), len(material), len(result)) != (
            104, 16, 8, 18, 146):
        raise AssertionError("literal signed-zero-b block lengths changed")
    return result


def make_artifact():
    source = Path(__file__)
    oracle = source.with_name("hand-oracles.json")
    fixtures = []
    for name, data in (("golden-a", golden_a()), ("signed-zero-b", signed_zero_b())):
        fixtures.append({"id": name, "byte_count": len(data),
                         "sha256": hashlib.sha256(data).hexdigest(),
                         "hex": data.hex()})
    return {"kind": "independent-synthetic-resident-grid-codec-reference",
            "version": 1,
            "producer_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "hand_oracles_sha256": hashlib.sha256(oracle.read_bytes()).hexdigest(),
            "fixtures": fixtures}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate expected JSON key")
        result[key] = value
    return result


def reject_nonfinite(value):
    raise ValueError("nonfinite expected JSON constant: " + value)


def main():
    if len(sys.argv) == 1:
        print(json.dumps(make_artifact(), indent=2, sort_keys=True))
        return 0
    if len(sys.argv) != 3 or sys.argv[1] != "--check":
        print("usage: fixture_producer.py [--check expected.json]", file=sys.stderr)
        return 2
    try:
        with Path(sys.argv[2]).open("rb") as source:
            data = source.read(MAX_CHECK_BYTES + 1)
        if len(data) > MAX_CHECK_BYTES:
            raise ValueError("expected JSON exceeds 1 MiB limit")
        expected = json.loads(data.decode("utf-8"), object_pairs_hook=unique_object,
                              parse_constant=reject_nonfinite)
        if expected != make_artifact():
            print("literal byte reference JSON mismatch", file=sys.stderr)
            return 1
    except (OSError, UnicodeError, ValueError) as error:
        print("literal byte reference check failed: " + str(error), file=sys.stderr)
        return 1
    print("literal byte reference JSON matches")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
