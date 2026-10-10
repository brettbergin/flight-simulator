"""Frozen pre-observation native lifecycle oracle; no JSBSim Python binding/model load.
Only an explicitly authorized invocation without --source-only launches native tests.
"""
from pathlib import Path
import argparse, hashlib, json, math, os, subprocess, sys, uuid
ROOT=Path(__file__).resolve().parent
LIMITS_SHA="9b667d4b61e47e94af1eed20701119bd72d6de63e6eac28b8597ab44ae6d9feb"
L=json.loads((ROOT/"native-limits.json").read_text(encoding="utf-8"))
assert hashlib.sha256((ROOT/"native-limits.json").read_bytes()).hexdigest()==LIMITS_SHA
UNITS={"fuel.total":"kg","engine.throttle":"fraction","engine.mixture":"fraction","propeller.angular_speed":"radps","engine.running":"bool","engine.ignition_left":"bool","engine.ignition_right":"bool","engine.starter":"bool","fuel.feed":"bool","engine.starved":"bool"}
LBKG=.45359237;SLUGLB=32.174049;SLUGKG=14.5939029372064
class Checks:
 def __init__(self):self.count=0;self.failures=[];self.failed_count=0
 def check(self,value,reason):
  self.count+=1
  if not value:
   self.failed_count+=1
   if len(self.failures)<100:self.failures.append(reason)
C=Checks()
def norm(v):return math.sqrt(sum(x*x for x in v))
def vector(v):return tuple(v[k] for k in ("x","y","z"))
def delta(a,b):return tuple(x-y for x,y in zip(a,b))
def system(row,id):return next(x["value"] for x in row["snapshot"]["systems"] if x["id"]==id)
def close(a,b):return abs(a-b)<=1e-10+1e-10*abs(b)
def velocity_ecef(row):
 s=row["snapshot"];q=s["orientation_body_to_ned"];w,x,y,z=(q[k] for k in ("w","x","y","z"));v=vector(s["velocity_body_mps"])
 # Direct quaternion rotation, then query-local NED to ECEF; binary64 throughout.
 n=((1-2*(y*y+z*z))*v[0]+2*(x*y-w*z)*v[1]+2*(x*z+w*y)*v[2],2*(x*y+w*z)*v[0]+(1-2*(x*x+z*z))*v[1]+2*(y*z-w*x)*v[2],2*(x*z-w*y)*v[0]+2*(y*z+w*x)*v[1]+(1-2*(x*x+y*y))*v[2])
 lat=s["position"]["latitude_rad"];lon=s["position"]["longitude_rad"];sp,cp,sl,cl=math.sin(lat),math.cos(lat),math.sin(lon),math.cos(lon)
 return (-sp*cl*n[0]-sl*n[1]-cp*cl*n[2],-sp*sl*n[0]+cl*n[1]-cp*sl*n[2],cp*n[0]-sp*n[2])
def speed(row):return norm(vector(row["snapshot"]["velocity_body_mps"]))
def required_shape(rows,hz,name):
 for i,row in enumerate(rows):
  s=row["snapshot"];d=row["stage"];systems=s["systems"]
  C.check(int(s["tick"])==i and s["clock"]["tick_rate_hz"]==hz and s["elapsed_s"]==i/hz,f"{name}: contiguous exact tick/time {i}")
  C.check(len(systems)==10 and {x["id"] for x in systems}==set(UNITS),f"{name}: ten unique systems {i}")
  for x in systems:
   if x["id"] not in UNITS:continue
   boolean=UNITS[x["id"]]=="bool"
   C.check(x["quantity"]==UNITS[x["id"]] and x["validity"]=="valid" and (type(x["value"]) is bool if boolean else type(x["value"]) in (int,float) and math.isfinite(x["value"])),f"{name}: exact system type/unit {i}/{x['id']}")
  C.check(all(type(x) in (int,float) and math.isfinite(x) for x in d.values()),f"{name}: finite stage {i}")
  C.check(close(system(row,"fuel.total"),d["tank_contents_lb"]*LBKG),f"{name}: actual public tank conversion {i}")
  C.check(close(system(row,"propeller.angular_speed"),d["post_prop_rpm"]*2*math.pi/60),f"{name}: post-prop shaft conversion {i}")
  C.check(0<=system(row,"propeller.angular_speed")<=120*math.pi,f"{name}: bounded shaft {i}")
  C.check(0<=system(row,"fuel.total")<=100+1e-10,f"{name}: finite nonnegative fuel {i}")
  if i:
   prev=rows[i-1]["stage"];actual=(prev["tank_contents_lb"]-d["tank_contents_lb"])*LBKG;requested=(d["fuel_used_lb"]-prev["fuel_used_lb"])*LBKG
   C.check(actual>=-1e-10 and 0<=requested<=.001 and close(actual,requested),f"{name}: actual supplied decrement vs actual requested {i}")
  if i>=2:
   prior=rows[i-1]["stage"];prior2=rows[i-2]["stage"];mass_drop=(d["mass_slug"]-prior["mass_slug"])*SLUGKG;pre_fuel_drop=(prior["tank_contents_lb"]-prior2["tank_contents_lb"])*SLUGKG/SLUGLB
   C.check(abs(mass_drop-pre_fuel_drop)<=1e-10+1e-10*abs(pre_fuel_drop),f"{name}: pre-drain mass phase {i}")
def validate(rows,hz,name):
 required_shape(rows,hz,name)
 negative=name in ("no-spark","no-feed","mixture-zero")
 expected=(13 if negative else 29 if name=="feed-recovery" else 111)*hz+1
 C.check(len(rows)==expected,f"{name}: full fixed trace length expected{expected} observed{len(rows)}")
 if len(rows)<expected:return None
 cold=rows[0];C.check(close(system(cold,"fuel.total"),100) and system(cold,"propeller.angular_speed")==0 and not system(cold,"engine.running") and not system(cold,"engine.starter") and system(cold,"engine.mixture")==0,f"{name}: unstarted tick0")
 C.check(all(system(r,"fuel.total")==system(cold,"fuel.total") for r in rows[:hz+1]),f"{name}: mixture-zero settle no draw")
 C.check(max(system(r,"propeller.angular_speed") for r in rows[hz:2*hz+1])>=math.pi,f"{name}: naturally cranked>=30RPM by t2")
 if negative:
  C.check(all(not system(r,"engine.running") for r in rows),f"{name}: no unsupported combustion")
  if name=="mixture-zero":C.check(all(r["stage"]["fuel_flow_lb_per_s"]==0 for r in rows),"mixture-zero: actual flow zero")
  if name=="no-feed":C.check(system(rows[hz+1],"engine.starved") and rows[hz+2]["stage"]["fuel_flow_lb_per_s"]==0,"no-feed: selection/starvation/flow stage")
  return None
 running=next((i/hz for i,r in enumerate(rows) if system(r,"engine.running")),None)
 C.check(running is not None and running<=8,f"{name}: Running deadline t8, observed{running}")
 C.check(all(system(r,"engine.running") and 16*math.pi<=system(r,"propeller.angular_speed")<=100*math.pi for r in rows[8*hz:13*hz+1]),f"{name}: warm stable before run-up")
 C.check(all(not system(r,"engine.starter") for r in rows[8*hz+1:]),f"{name}: unconditional starter release")
 if name=="feed-recovery":
  C.check(not system(rows[13*hz+1],"fuel.feed") and system(rows[13*hz+1],"engine.starved") and not system(rows[13*hz+2],"engine.running"),"feed recovery: loss phase")
  C.check(system(rows[17*hz+1],"fuel.feed") and not system(rows[17*hz+1],"engine.starved"),"feed recovery: actual restored selection/starvation")
  return None
 C.check(all(system(r,"engine.running") for r in rows[8*hz:51*hz+1]),f"{name}: continuous running through taxi/braking")
 C.check(all(16*math.pi<=system(r,"propeller.angular_speed")<=100*math.pi for r in rows[8*hz:29*hz+1]),f"{name}: bounded warm/run-up shaft")
 for r in rows[8*hz:51*hz+1]:C.check(all(x["on_ground"] for x in r["snapshot"]["contacts"]),f"{name}: all WOW after settle")
 # Forward displacement in the fixed prepared anchor's north/ECEF heading (yaw0).
 start=vector(rows[29*hz]["snapshot"]["ecef_position_m"]);end=vector(rows[39*hz]["snapshot"]["ecef_position_m"]);north=(-math.sin(.8)*math.cos(-2),-math.sin(.8)*math.sin(-2),math.cos(.8))
 C.check(sum(a*b for a,b in zip(delta(end,start),north))>=1,f"{name}: taxi forward progress>=1m")
 C.check(rows[39*hz]["snapshot"]["velocity_body_mps"]["x"]>=.5 and max(speed(r) for r in rows[29*hz:39*hz+1])<=8,f"{name}: taxi speed envelope")
 stopped=next((i/hz for i in range(39*hz+1,len(rows)) if speed(rows[i])<=.1),None)
 C.check(stopped is not None and stopped<=51,f"{name}: braking stop deadline, observed{stopped}")
 before=rows[51*hz];C.check(system(before,"engine.running") and system(before,"propeller.angular_speed")>0 and before["stage"]["fuel_flow_lb_per_s"]>0 and rows[51*hz-1]["stage"]["fuel_flow_lb_per_s"]>0 and not system(before,"engine.starter"),f"{name}: causal shutdown from live combustion")
 K=51*hz+1;off=K+1 if name=="feed-off" else K
 C.check(not system(rows[off],"engine.running"),f"{name}: phase-specific shutdown deadline")
 C.check(system(rows[K],"propeller.angular_speed")>0,f"{name}: cutoff coasts without shaft reset")
 if name=="feed-off":C.check(system(rows[K],"engine.starved") and rows[K+1]["stage"]["fuel_flow_lb_per_s"]==0,"feed-off: staged starvation/flow cutoff")
 if name=="lifecycle":C.check(rows[K]["stage"]["fuel_flow_lb_per_s"]==0,"mixture cutoff: same-step current flow zero")
 C.check(system(rows[81*hz],"propeller.angular_speed")<=2*math.pi and system(rows[111*hz],"propeller.angular_speed")<=math.pi/30,f"{name}: frozen coast thresholds")
 # Sole all-variant pumping sign oracle, not rawHP+1 while combustion may persist.
 displacement=286.2776305583699*(1/12)**3/(1/(.3048**3)) # exact accepted decimal parsed to binary64, pinned in3tom3 branch
 margins=[];raw_margins=[];guarded_pressure_margins=[]
 for r in rows[K:]:
  d=r["stage"];map_pa=d["manifold_pressure_inhg"]*3386.38;ambient_pa=d["engine_input_pressure_psf"]*47.88;raw_pmep=(map_pa-ambient_pa)*.8
  # Conservative finite roundtrip guard, source-only reviewed before observations.
  pmep=(map_pa+8*(math.ulp(map_pa)+math.ulp(ambient_pa))-ambient_pa)*.8
  upper=pmep*displacement*d["pre_prop_engine_rpm"]/(4*22371);margins.append(upper);raw_margins.append(raw_pmep);guarded_pressure_margins.append(pmep)
  C.check(math.isfinite(pmep) and math.isfinite(upper) and pmep<=0 and upper<=0 and d["engine_input_density_slug_per_ft3"]*SLUGKG/.3048**3>=1,f"{name}: finite source-derived pumping/density envelope")
 return {"first_running_s":running,"first_stopped_s":stopped,"pumping_upper_max_hp":max(margins),"pumping_upper_min_hp":min(margins),"raw_pmep_source_max_pa":max(raw_margins),"guarded_pmep_upper_max_pa":max(guarded_pressure_margins),"pumping_guard":"source-derived conservative bound;8*(ulp(reconstructed_MAPPa)+ulp(engine_ambientPa))"}
def convergence(a,b,c):
 hzsets={60:a,120:b,240:c};events={hz:{"running":next((i/hz for i,r in enumerate(rows) if system(r,"engine.running")),None),"stopped":next((i/hz for i,r in enumerate(rows) if i>=39*hz+1 and speed(r)<=.1),None)} for hz,rows in hzsets.items()}
 for key in ("running","stopped"):
  vals=[events[hz][key] for hz in (60,120,240)];C.check(all(v is not None for v in vals),f"convergence: absent {key} event fails")
  if all(v is not None for v in vals):C.check(max(vals)-min(vals)<=.25,f"convergence: {key} time envelope")
 path=[0.];
 for i in range(1,len(c)):path.append(path[-1]+norm(delta(vector(c[i]["snapshot"]["ecef_position_m"]),vector(c[i-1]["snapshot"]["ecef_position_m"]))))
 excluded=[]
 for n in range(1111):
  t=n/10
  if any(events[hz]["running"] is not None and abs(t-events[hz]["running"])<=.25 or abs(t-(51+1/hz))<=.25 for hz in (60,120,240)):excluded.append(t);continue
  ra,rb,rc=a[n*6],b[n*12],c[n*24];sa,sb,sc=system(ra,"propeller.angular_speed"),system(rb,"propeller.angular_speed"),system(rc,"propeller.angular_speed");ea,eb=abs(sa-sc),abs(sb-sc)
  C.check(eb<=math.pi/30+.03*abs(sc) and ea<=math.pi/15+.06*abs(sc) and eb<=ea+math.pi/30,f"convergence shaft/refinement at{t}s errors60={ea},120={eb}")
  C.check(norm(delta(vector(rb["snapshot"]["ecef_position_m"]),vector(rc["snapshot"]["ecef_position_m"])))<=.2+.02*path[n*24],f"convergence ECEF path at{t}s")
  C.check(norm(delta(velocity_ecef(rb),velocity_ecef(rc)))<=.05+.03*norm(velocity_ecef(rc)),f"convergence world velocity at{t}s")
 return {"events":events,"excluded_samples_s":excluded,"reference240_path_m":path[-1]}
def mechanism(rows):
 observed=[r for r in rows if r["phase"]=="observed-drain"];seed=[r for r in rows if r["phase"]=="seeded-boundary-not-completed"];C.check(len(observed)==8 and len(seed)==1,"mechanism: exactly one seed/eight steps")
 if len(observed)!=8:return
 k=observed[0];C.check(close(k["tank_before_lb"]*LBKG,1e-7) and close(k["tank_after_lb"]*LBKG,0) and k["requested_lb"]*LBKG>=2e-7 and k["actual_lb"]>=0,"mechanism: genuine partial first draw")
 C.check(observed[1]["starved"] and not observed[2]["running"] and observed[2]["potential_flow_lb_per_s"]==0,"mechanism: K/K+1/K+2 phases")
 C.check(0<=(k["requested_lb"]-k["actual_lb"])*LBKG<=.001,"mechanism: final partial draw discrepancy")
 C.check(sum(r["potential_flow_lb_per_s"]/120*LBKG-r["actual_lb"]*LBKG for r in observed[:2])<=.002,"mechanism: two-tick potential vs actual budget")
 for i,r in enumerate(observed):C.check(r["tank_after_lb"]>=0 and 0<=r["requested_lb"]*LBKG<=.001 and not r["starter"],"mechanism: fuel/request/starter bounded")
 expected_mass_drop=-1e-7/LBKG/SLUGLB;C.check(abs((observed[1]["mass_pre_drain_slug"]-k["mass_pre_drain_slug"])-expected_mass_drop)*SLUGKG<=1e-10,"mechanism: first mass reflects seeded PRE-drain contents, next mass drained")
 C.check(seed[0]["previous_completed_mass_slug"]>k["mass_pre_drain_slug"],"mechanism: old100kg mass not used as seeded pre-drain oracle")
 return {"K_actual_starved":k["starved"],"K_plus1_starved":observed[1]["starved"],"K_plus2_running":observed[2]["running"],"partial_requested_kg":k["requested_lb"]*LBKG,"partial_actual_kg":k["actual_lb"]*LBKG}
PROCESSES=[]
ALL_CASES=["admission120","no-spark120","no-feed120","mixture-zero120","feed-recovery120","lifecycle120","ignition-off120","feed-off120","lifecycle120-repeat","lifecycle60","lifecycle240","mechanism120"]
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def run(exe,case,hz=120,mechanism_only=False,suffix=""):
 name=case+str(hz)+suffix;prefix=OUTPUT/name
 args=[str(exe),ARGS.model_root,str(prefix)]+([] if mechanism_only else [case,str(hz)])
 identity={"qualified_library_path":str(Path(ARGS.jsbsim_dll).resolve())}
 try:
  identity["executable_before_sha256"]=digest(exe)
  identity["library_before_sha256"]=digest(ARGS.jsbsim_dll)
  expected_exe=APPROVAL["mechanism_sha256" if mechanism_only else "native_sha256"]
  if identity["executable_before_sha256"]!=expected_exe or identity["library_before_sha256"]!=APPROVAL["jsbsim_dll_sha256"]:
   raise RuntimeError("Authorized executable/library changed before spawn")
  result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=120,env=os.environ|{"JSBSIM_DEBUG":"0"})
  stdout,stderr,code,status=result.stdout,result.stderr,result.returncode,"completed" if result.returncode==0 else "failed"
 except subprocess.TimeoutExpired as error:
  # subprocess.run kills and reaps the direct child before raising.
  stdout,stderr,code,status=error.stdout or b"",error.stderr or b"",None,"timeout-killed-and-reaped"
 except OSError as error:
  stdout,stderr,code,status=b"",repr(error).encode("utf-8"),None,"spawn-failed"
 except RuntimeError as error:
  stdout,stderr,code,status=b"",repr(error).encode("utf-8"),None,"identity-rejected-before-spawn"
 prefix.with_suffix(".stdout.log").write_bytes(stdout);prefix.with_suffix(".stderr.log").write_bytes(stderr)
 process={"case":name,"returncode":code,"status":status,"terminal_exit_observed":status not in ("spawn-failed","identity-rejected-before-spawn"),"stderr":prefix.with_suffix(".stderr.log").name,"library_identity":identity};PROCESSES.append(process)
 C.check(code==0,f"{case}/{hz}: native process status{status} returned{code}; inspect preserved stderr")
 try:
  identity["executable_after_sha256"]=digest(exe);identity["qualified_library_after_sha256"]=digest(ARGS.jsbsim_dll)
  C.check(identity.get("executable_before_sha256")==identity["executable_after_sha256"]==APPROVAL["mechanism_sha256" if mechanism_only else "native_sha256"],f"{name}: authorized executable unchanged across child")
  C.check(identity.get("library_before_sha256")==identity["qualified_library_after_sha256"]==APPROVAL["jsbsim_dll_sha256"],f"{name}: qualified library unchanged across child")
  actual=json.loads(Path(str(prefix)+".json").read_text(encoding="utf-8"))
  reported=actual.get("loaded_library_path")
  assert type(reported) is str and reported and Path(reported).is_absolute(),"actual loaded-module UTF-8 path absent/relative"
  module=Path(reported)
  identity["actual_loaded_library_path"]=reported;identity["same_file"]=module.samefile(ARGS.jsbsim_dll)
  assert identity["same_file"],"address-resolved loaded library differs from qualified file"
  # Before-spawn qualified-file hash covers the actual reported module because
  # samefile establishes filesystem identity, rather than filename similarity.
  identity["actual_module_before_sha256"]=identity["library_before_sha256"]
  identity["actual_module_after_sha256"]=digest(module)
  C.check(identity["actual_module_before_sha256"]==identity["actual_module_after_sha256"]==APPROVAL["jsbsim_dll_sha256"],f"{name}: actual loaded library pre/post bytes equal qualified identity")
  if code!=0:return None
  C.check(actual.get("passed") is True,f"{name}: actual native receipt passed")
  C.check(actual.get("limits_sha256")==LIMITS_SHA,f"{name}: immutable physical limits identity")
  C.check(actual.get("source_fingerprint")==APPROVAL["source_fingerprint"],f"{name}: actual rebuilt consumer/backend fingerprint")
  C.check(actual.get("angular_integration_method")==ARGS.angular_method,f"{name}: actual getter-verified method")
  C.check(actual.get("fp_rounding")==0 and type(actual.get("fp_mxcsr")) is int and actual["fp_mxcsr"]&0xe040==0,f"{name}: actual worker rounding/FTZ/DAZ admission")
  path=Path(str(prefix)+".ndjson")
  return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []
 except Exception as error:
  C.check(False,f"{name}: native receipt/trace/actual-module verification failed {error!r}");return None
parser=argparse.ArgumentParser();parser.add_argument("--angular-method",choices=("event_aware_constant_power_v1","event_aware_coupled_midpoint_v1"),default="event_aware_constant_power_v1");parser.add_argument("--source-only",action="store_true");parser.add_argument("--native");parser.add_argument("--mechanism");parser.add_argument("--model-root");parser.add_argument("--output");parser.add_argument("--ratification");parser.add_argument("--pretrial-ratification");parser.add_argument("--jsbsim-dll");ARGS=parser.parse_args()
subprocess.run([sys.executable,str(ROOT/"native-generate.py"),"--check"],check=True)
if ARGS.source_only:print("PASS frozen schedule/source-only; NO model load");raise SystemExit(0)
assert all((ARGS.native,ARGS.mechanism,ARGS.model_root,ARGS.output,ARGS.ratification,ARGS.pretrial_ratification,ARGS.jsbsim_dll)),"Explicit native paths and Root execution ratification required"
APPROVAL=json.loads(Path(ARGS.ratification).read_text(encoding="utf-8"))
assert set(APPROVAL)=={"authorized","scope","native_sha256","mechanism_sha256","jsbsim_dll_sha256","limits_sha256","source_fingerprint","backend_identity_sha256","model_inventory_sha256","suite_source_sha256","pretrial_ratification_sha256"}
assert APPROVAL["authorized"] is True and APPROVAL["scope"]==("original-piston-coupled-midpoint-v1" if ARGS.angular_method=="event_aware_coupled_midpoint_v1" else "original-piston-event-aware-coupled-v1")
for key in ("source_fingerprint","backend_identity_sha256","pretrial_ratification_sha256"):
 assert type(APPROVAL[key]) is str and len(APPROVAL[key])==64 and all(c in "0123456789abcdef" for c in APPROVAL[key])
assert digest(ARGS.native)==APPROVAL["native_sha256"] and digest(ARGS.mechanism)==APPROVAL["mechanism_sha256"] and digest(ARGS.jsbsim_dll)==APPROVAL["jsbsim_dll_sha256"]
assert digest(ARGS.pretrial_ratification)==APPROVAL["pretrial_ratification_sha256"]
assert APPROVAL["limits_sha256"]==LIMITS_SHA and APPROVAL["model_inventory_sha256"]=="f7766fda173d8ee83d4c4a8c02f6333124175a1f7064d3f4d8e78df3d17da12a"
assert digest(Path(ARGS.model_root)/"inventory.json")==APPROVAL["model_inventory_sha256"]
assert APPROVAL["suite_source_sha256"]=={name:digest(ROOT/name) for name in ("CMakeLists.txt","loaded-library.hpp","selected-method.hpp","native.cpp","native-mechanism.cpp","native-validate.py","native-limits.json","native-limits.hpp","native-generate.py")}
OUTPUT=Path(ARGS.output)/("run-"+uuid.uuid4().hex);OUTPUT.mkdir(parents=True,exist_ok=False);metrics={};traces={};skipped_comparisons=[]
# Process schedules/order are unchanged. Preserve every process even if another
# fails; only dependent comparisons are omitted and explicitly labeled.
for case in ("admission","no-spark","no-feed","mixture-zero","feed-recovery","lifecycle","ignition-off","feed-off"):
 rows=run(ARGS.native,case)
 if case!="admission" and rows is not None:
  try:metrics[case]=validate(rows,120,case)
  except Exception as error:C.check(False,f"{case}: validation exception {error!r}")
 if case=="lifecycle":traces[120]=rows
repeated=run(ARGS.native,"lifecycle",suffix="-repeat")
complete=traces.get(120) is not None and repeated is not None and len(traces[120])==111*120+1 and len(repeated)==111*120+1
C.check(complete,"determinism requires two complete nonempty lifecycle traces");C.check(complete and traces[120]==repeated,"same-build canonical snapshots/atmosphere/stages deterministic")
try:C.check((OUTPUT/"lifecycle120.commands.ndjson").read_bytes()==(OUTPUT/"lifecycle120-repeat.commands.ndjson").read_bytes(),"same-build admitted command trace deterministic")
except OSError as error:C.check(False,f"determinism: missing preserved commands {error!r}")
for hz in (60,240):
 traces[hz]=run(ARGS.native,"lifecycle",hz)
 if traces[hz] is not None:
  try:metrics[str(hz)]=validate(traces[hz],hz,"lifecycle")
  except Exception as error:C.check(False,f"{hz}: validation exception {error!r}")
if all(traces.get(hz) is not None and len(traces[hz])==111*hz+1 for hz in (60,120,240)):
 try:metrics["convergence"]=convergence(traces[60],traces[120],traces[240])
 except Exception as error:C.check(False,f"convergence: validation exception {error!r}")
else:skipped_comparisons.append("convergence: incomplete or failed rate trace")
rows=run(ARGS.mechanism,"mechanism",mechanism_only=True)
if rows is not None:
 try:metrics["mechanism"]=mechanism(rows)
 except Exception as error:C.check(False,f"mechanism: validation exception {error!r}")
else:skipped_comparisons.append("mechanism: failed process")
FINAL_BINARY_IDENTITIES={}
for label,path,want in (("native",ARGS.native,APPROVAL["native_sha256"]),("mechanism",ARGS.mechanism,APPROVAL["mechanism_sha256"]),("qualified_library",ARGS.jsbsim_dll,APPROVAL["jsbsim_dll_sha256"])):
 try:
  actual=digest(path);FINAL_BINARY_IDENTITIES[label]={"path":str(Path(path).resolve()),"sha256":actual};C.check(actual==want,f"final suite: {label} remains exact authorized binary")
 except OSError as error:C.check(False,f"final suite: {label} cannot be rehashed {error!r}")
SKIPPED=[name for name in ALL_CASES if name not in {x["case"] for x in PROCESSES}]
C.check(not SKIPPED and len(PROCESSES)==12,"all12 unchanged native processes observed")
receipt={"format":"OriginalPistonNativeSuite/v3","angular_integration_method":ARGS.angular_method,"passed":C.failed_count==0,"checks":C.count,"failed_checks":C.failed_count,"failures":C.failures,"metrics":metrics,"processes":PROCESSES,"final_binary_identities":FINAL_BINARY_IDENTITIES,"skipped_cases":SKIPPED,"skipped_comparisons":skipped_comparisons,"dependent_comparisons_skipped":bool(SKIPPED or skipped_comparisons),"limits_sha256":LIMITS_SHA,"ratification_sha256":digest(ARGS.ratification),"scope":"original engineering lifecycle and separate backend mechanism; no C172/electrical/pilot/phase claim","output_files":[{"path":p.name,"bytes":p.stat().st_size,"sha256":hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(OUTPUT.iterdir()) if p.is_file()]}
(OUTPUT/"suite-receipt.json").write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf-8",newline="\n");print(json.dumps({"passed":receipt["passed"],"checks":C.count,"failed_checks":C.failed_count,"receipt":str(OUTPUT/"suite-receipt.json"),"failures":C.failures[:8]},indent=2));raise SystemExit(0 if receipt["passed"] else 1)
