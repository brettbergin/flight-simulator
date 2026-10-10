"""PROPOSED schema3 ZIP_STORED packer; unchanged schema1 packer remains separate."""
import argparse
import hashlib
from pathlib import Path
import sys
import zipfile
sys.dont_write_bytecode = True
from materialize import require, scan
from verify import verify

def pack(root, output):
    root, output = Path(root), Path(output)
    verify(root)
    snapshot = scan(root)
    require(sum(entry["bytes"] for entry in snapshot.values()) < 16 * 1024 * 1024, "Source exceeds archive bound")
    require(not output.exists(), "Refuse existing archive")
    require(not output.resolve().is_relative_to(root.resolve()), "Archive must be outside source")
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_STORED) as archive:
        for name in snapshot:
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_STORED
            archive.writestr(info, (root / name).read_bytes())
    require(scan(root) == snapshot, "Source changed during packing; archive is not accepted")
    return hashlib.sha256(output.read_bytes()).hexdigest()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(pack(args.root, args.output))
