"""Windows bindings-ON CI metadata qualification and explicit authorization.

This source-reviewed hosted gate performs mechanical source/build checks; it
never claims an independent human compile review. Compiler, native children and
Godot execution belong to the separately staged bootstrap/player commands.
The distinct coupled-native.py headless qualifier remains OFF-only.
"""
from pathlib import Path
import argparse, hashlib, importlib.util, json, os, re, shutil, subprocess, sys

HERE=Path(__file__).resolve().parent
CTESTS=('native_toolchain_smoke','contract_boundary','ground_contract','ground_contact_proof',
        'fdm_boundary','interactive_loop','interactive_negative_readback','piston_engine_lifecycle',
        'coupled_shaft_math','coupled_shaft_native','replay_reconstruction')
VARIANT='jsbsim-1.3.1-event-aware-coupled-midpoint-v1'
AUTH_SCOPE='automated Windows bindings-ON measured source/build gate; explicit hosted execution approval, not independent compile review'
GODOT_FILES={'CMakeLists.txt','src/bridge.cpp','src/codec.cpp','src/codec.hpp','src/worker.cpp','src/worker.hpp',
             'src/interactive_bridge.cpp','src/interactive_worker.cpp','src/interactive_worker.hpp'}

def require(ok,message):
    if not ok:raise ValueError(message)

def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def objhash(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def exact(left,right):return objhash(left)==objhash(right)

def load(path):
    def unique(pairs):
        out={}
        for key,value in pairs:
            require(key not in out,'duplicate JSON key');out[key]=value
        return out
    return json.loads(Path(path).read_text(encoding='utf-8-sig'),object_pairs_hook=unique,
                      parse_constant=lambda value:(_ for _ in ()).throw(ValueError(value)))
def save(path,value):
    with Path(path).open('x',encoding='utf-8',newline='\n') as stream:
        json.dump(value,stream,indent=2);stream.write('\n')
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);out=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(out);return out
def APIs(repo):
    ci=module('player_ci_metadata',repo/'tools/ci/coupled-native.py')
    identity=module('player_native_identity',repo/'tools/interactive-preview/native-identity.py')
    # The reviewed public runner is already route-aware and supports bindings ON.
    # Never change/patch the distinct public CI qualifier's hardcoded OFF guard.
    probes=repo/'tests/engine/shaft-method/probes'
    require('validate' not in sys.modules,'unexpected preloaded probe module')
    sys.path.insert(0,str(probes))
    try:unit=module('player_unit_metadata',probes/'run.py')
    finally:sys.path.pop(0)
    require(Path(unit.v.__file__).resolve()==(probes/'validate.py').resolve(),'probe import path mismatch')
    return ci,identity,unit
def source_inputs(repo,work,ci,identity):
    pins=ci.source_inputs(repo)
    godot=repo/'native/godot_bridge';files=set()
    for path in godot.rglob('*'):
        identity.ordinary(path,path.is_dir())
        if path.is_file():files.add(path.relative_to(godot).as_posix())
    require(files==GODOT_FILES,'closed nine-file Godot bridge source roster required')
    extra={'native/godot_bridge/'+name for name in files}
    extra.add('tools/interactive-preview/native-identity.py')
    extra.update(('tools/ci/coupled-player.py','tools/ci/test_coupled_player.py',work.relative_to(repo).as_posix()+'/source-gates.json'))
    for name in extra:
        file=identity.contained(repo,name);pins[name]={'sha256':digest(file),'bytes':file.stat().st_size}
    # Recheck ordinary contained files even for rows supplied by the shared helper.
    for name in pins:identity.contained(repo,name)
    return dict(sorted(pins.items()))
def check_gates(repo,work):
    gates=load(work/'source-gates.json')
    head=subprocess.check_output(['git','-C',str(repo),'rev-parse','--verify','HEAD^{commit}'],text=True,timeout=30).strip()
    require(set(gates)=={'schema','numerics_merge','delivery_contract_merge','git_head'},'source gates closed shape')
    require(gates['schema']=='coupled-player-source-gates-v1','source gates schema')
    for key in ('numerics_merge','delivery_contract_merge','git_head'):
        require(type(gates[key]) is str and re.fullmatch('[0-9a-f]{40}',gates[key]),'exact merged commit required')
        process=subprocess.run(['git','-C',str(repo),'merge-base','--is-ancestor',gates[key],'HEAD'],capture_output=True,timeout=30)
        require(process.returncode==0,'required merge/head is not current ancestor: '+key)
    require(head==gates['git_head'],'checkout HEAD changed after fixed pretrial')
    return gates
def pretrial(repo,work,ci,identity,args):
    require(not work.exists(),'fresh work root required; retain all old evidence')
    identity.ordinary(work.parent,True);work.mkdir();(work/'evidence').mkdir()
    head=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD^{commit}'],text=True,timeout=30).strip()
    save(work/'source-gates.json',{'schema':'coupled-player-source-gates-v1','numerics_merge':args.numerics_merge,
         'delivery_contract_merge':args.delivery_contract_merge,'git_head':head})
    check_gates(repo,work)
    manifest=ci.reference(repo)
    save(work/'pretrial.json',{'schema':'coupled-ci-pretrial-v1',
         'scope':'fixed source/reference/budgets before fresh compilation; no native execution',
         'source_inputs':source_inputs(repo,work,ci,identity),
         'reference_manifest_sha256':digest(repo/'tests/engine/shaft-method/coupled-midpoint-v1/reference-manifest.json'),
         'packet_sha256':manifest['packet']['sha256'],'required_ctests':sorted(CTESTS)})
def check_pretrial(repo,work,ci,identity):
    identity.ordinary(work,True);identity.ordinary(work/'evidence',True)
    check_gates(repo,work);before=load(work/'pretrial.json')
    require(set(before)=={'schema','scope','source_inputs','reference_manifest_sha256','packet_sha256','required_ctests'},'pretrial closed schema')
    require(before['schema']=='coupled-ci-pretrial-v1' and before['scope']=='fixed source/reference/budgets before fresh compilation; no native execution','pretrial schema/scope')
    require(before['required_ctests']==sorted(CTESTS),'all eleven exact CTests required')
    require(before['source_inputs']==source_inputs(repo,work,ci,identity),'current source/control/model closure differs from pretrial')
    manifest=ci.reference(repo)
    require(before['reference_manifest_sha256']==digest(repo/'tests/engine/shaft-method/coupled-midpoint-v1/reference-manifest.json') and before['packet_sha256']==manifest['packet']['sha256'],'fixed reference changed')
    return before
def check_binding_route(route,values):
    require(route['headless_native'] is False and route['source_variant']==VARIANT,'Godot-ON coupled route required; no headless evidence reuse')
    require(values.get('FLIGHT_BUILD_GODOT_BINDINGS')=='ON' and values.get('FLIGHT_JSBSIM_VARIANT')=='event-aware-coupled-midpoint-v1','bindings must actually be configured ON')
    require(values.get('CMAKE_EXPORT_COMPILE_COMMANDS')=='ON','actual compiler declarations required')
def actual_compile_rows(text,file):
    name=str(file).replace('\\','/')
    return [line for line in text.splitlines() if name in line and re.search(r'(^|[\s"])(/c|-c)($|[\s"])',line)]

def measure(repo,work,ci,identity,unit):
    require(os.name=='nt','Windows x64 qualification only')
    require(not os.environ.get('CL') and not os.environ.get('_CL_'),'implicit MSVC options not admitted')
    check_pretrial(repo,work,ci,identity)
    build=identity.ordinary(work/'build',True);route=load(build/'event-aware-route.json');result=load(build/'event-aware-build-result.json')
    values=ci.cache(build/'CMakeCache.txt');check_binding_route(route,values)
    for key,want in [('repository_root',repo),('build_directory',build),('pretrial_path',work/'pretrial.json')]:ci.same(route[key],want)
    for key,want in [('execution_path',work/'physical-execution.json'),('probe_execution_path',work/'unit-execution.json')]:
        require(Path(route[key]).resolve()==want.resolve(),'compiled authorization path differs')
    require(route['pretrial_sha256']==digest(work/'pretrial.json') and route['build_entry_sha256']==digest(repo/'tools/bootstrap/build.ps1'),'compiled pretrial/build entry changed')
    require(result['status']=='COMPILED_NOT_TESTED' and result['route_sha256']==digest(build/'event-aware-route.json'),'fresh staged compilation receipt required')
    for key,name in [('cmake_cache_sha256','CMakeCache.txt'),('compile_commands_sha256','compile_commands.json'),('verbose_build_sha256','native-verbose-build.log')]:require(result[key]==digest(build/name),'staged compiler evidence changed')
    native=identity.qualify(repo,build)
    require(native['source_variant']==VARIANT and native['backend_identity_sha256']==route['backend_identity_sha256'],'qualified selected backend differs')
    vendor=Path(route['source_bundle_root'])/'vendor'
    commands=load(build/'compile_commands.json');verbose=(build/'native-verbose-build.log').read_text(encoding='utf-8').replace('\\','/')
    strict_rows={}
    for name in ('FGPiston.cpp','FGPropeller.cpp'):
        file=(vendor/'src/models/propulsion'/name).resolve()
        rows=[row for row in commands if (Path(row['directory'])/row['file']).resolve()==file]
        require(len(rows)==1,'one selected numerical compile declaration required')
        declared=rows[0].get('command') or ' '.join(rows[0]['arguments']);ci.strict(declared,True)
        actual=actual_compile_rows(verbose,file)
        require(len(actual)==1,'one actual strict numerical invocation required');ci.strict(actual[0],True)
        strict_rows[name]={'file':str(file),'declared':declared,'actual':actual[0]}
    config=unit.config(build/'coupled-probes-config.json');config['_config']=str(build/'coupled-probes-config.json')
    expected_unit=unit.qualify(config)  # Computes metadata only, creates no execution record/child.
    require(expected_unit['consumer_fingerprint']==native['declared_source_fingerprint'] and expected_unit['build_control_sha256']==native['build_control_sha256'] and expected_unit['backend_identity_sha256']==native['backend_identity_sha256'],'unit/bridge identity mismatch')
    ci.same(config['vendor_root'],vendor);ci.same(config['build_root'],build);ci.same(config['repository_root'],repo)
    tools=load(repo/'.local/toolchain/environment.json')['tools'];ctest=Path(tools['cmake']).with_name('ctest.exe')
    discovery=load_json_command([ctest,'--test-dir',build,'--show-only=json-v1'],repo)
    tests=discovery['tests'];names=[row['name'] for row in tests]
    require(len(names)==11 and len(set(names))==11 and set(names)==set(CTESTS),'all eleven real CTests required')
    physical=next(row for row in tests if row['name']=='piston_engine_lifecycle')['command']
    ci.same(physical[1],repo/'tests/engine/native-validate.py')
    def arg(name):
        require(physical.count(name)==1,'missing/duplicate physical argument');return physical[physical.index(name)+1]
    require(arg('--angular-method')=='event_aware_coupled_midpoint_v1' and '--source-only' not in physical,'unchanged actual physical suite required')
    ci.same(arg('--pretrial-ratification'),work/'pretrial.json')
    require(Path(arg('--ratification')).resolve()==(work/'physical-execution.json').resolve(),'physical authorization route mismatch')
    ci.same(arg('--jsbsim-dll'),config['dll']);ci.same(arg('--model-root'),repo/'native/fdm_jsbsim/models/original-piston-prop')
    for name in (arg('--native'),arg('--mechanism'),config['dll'],*(config[label] for label in ('kernel','library','chronology','terminal'))):
        require(identity.ordinary(name).is_relative_to(build),'qualified binary outside fresh build')
    binaries={}
    for file in (build/'bin').rglob('*'):
        ordinary=identity.ordinary(file,file.is_dir())
        if file.is_file():binaries[str(file.relative_to(build)).replace('\\','/')]={'bytes':ordinary.stat().st_size,'sha256':digest(ordinary)}
    measurement={'schema':'coupled-player-ci-measurement-v1','scope':'automated actual fresh Windows bindings-ON source/build measurement; no native execution authorization or independent review claim',
        'pretrial_sha256':digest(work/'pretrial.json'),'source_gates_sha256':digest(work/'source-gates.json'),
        'native_identity':native,'strict_units':strict_rows,'expected_unit_record_sha256':objhash(expected_unit),
        'ctests':[{'name':row['name'],'command':row['command']} for row in tests],
        'compiled_binary_roster':dict(sorted(binaries.items())),
        'build_inputs':{name:digest(build/name) for name in ['event-aware-route.json','event-aware-build-result.json','native-verbose-build.log','coupled-probes-config.json']},
        'physical_native':arg('--native'),'physical_mechanism':arg('--mechanism'),'qualified_dll':arg('--jsbsim-dll')}
    return measurement,expected_unit
def load_json_command(args,repo):
    process=subprocess.run([str(value) for value in args],cwd=repo,capture_output=True,text=True,encoding='utf-8',timeout=180)
    require(process.returncode==0,'read-only test discovery failed');return json.loads(process.stdout)
def current_measurement(repo,work,ci,identity,unit):
    measurement,expected=measure(repo,work,ci,identity,unit)
    require(exact(measurement,load(work/'evidence/compile-measurement.json')),'compiled measured inputs changed after measurement')
    for row in measurement['native_identity']['build_witnesses']:
        archived=identity.contained(work/'evidence/compiled',row['path'])
        require(digest(archived)==row['sha256'] and archived.stat().st_size==row['bytes'],'saved seven-artifact witness changed')
    resource=measurement['native_identity']['resource']
    archived=identity.contained(work/'evidence/compiled',resource['build_path'])
    require(digest(archived)==resource['sha256'] and archived.stat().st_size==resource['bytes'],'saved raw native resource changed')
    return measurement,expected

def physical_record(repo,work,ci,measurement):
    native=measurement['native_identity']
    return ci.physical_record(repo,work,{'native':measurement['physical_native'],'mechanism':measurement['physical_mechanism'],
        'dll':measurement['qualified_dll'],'consumer':native['declared_source_fingerprint'],'selected':{'backend_identity_sha256':native['backend_identity_sha256']}})
def authorization_record(work):
    return {'schema':'coupled-player-ci-authorization-v1','scope':AUTH_SCOPE,
        'measurement_sha256':digest(work/'evidence/compile-measurement.json'),
        'unit_authorization_sha256':digest(work/'unit-execution.json'),
        'physical_authorization_sha256':digest(work/'physical-execution.json')}

def authorize(repo,work,ci,identity,unit,args):
    require(args.approve_execution,'hosted physical authorization requires explicit --approve-execution')
    measurement,expected=current_measurement(repo,work,ci,identity,unit)
    require(exact(load(work/'unit-execution.json'),expected),'separately issued current unit authorization missing')
    record=physical_record(repo,work,ci,measurement);require(set(record)==ci.AUTH_KEYS,'physical eleven-field schema changed')
    save(work/'physical-execution.json',record)
    save(work/'evidence/player-authorization.json',authorization_record(work))

def ctest_complete(text):
    rows=re.findall(r'^\s*(\d+)/11 Test\s+#\d+:\s+([a-z_]+)\s+\.{2,}\s+Passed\b.*$',text,re.M)
    require(len(rows)==11 and {int(row[0]) for row in rows}==set(range(1,12)) and {row[1] for row in rows}==set(CTESTS),'eleven unique actual passed CTest rows required')
    require('100% tests passed, 0 tests failed out of 11' in text,'full CTest success summary required')
def verify(repo,work,ci,identity,unit):
    measurement,expected=current_measurement(repo,work,ci,identity,unit)
    require(exact(load(work/'evidence/player-authorization.json'),authorization_record(work)),'hosted execution authorization evidence changed')
    require(exact(load(work/'unit-execution.json'),expected) and exact(load(work/'physical-execution.json'),physical_record(repo,work,ci,measurement)),'current explicit authorizations differ')
    build=work/'build';ctest_complete((build/'native-ctest.log').read_text(encoding='utf-8'))
    physical_paths=list((build/'piston-engine-proof').glob('run-*/suite-receipt.json'));unit_paths=list((build/'coupled-unit-proof').glob('run-*/validation-result.json'))
    require(len(physical_paths)==len(unit_paths)==1,'one fresh complete physical/unit suite required')
    physical=load(physical_paths[0]);result=load(unit_paths[0]);execution=load(unit_paths[0].parent/'execution-receipt.json')
    require(physical['passed'] is True and type(physical['failed_checks']) is int and physical['failed_checks']==0 and type(physical['checks']) is int and physical['checks']>0 and len(physical['processes'])==12 and physical['skipped_cases']==[] and physical['skipped_comparisons']==[] and physical['dependent_comparisons_skipped'] is False,'original twelve-process physical gate failed/skipped')
    require(physical['limits_sha256']==ci.LIMITS and physical['ratification_sha256']==digest(work/'physical-execution.json') and physical['angular_integration_method']=='event_aware_coupled_midpoint_v1','physical receipt identity mismatch')
    require(result['passed'] is True and all(type(result[key]) is int and result[key]==want for key,want in [('native_rows',137),('legacy_checks',270),('actual_chronology_rows',12)]),'fixed unit/default/chronology comparisons failed')
    ci.check_unit_receipt(unit_paths[0].parent,execution,expected,work/'unit-execution.json')
    require(result['packet_sha256']==expected['packet_sha256'] and result['source_binding_sha256']==expected['source_manifest_sha256'],'unit source/reference mismatch')
    save(work/'evidence/player-ctest-result.json',{'schema':'coupled-player-ci-ctest-result-v1','passed':True,'scope':'automated hosted Windows bindings-ON engineering tests; whole-flight/editor/export/replacement/pilot gates separate',
        'measurement_sha256':digest(work/'evidence/compile-measurement.json'),'native_ctest_log_sha256':digest(build/'native-ctest.log'),
        'unit_receipt_sha256':digest(unit_paths[0]),'physical_receipt_sha256':digest(physical_paths[0]),'ctests':11,'physical_processes':12,'skipped':False})
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['pretrial','measure','authorize','verify'])
    parser.add_argument('--repository-root',type=Path,default=HERE.parents[1]);parser.add_argument('--work-root',type=Path,required=True)
    parser.add_argument('--numerics-merge');parser.add_argument('--delivery-contract-merge');parser.add_argument('--approve-execution',action='store_true')
    args=parser.parse_args();repo=args.repository_root.resolve();ci,identity,unit=APIs(repo)
    repo=identity.ordinary(repo,True)
    work=Path(os.path.abspath(args.work_root))
    require(work.parent==repo/'.local','fresh run directory must be a direct child of repository .local')
    if args.mode=='pretrial' and not work.parent.exists():work.parent.mkdir()
    identity.ordinary(work.parent,True)
    if args.mode=='pretrial':
        require(not args.approve_execution,'pretrial cannot authorize execution')
        pretrial(repo,work,ci,identity,args)
    elif args.mode=='measure':
        require(not args.approve_execution,'measurement cannot authorize execution')
        require(not (work/'unit-execution.json').exists() and not (work/'physical-execution.json').exists(),'measurement must precede execution authorizations')
        require(not any((work/'build'/name).exists() for name in ['native-ctest.log','piston-engine-proof','coupled-unit-proof']),'measurement cannot relabel a previously run suite')
        measured,_=measure(repo,work,ci,identity,unit)
        save(work/'evidence/compile-measurement.json',measured)
        archived=work/'evidence/compiled';archived.mkdir()
        for row in measured['native_identity']['build_witnesses']:
            target=archived/row['path'];target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(work/'build'/row['path'],target)
            require(digest(target)==row['sha256'],'saved seven-artifact witness changed')
        resource=measured['native_identity']['resource']
        target=archived/resource['build_path'];target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(work/'build'/resource['build_path'],target)
        require(digest(target)==resource['sha256'] and target.stat().st_size==resource['bytes'],'saved raw native resource changed')
    elif args.mode=='authorize':authorize(repo,work,ci,identity,unit,args)
    else:
        require(not args.approve_execution,'verification cannot newly authorize execution')
        verify(repo,work,ci,identity,unit)
    print('PASS '+args.mode+'; automated metadata gate, no native/test/Godot execution launched')
if __name__=='__main__':main()
