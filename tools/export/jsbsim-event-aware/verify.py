"""PROPOSED schema2 verification; schema1 stays on its unchanged legacy route."""
import argparse
from pathlib import Path
import sys
import tempfile
sys.dont_write_bytecode = True
from materialize import (ACQUISITION, COMMIT, PREFIX, VARIANT, blob, closed,
                         digest_inventory, inventory, materialize, read_json,
                         recipe, require, safe, scan, sha)

WRAPPERS = {"CMakeLists.txt", "BUILD.md", "verify.py", "pack.py", "upstream-file-inventory.json",
            "LICENSE.first-party.txt", "manifest.json", "materialize.py", "MODIFICATIONS.md",
            PREFIX + "recipe.json", PREFIX + "FGPropeller.cpp.before", PREFIX + "FGPropeller.h.before"}

def verify(root):
    root = Path(root)
    actual = scan(root)
    require(len(actual) == 291, "Schema2 requires exactly 291 regular files")
    value = read_json(root / "manifest.json")
    closed(value, ("schema_version", "source_variant", "vendor_modified", "upstream_commit",
                   "acquisition_sha256", "recipe_sha256", "files", "self_exclusion"))
    require(type(value["schema_version"]) is int and value["schema_version"] == 2 and
            value["vendor_modified"] is True and value["source_variant"] == VARIANT and
            value["upstream_commit"] == COMMIT and value["acquisition_sha256"] == ACQUISITION and
            value["self_exclusion"] == "manifest.json is covered by external archive SHA256",
            "Unsupported schema2 source identity")
    require(type(value["files"]) is list and len(value["files"]) == 290, "Wrong manifest count")
    declared = {}
    for entry in value["files"]:
        closed(entry, ("path", "bytes", "sha256"))
        name = safe(entry["path"])
        blob(entry)
        require(name not in declared, "Duplicate source manifest path")
        declared[name] = entry
    require(list(declared) == sorted(declared), "Nonordinal manifest")
    before = inventory(root)
    require(set(actual) == WRAPPERS | {"vendor/" + name for name in before}, "Wrong source roster")
    require(declared == {p: e for p, e in actual.items() if p != "manifest.json"}, "Manifest hash/closure mismatch")
    patch, _ = recipe(root, value["recipe_sha256"])
    # Independently reconstruct both complete source trees from the delivered bytes.
    # No upstream cache, repository checkout, download or shell patch invocation.
    with tempfile.TemporaryDirectory(prefix="jsbsim-source-provenance-") as temporary:
        work = Path(temporary)
        pristine = work / "pristine"
        replacements = {e["path"]: e for e in patch["changes"]}
        for name in before:
            source = root / replacements[name]["before"]["member"] if name in replacements else root / "vendor" / name
            target = pristine / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
        require(scan(pristine) == before, "Reconstructed pristine closure mismatch")
        receipt = materialize(pristine, root, work / "reproduced", value["recipe_sha256"])
        supplied = {p.removeprefix("vendor/"): {**e, "path": p.removeprefix("vendor/")}
                    for p, e in actual.items() if p.startswith("vendor/")}
        require(scan(work / "reproduced/vendor") == supplied, "Modified source cannot be reproduced")
    require(scan(root) == actual, "Source changed during verification")
    return {"schema_version": 2, "source_variant": VARIANT, "bundle_files": 291, "vendor_files": 279,
            "unchanged_vendor_files": 277, "modified_vendor_files": 2, "provenance_reconstructed": True,
            "recipe_sha256": value["recipe_sha256"], "vendor_tree_sha256": digest_inventory(supplied),
            "materializer_sha256": receipt["materializer_sha256"]}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    import json
    print(json.dumps(verify(parser.parse_args().root)))
