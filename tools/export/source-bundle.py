"""Build exact library-only corresponding source; no upstream model XML."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
sys.dont_write_bytecode = True
REPO=Path(__file__).resolve().parents[2]
INPUTS=Path(__file__).resolve().parent/"jsbsim"
COMMIT="3b25f25e49b42d0489c04ac805674fc1450ca579"
ACQUISITION="df57467a831cfa3ee3cadcb98d8291ce56bb11976e35dd9e93c94201ff1420d5"
def require(condition,message):
    if not condition: raise ValueError(message)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def create(source,output):
    require(not output.exists(),"Refuse reused corresponding-source output")
    inventory=json.loads((INPUTS/"upstream-file-inventory.json").read_text(encoding="utf-8-sig"))
    require(inventory["upstream_commit"]==COMMIT and inventory["acquisition_sha256"]==ACQUISITION,"Source inventory pin mismatch")
    require(len(inventory["files"])==inventory["upstream_file_count"]==279,"Unexpected source closure")
    receipt=json.loads((source/".verified.json").read_text())
    require(receipt["sha256"]==ACQUISITION,"Unverified JSBSim acquisition")
    spec=importlib.util.spec_from_file_location("bootstrap",REPO/"tools/bootstrap/bootstrap.py")
    bootstrap=importlib.util.module_from_spec(spec);spec.loader.exec_module(bootstrap)
    require(bootstrap.tree_digest(source)==receipt["tree_sha256"],"Acquisition tree mutation")
    stage=output/"source";stage.mkdir(parents=True)
    for entry in inventory["files"]:
        relative=Path(entry["path"])
        require(not relative.is_absolute() and ".." not in relative.parts and ":" not in entry["path"],"Unsafe source path")
        vendor=source/relative
        require(vendor.is_file() and not vendor.is_symlink() and vendor.stat().st_size==entry["bytes"] and sha(vendor)==entry["sha256"],"Vendor digest mismatch: "+entry["path"])
        destination=stage/"vendor"/relative;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(vendor,destination)
    for name in ["CMakeLists.txt","BUILD.md","verify.py","pack.py","upstream-file-inventory.json"]:
        # Canonical LF for first-party build/metadata files across Git checkout hosts.
        text=(INPUTS/name).read_text(encoding="utf-8-sig")
        (stage/name).write_text(text.replace("\r\n","\n"),encoding="utf-8",newline="\n")
    (stage/"LICENSE.first-party.txt").write_text((REPO/"LICENSE").read_text().replace("\r\n","\n"),encoding="utf-8",newline="\n")
    files=[{"path":p.relative_to(stage).as_posix(),"bytes":p.stat().st_size,"sha256":sha(p)} for p in sorted((p for p in stage.rglob("*") if p.is_file()),key=lambda p:p.relative_to(stage).as_posix())]
    manifest={"schema_version":1,"vendor_modified":False,"upstream_commit":COMMIT,"acquisition_sha256":ACQUISITION,"files":files,"self_exclusion":"manifest.json is covered by external archive SHA256"}
    (stage/"manifest.json").write_text(json.dumps(manifest,sort_keys=True,indent=2)+"\n",encoding="utf-8",newline="\n")
    sys.path.insert(0,str(stage))
    from pack import pack
    from verify import verify
    archive=output/"jsbsim-1.3.1-library-source.zip"
    repeat=output/"source-repeat.zip"
    digest=pack(stage,archive);require(pack(stage,repeat)==digest,"Nondeterministic archive")
    result={"schema_version":1,"upstream_commit":COMMIT,"acquisition_sha256":ACQUISITION,"source_archive_sha256":digest,"bundled_inventory_sha256":sha(stage/"upstream-file-inventory.json"),"source_archive_bytes":archive.stat().st_size,"repeat_matches":True,"source_verification":verify(stage)}
    (output/"source-bundle-evidence.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    return result
if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--source",type=Path,default=REPO/".local/deps/jsbsim");parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args();print(json.dumps(create(args.source.resolve(),args.output.resolve())))
