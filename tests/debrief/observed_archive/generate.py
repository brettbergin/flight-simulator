"""Original MIT: readonly verification of independently frozen ADR012 references."""
import hashlib,json,pathlib,runpy,tempfile
HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REFERENCE=HERE/'reference'
def sha(b): return hashlib.sha256(b).hexdigest()
def main():
    bit=runpy.run_path(str(HERE/'preparation/generate-binary64-original.py'))
    generated=(json.dumps(bit['generate'](),indent=2)+'\n').encode('utf8')
    assert generated==(REFERENCE/'expected-binary64-v1.json').read_bytes()
    module=runpy.run_path(str(HERE/'preparation/generate-archive-original.py'))
    with tempfile.TemporaryDirectory(prefix='flight-archive-reference-') as scratch:
        module['generate'].__globals__['ROOT']=ROOT
        module['generate'].__globals__['HERE']=pathlib.Path(scratch)
        module['generate']()
        emitted={p.name for p in pathlib.Path(scratch).iterdir()}
        expected={p.name for p in REFERENCE.iterdir() if p.name!='expected-binary64-v1.json'}
        expected.discard('nul-input.bin');expected.add('nul.bin')
        assert emitted==expected
        for name in emitted:
            published='nul-input.bin' if name=='nul.bin' else name
            assert (pathlib.Path(scratch)/name).read_bytes()==(REFERENCE/published).read_bytes(),name
    manifest=json.loads((REFERENCE/'expected-text-v1.json').read_bytes())
    for case in manifest['positives']+manifest['negatives']:
        published='nul-input.bin' if case['file']=='nul.bin' else case['file']
        assert sha((REFERENCE/published).read_bytes())==case['sha256']
    print(json.dumps({'readonly':True,'bit_cases':26,'archive_positive':8,'archive_negative':32,'archive_manifest_sha256':sha((REFERENCE/'expected-text-v1.json').read_bytes()),'bit_manifest_sha256':sha(generated)}))
if __name__=='__main__':main()
