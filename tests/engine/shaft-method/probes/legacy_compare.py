"""Immutable original13-row comparator. No process launcher or alternate budgets."""
from pathlib import Path
from decimal import Decimal as D
import hashlib,json,math
HERE=Path(__file__).resolve().parent
REPO=HERE.parents[3]
REFERENCE_SHA='36aac20d85e841743d7eb9a357be8a0d40d8f103c1cbc60e084dde9ef23db63b'

MODEL_PINS = {
 'aircraft/original-piston-prop/original-piston-prop.xml': (6784, 'b9a41861fcbca1917978312d73a192cbe2c2ea0e6ef0e13512c76148a6c9d4c5'),
 'engine/original-fixed-prop.xml': (826, 'b4f3f376f062d869a338bb2757466c9ba23d6320d895d3fc5921e351748bb0af'),
 'engine/original-piston.xml': (1870, '4212b398118be77cdff44f6e41abfded7e4fd8fcfece422dba27fd64ad30b638'),
 'inventory.json': (3307, 'f7766fda173d8ee83d4c4a8c02f6333124175a1f7064d3f4d8e78df3d17da12a'),
 'NOTICE-MIT.txt': (1069, 'ca8c1205d820d40917b54d548b97dde200bc24bc6c3166358e8bc6cc27eb0e9e'),
 'parameter-ledger.json': (23421, 'eb471b5590351bee000c346acfa091a2c84ae526540794afe0e23833ca02106c'),
 'README.md': (3197, '7c7e04079448568a25fad6a49dbca63edc97d91d4e5c47cd2ffd7e36ddb096df'),
}

def digest(path):
 return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def load_reference():
 path=REPO/'tests/engine/reference/expected-v3.json'
 assert digest(path)==REFERENCE_SHA, 'Immutable original v3 reference changed'
 packet=json.loads(path.read_bytes())
 assert packet['case_count']==55 and len(packet['cases'])==55
 cases=[c for c in packet['cases'] if c['kind']=='prop-discrete']
 assert len(cases)==13 and len({c['id'] for c in cases})==13
 return packet,cases

def requests(cases):
 keys=('rps','axial_velocity_fps','engine_power_ftlbf_per_s','density_slug_per_ft3','hz','pitch_rate_radps','yaw_rate_radps')
 return ''.join(' '.join([c['id']]+[str(c['input'][key]) for key in keys])+'\n' for c in cases).encode('ascii')

def budget_for(key):
 if key in ('advance_ratio','ct','cp'): return 'coefficient'
 if key=='thrust_n': return 'force_n'
 if key=='load_power_w': return 'power_w'
 if key in ('pre_omega_radps','post_omega_radps'): return 'angular_radps'
 return 'scalar'

def compare(packet,cases,rows):
 failures=[];checks=0
 def check(ok,message):
  nonlocal checks
  checks+=1
  if not ok:failures.append(message)
 check(len(rows)==14,'one guard and all thirteen output rows')
 if not rows:return checks,failures
 guard=rows[0]
 for key in ('passed','fresh_legacy','unknown_rejected_unchanged','reset_retains_event','legacy_return','case_object_fresh_unset'):
  check(guard.get(key) is True,'guard '+key)
 check(guard.get('kind')=='guard','guard kind')
 check(guard.get('fp_rounding')==0 and type(guard.get('fp_mxcsr')) is int and guard['fp_mxcsr']&0xe040==0,'actual supported FP controls')
 check([row.get('id') for row in rows[1:]]==[c['id'] for c in cases],'exact unique original case ordering')
 for c,row in zip(cases,rows[1:]):
  check(row.get('kind')=='prop-discrete' and row.get('actual_default_legacy') is True,c['id']+' actual default legacy')
  actual=row.get('observations',{})
  check(type(actual) is dict and set(actual)==set(c['expected']),c['id']+' complete unchanged fields')
  for key,expected in c['expected'].items():
   got=actual.get(key)
   if type(expected) is bool:check(type(got) is bool and got==expected,c['id']+'/'+key+' exact boolean');continue
   valid=type(got) in (int,float) and math.isfinite(got)
   if valid:
    budget=packet['budgets_before_observation'][budget_for(key)]
    # Decimal.from_float retains the observed binary64 value, not a rounded print.
    value=D.from_float(got) if type(got) is float else D(got)
    target=D(expected);valid=abs(value-target)<=D(budget['abs'])+D(budget['rel'])*abs(target)
   check(valid,c['id']+'/'+key+' original '+budget_for(key)+' budget')
 return checks,failures
