"""Verify immutable complete corresponding-source inventory; Python stdlib."""
import argparse
import hashlib
import json
from pathlib import Path
def require(condition,message):
    if not condition: raise ValueError(message)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def safe(name):
    path=Path(name)
    return not path.is_absolute() and ".." not in path.parts and ":" not in name and "\\" not in name and name and not name.startswith("/")
def verify(root):
    manifest=json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    require(manifest.get("schema_version")==1 and manifest.get("vendor_modified") is False,"Unsupported source manifest")
    files=manifest["files"];declared={e["path"] for e in files}
    require(len(files)==len(declared),"Duplicate manifest path")
    require(all(safe(name) for name in declared),"Unsafe manifest path")
    actual={p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()}
    require(actual==declared|{"manifest.json"},"Undeclared/missing source files")
    for path in root.rglob("*"):require(not path.is_symlink(),"Source symlink forbidden")
    for entry in files:
        path=root/entry["path"]
        require(path.stat().st_size==entry["bytes"] and sha(path)==entry["sha256"],"Source hash mismatch: "+entry["path"])
    upstream=json.loads((root/"upstream-file-inventory.json").read_text(encoding="utf-8"))
    require(upstream["upstream_commit"]=="3b25f25e49b42d0489c04ac805674fc1450ca579" and upstream["upstream_file_count"]==len(upstream["files"])==279,"Upstream pin/closure mismatch")
    for entry in upstream["files"]:
        require(safe(entry["path"]),"Unsafe vendor inventory path")
        path=root/"vendor"/entry["path"]
        require(path.stat().st_size==entry["bytes"] and sha(path)==entry["sha256"],"Vendor changed: "+entry["path"])
    actual_vendor={p.relative_to(root/"vendor").as_posix() for p in (root/"vendor").rglob("*") if p.is_file()}
    require(actual_vendor=={e["path"] for e in upstream["files"]},"Vendor closure mismatch")
    require(not any(Path(p).suffix.lower() in {".xml",".exe",".dll",".lib",".zip"} for p in actual_vendor),"Forbidden vendor binary/model payload")
    return {"bundle_files":len(actual),"vendor_files":279,"all_hashes_unchanged":True}
if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--root",type=Path,required=True)
    print(json.dumps(verify(parser.parse_args().root.resolve())))
