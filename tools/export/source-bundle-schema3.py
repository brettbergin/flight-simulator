"""PROPOSED separate opt-in builder. Never replaces source-bundle.py/schema1.

Inputs: complete verified filtered pristine closure; reviewed patch transport
(vendor/<target> after-images, patches/... before-images + recipe, inventory);
the schema3 wrapper directory; an independently supplied reviewed recipe pin.
Bootstrap's acquisition verification/filtering remains an upstream seam.
"""
import argparse
import json
from pathlib import Path
import shutil
import sys
sys.dont_write_bytecode = True
TOOL_ROOT = Path(__file__).resolve().parent
if (TOOL_ROOT / "jsbsim-coupled-midpoint").is_dir():
    TOOL_ROOT = TOOL_ROOT / "jsbsim-coupled-midpoint"
sys.path.insert(0, str(TOOL_ROOT))
# Public CLI invocations are isolated. Refuse cached helpers from another
# variant rather than silently reusing their constants under Python import caching.
for module_name in ("materialize", "verify", "pack"):
    existing = sys.modules.get(module_name)
    if existing is not None:
        origin = getattr(existing, "__file__", None)
        if origin is None or Path(origin).resolve() != (TOOL_ROOT / (module_name + ".py")).resolve():
            raise ValueError("Use a separate interpreter for each corresponding-source variant")
from materialize import ACQUISITION, COMMIT, PREFIX, TARGETS, VARIANT, ancestors, materialize, regular, require, scan, sha
from pack import pack
from verify import verify

def create(pristine, patch_root, wrappers, license_file, output, recipe_sha256):
    pristine, patch_root, wrappers, license_file, output = map(Path, (pristine, patch_root, wrappers, license_file, output))
    require(not output.exists(), "Refuse reused corresponding-source output")
    ancestors(wrappers)
    ancestors(license_file.parent)
    regular(license_file)
    wrapper_names = ("CMakeLists.txt", "BUILD.md", "verify.py", "pack.py", "materialize.py", "MODIFICATIONS.md")
    for name in wrapper_names:
        regular(wrappers / name)
    wrapper_hashes = {name: sha(wrappers / name) for name in wrapper_names}
    for name in ("verify.py", "pack.py", "materialize.py"):
        require(wrapper_hashes[name] == sha(TOOL_ROOT / name), "Bundled/source-tool mismatch")
    receipt = materialize(pristine, patch_root, output, recipe_sha256)
    source = output / "source"
    source.mkdir()
    (output / "vendor").rename(source / "vendor")
    for name in wrapper_names:
        # Wrapper candidates are frozen LF UTF8 inputs; byte-copy, never rewrite a reviewed tool.
        shutil.copyfile(wrappers / name, source / name)
    require(sha(source / "materialize.py") == receipt["materializer_sha256"], "Bundled/executed materializer mismatch")
    shutil.copyfile(patch_root / "upstream-file-inventory.json", source / "upstream-file-inventory.json")
    shutil.copyfile(license_file, source / "LICENSE.first-party.txt")
    for name in ("recipe.json", *(Path(target).name + ".before" for target in TARGETS)):
        destination = source / PREFIX / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(patch_root / PREFIX / name, destination)
    files = scan(source)
    manifest = {"schema_version": 3, "source_variant": VARIANT, "vendor_modified": True,
                "upstream_commit": COMMIT, "acquisition_sha256": ACQUISITION,
                "recipe_sha256": recipe_sha256, "files": list(files.values()),
                "self_exclusion": "manifest.json is covered by external archive SHA256"}
    (source / "manifest.json").write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")
    archive = output / (VARIANT + "-library-source.zip")
    digest = pack(source, archive)
    require(pack(source, output / "source-repeat.zip") == digest, "Nonreproducible schema3 archive")
    require({name: sha(wrappers / name) for name in wrapper_names} == wrapper_hashes, "Wrapper input drift")
    result = {"schema_version": 3, "source_variant": VARIANT, "source_archive_sha256": digest,
              "source_archive_bytes": archive.stat().st_size, "source_verification": verify(source),
              "recipe_sha256": recipe_sha256, "materialization_receipt_sha256": sha(output / "materialization-receipt.json"),
              "repeat_matches": True}
    (output / "source-bundle-evidence.json").write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("pristine", "patch-root", "wrappers", "license-file", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--recipe-sha256", required=True)
    args = parser.parse_args()
    print(json.dumps(create(args.pristine, args.patch_root, args.wrappers, args.license_file, args.output, args.recipe_sha256)))
