"""Ordinal POSIX ZIP_STORED packing with fixed cross-host metadata."""
import argparse
import hashlib
from pathlib import Path
import sys
import zipfile
sys.dont_write_bytecode=True
from verify import verify,require
def pack(root,output):
    verify(root)
    require(not output.exists(),"Refuse existing archive")
    require(not output.resolve().is_relative_to(root.resolve()),"Archive must be outside source")
    with zipfile.ZipFile(output,"x",compression=zipfile.ZIP_STORED) as archive:
        for path in sorted((p for p in root.rglob("*") if p.is_file()),key=lambda p:p.relative_to(root).as_posix()):
            info=zipfile.ZipInfo(path.relative_to(root).as_posix(),date_time=(1980,1,1,0,0,0))
            info.create_system=3;info.external_attr=0o100644<<16;info.compress_type=zipfile.ZIP_STORED
            archive.writestr(info,path.read_bytes())
    return hashlib.sha256(output.read_bytes()).hexdigest()
if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--root",type=Path,required=True);parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args();print(pack(args.root.resolve(),args.output.resolve()))
