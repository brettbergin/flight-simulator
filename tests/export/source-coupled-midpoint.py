"""Offline schema3 source-tool fixtures only; never compile or run aircraft code.

Requires a fully verified real upstream acquisition. Four after-images append
only visibly synthetic comments. Every created archive is synthetic evidence,
not the coupled implementation, a production source identity or numerical proof.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import traceback
import zipfile
sys.dont_write_bytecode = True

COMMIT = '3b25f25e49b42d0489c04ac805674fc1450ca579'
ACQUISITION = 'df57467a831cfa3ee3cadcb98d8291ce56bb11976e35dd9e93c94201ff1420d5'
INVENTORY = '083ba0601443c0d24b6641fd04794840cd3054fb7adc98e47f2fb7a1a1048fc5'
VARIANT = 'jsbsim-1.3.1-event-aware-coupled-midpoint-v1'
PREFIX = 'patches/event-aware-coupled-midpoint-v1/'
TARGETS = ('src/models/propulsion/FGPiston.cpp', 'src/models/propulsion/FGPiston.h',
           'src/models/propulsion/FGPropeller.cpp', 'src/models/propulsion/FGPropeller.h')
COMMENT = b'\n// SYNTHETIC SOURCE-TOOL FIXTURE ONLY: no coupled kernel or numerical behavior added.\n'
NOTICE = b'# SYNTHETIC SOURCE-TOOL FIXTURE ONLY\n\nNo coupled implementation, numerical result, production source identity or actual modification attribution is established by this fabricated comment-only transport. The following is the source-tool wrapper under test.\n\n'
APPROVED_SCHEMA3 = {
    'extract-source-schema3.py':'720c381e510f7e82b407d989ac6d0c6cbdee52220574ea0a7f5c3b4164badfa9',
    'source-bundle-schema3.py':'0b1df62cf403687b946dad4d22ae55583255f30f9beb89b77587deb8ee31ccfa',
    'jsbsim-coupled-midpoint/materialize.py':'6774634a5b930bf18dd718e2a63661dfad6f4ca0064de4655ad202cc00722867',
    'jsbsim-coupled-midpoint/verify.py':'7bd0d8daa8c24a5b791359dbfff365218ccacac14ee93bc56561df765933b169',
    'jsbsim-coupled-midpoint/pack.py':'88fa396c2a17b90911daf8b1a7c96198ca461553eab49dc27fe55bf1fa2a62cb',
    'jsbsim-coupled-midpoint/CMakeLists.txt':'3cb349aa8e0db8c5c10e9fded5a0ac6052feae8f9b99b372984fa3f0c94e81a4',
    'jsbsim-coupled-midpoint/BUILD.md':'d5db0dfa422010d78c45dc590f3a57f5c134cbc0ae4a088ef4d30683f1206f76',
    'jsbsim-coupled-midpoint/MODIFICATIONS.md':'e550d82f1ff0dd5b545fd0abc2410e2047edcb5495b7967ba003332da7238035',
}

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2)+'\n', encoding='utf-8', newline='\n')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository-root', type=Path, required=True)
    parser.add_argument('--upstream-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo, upstream, output = map(lambda p:p.resolve(), (args.repository_root,args.upstream_root,args.output))
    assert output.is_relative_to(repo/'.local') and not output.exists(), 'Fresh private .local output required'
    assert not output.is_relative_to(upstream) and not upstream.is_relative_to(output)
    tools = repo/'tools/export/jsbsim-coupled-midpoint'
    old_tools = repo/'tools/export/jsbsim-event-aware'
    # Fail before importing executable helpers if the reviewed source changed.
    for relative,digest in APPROVED_SCHEMA3.items():
        assert sha(repo/'tools/export'/relative)==digest, relative
    # Trusted repository helpers only. Never load any helper from a created ZIP.
    sys.path.insert(0, str(tools))
    m = load('materialize', tools/'materialize.py')
    assert 'materialize' not in sys.modules, 'Run each source variant in a separate interpreter'
    sys.modules['materialize'] = m
    v = load('verify',tools/'verify.py');sys.modules['verify'] = v
    p = load('pack',tools/'pack.py');sys.modules['pack'] = p
    builder = load('fixture_schema3_builder',repo/'tools/export/source-bundle-schema3.py')
    extractor = load('fixture_schema3_extract',repo/'tools/export/extract-source-schema3.py')
    bootstrap = load('fixture_bootstrap',repo/'tools/bootstrap/bootstrap.py')
    assert (m.COMMIT,m.ACQUISITION,m.INVENTORY_SHA,m.VARIANT,m.PREFIX,m.TARGETS)==(COMMIT,ACQUISITION,INVENTORY,VARIANT,PREFIX,TARGETS)
    lock = m.read_json(repo/'third_party/dependencies.lock.json')
    pin = next(row for row in lock['sources'] if row['id']=='jsbsim')
    upstream_receipt = m.read_json(upstream/'.verified.json')
    assert all(upstream_receipt[key]==pin[key] for key in ('id','version','url','sha256'))
    assert pin['sha256']==ACQUISITION
    m.scan(upstream)
    full_tree = bootstrap.tree_digest(upstream)
    assert full_tree==upstream_receipt['tree_sha256'], 'Complete acquisition changed before filtering'
    inventory_path = repo/'tools/export/jsbsim/upstream-file-inventory.json'
    assert sha(inventory_path)==INVENTORY
    inventory = m.read_json(inventory_path)
    assert inventory['upstream_commit']==COMMIT and inventory['acquisition_sha256']==ACQUISITION
    assert inventory['upstream_file_count']==len(inventory['files'])==279
    old_paths = [old_tools/name for name in ('materialize.py','verify.py','pack.py','CMakeLists.txt','BUILD.md','MODIFICATIONS.md')]
    old_paths += [repo/'tools/export/source-bundle-schema2.py',repo/'tools/export/extract-source-schema2.py']
    controls = [tools/name for name in ('materialize.py','verify.py','pack.py','CMakeLists.txt','BUILD.md','MODIFICATIONS.md')]
    controls += [repo/'tools/export/source-bundle-schema3.py',repo/'tools/export/extract-source-schema3.py']
    source_pins = {str(path.relative_to(repo)):sha(path) for path in controls+old_paths}
    m.ancestors(output.parent)
    output.mkdir(parents=True)
    receipt = {'schema_version':1,'scope':'SYNTHETIC SOURCE-TOOL FIXTURES ONLY; no actual coupled source, compiler, reference, engine or numerical outputs',
               'runner_sha256':sha(Path(__file__)),'upstream_tree_sha256':full_tree,'upstream_inventory_sha256':INVENTORY,
               'tool_sha256':source_pins,'groups':[],'rejections':0,'child_invocations':[],'passed':False}
    def save():
        write_json(output/'run-receipt.json',receipt)
    def reject(action, destination=None):
        try:
            action()
        except (ValueError,FileNotFoundError):
            receipt['rejections']+=1
        else:
            raise AssertionError('Invalid fixture unexpectedly accepted')
        if destination is not None:
            assert not destination.exists(), 'Rejection created output'
    def group(name, action):
        row={'name':name,'passed':False};receipt['groups'].append(row)
        try:
            action();row['passed']=True
        except Exception:
            row['error']=traceback.format_exc();save();raise
        save()
    def child(label, arguments):
        result=subprocess.run([sys.executable,*arguments],cwd=output,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                              timeout=90,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        text=result.stdout.decode('utf-8',errors='replace')
        receipt['child_invocations'].append({'label':label,'arguments':arguments,'exit_code':result.returncode,'stdout':text})
        assert result.returncode==0,(label,text)
        return text
    pristine=output/'pristine';patch=output/'synthetic-patch';wrappers=output/'synthetic-wrappers'
    for entry in inventory['files']:
        path=upstream/m.safe(entry['path']);m.regular(path)
        assert path.stat().st_size==entry['bytes'] and sha(path)==entry['sha256']
        dest=pristine/entry['path'];dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,dest)
    baseline=m.scan(pristine)
    assert len(baseline)==279
    patch.mkdir();shutil.copyfile(inventory_path,patch/'upstream-file-inventory.json')
    recipe={'schema_version':1,'patch_kind':'exact-file-replacement-v1','source_bundle_schema':3,'source_variant':VARIANT,
            'upstream_commit':COMMIT,'acquisition_sha256':ACQUISITION,'upstream_inventory_sha256':INVENTORY,
            'materializer':{'bytes':(tools/'materialize.py').stat().st_size,'sha256':sha(tools/'materialize.py')},
            'modifications':{'author':'SYNTHETIC SOURCE-TOOL FIXTURE ONLY','date':'2026-10-09','license':'LGPL-2.1-or-later','method_revision':'event_aware_coupled_midpoint_v1'},'changes':[]}
    for target in TARGETS:
        before=patch/PREFIX/(Path(target).name+'.before');after=patch/'vendor'/target
        before.parent.mkdir(parents=True,exist_ok=True);after.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(pristine/target,before);after.write_bytes(before.read_bytes()+COMMENT)
        recipe['changes'].append({'path':target,'before':{'member':before.relative_to(patch).as_posix(),'bytes':before.stat().st_size,'sha256':sha(before)},
                                  'after':{'member':after.relative_to(patch).as_posix(),'bytes':after.stat().st_size,'sha256':sha(after)}})
    recipe_path=patch/PREFIX/'recipe.json';write_json(recipe_path,recipe);recipe_pin=sha(recipe_path)
    wrappers.mkdir()
    for name in ('CMakeLists.txt','BUILD.md','MODIFICATIONS.md','materialize.py','verify.py','pack.py'):
        shutil.copyfile(tools/name,wrappers/name)
    for name in ('BUILD.md','MODIFICATIONS.md'):
        f=wrappers/name;f.write_bytes(NOTICE+f.read_bytes())
    license_file=output/'LICENSE.first-party.txt'
    license_file.write_text((repo/'LICENSE').read_text(encoding='utf-8'),encoding='utf-8',newline='\n')
    bundle=output/'synthetic-schema3-bundle';archive=bundle/(VARIANT+'-library-source.zip')
    def success():
        result=builder.create(pristine,patch,wrappers,license_file,bundle,recipe_pin)
        assert result['repeat_matches'] and sha(archive)==sha(bundle/'source-repeat.zip')
        checked=result['source_verification']
        assert (checked['schema_version'],checked['bundle_files'],checked['vendor_files'],checked['unchanged_vendor_files'],checked['modified_vendor_files'])==(3,293,279,275,4)
        assert checked['provenance_reconstructed']
        assert m.scan(pristine)==baseline
        supplied=m.scan(bundle/'source/vendor')
        assert len(supplied)==279 and {k for k in baseline if baseline[k]!=supplied[k]}==set(TARGETS)
        for target in TARGETS:assert (bundle/'source/vendor'/target).read_bytes()==(pristine/target).read_bytes()+COMMENT
        dest=output/'synthetic-extraction';extracted=extractor.extract(archive,sha(archive),dest)
        assert extracted==checked and m.scan(dest)==m.scan(bundle/'source')
        receipt['synthetic_archive']={'sha256':sha(archive),'bytes':archive.stat().st_size,'members':293,'not_production_source':True}
    group('four-file provenance, deterministic293 archive and trusted extraction',success)
    def recipes():
        mutations=[lambda x:x.update(source_bundle_schema=2),lambda x:x.update(source_variant='jsbsim-1.3.1-event-aware-constant-power-v1'),
                   lambda x:x['changes'].pop(),lambda x:x['changes'].append(copy.deepcopy(x['changes'][0])),lambda x:x['changes'].reverse(),
                   lambda x:x['changes'][0].update(path='../FGPiston.cpp'),lambda x:x['materializer'].update(sha256='0'*64),
                   lambda x:x['changes'][0]['before'].update(sha256='0'*64),lambda x:x['changes'][0]['after'].update(sha256='0'*64),
                   lambda x:x['changes'][0]['before'].update(member='vendor/'+TARGETS[0]),lambda x:x['modifications'].update(method_revision='legacy_euler'),
                   lambda x:x.update(unexpected=True),lambda x:x['modifications'].update(date='2026-99-99')]
        for index,mutate in enumerate(mutations):
            value=copy.deepcopy(recipe);mutate(value);write_json(recipe_path,value)
            dest=output/f'rejected-recipe-{index}';reject(lambda:m.materialize(pristine,patch,dest,sha(recipe_path)),dest)
        write_json(recipe_path,recipe)
        dest=output/'rejected-recipe-pin';reject(lambda:m.materialize(pristine,patch,dest,'0'*64),dest)
    group('closed schema, variant, target roster, recipe and materializer pins reject before output',recipes)
    def source_mutants():
        targets=[patch/PREFIX/(Path(TARGETS[0]).name+'.before'),patch/'vendor'/TARGETS[0],pristine/TARGETS[0]]
        for index,path in enumerate(targets):
            raw=path.read_bytes()
            try:
                path.write_bytes(raw+b'corrupt');dest=output/f'rejected-source-{index}'
                reject(lambda:m.materialize(pristine,patch,dest,recipe_pin),dest)
            finally:path.write_bytes(raw)
        for index,path in enumerate([patch/'vendor/extra.cpp',pristine/'extra.cpp']):
            try:
                path.write_bytes(COMMENT);dest=output/f'rejected-extra-{index}'
                reject(lambda:m.materialize(pristine,patch,dest,recipe_pin),dest)
            finally:path.unlink()
        missing=patch/PREFIX/(Path(TARGETS[1]).name+'.before');raw=missing.read_bytes()
        try:
            missing.unlink();dest=output/'rejected-missing-before';reject(lambda:m.materialize(pristine,patch,dest,recipe_pin),dest)
        finally:missing.write_bytes(raw)
    group('actual pristine, before-image, after-image and extra-file corruption',source_mutants)
    def manifest_mutants():
        source=output/'mutant-bundle';shutil.copytree(bundle/'source',source)
        manifest=source/'manifest.json';original_manifest=manifest.read_bytes()
        for index,name in enumerate(['vendor/'+TARGETS[0],PREFIX+Path(TARGETS[0]).name+'.before','vendor/src/FGFDMExec.cpp']):
            path=source/name;raw=path.read_bytes()
            try:
                path.write_bytes(raw+COMMENT);value=m.read_json(manifest);value['files']=[e for k,e in m.scan(source).items() if k!='manifest.json'];write_json(manifest,value)
                reject(lambda:v.verify(source))
            finally:path.write_bytes(raw);manifest.write_bytes(original_manifest)
        value=m.read_json(manifest);value['schema_version']=2;write_json(manifest,value);reject(lambda:v.verify(source));manifest.write_bytes(original_manifest)
        extra=source/'vendor/extra.cpp';extra.write_bytes(COMMENT);reject(lambda:v.verify(source));extra.unlink()
        assert v.verify(source)==v.verify(bundle/'source')
    group('rehashing manifest cannot hide provenance/closure corruption',manifest_mutants)
    def root_guards():
        dest=output/'materialized-once';m.materialize(pristine,patch,dest,recipe_pin)
        reject(lambda:m.materialize(pristine,patch,dest,recipe_pin))
        reject(lambda:m.materialize(pristine,patch,pristine/'nested',recipe_pin),pristine/'nested')
        reject(lambda:m.materialize(pristine,patch,patch/'nested',recipe_pin),patch/'nested')
        reject(lambda:extractor.extract(archive,sha(archive),dest))
        reject(lambda:p.pack(bundle/'source',archive))
        for name in ('../escape','a/../b','/root','C:/file','a\\b','a//b','a/./b','NUL.txt','a./b','a /b','AUX.cpp','a\t.cpp','a\n.cpp','a\x7f.cpp','a*.cpp'):
            reject(lambda name=name:m.safe(name))
        # A direct hard link must not masquerade as an independent source file.
        import os
        link=pristine/'hardlink.cpp'
        try:
            os.link(pristine/TARGETS[0],link);reject(lambda:m.scan(pristine))
        finally:
            if link.exists():link.unlink()
        raw=recipe_path.read_bytes()
        try:
            recipe_path.write_bytes(b'{"schema_version":1,"schema_version":1}');reject(lambda:m.read_json(recipe_path))
        finally:recipe_path.write_bytes(raw)
    group('unsafe names, hardlinks, duplicateJSON, reused/overlapping roots',root_guards)
    def archives():
        dest=output/'bad-pin';reject(lambda:extractor.extract(archive,'0'*64,dest),dest)
        with zipfile.ZipFile(archive) as z:members=[(copy.copy(i),z.read(i)) for i in z.infolist()]
        changes=[lambda a:setattr(a[0][0],'filename','../escape'),lambda a:setattr(a[0][0],'filename',a[1][0].filename.upper()),
                 lambda a:setattr(a[0][0],'filename',a[1][0].filename),lambda a:setattr(a[0][0],'extra',b'\x01\x00\x00\x00'),
                 lambda a:setattr(a[0][0],'comment',b'unknown'),lambda a:setattr(a[0][0],'date_time',(2001,1,1,0,0,0)),
                 lambda a:setattr(a[0][0],'external_attr',0o120777<<16),lambda a:setattr(a[0][0],'compress_type',zipfile.ZIP_DEFLATED),
                 lambda a:a.pop(),lambda a:setattr(a[0][0],'filename','NUL.cpp')]
        for index,change in enumerate(changes):
            mutant=[(copy.copy(i),data) for i,data in members];change(mutant);mutant.sort(key=lambda row:row[0].filename)
            bad=output/f'unsafe-{index}.zip'
            with zipfile.ZipFile(bad,'x') as z:
                for info,data in mutant:z.writestr(info,data)
            dest=output/f'unsafe-destination-{index}';reject(lambda:extractor.extract(bad,sha(bad),dest),dest)
    group('unsafe aliases and unsupportedZIP metadata fail before extraction',archives)
    def cached_imports():
        code='''import importlib,importlib.util,pathlib,sys
sys.dont_write_bytecode=True
sys.path.insert(0,sys.argv[1]);importlib.import_module(sys.argv[2])
s=importlib.util.spec_from_file_location("newvariant_cli",sys.argv[3]);m=importlib.util.module_from_spec(s)
try:s.loader.exec_module(m)
except ValueError as e:
 assert "separate interpreter" in str(e);print("CACHED_OTHER_VARIANT_REJECTED")
else:raise AssertionError("cached other-variant helper accepted")
'''
        for helper in ('materialize','verify','pack'):
            for dispatcher in ('source-bundle-schema3.py','extract-source-schema3.py'):
                text=child('cached-'+helper+'-'+dispatcher,['-c',code,str(old_tools),helper,str(repo/'tools/export'/dispatcher)])
                assert 'CACHED_OTHER_VARIANT_REJECTED' in text
    group('cross-variant cached helper imports rejected by both public dispatchers',cached_imports)
    def historical():
        old_patch=output/'synthetic-schema2-patch';old_patch.mkdir();shutil.copyfile(inventory_path,old_patch/'upstream-file-inventory.json')
        value=copy.deepcopy(recipe);value.update(source_bundle_schema=2,source_variant='jsbsim-1.3.1-event-aware-constant-power-v1')
        value['materializer']={'bytes':(old_tools/'materialize.py').stat().st_size,'sha256':sha(old_tools/'materialize.py')}
        value['modifications']['method_revision']='event_aware_constant_power_v1';value['changes']=[]
        prefix='patches/event-aware-constant-power-v1/'
        for target in TARGETS[2:]:
            before=old_patch/prefix/(Path(target).name+'.before');after=old_patch/'vendor'/target
            before.parent.mkdir(parents=True,exist_ok=True);after.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(pristine/target,before);after.write_bytes(before.read_bytes()+COMMENT)
            value['changes'].append({'path':target,'before':{'member':before.relative_to(old_patch).as_posix(),'bytes':before.stat().st_size,'sha256':sha(before)},'after':{'member':after.relative_to(old_patch).as_posix(),'bytes':after.stat().st_size,'sha256':sha(after)}})
        recipe2=old_patch/prefix/'recipe.json';write_json(recipe2,value)
        old_out=output/'synthetic-schema2-bundle'
        text=child('historical-schema2-build',[str(repo/'tools/export/source-bundle-schema2.py'),'--pristine',str(pristine),'--patch-root',str(old_patch),'--wrappers',str(old_tools),'--license-file',str(license_file),'--output',str(old_out),'--recipe-sha256',sha(recipe2)])
        result=json.loads(text);assert result['source_verification']['bundle_files']==291 and result['source_verification']['modified_vendor_files']==2
        old_zip=old_out/'jsbsim-1.3.1-event-aware-constant-power-v1-library-source.zip'
        text=child('historical-schema2-extract',[str(repo/'tools/export/extract-source-schema2.py'),'--archive',str(old_zip),'--sha256',sha(old_zip),'--destination',str(output/'historical-extraction')])
        assert json.loads(text)['unchanged_vendor_files']==277
        dest=output/'schema2-rejected-by-schema3';reject(lambda:extractor.extract(old_zip,sha(old_zip),dest),dest)
    group('historical schema2 isolated source-only route remains separate and unchanged',historical)
    assert m.scan(pristine)==baseline
    assert bootstrap.tree_digest(upstream)==full_tree and m.read_json(upstream/'.verified.json')==upstream_receipt
    assert all(sha(repo/name)==digest for name,digest in source_pins.items())
    assert len(receipt['groups'])==8 and all(x['passed'] for x in receipt['groups'])
    receipt.update(passed=True,actual_upstream_and_all_tool_inputs_unchanged=True,no_compiler_engine_reference_or_numerical_execution=True)
    save();print('SYNTHETIC_COUPLED_SOURCE_TOOLS_PASSED')

if __name__=='__main__':
    main()
