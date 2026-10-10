"""Reproduce the C++ phase schedule from the independently frozen pretrial JSON."""
from pathlib import Path
import argparse, hashlib, json
ROOT=Path(__file__).resolve().parent
PIN="9b667d4b61e47e94af1eed20701119bd72d6de63e6eac28b8597ab44ae6d9feb"
p=ROOT/"native-limits.json"
assert hashlib.sha256(p.read_bytes()).hexdigest()==PIN,"Pretrial packet changed; review a new version before trials"
j=json.loads(p.read_text(encoding="utf-8"))
fields=("roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim")
systems=("engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed")
text="#pragma once\n#include <flight/interactive/session.hpp>\n#include <array>\nnamespace piston_fixture {\nstruct Phase {unsigned second;flight::interactive::c::PilotAxes axes;std::array<bool,4> switches;};\ninline constexpr const char* limits_sha=\""+PIN+"\";\ninline constexpr std::array<Phase,10> phases{{\n"
for x in j["schedule"]:
 text+="  {"+str(x["at_elapsed_s"])+",{"+",".join(format(x["axes"][f],".17g") for f in fields)+"},{"+",".join("true" if x["systems"][f] else "false" for f in systems)+"}},\n"
text+="}};\ninline constexpr std::array<const char*,4> switch_ids{\"engine.ignition_left\",\"engine.ignition_right\",\"engine.starter\",\"fuel.feed\"};\n}\n"
parser=argparse.ArgumentParser();parser.add_argument("--check",action="store_true");args=parser.parse_args();out=ROOT/"native-limits.hpp"
if args.check:assert out.read_text(encoding="utf-8")==text,"Generated native phase header drift"
else:out.write_text(text,encoding="utf-8",newline="\n")
print("PASS frozen pretrial schedule/header" if args.check else "Generated frozen pretrial header")
