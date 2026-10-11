"""Read-only static call/order evidence; never compiles or executes vendor code."""
from pathlib import Path
import argparse,hashlib,json,re
HERE=Path(__file__).resolve().parent

def sha(b):return hashlib.sha256(b).hexdigest()
def stripped(s):
    # Preserve offsets; erase comments/string/character literals for call counts.
    return re.sub(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27',lambda m:' '*len(m[0]),s)
def function(s,name):
    t=stripped(s);m=re.search(re.escape(name)+r'\s*\([^)]*\)\s*\{',t);assert m,name
    start=m.end();depth=1;i=start
    while depth:
        if t[i]=='{':depth+=1
        if t[i]=='}':depth-=1
        i+=1
    return t[start:i-1]
def build_evidence(vendor):
    base=vendor/'src/models/propulsion'
    piston=(base/'FGPiston.cpp').read_bytes();prop=(base/'FGPropeller.cpp').read_bytes()
    propulsion_path=vendor/'src/models/FGPropulsion.cpp';propulsion=propulsion_path.read_bytes()
    f=function(piston.decode(),'FGPiston::CalculateCoupled')
    calls=['RunPreFunctions','doMAP','doAirFlow','doFuelFlow','doEGT','doCHT','doOilTemperature','doOilPressure','CalculateCoupled','RunPostFunctions']
    counts={name:len(re.findall(r'\b'+name+r'\s*\(',f)) for name in calls};assert all(v==1 for v in counts.values())
    assert f.index('doMAP(')<f.index('doAirFlow(')<f.index('doFuelFlow(')<f.index('if(Running)')<f.index('FMEP=0.0')<f.index('doEGT(')<f.index('propeller.CalculateCoupled(')<f.index('RunPostFunctions(')
    run=function(propulsion.decode(),'FGPropulsion::Run');assert run.count('engine->Calculate();')==1 and run.count('ConsumeFuel(engine.get());')==1 and run.index('engine->Calculate();')<run.index('ConsumeFuel(engine.get());')
    text=prop.decode();helper=text[text.index('// ADR015, original project modification.'):text.index('} // anonymous namespace')]
    forbidden=r'\b(?:FGPiston|FGPropulsion|ConsumeFuel|doMAP|doAirFlow|doFuelFlow|doEGT|doCHT|doOilTemperature|doOilPressure|RunPreFunctions|RunPostFunctions)\b|\bRunning\s*='
    assert not re.search(forbidden,stripped(helper))
    record={'source_only':True,'checks_passed':True,'evidence_kind':'static source call/order proof, not instrumented runtime counters','group':'M05','piston_calls_per_public_new_method_body':counts,'propulsion_calculate_then_consume_once_per_engine_loop':True,'scalar_helpers_have_no_engine_fuel_thermal_callback_or_running_assignment':True,'source_sha256':{'FGPiston.cpp':sha(piston),'FGPropeller.cpp':sha(prop),'FGPropulsion.cpp':sha(propulsion)}}
    return record

def main():
    p=argparse.ArgumentParser();p.add_argument('--vendor-root',required=True,type=Path);p.add_argument('--output',required=True,type=Path)
    a=p.parse_args();record=build_evidence(a.vendor_root)
    with a.output.open('x',encoding='utf-8',newline='\n') as f:f.write(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record,indent=2))
if __name__=='__main__':main()
