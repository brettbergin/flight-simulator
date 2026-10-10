"""PROPOSED checked JSBSim source selection; source-only, no compiler invocation."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile
sys.dont_write_bytecode = True

def require(condition, message):
    if not condition:
        raise ValueError(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def context(repository):
    repository = Path(repository).resolve()
    tools = repository / 'tools/export/jsbsim-event-aware'
    sys.path.insert(0, str(tools))
    import materialize
    import verify
    identity_file = repository / 'third_party/patches/jsbsim/event-aware-constant-power-v1/identity.json'
    identity = materialize.read_json(identity_file)
    materialize.closed(identity, ('schema_version', 'source_variant', 'upstream_commit',
        'acquisition_sha256', 'upstream_inventory_sha256', 'recipe_sha256',
        'materializer_sha256', 'vendor_tree_sha256', 'source_archive_sha256',
        'source_archive_bytes', 'bundle_files', 'vendor_files', 'modified_vendor_files', 'changes'))
    require(type(identity['schema_version']) is int and identity['schema_version'] == 1 and
        identity['source_variant'] == materialize.VARIANT and
        identity['upstream_commit'] == materialize.COMMIT and
        identity['acquisition_sha256'] == materialize.ACQUISITION and
        identity['upstream_inventory_sha256'] == materialize.INVENTORY_SHA and
        identity['bundle_files'] == 291 and identity['vendor_files'] == 279 and
        identity['modified_vendor_files'] == 2, 'Unsupported reviewed source identity')
    for name in ('recipe_sha256', 'materializer_sha256', 'vendor_tree_sha256', 'source_archive_sha256'):
        require(type(identity[name]) is str and materialize.HASH.fullmatch(identity[name]),
                'Malformed reviewed source digest')
    require(type(identity['source_archive_bytes']) is int and 0 < identity['source_archive_bytes'] < 16 * 1024 * 1024,
            'Malformed reviewed source archive size')
    require(sha(tools / 'materialize.py') == identity['materializer_sha256'],
            'Trusted materializer differs from reviewed identity')
    return repository, identity_file, identity, materialize, verify

def fingerprint(identity):
    return hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(',', ':')).encode('utf-8')).hexdigest()

def upstream(repository, source_root):
    repository, identity_file, identity, materialize, _ = context(repository)
    source_root = Path(source_root).resolve()
    receipt_file = source_root / '.verified.json'
    materialize.regular(receipt_file)
    receipt = materialize.read_json(receipt_file)
    require(receipt['sha256'] == identity['acquisition_sha256'], 'Unverified pristine acquisition')
    # Verify every acquired file, not merely the library's filtered subset.
    materialize.scan(source_root)
    bootstrap = load('source_variant_bootstrap', repository / 'tools/bootstrap/bootstrap.py')
    require(bootstrap.tree_digest(source_root) == receipt['tree_sha256'], 'Complete pristine acquisition changed')
    inventory_file = repository / 'tools/export/jsbsim/upstream-file-inventory.json'
    require(sha(inventory_file) == identity['upstream_inventory_sha256'], 'Pristine library inventory changed')
    inventory = materialize.read_json(inventory_file)
    require(inventory['upstream_file_count'] == len(inventory['files']) == 279, 'Wrong pristine library closure')
    expected = {}
    for entry in inventory['files']:
        name = materialize.safe(entry['path'])
        path = source_root / name
        require(path.stat().st_size == entry['bytes'] and sha(path) == entry['sha256'],
                'Pristine library file mismatch')
        expected[name] = entry
    backend = {'schema_version': 1, 'source_variant': 'jsbsim-1.3.1-upstream',
        'upstream_commit': identity['upstream_commit'], 'acquisition_sha256': identity['acquisition_sha256'],
        'upstream_inventory_sha256': identity['upstream_inventory_sha256'],
        'vendor_tree_sha256': materialize.digest_inventory(expected)}
    return {'source_root': str(source_root), 'source_variant': backend['source_variant'],
        'backend_identity_sha256': fingerprint(backend), 'backend_identity': backend}, inventory

def event_aware(repository, source_root):
    repository, identity_file, identity, materialize, verifier = context(repository)
    source_root = Path(source_root).resolve()
    require(source_root.name == 'vendor', 'Patched source root must be a complete bundle vendor directory')
    bundle = source_root.parent
    snapshot = materialize.scan(bundle)
    require(len(snapshot) == identity['bundle_files'], 'Wrong complete source member count')
    require(sum(entry['bytes'] for entry in snapshot.values()) < 16 * 1024 * 1024, 'Oversized source closure')
    # Reconstruct the canonical archive in memory: the immutable external pin
    # covers manifest, wrappers and every source byte, preventing a self-
    # consistent altered manifest/recipe from being accepted as reviewed source.
    memory = io.BytesIO()
    with zipfile.ZipFile(memory, 'w', compression=zipfile.ZIP_STORED) as archive:
        for name in snapshot:
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            entry.compress_type = zipfile.ZIP_STORED
            archive.writestr(entry, (bundle / name).read_bytes())
    archive_bytes = memory.getvalue()
    require(len(archive_bytes) == identity['source_archive_bytes'] and
        hashlib.sha256(archive_bytes).hexdigest() == identity['source_archive_sha256'],
        'Complete source differs from reviewed archive identity')
    manifest = materialize.read_json(bundle / 'manifest.json')
    require(manifest['recipe_sha256'] == identity['recipe_sha256'], 'Wrong reviewed recipe')
    recipe_file = bundle / materialize.PREFIX / 'recipe.json'
    require(sha(recipe_file) == identity['recipe_sha256'], 'Recipe digest differs from reviewed identity')
    recipe = materialize.read_json(recipe_file)
    require(recipe['changes'] == identity['changes'] and
            recipe['materializer']['sha256'] == identity['materializer_sha256'],
            'Reviewed replacement/materializer identity mismatch')
    verification = verifier.verify(bundle)
    require(verification['vendor_tree_sha256'] == identity['vendor_tree_sha256'] and
            verification['materializer_sha256'] == identity['materializer_sha256'] and
            verification['recipe_sha256'] == identity['recipe_sha256'], 'Verified source identity mismatch')
    require(materialize.scan(bundle) == snapshot, 'Source changed during selection')
    backend = {'schema_version': 1, 'identity_file_sha256': sha(identity_file),
               'identity': identity, 'verification': verification}
    return {'source_root': str(source_root), 'source_variant': identity['source_variant'],
        'backend_identity_sha256': fingerprint(backend), 'backend_identity': backend}

def prepare(repository, source_root, output):
    repository, _, identity, materialize, _ = context(repository)
    _, inventory = upstream(repository, source_root)
    source_root, output = Path(source_root).resolve(), Path(output)
    materialize.ancestors(output.parent)
    require(not output.exists() and not output.is_symlink(), 'Refuse reused source preparation output')
    require(not output.resolve().is_relative_to(source_root) and
            not source_root.is_relative_to(output.resolve()), 'Overlapping source preparation roots')
    transport = repository / 'third_party/patches/jsbsim/event-aware-constant-power-v1'
    require(sha(transport / materialize.PREFIX / 'recipe.json') == identity['recipe_sha256'],
            'Public transport recipe changed')
    builder = load('source_variant_builder', repository / 'tools/export/source-bundle-schema2.py')
    with tempfile.TemporaryDirectory(prefix='jsbsim-pristine-selection-', dir=output.parent) as temporary:
        pristine = Path(temporary) / 'pristine'
        for entry in inventory['files']:
            destination = pristine / entry['path']
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source_root / entry['path'], destination)
        # The committed MIT notice is canonical LF; the owner's Windows Git
        # checkout currently stores LICENSE as CRLF. Never let checkout EOL
        # change the already reviewed source archive's actual byte identity.
        license_file = Path(temporary) / 'LICENSE.first-party.txt'
        license_file.write_text((repository / 'LICENSE').read_text(encoding='utf-8'),
                                encoding='utf-8', newline='\n')
        result = builder.create(pristine, transport, repository / 'tools/export/jsbsim-event-aware',
                                license_file, output, identity['recipe_sha256'])
    require(result['source_archive_sha256'] == identity['source_archive_sha256'] and
            result['source_archive_bytes'] == identity['source_archive_bytes'],
            'Produced source archive differs from reviewed identity')
    # Reverify full pristine acquisition and complete new source independently.
    upstream(repository, source_root)
    return event_aware(repository, output / 'source/vendor')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--event-aware', action='store_true')
    parser.add_argument('--prepare', type=Path, metavar='FRESH_OUTPUT')
    args = parser.parse_args()
    require(not (args.event_aware and args.prepare), 'Select validation or preparation, not both')
    result = prepare(args.repository_root, args.source_root, args.prepare) if args.prepare else (
        event_aware(args.repository_root, args.source_root) if args.event_aware else
        upstream(args.repository_root, args.source_root)[0])
    print(json.dumps(result, sort_keys=True))
