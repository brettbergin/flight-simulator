"""PROPOSED ADR014 source-only materializer; no build, download or patch parser.

The input pristine directory is the exact filtered 279-file library closure,
not an unchecked acquisition. Bootstrap must verify the complete acquisition
before making that selection. The receipt lives outside the vendor directory.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
sys.dont_write_bytecode = True

COMMIT = "3b25f25e49b42d0489c04ac805674fc1450ca579"
ACQUISITION = "df57467a831cfa3ee3cadcb98d8291ce56bb11976e35dd9e93c94201ff1420d5"
INVENTORY_SHA = "083ba0601443c0d24b6641fd04794840cd3054fb7adc98e47f2fb7a1a1048fc5"
VARIANT = "jsbsim-1.3.1-event-aware-constant-power-v1"
PREFIX = "patches/event-aware-constant-power-v1/"
TARGETS = ("src/models/propulsion/FGPropeller.cpp", "src/models/propulsion/FGPropeller.h")
HASH = re.compile(r"[0-9a-f]{64}\Z")

def require(condition, message):
    if not condition:
        raise ValueError(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def closed(value, names):
    require(type(value) is dict and set(value) == set(names), "Unexpected object members")

def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, "Duplicate JSON member")
        result[key] = value
    return result

def read_json(path):
    require(path.stat().st_size < 1024 * 1024, "Oversized metadata")
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs,
                      parse_constant=lambda _: require(False, "Nonfinite JSON"))

def safe(name):
    require(type(name) is str and name and not any(
                ord(character) < 32 or ord(character) == 127 or character in '\\:<>"|?*'
                for character in name), "Unsafe relative path")
    path = PurePosixPath(name)
    require(not path.is_absolute() and all(p not in ("", ".", "..") for p in name.split("/"))
            and str(path) == name, "Noncanonical relative path")
    require(all(not p.endswith((".", " ")) and p.split(".")[0].upper() not in
                {"CON", "PRN", "AUX", "NUL", *("COM" + str(i) for i in range(1, 10)),
                 *("LPT" + str(i) for i in range(1, 10))} for p in path.parts),
            "Unsafe Windows path")
    return name

def regular(path, directory=False):
    info = path.lstat()
    require(not path.is_symlink() and not getattr(info, "st_file_attributes", 0) & 0x400,
            "Links/reparse points forbidden")
    require(stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode),
            "Special filesystem member forbidden")
    if not directory:
        require(info.st_nlink == 1, "Hard-linked source forbidden")

def ancestors(path):
    for parent in (path, *path.parents):
        if parent.exists() or parent.is_symlink():
            regular(parent, directory=True)

def scan(root):
    ancestors(root)
    files = {}
    folded = set()
    for parent, directories, names in os.walk(root, followlinks=False):
        for name in directories:
            regular(Path(parent) / name, directory=True)
        for name in names:
            path = Path(parent) / name
            regular(path)
            relative = safe(path.relative_to(root).as_posix())
            require(relative.casefold() not in folded, "Case-alias source path")
            folded.add(relative.casefold())
            files[relative] = {"path": relative, "bytes": path.stat().st_size, "sha256": sha(path)}
    return dict(sorted(files.items()))

def digest_inventory(files):
    # Explicit identity: ordinal POSIX path UTF8, NUL, raw SHA256, LF per file.
    digest = hashlib.sha256()
    for name, entry in sorted(files.items()):
        digest.update(name.encode("utf-8") + b"\0" + bytes.fromhex(entry["sha256"]) + b"\n")
    return digest.hexdigest()

def blob(entry):
    require(type(entry["bytes"]) is int and 0 < entry["bytes"] < 16 * 1024 * 1024,
            "Missing/invalid reviewed byte count")
    require(type(entry["sha256"]) is str and HASH.fullmatch(entry["sha256"]),
            "Missing/invalid reviewed digest")

def inventory(root):
    path = root / "upstream-file-inventory.json"
    regular(path)
    require(sha(path) == INVENTORY_SHA, "Upstream inventory bytes changed")
    value = read_json(path)
    require(value["upstream_commit"] == COMMIT and value["acquisition_sha256"] == ACQUISITION
            and type(value["upstream_file_count"]) is int and value["upstream_file_count"] == 279
            and len(value["files"]) == 279, "Upstream identity/closure mismatch")
    result = {}
    for entry in value["files"]:
        closed(entry, ("path", "bytes", "sha256"))
        name = safe(entry["path"])
        blob(entry)
        require(name.casefold() not in {p.casefold() for p in result}, "Duplicate inventory path")
        require(Path(name).suffix.lower() not in {".xml", ".exe", ".dll", ".lib", ".zip"},
                "Forbidden library payload")
        result[name] = entry
    require(set(TARGETS) <= set(result), "Missing two patch targets")
    return dict(sorted(result.items()))

def recipe(root, expected_sha256):
    scan(root)  # Reject links/reparse aliases in parents as well as blob leaves.
    require(type(expected_sha256) is str and HASH.fullmatch(expected_sha256), "Reviewed recipe pin required")
    path = root / (PREFIX + "recipe.json")
    regular(path)
    require(sha(path) == expected_sha256, "Recipe digest mismatch")
    value = read_json(path)
    closed(value, ("schema_version", "patch_kind", "source_bundle_schema", "source_variant",
                   "upstream_commit", "acquisition_sha256", "upstream_inventory_sha256",
                   "materializer", "modifications", "changes"))
    require(type(value["schema_version"]) is int and value["schema_version"] == 1 and
            type(value["source_bundle_schema"]) is int and value["source_bundle_schema"] == 2 and
            value["patch_kind"] == "exact-file-replacement-v1" and value["source_variant"] == VARIANT and
            value["upstream_commit"] == COMMIT and value["acquisition_sha256"] == ACQUISITION and
            value["upstream_inventory_sha256"] == INVENTORY_SHA, "Unsupported recipe identity")
    closed(value["materializer"], ("bytes", "sha256"))
    blob(value["materializer"])
    tool = Path(__file__)
    require(tool.stat().st_size == value["materializer"]["bytes"] and sha(tool) == value["materializer"]["sha256"],
            "Materializer identity mismatch")
    closed(value["modifications"], ("author", "date", "license", "method_revision"))
    notice = value["modifications"]
    require(type(notice["author"]) is str and 0 < len(notice["author"]) <= 256 and
            type(notice["date"]) is str and re.fullmatch(r"\d{4}-\d{2}-\d{2}", notice["date"]) and
            notice["license"] == "LGPL-2.1-or-later" and
            notice["method_revision"] == "event_aware_constant_power_v1", "Unreviewed modification identity")
    from datetime import date
    date.fromisoformat(notice["date"])
    require(type(value["changes"]) is list and len(value["changes"]) == 2, "Exactly two replacements required")
    before = inventory(root)
    for target, change in zip(TARGETS, value["changes"]):
        closed(change, ("path", "before", "after"))
        require(change["path"] == target, "Unknown/duplicate/unsorted patch target")
        for phase, member in (("before", PREFIX + Path(target).name + ".before"), ("after", "vendor/" + target)):
            entry = change[phase]
            closed(entry, ("member", "bytes", "sha256"))
            blob(entry)
            require(entry["member"] == member, "Replacement transport path mismatch")
            file = root / member
            regular(file)
            require(file.stat().st_size == entry["bytes"] and sha(file) == entry["sha256"], "Patch blob mismatch")
        require({k: change["before"][k] for k in ("bytes", "sha256")} ==
                {k: before[target][k] for k in ("bytes", "sha256")}, "Before-image is not pristine")
        require(change["after"]["sha256"] != change["before"]["sha256"], "Already-unmodified replacement")
    after_files = scan(root / "vendor")
    expected = expected_after(value, before)
    require(after_files == expected or after_files == {p: expected[p] for p in TARGETS},
            "Unknown/missing/extra modified transport file")
    return value, before

def expected_after(value, before):
    result = {name: dict(entry) for name, entry in before.items()}
    for change in value["changes"]:
        result[change["path"]] = {"path": change["path"], **{k: change["after"][k] for k in ("bytes", "sha256")}}
    return result

def materialize(pristine, patch_root, output, expected_recipe_sha256):
    pristine, patch_root, output = map(Path, (pristine, patch_root, output))
    ancestors(output.parent)
    require(not output.exists() and not output.is_symlink(), "Refuse reused materialization output")
    for source in (pristine, patch_root):
        require(not output.resolve().is_relative_to(source.resolve()) and
                not source.resolve().is_relative_to(output.resolve()), "Overlapping materialization roots")
    value, before = recipe(patch_root, expected_recipe_sha256)
    require(scan(pristine) == before, "Complete pristine tree mismatch/already applied")
    expected = expected_after(value, before)
    # No external side effect occurs until every blob and the complete input tree pass.
    output.mkdir(parents=False)
    vendor = output / "vendor"
    for name in before:
        source = patch_root / ("vendor/" + name) if name in TARGETS else pristine / name
        destination = vendor / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("xb") as stream:
            stream.write(source.read_bytes())
    require(scan(vendor) == expected, "Complete modified tree mismatch")
    require(scan(pristine) == before, "Pristine input changed while copying")
    require(recipe(patch_root, expected_recipe_sha256)[0] == value, "Patch input changed while copying")
    receipt = {"schema_version": 1, "source_variant": VARIANT, "upstream_commit": COMMIT,
               "acquisition_sha256": ACQUISITION, "upstream_inventory_sha256": INVENTORY_SHA,
               "recipe_sha256": expected_recipe_sha256, "materializer_sha256": sha(Path(__file__)),
               "vendor_tree_sha256": digest_inventory(expected), "vendor_files": 279,
               "unchanged_files": 277, "modified_files": 2, "changes": value["changes"],
               "files": list(expected.values())}
    with (output / "materialization-receipt.json").open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
    return receipt

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pristine", required=True, type=Path)
    parser.add_argument("--patch-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--recipe-sha256", required=True)
    args = parser.parse_args()
    print(json.dumps(materialize(args.pristine, args.patch_root, args.output, args.recipe_sha256)))
