"""Run actual Windows mapper/codec fixtures before native compilation; offline."""
import argparse, hashlib, importlib.util, json, os, shutil, subprocess, uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolchain', type=Path, default=ROOT/'.local/toolchain')
    args = parser.parse_args()
    if os.name != 'nt':
        raise RuntimeError('This preflight requires Windows editor and portable export')
    lock = json.loads((ROOT/'third_party/dependencies.lock.json').read_text(encoding='utf-8-sig'))
    spec = importlib.util.spec_from_file_location('input_bootstrap', ROOT/'tools/bootstrap/bootstrap.py')
    bootstrap = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bootstrap)
    toolchain = args.toolchain.resolve()
    pins = {}
    for name in ('godot', 'godot-templates'):
        item = next(row for row in lock['tools'] if row['id']==name and row['platform'] in ('windows','all'))
        directory = toolchain/name
        receipt = json.loads((directory/'.verified.json').read_text(encoding='utf-8-sig'))
        if any(receipt.get(key)!=item[key] for key in ('id','version','url','sha256')) or bootstrap.tree_digest(directory)!=receipt['tree_sha256']:
            raise RuntimeError('Verified toolchain drift: '+name)
        pins[name] = receipt
    godot = toolchain/'godot'/next(row['executable'] for row in lock['tools'] if row['id']=='godot' and row['platform']=='windows')
    template = toolchain/'godot-templates/windows_release_x86_64.exe'
    run = ROOT/'.local/input-preflight'/uuid.uuid4().hex
    project = run/'p'
    project.mkdir(parents=True)
    sources = {
        'app/input/input_mapper.gd':'input/input_mapper.gd',
        'app/input/input_preset.gd':'input/input_preset.gd',
        'app/simulation/wire_validation.gd':'simulation/wire_validation.gd',
        'app/simulation/uint64.gd':'simulation/uint64.gd',
        'tests/input/input_checks.gd':'input_tests/input_checks.gd',
        'tests/input/reference.json':'input_tests/reference.json',
    }
    hashes = {}
    for source, destination in sources.items():
        target = project/destination
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT/source, target)
        hashes[source] = sha(target)
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Input Fixture"\nrun/main_scene="res://check.tscn"\n', encoding='utf-8')
    (project/'check.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://check.gd" id="1"]\n[node name="InputCheck" type="Node"]\nscript=ExtResource("1")\n', encoding='utf-8')
    (project/'check.gd').write_text('''extends Node
func _ready() -> void:
 var result: Dictionary=load("res://input_tests/input_checks.gd").run()
 var file=FileAccess.open("res://receipt.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(result))
 file.close()
 print("INPUT_PREFLIGHT_PASSED" if result.passed else "INPUT_PREFLIGHT_FAILED")
 get_tree().quit(0 if result.passed else 1)
''', encoding='utf-8')
    (project/'export_presets.cfg').write_text('''[preset.0]
name="Windows Input"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter="receipt.json"
script_export_mode=2
[preset.0.options]
custom_template/release="'''+template.as_posix()+'''"
binary_format/embed_pck=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=false
debug/export_console_wrapper=0
texture_format/bptc=true
texture_format/s3tc=true
''', encoding='utf-8')
    observations = {}
    def execute(label, command, receipt=None):
        environment = {'SystemRoot':os.environ['SystemRoot'], 'WINDIR':os.environ['WINDIR'], 'PATH':'', 'JSBSIM_DEBUG':'0'}
        for name in ('APPDATA','LOCALAPPDATA','TEMP','TMP'):
            directory = run/label/name
            directory.mkdir(parents=True, exist_ok=True)
            environment[name] = str(directory)
        environment['PATH'] = ''
        log = run/(label+'.log')
        with log.open('wb') as stream:
            result = subprocess.run(command, cwd=run, env=environment, stdout=stream, stderr=subprocess.STDOUT, timeout=90, creationflags=subprocess.CREATE_NO_WINDOW)
        text = log.read_text(encoding='utf-8', errors='replace')
        observed = {'exit_code':result.returncode,'log_sha256':sha(log)}
        if receipt and receipt.exists():
            shutil.copyfile(receipt, run/(label+'-receipt.json'))
            observed['receipt'] = json.loads(receipt.read_text(encoding='utf-8-sig'))
        observations[label] = observed
        (run/'observation.json').write_text(json.dumps({'sources':hashes,'pins':pins,'observations':observations},indent=2)+'\n',encoding='utf-8')
        if result.returncode or 'SCRIPT ERROR:' in text or 'ERROR:' in text:
            raise RuntimeError(label+' failed; raw evidence retained at '+str(run))
        if receipt:
            data = observed.get('receipt', {})
            if data.get('passed') is not True or data.get('checks')!=310 or data.get('failures')!=[] or 'INPUT_PREFLIGHT_PASSED' not in text:
                raise RuntimeError(label+' assertions failed; raw evidence retained at '+str(run))
    execute('import',[str(godot),'--headless','--editor','--path',str(project),'--import','--quit'])
    execute('editor',[str(godot),'--headless','--path',str(project)],project/'receipt.json')
    executable = run/'InputFixture.exe'
    execute('export',[str(godot),'--headless','--path',str(project),'--export-release','Windows Input',str(executable)])
    execute('portable',[str(executable),'--headless'],run/'receipt.json')
    for source,destination in sources.items():
        if sha(ROOT/source)!=hashes[source] or sha(project/destination)!=hashes[source]:
            raise RuntimeError('Input source changed during preflight: '+source)
    print('Windows input editor/portable preflight passed: '+str(run))

if __name__=='__main__':
    main()
