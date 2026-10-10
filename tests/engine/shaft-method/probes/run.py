"""Fixed coupled-unit runner. Compilation, unit checks and flight gates are separate.

Authorization is an explicit action after a staged strict build, never an implied
side effect of compiling. No property injection or altered numerical expectations.
"""
from pathlib import Path
from types import SimpleNamespace
import argparse,datetime,hashlib,json,os,re,subprocess,sys,unittest,uuid
import validate as v

LABELS=('kernel','library','chronology','terminal')

def save(path,obj):
    with path.open('x',encoding='utf-8',newline='\n') as f:json.dump(obj,f,indent=2);f.write('\n')

def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()

def observed_hash(path):
    # Loss of a qualified file is recorded as failed identity; preserve logs.
    try:return v.sha(path)
    except OSError:return None

def config(path):
    a=v.load(path)
    v.demand(a['schema']=='coupled-probe-config-v1','wrong configured route')
    v.SOURCE_MANIFEST=Path(a['source_manifest'])
    v.source_files();v.reference_manifest()
    return a

def verify_model(a):
    repo=Path(a['repository_root']);model=Path(a['model_root'])
    legacy=v.legacy_comparator()
    for name,(size,want) in legacy.MODEL_PINS.items():
        p=model/name;v.demand(p.stat().st_size==size and v.sha(p)==want,'model changed: '+name)
    for name,want in v.reference_manifest()['model_pins'].items():
        v.demand(v.sha(v.contained(repo,name))==want,'reference model pin changed: '+name)

def strict(command,msvc):
    def flag(s):return re.search(r'(^|[\s\"])'+re.escape(s)+r'($|[\s\"])',command) is not None
    if msvc:
        v.demand(flag('/fp:strict') and not any(flag('/fp:'+x) for x in ('fast','precise')),'missing/conflicting actual strict FP')
    else:
        v.demand(all(flag(x) for x in ('-fno-fast-math','-ffp-contract=off','-frounding-math')),'missing actual strict FP')
        v.demand(not any(flag(x) for x in ('-ffast-math','-Ofast','-ffp-contract=fast','-ffp-contract=on','-fno-rounding-math')),'conflicting actual FP')

def verify_pretrial(path,repo,consumer_paths):
    pretrial=v.load(path)
    v.demand(set(pretrial)=={'schema','scope','source_inputs','reference_manifest_sha256','packet_sha256','required_ctests'},'wrong public staged pretrial fields')
    v.demand(pretrial['schema']=='coupled-ci-pretrial-v1' and pretrial['scope']=='fixed source/reference/budgets before fresh compilation; no native execution','wrong public staged pretrial schema/scope')
    required=pretrial['required_ctests']
    v.demand(isinstance(required,list) and all(isinstance(x,str) for x in required) and len(required)==len(set(required)) and {'coupled_shaft_math','coupled_shaft_native','piston_engine_lifecycle'}<=set(required),'missing required staged numerical CTests')
    v.demand(pretrial['reference_manifest_sha256']==v.sha(v.REFERENCE/'reference-manifest.json') and pretrial['packet_sha256']==v.reference_manifest()['packet']['sha256'],'pretrial reference identity changed')
    prefix='tests/engine/shaft-method/'
    critical={prefix+'probes/'+n for n in v.PROBE_FILES|{'probe-manifest.json'}}|v.SHARED_FILES
    critical|={prefix+'coupled-midpoint-v1/'+n for n in v.REFERENCE_FILES|{'reference-manifest.json','references.json'}}
    critical|=set(consumer_paths)
    v.demand(isinstance(pretrial['source_inputs'],dict) and critical<=set(pretrial['source_inputs']),'pretrial omitted critical source closure')
    for name,meta in pretrial['source_inputs'].items():v.file_identity(v.contained(repo,name),meta)

def qualify(a):
    v.source_files()
    build=Path(a['build_root']);source=v.load(a['source_manifest']);verify_model(a)
    consumer=(build/'interactive-source-fingerprint.txt').read_text(encoding='utf-8')
    first,body=consumer.split('\n',1)
    v.demand(first==source['consumer_fingerprint']==hashlib.sha256(body.encode()).hexdigest(),'consumer declaration hash mismatch')
    rows=body.splitlines()
    v.demand(rows[:2]==['verified-jsbsim-backend:'+source['backend_identity_sha256'],'jsbsim-build-controls:'+source['build_control_sha256']],'consumer backend/control mismatch')
    repo=Path(a['repository_root']).resolve()
    for row in rows[2:]:
        name,want=row.rsplit(':',1);path=(repo/name).resolve()
        v.demand(path.is_relative_to(repo),'consumer path escaped repository')
        text=path.read_bytes().decode('utf-8').replace('\r\n','\n')
        v.demand(hashlib.sha256(text.encode()).hexdigest()==want,'consumer source changed: '+name)
    route=v.load(build/'event-aware-route.json');result=v.load(build/'event-aware-build-result.json')
    v.demand(result['status']=='COMPILED_NOT_TESTED' and result['route_sha256']==v.sha(build/'event-aware-route.json'),'staged compilation absent')
    v.demand(route['source_variant']=='jsbsim-1.3.1-event-aware-coupled-midpoint-v1' and route['backend_identity_sha256']==source['backend_identity_sha256'],'wrong compiled backend')
    v.demand(Path(route['repository_root']).samefile(a['repository_root']) and Path(route['build_directory']).samefile(build),'staged path mismatch')
    v.demand(v.sha(route['pretrial_path'])==route['pretrial_sha256'],'pretrial identity changed')
    verify_pretrial(Path(route['pretrial_path']),repo,[row.rsplit(':',1)[0] for row in rows[2:]])
    v.demand(route['build_entry_sha256']==v.sha(Path(a['repository_root'])/'tools/bootstrap/build.ps1'),'staged build entry changed')
    for key,name in (('cmake_cache_sha256','CMakeCache.txt'),('compile_commands_sha256','compile_commands.json'),('verbose_build_sha256','native-verbose-build.log')):
        v.demand(result[key]==v.sha(build/name),'staged compiler input changed: '+name)
    cache=(build/'CMakeCache.txt').read_text(encoding='utf-8')
    expected='OFF' if route['headless_native'] else 'ON'
    v.demand(re.findall(r'^FLIGHT_BUILD_GODOT_BINDINGS:BOOL=(ON|OFF)$',cache,re.M)==[expected],'headless binding cache differs from route')
    vendor=Path(a['vendor_root'])
    v.demand(vendor.samefile(source['vendor_root']) and (Path(route['source_bundle_root'])/'vendor').samefile(vendor),'selected vendor root differs from compiled route')
    commands=v.load(build/'compile_commands.json')
    log=(build/'native-verbose-build.log').read_text(encoding='utf-8',errors='strict').replace('\\','/')
    for name in ('FGPiston.cpp','FGPropeller.cpp'):
        path=vendor/'src/models/propulsion'/name
        entries=[e for e in commands if (Path(e['directory'])/e['file']).resolve()==path.resolve()]
        v.demand(len(entries)==1,'one selected numerical translation unit required: '+name)
        e=entries[0];cmd=e.get('command') or ' '.join(e['arguments']);msvc='/fp:strict' in cmd
        strict(cmd,msvc)
        observed=[line for line in log.splitlines() if str(path.resolve()).replace('\\','/') in line and re.search(r'(^|[\s\"])(/c|-c)($|[\s\"])',line)]
        v.demand(len(observed)==1,'one actual numerical compiler invocation required: '+name);strict(observed[0],msvc)
    pins={}
    for name in ('event-aware-route.json','event-aware-build-result.json','CMakeCache.txt','compile_commands.json','native-verbose-build.log'):
        pins[str((build/name).resolve())]=v.sha(build/name)
    pins[str(Path(route['pretrial_path']).resolve())]=route['pretrial_sha256']
    pins[str(Path(a['repository_root'])/'tools/bootstrap/build.ps1')]=v.sha(Path(a['repository_root'])/'tools/bootstrap/build.ps1')
    return {'schema':'coupled-probe-execution-v1','authorized':True,'scope':'coupled-midpoint-isolated-public-probes-v1',
      'source_manifest_sha256':v.sha(a['source_manifest']),'config_sha256':v.sha(a['_config']),
      'reference_manifest_sha256':v.sha(v.REFERENCE/'reference-manifest.json'),
      'packet_sha256':v.reference_manifest()['packet']['sha256'],
      'backend_identity_sha256':source['backend_identity_sha256'],'build_control_sha256':source['build_control_sha256'],
      'consumer_fingerprint':source['consumer_fingerprint'],
      'executables':{label:{'path':str(Path(a[label]).resolve()),'sha256':v.sha(a[label])} for label in LABELS},
      'dll':{'path':str(Path(a['dll']).resolve()),'sha256':v.sha(a['dll'])},'build_inputs':pins}

def authorize(a,path,approved):
    v.demand(approved,'authorization requires explicit --approve-execution')
    record=qualify(a);save(path,record)

def math_checks():
    manifest=v.reference_manifest();packet=v.load(v.REFERENCE/manifest['packet']['path']);v.native_cases(packet)
    # Keep generator imports local to this explicit offline test action.
    sys.path.insert(0,str(v.REFERENCE));suite=unittest.TestSuite()
    loader=unittest.defaultTestLoader
    for name in ('test_reference','test_native_fixture','test_validate','test_portable'):suite.addTests(loader.loadTestsFromName(name))
    v.demand(unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful(),'offline mathematical/tamper tests failed')

def execute(a,path,output):
    auth=v.load(path);current=qualify(a)
    v.demand(auth==current,'execution record differs from qualified current build')
    output.mkdir(parents=True,exist_ok=False)
    packet=v.REFERENCE/'references.json';plan_dir=output/'requests'
    v.prepare(SimpleNamespace(packet=packet,packet_sha256=auth['packet_sha256'],output=plan_dir))
    plan=v.load(plan_dir/'plan.json');dll=Path(a['dll'])
    record={'scope':auth['scope'],'authorization_sha256':v.sha(path),'utc_before':now(),
      'authorized_source_binding_sha256':v.sha(a['source_manifest']),
      'packet_sha256':plan['packet_sha256'],'requests_sha256':plan['requests_sha256'],
      'legacy_requests_sha256':plan['legacy_requests_sha256'],'dll_path':str(dll.resolve()),
      'dll_sha256_before':v.sha(dll),'children':{}}
    errors=[]
    for label in LABELS:
        exe=Path(a[label]);payload=(plan_dir/('requests.txt' if label=='kernel' else 'legacy-requests.txt')).read_bytes() if label in ('kernel','library') else b''
        child={'executable_path':str(exe.resolve()),'executable_sha256_before':observed_hash(exe),'dll_sha256_before':observed_hash(dll),'stdin_sha256':hashlib.sha256(payload).hexdigest(),'utc_before':now()}
        record['children'][label]=child
        stdout=stderr=b'';code=None
        try:
            v.demand(child['executable_sha256_before']==auth['executables'][label]['sha256'] and child['dll_sha256_before']==auth['dll']['sha256'],'child input changed before spawn')
            command=[str(exe)]+([] if label=='kernel' else [a['model_root']]);child['command']=command
            env=os.environ|{'JSBSIM_DEBUG':'0'}
            # Select only the explicitly qualified library directory; preserve
            # remaining loader search entries, then verify actual loaded identity.
            key='PATH' if os.name=='nt' else 'LD_LIBRARY_PATH'
            env[key]=str(dll.parent)+os.pathsep+env.get(key,'')
            r=subprocess.run(command,input=payload,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30,env=env)
            stdout,stderr,code=r.stdout,r.stderr,r.returncode
        except subprocess.TimeoutExpired as e:
            stdout,stderr=e.stdout or b'',e.stderr or b'';errors.append(label+': timeout killed/reaped')
        except Exception as e:stderr=repr(e).encode();errors.append(label+': spawn/identity failure')
        finally:
            (output/(label+'.stdout')).write_bytes(stdout);(output/(label+'.stderr')).write_bytes(stderr)
            child.update(exit_code=code,stdout_sha256=hashlib.sha256(stdout).hexdigest(),stderr_sha256=hashlib.sha256(stderr).hexdigest(),utc_after=now(),executable_sha256_after=observed_hash(exe),dll_sha256_after=observed_hash(dll))
        if code!=0:errors.append(label+': nonzero/no exit')
        try:
            v.demand(child['executable_sha256_before']==child['executable_sha256_after']==auth['executables'][label]['sha256'],'child bytes changed')
            v.demand(child['dll_sha256_before']==child['dll_sha256_after']==auth['dll']['sha256'],'DLL bytes changed')
            if label!='kernel':
                rows=v.lines(output/(label+'.stdout'));row=rows[0] if label in ('library','terminal') else rows[-1]
                # Chronology identity row is located explicitly by kind.
                if label=='chronology':row=next(r for r in rows if r.get('kind')=='chronology-identity')
                actual=Path(row['loaded_library_path']);v.demand(actual.is_absolute() and actual.samefile(dll) and v.sha(actual)==auth['dll']['sha256'],'wrong actual loaded DLL')
                child['actual_loaded_library_path']=str(actual);child['actual_module_sha256']=v.sha(actual)
                if label=='terminal':
                    v.demand(len(rows)==1 and row=={'passed':True,'scope':'actual coupled Session terminal-retention negative unit; not physical lifecycle','completed_tick':1,'failure':'coupled piston: rounding mode unsupported','candidate_controls_uncommitted':True,'fe_mxcsr_restored':True,'loaded_library_path':row['loaded_library_path'],'source_fingerprint':auth['consumer_fingerprint']},'terminal retention assertion failed')
        except Exception as e:errors.append(label+': '+repr(e))
    try:v.demand(qualify(a)==auth,'source/build/model changed during trial')
    except Exception as e:errors.append('post-trial identity: '+repr(e))
    record.update(dll_sha256_after=observed_hash(dll),utc_after=now(),failures=errors,identities_passed=not errors)
    receipt=output/'execution-receipt.json';save(receipt,record)
    v.demand(not errors,'unit children/identities failed: '+repr(errors))
    v.check(SimpleNamespace(plan=plan_dir/'plan.json',kernel_output=output/'kernel.stdout',library_output=output/'library.stdout',chronology_output=output/'chronology.stdout',dll=dll,execution_receipt=receipt,output=output/'validation-result.json'))

def main():
    p=argparse.ArgumentParser();p.add_argument('mode',choices=('math','authorize','execute'))
    p.add_argument('--config');p.add_argument('--ratification');p.add_argument('--output-root');p.add_argument('--approve-execution',action='store_true')
    args=p.parse_args()
    if args.mode=='math':math_checks();return
    v.demand(args.config and args.ratification,'explicit configured route and execution record required')
    a=config(args.config);a['_config']=str(Path(args.config).resolve())
    if args.mode=='authorize':authorize(a,Path(args.ratification),args.approve_execution)
    else:
        v.demand(args.output_root,'explicit evidence root required')
        execute(a,Path(args.ratification),Path(args.output_root)/('run-'+uuid.uuid4().hex))

if __name__=='__main__':main()
