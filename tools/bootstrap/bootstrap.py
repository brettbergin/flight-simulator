"""Fetch verified build dependencies into this checkout; never install globally."""
import argparse, hashlib, json, os, platform, shutil, stat, sys, tarfile, tempfile, urllib.request, zipfile
from pathlib import Path, PurePosixPath
ROOT = Path(__file__).resolve().parents[2]
MAX_BYTES = 4 * 1024**3

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024**2), b""): h.update(block)
    return h.hexdigest()

def safe_name(name):
    p = PurePosixPath(name)
    if "\\" in name or ":" in name or p.is_absolute() or ".." in p.parts:
        raise ValueError(f"Unsafe archive member: {name}")
    return p

def tree_digest(root):
    h = hashlib.sha256()
    for p in sorted(root.rglob("*")):
        if p.is_file() and p.name != ".verified.json":
            h.update(p.relative_to(root).as_posix().encode())
            h.update(bytes.fromhex(digest(p)))
    return h.hexdigest()

def extract(archive, destination):
    destination.mkdir(parents=True, exist_ok=True)
    total = 0
    is_zip = zipfile.is_zipfile(archive)
    with zipfile.ZipFile(archive) if is_zip else tarfile.open(archive) as source:
        members = source.infolist() if is_zip else source
        for m in members:
            name = safe_name(m.filename if is_zip else m.name)
            if is_zip and stat.S_ISLNK(m.external_attr >> 16) or not is_zip and not (m.isfile() or m.isdir()):
                raise ValueError("Archive links/special members forbidden")
            total += m.file_size if is_zip else m.size
            if total > MAX_BYTES: raise ValueError("Expanded archive exceeds limit")
            target = destination.joinpath(*name.parts)
            directory = m.is_dir() if is_zip else m.isdir()
            if directory: target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with source.open(m) if is_zip else source.extractfile(m) as incoming, target.open("wb") as outgoing:
                    shutil.copyfileobj(incoming, outgoing)
                mode = (m.external_attr >> 16) if is_zip else m.mode
                if os.name != "nt" and mode & 0o111: target.chmod(mode & 0o777)

def acquire(item, destination, cache, offline):
    fingerprint = item["sha256"]
    archive = cache / (fingerprint + ".archive")
    if archive.exists() and digest(archive) != fingerprint: raise ValueError(f"Cached archive checksum mismatch: {item['id']}")
    if not archive.exists():
        if offline: raise FileNotFoundError(f"Offline cache missing: {item['id']}")
        cache.mkdir(parents=True, exist_ok=True)
        temporary = archive.with_suffix(".download")
        request = urllib.request.Request(item["url"], headers={"User-Agent":"FlightSimulator-P1-bootstrap/1"})
        with urllib.request.urlopen(request,timeout=120) as incoming, temporary.open("wb") as outgoing:
            shutil.copyfileobj(incoming,outgoing)
        if digest(temporary) != fingerprint: raise ValueError(f"Downloaded checksum mismatch: {item['id']}")
        temporary.replace(archive)
    marker = destination / ".verified.json"
    if marker.exists():
        prior = json.loads(marker.read_text(encoding="utf-8"))
        if prior.get("sha256") == fingerprint and prior.get("tree_sha256") == tree_digest(destination):
            print(f"Verified cached {item['id']} {item['version']}",flush=True)
            return destination
        raise ValueError(f"Extracted dependency changed: {destination}")
    if destination.exists(): raise ValueError(f"Unverified destination exists: {destination}")
    destination.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="extract-",dir=destination.parent) as staging:
        staged = Path(staging)
        extract(archive,staged)
        extracted = staged / item["archive_root"] if item["archive_root"] else staged
        if not extracted.is_dir(): raise ValueError("Expected archive root missing")
        shutil.copytree(extracted,destination)
    receipt = {key:item[key] for key in ("id","version","url","sha256")}
    receipt["tree_sha256"] = tree_digest(destination)
    marker.write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf-8")
    print(f"Downloaded and verified {item['id']} {item['version']}",flush=True)
    return destination

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline",action="store_true")
    parser.add_argument("--with-godot",action="store_true")
    parser.add_argument("--with-export-templates",action="store_true")
    args = parser.parse_args()
    if sys.version_info < (3,12): raise RuntimeError("Python 3.12+ required")
    system = "windows" if sys.platform == "win32" else "linux" if sys.platform.startswith("linux") else ""
    if not system or platform.machine().lower() not in ("amd64","x86_64"): raise RuntimeError("Only Windows/Linux x64 supported")
    lock_path = ROOT / "third_party/dependencies.lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8-sig"))
    local = ROOT / ".local"
    cache = local / "download-cache"
    tools = {}
    for item in lock["sources"]: acquire(item,local/"deps"/item["id"],cache,args.offline)
    for item in lock["tools"]:
        if item["platform"] not in (system,"all"): continue
        if item.get("optional") == "godot" and not args.with_godot: continue
        if item.get("optional") == "templates" and not args.with_export_templates: continue
        destination = acquire(item,local/"toolchain"/item["id"],cache,args.offline)
        if "executable" in item:
            executable = destination/item["executable"]
            if not executable.is_file(): raise FileNotFoundError(executable)
            if os.name != "nt": executable.chmod(0o755)
            tools[item["id"]] = str(executable)
    manifest = {"schema_version":1,"platform":system,"python":sys.version,"python_executable":sys.executable,"lock_sha256":digest(lock_path),"tools":tools}
    output = local/"toolchain/environment.json"
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print(f"Environment manifest: {output}",flush=True)
if __name__ == "__main__": main()
