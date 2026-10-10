"""PROPOSED opt-in schema3 extractor. The legacy 286-member extractor is unchanged."""
import argparse
import hashlib
from pathlib import Path
import sys
import zipfile
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
from materialize import HASH, ancestors, require, safe
from verify import verify

def extract(archive_file, reviewed_sha256, destination):
    archive_file, destination = Path(archive_file), Path(destination)
    require(type(reviewed_sha256) is str and HASH.fullmatch(reviewed_sha256), "Reviewed archive pin required")
    require(archive_file.stat().st_size < 16 * 1024 * 1024 and
            hashlib.sha256(archive_file.read_bytes()).hexdigest() == reviewed_sha256, "Archive digest/size mismatch")
    ancestors(destination.parent)
    require(not destination.exists() and not destination.is_symlink(), "Refuse reused extraction")
    with zipfile.ZipFile(archive_file) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        require(len(names) == len(set(names)) == len({name.casefold() for name in names}) == 293
                and names == sorted(names), "Unexpected schema3 inventory/order/alias")
        require(sum(entry.file_size for entry in entries) < 16 * 1024 * 1024, "Expanded archive too large")
        for entry in entries:
            safe(entry.filename)
            require(entry.create_system == 3 and entry.external_attr == 0o100644 << 16 and entry.internal_attr == 0 and
                    entry.compress_type == zipfile.ZIP_STORED and entry.date_time == (1980, 1, 1, 0, 0, 0)
                    and entry.flag_bits & 1 == 0 and not entry.extra and not entry.comment,
                    "Unsupported archive metadata")
        require(not archive.comment, "Unexpected archive comment")
        destination.mkdir()
        for entry in entries:
            path = destination / entry.filename
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("xb") as output:
                output.write(archive.read(entry))
    # Trusted repository verifier; no code imported/executed from an unreviewed ZIP.
    return verify(destination)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    import json
    print(json.dumps(extract(args.archive, args.sha256, args.destination)))
