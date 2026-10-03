"""Meaningful corruption/undeclared-file checks against the generated source bundle."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
sys.dont_write_bytecode=True
parser=argparse.ArgumentParser();parser.add_argument("source",type=Path);args=parser.parse_args()
spec=importlib.util.spec_from_file_location("source_verify",args.source/"verify.py")
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
module.verify(args.source)
candidate=args.source/"vendor/src/FGFDMExec.cpp"
original=candidate.read_bytes()
try:
 candidate.write_bytes(original+b"\n")
 try:module.verify(args.source)
 except ValueError:pass
 else:raise RuntimeError("Modified vendor source was accepted")
finally:candidate.write_bytes(original)
extra=args.source/"vendor/forbidden.xml"
try:
 extra.write_text("<not-approved/>")
 try:module.verify(args.source)
 except ValueError:pass
 else:raise RuntimeError("Undeclared model XML was accepted")
finally:extra.unlink()
module.verify(args.source)
print("PASS source-corruption and undeclared-model rejection; original source restored")
