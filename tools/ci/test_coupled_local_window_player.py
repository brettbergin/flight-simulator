"""Offline admission fixtures: no compiler, native child, Godot or source generator."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SPEC=importlib.util.spec_from_file_location('coupled_player',Path(__file__).with_name('coupled-local-window-player.py'))
q=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(q)

EXPECTED_CTESTS=(
    'native_toolchain_smoke','contract_boundary','ground_contract','ground_contact_proof',
    'fdm_boundary','interactive_loop','interactive_negative_readback','piston_engine_lifecycle',
    'coupled_shaft_math','coupled_shaft_native','replay_reconstruction','wire_numbers_native',
    'piston_local_window_native_references','interactive_apron_starts',
    'kawo_readiness','kawo_startup','kawo_ground_contact')


def contained(root,name):
    result=(root/name).resolve()
    if not result.is_relative_to(root.resolve()) or not result.is_file():raise ValueError('fixture containment')
    return result


class AdmissionTests(unittest.TestCase):
    def test_on_route_rejects_headless_wrong_variant_and_nonbool(self):
        route={'headless_native':False,'source_variant':q.VARIANT}
        cache={'FLIGHT_BUILD_GODOT_BINDINGS':'ON','FLIGHT_JSBSIM_VARIANT':'event-aware-coupled-midpoint-local-window-v2','CMAKE_EXPORT_COMPILE_COMMANDS':'ON'}
        q.check_binding_route(route,cache)
        for bad in ({**route,'headless_native':True},{**route,'headless_native':0},{**route,'source_variant':'jsbsim-1.3.1-upstream'}):
            with self.assertRaises(ValueError):q.check_binding_route(bad,cache)
        for key,value in (('FLIGHT_BUILD_GODOT_BINDINGS','OFF'),('FLIGHT_JSBSIM_VARIANT','event-aware-constant-power-v1'),('CMAKE_EXPORT_COMPILE_COMMANDS','OFF')):
            with self.assertRaises(ValueError):q.check_binding_route(route,{**cache,key:value})

    def test_actual_msvc_compile_rows_accept_both_compile_flag_spellings(self):
        selected=Path('C:/selected/vendor/FGPiston.cpp')
        slash='cl.exe /fp:strict /c "C:/selected/vendor/FGPiston.cpp" /Fo:piston.obj'
        dash='cl.exe /fp:strict -c "C:/selected/vendor/FGPiston.cpp" -Fo:piston.obj'
        for row in (slash,dash):self.assertEqual(q.actual_compile_rows(row,selected),[row])
        other='cl.exe /fp:strict -c "C:/other/vendor/FGPiston.cpp" -Fo:other.obj'
        for invalid in (other,slash.replace(' /c ',' /cxx '),dash.replace(' -c ',' -cxx '),slash.replace(' /c ',' ')):
            self.assertEqual(q.actual_compile_rows(invalid,selected),[])
        self.assertEqual(q.actual_compile_rows(other+'\n'+dash,selected),[dash])
        # Duplicate real invocations remain two rows: the measure gate rejects them.
        self.assertEqual(len(q.actual_compile_rows(slash+'\n'+dash,selected)),2)

    def test_all_seventeen_actual_pass_rows_and_full_summary_are_required(self):
        self.assertEqual(q.CTESTS,EXPECTED_CTESTS)
        rows='\n'.join(f'{i}/17 Test #{i}: {name} ........ Passed 0.01 sec' for i,name in enumerate(EXPECTED_CTESTS,1))
        text=rows+'\n100% tests passed, 0 tests failed out of 17\n';q.ctest_complete(text)
        for bad in (text.replace('100% tests passed','99% tests passed'),text.replace('Passed','Skipped',1),
                    text.replace(EXPECTED_CTESTS[-1],EXPECTED_CTESTS[0]),'\n'.join(text.splitlines()[1:]),
                    text+'\n'+text.splitlines()[0],text+'\n18/18 Test #18: extra_test ........ Passed 0.01 sec\n',
                    text+'\n18/18 Test #18: extra_test ........ Skipped 0.01 sec\n',
                    text.replace('17/17 Test #17:','16/17 Test #17:'),text.replace('/17 Test','/18 Test',1),
                    text.replace('out of 17','out of 16'),text.replace('0 tests failed','1 tests failed')):
            with self.assertRaises(ValueError):q.ctest_complete(bad)

    def test_exact_local_window_route_rejects_old14_and_crossed_v1_16(self):
        for count in (13,14):
            old='\n'.join(f'{i}/{count} Test #{i}: {name} ........ Passed 0.01 sec' for i,name in enumerate(EXPECTED_CTESTS[:count],1))
            with self.assertRaises(ValueError):q.ctest_complete(old+f'\n100% tests passed, 0 tests failed out of {count}\n')
        other=tuple(name for name in EXPECTED_CTESTS if name!='piston_local_window_native_references')
        text='\n'.join(f'{i}/16 Test #{i}: {name} ........ Passed 0.01 sec' for i,name in enumerate(other,1))
        with self.assertRaises(ValueError):q.ctest_complete(text+'\n100% tests passed, 0 tests failed out of 16\n')

    def test_pretrial_requires_exact17_not_old14_crossed16_or_partial(self):
        with tempfile.TemporaryDirectory() as directory:
            repo=Path(directory);work=repo/'work';(work/'evidence').mkdir(parents=True)
            reference=repo/'tests/engine/shaft-method/coupled-midpoint-v1/reference-manifest.json'
            reference.parent.mkdir(parents=True);reference.write_bytes(b'synthetic reference identity\n')
            before={'schema':'coupled-ci-pretrial-local-window-v2','scope':'fixed source/reference/budgets before fresh compilation; no native execution',
                    'source_inputs':{},'reference_manifest_sha256':q.digest(reference),'packet_sha256':'b'*64,
                    'required_ctests':sorted(EXPECTED_CTESTS)}
            ci=SimpleNamespace(reference=lambda repo:{'packet':{'sha256':'b'*64}})
            identity=SimpleNamespace(ordinary=lambda path,directory=False:path)
            path=work/'pretrial.json'
            with patch.object(q,'check_gates',return_value={}),patch.object(q,'source_inputs',return_value={}):
                path.write_text(json.dumps(before));q.check_pretrial(repo,work,ci,identity)
                crossed=tuple(name for name in EXPECTED_CTESTS if name!='piston_local_window_native_references')
                for names in (EXPECTED_CTESTS[:14],EXPECTED_CTESTS[:-1],crossed,
                              EXPECTED_CTESTS+(EXPECTED_CTESTS[0],),EXPECTED_CTESTS+('extra_test',)):
                    path.write_text(json.dumps({**before,'required_ctests':sorted(names)}))
                    with self.assertRaisesRegex(ValueError,'seventeen exact CTests'):q.check_pretrial(repo,work,ci,identity)

    def test_json_duplicate_fields_and_nonfinite_values_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'record.json'
            for raw in ('{"passed":true,"passed":false}','{"value":NaN}','{"value":Infinity}'):
                path.write_text(raw)
                with self.assertRaises(ValueError):q.load(path)

    def test_exact_records_do_not_equate_bool_int_or_float(self):
        self.assertTrue(q.exact({'authorized':True,'count':1},{'count':1,'authorized':True}))
        for changed in ({'authorized':1,'count':1},{'authorized':True,'count':True},{'authorized':True,'count':1.0}):
            self.assertFalse(q.exact({'authorized':True,'count':1},changed))

    def test_source_gates_require_real_ancestors_and_exact_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            repo=Path(directory);work=repo/'work';work.mkdir()
            good={'schema':'coupled-local-window-player-source-gates-v2','numerics_merge':'a'*40,'delivery_contract_merge':'b'*40,'git_head':'c'*40}
            path=work/'source-gates.json'
            path.write_text(json.dumps(good))
            with patch.object(q.subprocess,'check_output',return_value='c'*40+'\n'),patch.object(q.subprocess,'run',return_value=SimpleNamespace(returncode=0)):
                self.assertEqual(q.check_gates(repo,work),good)
            with patch.object(q.subprocess,'check_output',return_value='d'*40+'\n'),patch.object(q.subprocess,'run',return_value=SimpleNamespace(returncode=0)):
                with self.assertRaises(ValueError):q.check_gates(repo,work)
            with patch.object(q.subprocess,'check_output',return_value='c'*40+'\n'),patch.object(q.subprocess,'run',return_value=SimpleNamespace(returncode=1)):
                with self.assertRaises(ValueError):q.check_gates(repo,work)
            path.write_text(json.dumps({**good,'numerics_merge':'not-yet-merged'}))
            with patch.object(q.subprocess,'check_output',return_value='c'*40+'\n'):
                with self.assertRaises(ValueError):q.check_gates(repo,work)

    def test_closed_bridge_roster_and_hosted_helper_pins(self):
        with tempfile.TemporaryDirectory() as directory:
            repo=Path(directory);work=repo/'.local/player';work.mkdir(parents=True)
            names={'native/godot_bridge/'+name for name in q.GODOT_FILES}|q.WIRE_CODEC_FILES|{'tools/interactive-preview/native-identity.py','tools/ci/coupled-local-window-player.py','tools/ci/test_coupled_local_window_player.py','.local/player/source-gates.json','.github/workflows/coupled-ci.yml'}
            for name in names:
                file=repo/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_text('synthetic source '+name)
            ci=SimpleNamespace(source_inputs=lambda repo:{'.github/workflows/coupled-ci.yml':{'sha256':q.digest(repo/'.github/workflows/coupled-ci.yml'),'bytes':(repo/'.github/workflows/coupled-ci.yml').stat().st_size}})
            identity=SimpleNamespace(ordinary=lambda path,directory=False:path,contained=contained)
            self.assertEqual(set(q.source_inputs(repo,work,ci,identity)),names)
            extra=repo/'native/godot_bridge/extra.cpp';extra.write_text('extra')
            with self.assertRaises(ValueError):q.source_inputs(repo,work,ci,identity)
            extra.unlink()
            missing_wire=repo/'tests/wire_codec/native.cpp';saved_wire=missing_wire.read_bytes();missing_wire.unlink()
            with self.assertRaises(ValueError):q.source_inputs(repo,work,ci,identity)
            missing_wire.write_bytes(saved_wire)
            (repo/'native/godot_bridge/src/interactive_bridge.cpp').unlink()
            with self.assertRaises(ValueError):q.source_inputs(repo,work,ci,identity)

    def measurement_fixture(self,work):
        (work/'evidence/compiled').mkdir(parents=True)
        rows=[]
        for index in range(7):
            name=f'witness-{index}.txt';path=work/'evidence/compiled'/name;path.write_bytes(b'fixture build witness')
            rows.append({'path':name,'bytes':path.stat().st_size,'sha256':q.digest(path)})
        resource=work/'evidence/compiled/native-identity.gd';resource.write_bytes(b'fixture canonical resource\n')
        measurement={'native_identity':{'build_witnesses':rows,'resource':{'build_path':'native-identity.gd','bytes':resource.stat().st_size,'sha256':q.digest(resource)}}}
        q.save(work/'evidence/compile-measurement.json',measurement)
        return measurement,{'fixture_unit':'current'}

    def test_saved_measurement_seven_witnesses_and_raw_resource_cannot_change(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);measurement,unit=self.measurement_fixture(work)
            identity=SimpleNamespace(contained=contained)
            with patch.object(q,'measure',return_value=(measurement,unit)):
                self.assertEqual(q.current_measurement(work,work,None,identity,None),(measurement,unit))
                resource=work/'evidence/compiled/native-identity.gd';resource.write_bytes(b'fixture canonical resource\r\n')
                with self.assertRaises(ValueError):q.current_measurement(work,work,None,identity,None)
                resource.write_bytes(b'fixture canonical resource\n')
                witness=work/'evidence/compiled/witness-3.txt';witness.write_bytes(b'changed')
                with self.assertRaises(ValueError):q.current_measurement(work,work,None,identity,None)
            with patch.object(q,'measure',return_value=({**measurement,'different':True},unit)):
                with self.assertRaises(ValueError):q.current_measurement(work,work,None,identity,None)

    def test_apron_command_and_binary_measurement_changes_are_rejected(self):
        # An isolated measurement-consumer fixture, not a build/measure claim.
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);measurement,unit=self.measurement_fixture(work)
            measurement['ctests']=[{'name':'interactive_apron_starts','command':[
                str(work/'build/bin/interactive_tests.exe'),str(work/'source/native/fdm_jsbsim/models/original-interactive'),
                str(work/'build/interactive-proof/ctest-apron'),'apron',
                str(work/'source/native/fdm_jsbsim/models/original-piston-prop')]}]
            measurement['compiled_binary_roster']={'bin/interactive_tests.exe':{'bytes':19,'sha256':'a'*64}}
            (work/'evidence/compile-measurement.json').write_text(json.dumps(measurement))
            identity=SimpleNamespace(contained=contained)
            with patch.object(q,'measure',return_value=(measurement,unit)):
                self.assertEqual(q.current_measurement(work,work,None,identity,None),(measurement,unit))
            changed=[]
            for index in range(5):
                value=copy.deepcopy(measurement);value['ctests'][0]['command'][index]='changed argument'
                changed.append(value)
            value=copy.deepcopy(measurement);value['compiled_binary_roster']['bin/interactive_tests.exe']['sha256']='b'*64;changed.append(value)
            value=copy.deepcopy(measurement);value['compiled_binary_roster']['bin/interactive_tests.exe']['bytes']=20;changed.append(value)
            for value in changed:
                with patch.object(q,'measure',return_value=(value,unit)),self.assertRaisesRegex(ValueError,'compiled measured inputs changed'):
                    q.current_measurement(work,work,None,identity,None)

    def test_authorization_requires_explicit_approval_and_current_unit_record(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);measurement,unit=self.measurement_fixture(work)
            q.save(work/'unit-execution.json',unit)
            record={'authorized':True,'fixture_physical':True};ci=SimpleNamespace(AUTH_KEYS=set(record))
            with patch.object(q,'current_measurement',return_value=(measurement,unit)),patch.object(q,'physical_record',return_value=record):
                with self.assertRaises(ValueError):q.authorize(work,work,ci,None,None,SimpleNamespace(approve_execution=False))
                self.assertFalse((work/'physical-execution.json').exists())
                q.authorize(work,work,ci,None,None,SimpleNamespace(approve_execution=True))
                proof=q.load(work/'evidence/player-authorization.json')
                self.assertEqual(proof['scope'],q.AUTH_SCOPE)
                self.assertNotIn('compile_review_sha256',proof)
                self.assertEqual(q.load(work/'physical-execution.json'),record)
                self.assertFalse((work/'compile-review.json').exists())
            with patch.object(q,'current_measurement',return_value=(measurement,{'fixture_unit':'changed'})):
                with self.assertRaises(ValueError):q.authorize(work,work,ci,None,None,SimpleNamespace(approve_execution=True))

    def test_postcheck_rejects_changed_authorization_before_receipt_admission(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);measurement,unit=self.measurement_fixture(work)
            q.save(work/'unit-execution.json',unit);q.save(work/'physical-execution.json',{'fixture_physical':True})
            q.save(work/'evidence/player-authorization.json',q.authorization_record(work))
            (work/'physical-execution.json').write_text('{"fixture_physical":false}')
            with patch.object(q,'current_measurement',return_value=(measurement,unit)):
                with self.assertRaisesRegex(ValueError,'authorization evidence changed'):q.verify(work,work,None,None,None)


if __name__=='__main__':unittest.main()
