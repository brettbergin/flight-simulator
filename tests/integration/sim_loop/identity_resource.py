"""Godot-only identity admission fixtures. Never loads a native extension.

Synthetic digest strings test shape admission, not source qualification. An
observed null factory proves invalid expectations fail before bridge allocation.
The actual-library wrong-reply/join case remains in facade_checks.gd.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def digest(data):
    return hashlib.sha256(data).hexdigest()


def resource(values):
    return ('extends RefCounted\n' + ''.join(
        'const '+key+': String = '+json.dumps(value)+'\n'
        for key, value in values.items())).encode('utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo-root', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo, godot, output = args.repo_root.resolve(), args.godot.resolve(), args.output.resolve()
    if output.exists():
        raise ValueError('Use a fresh output directory; preserve failed fixtures')
    output.mkdir(parents=True)
    environment = dict(os.environ)
    for name in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME'):
        target = output/'userdata'/name
        target.mkdir(parents=True)
        environment[name] = str(target)
    version = subprocess.run([str(godot), '--headless', '--version'], capture_output=True,
                             timeout=30, env=environment, cwd=output)
    (output/'version.stdout').write_bytes(version.stdout)
    (output/'version.stderr').write_bytes(version.stderr)
    if version.returncode or version.stdout.decode().strip() != '4.7.2.stable.official.ed1daf0bf':
        raise ValueError('Pinned Godot version required')
    source = repo/'app/simulation'
    pins = {p.relative_to(source).as_posix(): digest(p.read_bytes())
            for p in sorted(source.rglob('*')) if p.is_file()}
    base = {'SCHEMA': 'flight-native-build-identity-v1',
            'SOURCE_VARIANT': 'jsbsim-1.3.1-upstream',
            'BACKEND_IDENTITY_SHA256': 'a'*64,
            'BUILD_CONTROL_SHA256': 'b'*64,
            'SOURCE_FINGERPRINT': 'c'*64}
    cases = []
    for variant in ('upstream', 'event-aware-constant-power-v1', 'event-aware-coupled-midpoint-v1'):
        values = dict(base, SOURCE_VARIANT='jsbsim-1.3.1-'+variant)
        cases.append(('shape-'+variant, values, 1))
    for name, key, value in [('bad-schema', 'SCHEMA', 'flight-native-build-identity-v2'),
                              ('bad-variant', 'SOURCE_VARIANT', 'jsbsim-any'),
                              ('empty-variant', 'SOURCE_VARIANT', '')]:
        cases.append((name, dict(base, **{key: value}), 0))
    for key in ('BACKEND_IDENTITY_SHA256', 'BUILD_CONTROL_SHA256', 'SOURCE_FINGERPRINT'):
        for suffix, value in (('uppercase', 'A'*64), ('short', 'a'*63), ('nonhex', 'g'*64)):
            cases.append((key.lower()+'-'+suffix, dict(base, **{key: value}), 0))
    results = []
    for name, values, count in cases:
        case = output/name
        case.mkdir()
        shutil.copytree(source, case/'simulation')
        (case/'build').mkdir()
        (case/'build/native_identity.gd').write_bytes(resource(values))
        (case/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Synthetic identity admission"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8', newline='\n')
        model = json.dumps((repo/'native/fdm_jsbsim/models/original-interactive').as_posix())
        expected_error = ('Native interactive session unavailable' if count
                          else 'Qualified generated native build identity required')
        driver = '''extends SceneTree
const Facade = preload("res://simulation/session_facade.gd")
var allocations: int=0
func _initialize() -> void:
    var factory: Callable=func() -> RefCounted:
        allocations+=1
        return null
    var facade:=Facade.new(factory)
    var result: Dictionary=facade.start(MODEL,"ground-ready","calm")
    var truth: Dictionary=facade.readback()
    var passed: bool=not result.ok and allocations==COUNT and result.error==ERROR and not truth.native_live and truth.historical and truth.tick==null and truth.native_source_fingerprint==null
    print("SYNTHETIC_IDENTITY_ADMISSION "+JSON.stringify({"passed":passed,"factory_calls":allocations,"expected_factory_calls":COUNT,"no_native_extension":not ClassDB.class_exists("FlightInteractiveSession")}))
    quit(0 if passed and not ClassDB.class_exists("FlightInteractiveSession") else 1)
'''.replace('MODEL', model).replace('COUNT', str(count)).replace('ERROR', json.dumps(expected_error))
        (case/'check.gd').write_text(driver, encoding='utf-8', newline='\n')
        observed = subprocess.run([str(godot), '--headless', '--path', str(case), '--script', 'res://check.gd'],
                                  capture_output=True, timeout=30, env=environment, cwd=case)
        (case/'stdout.log').write_bytes(observed.stdout)
        (case/'stderr.log').write_bytes(observed.stderr)
        text = observed.stdout.decode('utf-8', errors='replace')+'\n'+observed.stderr.decode('utf-8', errors='replace')
        marker = 'SYNTHETIC_IDENTITY_ADMISSION '
        rows = [json.loads(line[len(marker):]) for line in text.splitlines() if line.startswith(marker)]
        passed = (observed.returncode == 0 and len(rows) == 1 and rows[0]['passed'] is True
                  and rows[0]['no_native_extension'] is True and rows[0]['factory_calls'] == count
                  and not any(token in text for token in ('ERROR:', 'SCRIPT ERROR:', 'FATAL', 'leaked')))
        results.append({'case': name, 'passed': passed, 'exit_code': observed.returncode,
                        'expected_factory_calls': count, 'resource_sha256': digest(resource(values)),
                        'stdout_sha256': digest(observed.stdout), 'stderr_sha256': digest(observed.stderr)})
        if not passed:
            break
    current = {p.relative_to(source).as_posix(): digest(p.read_bytes())
               for p in sorted(source.rglob('*')) if p.is_file()}
    passed = len(results) == len(cases) and all(row['passed'] for row in results) and current == pins
    receipt = {'schema': 'synthetic-facade-identity-admission-v1', 'passed': passed,
               'scope': 'Synthetic resource shape admission; no native extension, aircraft execution or source qualification',
               'time_utc': datetime.now(timezone.utc).isoformat(), 'cases_expected': len(cases),
               'godot_sha256': digest(godot.read_bytes()), 'script_sha256': digest(Path(__file__).read_bytes()),
               'simulation_source_sha256': pins, 'source_unchanged': current == pins, 'results': results}
    (output/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8', newline='\n')
    print(json.dumps({'passed': passed, 'cases': len(results), 'scope': receipt['scope']}))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
