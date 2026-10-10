"""Extract bounded source archive with no traversal/links; verify full inventory."""
import argparse
import hashlib
from pathlib import Path,PurePosixPath
import sys
import zipfile
sys.dont_write_bytecode=True
parser=argparse.ArgumentParser();parser.add_argument("--source-variant",choices=("jsbsim-1.3.1-upstream","jsbsim-1.3.1-event-aware-coupled-midpoint-v1"),default="jsbsim-1.3.1-upstream");parser.add_argument("--archive",type=Path,required=True);parser.add_argument("--sha256",required=True);parser.add_argument("--destination",type=Path,required=True)
args=parser.parse_args()
def require(condition,message):
    if not condition: raise ValueError(message)
require(hashlib.sha256(args.archive.read_bytes()).hexdigest()==args.sha256,"Archive digest mismatch")
require(not args.destination.exists(),"Refuse reused extraction")
with zipfile.ZipFile(args.archive) as archive:
    names=archive.namelist()
    count=293 if args.source_variant=="jsbsim-1.3.1-event-aware-coupled-midpoint-v1" else 286
    require(len(names)==len(set(names))==count and names==sorted(names),"Unexpected source archive inventory/order")
    require(sum(info.file_size for info in archive.infolist())<16*1024*1024,"Source archive exceeds size bound")
    for info in archive.infolist():
        path=PurePosixPath(info.filename)
        require(not path.is_absolute() and ".." not in path.parts and ":" not in info.filename and "\\" not in info.filename,"Unsafe archive path")
        require(info.create_system==3 and info.external_attr>>16==0o100644 and info.compress_type==zipfile.ZIP_STORED,"Unsupported archive member metadata")
    args.destination.mkdir(parents=True)
    for info in archive.infolist():
        destination=args.destination/info.filename;destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(archive.read(info))
sys.path.insert(0,str(args.destination.resolve()))
from verify import verify
result=verify(args.destination.resolve())
import json
manifest=json.loads((args.destination/"manifest.json").read_text(encoding="utf-8"))
require(manifest["schema_version"]==(3 if args.source_variant=="jsbsim-1.3.1-event-aware-coupled-midpoint-v1" else 1),"Source manifest differs from selected variant")
if args.source_variant!="jsbsim-1.3.1-upstream":
    require(result["source_variant"]==args.source_variant,"Source variant differs")
print(json.dumps(result,sort_keys=True))
