"""MIT. Mechanical frozen-oracle C++ table emitter, never a decimal converter.

Default --check verifies the existing table. --write explicitly authors the table.
The separately frozen Fraction generator/reference bytes are never modified.
"""
import argparse
import hashlib
import json
from pathlib import Path

PIN = "1cab52841eb0cb063d547bf90e7a50f04a1871a5293bdfee4e0a78ddb8940ff6"


def rendered(path):
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != PIN:
        raise ValueError("Frozen 49-case oracle bytes changed")
    data = json.loads(raw)
    if len(data["cases"]) != 49 or data["candidate_outputs_consumed"] is not False:
        raise ValueError("Unexpected oracle provenance")
    result = ["#pragma once", "// MIT. Mechanical copy of frozen Fraction oracle; no numeric conversion.",
              "#include <array>", "#include <cstdint>", "#include <string_view>",
              "namespace wire_reference {", "struct Case { std::string_view id; std::string_view token; bool ok; std::uint64_t bits; };",
              'inline constexpr std::string_view sha256 = "' + PIN + '";',
              "inline constexpr std::array<Case, 49> cases{{"]
    for item in data["cases"]:
        # Oracle hex is an already selected bit pattern; reversing bytes is not conversion.
        bits = int.from_bytes(bytes.fromhex(item["le_hex"]), "little") if item["ok"] else 0
        result.append("  {" + json.dumps(item["id"]) + ", " + json.dumps(item["token"]) + ", " +
                      ("true" if item["ok"] else "false") + ", 0x%016xULL}," % bits)
    return ("\n".join(result + ["}};", "}", ""])).encode("utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, default=Path(__file__).with_name("reference.json"))
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("reference_cases.hpp"))
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = rendered(args.reference)
    if args.write:
        args.output.write_bytes(expected)
    elif args.output.read_bytes() != expected:
        raise ValueError("Mechanical table differs from frozen fixture")
    print("Frozen49 table " + ("authored" if args.write else "checked") + "; expected bits unchanged")


if __name__ == "__main__":
    main()
