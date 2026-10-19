"""Offline pinned authoring environment. Enter through bootstrap.ps1, not PATH Python.

No third-party import occurs in creation or before installed-input verification.
Private parser functions accept synthetic inputs in unit tests; production pins do not.
"""
from __future__ import annotations

import argparse
import base64
import csv
import ctypes
import email.parser
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import sqlite3
import stat
import struct
import subprocess
import sys
import time
import traceback
import zipfile

# -I -S deliberately excludes the script directory and all site processing.
SOURCE = Path(__file__).absolute().parent
sys.path.insert(0, str(SOURCE))
from terrain_pins import (EXPECTED_LOCK, RASTER, PROJ_PREFIX, PROJ_DLL,
                          MAX_WHEEL_FILES, MAX_WHEEL_MEMBER, MAX_WHEEL_EXPANDED, MAX_INSTALLED_BYTES,
                          MAX_QUALIFY_SECONDS, MAX_PEAK_WORKING_SET)
sys.path.pop(0)


class Refusal(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise Refusal(message)


def strict_json(raw, limit=65536):
    require(type(raw) is bytes and len(raw) <= limit and not raw.startswith(b'\xef\xbb\xbf'), 'JSON size/BOM/type')
    def pairs(items):
        obj = {}
        for key, value in items:
            require(key not in obj, 'duplicate JSON key')
            obj[key] = value
        return obj
    def invalid(value):
        raise Refusal('nonfinite JSON number: ' + value)
    return json.loads(raw.decode('utf-8', errors='strict'), object_pairs_hook=pairs, parse_constant=invalid)


def exact(actual, expected, label='value'):
    require(type(actual) is type(expected), label + ': type')
    if isinstance(expected, dict):
        require(actual.keys() == expected.keys(), label + ': keys')
        for key in expected:
            exact(actual[key], expected[key], label + '.' + key)
    elif isinstance(expected, list):
        require(len(actual) == len(expected), label + ': length')
        for index, value in enumerate(expected):
            exact(actual[index], value, label + '[' + str(index) + ']')
    else:
        require(actual == expected, label + ': pin')


def lock_file(path):
    raw = plain(path).read_bytes()
    lock = strict_json(raw)
    exact(lock, EXPECTED_LOCK, 'lock')
    return lock, hashlib.sha256(raw).hexdigest()


def member_name(name):
    require(type(name) is str and name and len(name) <= 240 and name.isascii(), 'member name')
    require('\\' not in name and ':' not in name and not name.startswith('/'), 'unsafe member path')
    parts = name.split('/')
    for part in parts:
        require(part not in ('', '.', '..') and part == part.rstrip(' .'), 'unsafe path component')
        require(not re.search(r'[<>"|?*\x00-\x1f\x7f]', part), 'Windows path character')
        require(part.split('.')[0].upper() not in {'CON', 'PRN', 'AUX', 'NUL', 'CLOCK$', *(f'COM{i}' for i in range(1, 10)), *(f'LPT{i}' for i in range(1, 10))}, 'Windows device name')
    return name


def plain(path):
    path = Path(path)
    require(path.is_absolute(), 'absolute path required')
    require(not str(path).startswith('\\\\'), 'UNC path refused')
    require(all(':' not in part for part in path.parts[1:]), 'alternate data stream refused')
    path = Path(os.path.abspath(path))
    for item in (path, *path.parents):
        try:
            info = item.lstat()
        except FileNotFoundError:
            continue
        require(not stat.S_ISLNK(info.st_mode) and not (getattr(info, 'st_file_attributes', 0) & 0x400), 'reparse path: ' + str(item))
        require(stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode), 'special file')
        if stat.S_ISREG(info.st_mode):
            require(info.st_nlink == 1, 'hard-linked file refused')
    return path


def within(path, root):
    return Path(path).is_relative_to(Path(root))


def output_path(path):
    path = plain(path)
    local = SOURCE.parents[2] / '.local'
    require(path != local and within(path, local), 'output must be below checkout .local')
    return path


def digest(path):
    path = plain(path)
    result = hashlib.sha256()
    count = 0
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            result.update(chunk)
            count += len(chunk)
    return {'bytes': count, 'sha256': result.hexdigest()}


def pinned(path, pin):
    actual = digest(path)
    exact(actual, {key: pin[key] for key in ('bytes', 'sha256')}, str(path))
    return actual


def write_json(path, value):
    path = plain(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, indent=2, ensure_ascii=True, allow_nan=False)
        stream.write('\n')


def tree(root):
    root = plain(root)
    require(root.is_dir(), 'tree root missing')
    files, directories, keys = [], [], set()
    todo = [root]
    while todo:
        folder = todo.pop()
        for path in sorted(folder.iterdir()):
            plain(path)
            rel = member_name(path.relative_to(root).as_posix())
            key = rel.casefold()
            require(key not in keys, 'case-alias tree member')
            keys.add(key)
            require(len(keys) <= 30000, 'tree member budget')
            if path.is_dir():
                directories.append(rel)
                todo.append(path)
            else:
                files.append({'path': rel, **digest(path)})
    return {'files': sorted(files, key=lambda r: r['path']), 'directories': sorted(directories)}


def directory_closure(files, directories=()):
    result = set(directories)
    for row in files:
        parent = PurePosixPath(row['path']).parent
        while str(parent) != '.':
            result.add(parent.as_posix())
            parent = parent.parent
    return sorted(result)


def baseline_manifest(path, baseline):
    host = EXPECTED_LOCK['host']
    require(digest(path)['sha256'] == host['frozen_runtime_manifest_sha256'], 'baseline manifest pin')
    manifest = strict_json(plain(path).read_bytes(), 16 * 1024 * 1024)
    require(manifest['schema'] == 'RootFrozenInstalledPythonToolRuntime/v1' and manifest['source_and_copy_raw_exact'] is True, 'baseline provenance')
    base = plain(baseline).parent
    require(os.path.normcase(str(base)) == os.path.normcase(manifest['frozen_root']), 'wrong baseline root')
    expected = {'files': sorted(manifest['files'], key=lambda r: r['path']), 'directories': sorted(manifest['directories'])}
    require(tree(base) == expected, 'baseline complete inventory drift')
    pinned(baseline, {'bytes': host['python_executable_bytes'], 'sha256': host['python_executable_sha256']})
    for filename, key in [('python312.dll', 'python312_dll_sha256'), ('LICENSE.txt', 'python_license_sha256')]:
        require(digest(base / filename)['sha256'] == host[key], 'baseline core pin: ' + filename)
    return manifest


def wheel_roster(archive):
    infos = archive.infolist()
    require(0 < len(infos) <= MAX_WHEEL_FILES, 'wheel entry budget')
    names, directories, folded, spellings, total = {}, [], set(), {}, 0
    for info in infos:
        is_directory = info.is_dir()
        # Exactly one trailing separator denotes a ZIP directory; strip it
        # before applying the same canonical Windows component rules as files.
        name = member_name(info.filename[:-1] if is_directory else info.filename)
        require(name.casefold() not in folded, 'duplicate/alias/file-directory ZIP member')
        parts = name.split('/')
        for depth in range(1, len(parts) + 1):
            prefix = '/'.join(parts[:depth])
            require(spellings.setdefault(prefix.casefold(), prefix) == prefix, 'case-alias ZIP directory spelling')
        mode = info.external_attr >> 16
        require(stat.S_IFMT(mode) in ((0, stat.S_IFDIR) if is_directory else (0, stat.S_IFREG)), 'ZIP special/member-kind mismatch')
        require(not info.flag_bits & 1 and info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), 'ZIP encryption/compression')
        require(0 <= info.file_size <= MAX_WHEEL_MEMBER and info.file_size <= max(1024, info.compress_size * 1000), 'ZIP expansion/member budget')
        total += info.file_size
        require(total <= MAX_WHEEL_EXPANDED, 'ZIP expanded total budget')
        directory_parts = parts if is_directory else parts[:-1]
        require(not name.lower().endswith(('.pth', '.exe', '.bat', '.cmd', '.ps1')) and not any(part.endswith('.data') for part in directory_parts), 'unsupported executable/install layout')
        if is_directory:
            require(info.file_size == 0 and info.CRC == 0 and archive.read(info) == b'', 'ZIP directory must have zero payload')
            directories.append(name)
        else:
            names[name] = info
        folded.add(name.casefold())
    # A file cannot also be an ancestor directory of another file.
    file_names = {name.casefold() for name in names}
    for name in [*names, *directories]:
        for parent in PurePosixPath(name).parents:
            require(str(parent).casefold() not in file_names, 'ZIP file/directory collision')
    return names, sorted(directories)


def record_rows(raw, names, record_name):
    require(len(raw) <= 2 * 1024 * 1024, 'RECORD budget')
    result = {}
    for row in csv.reader(io.StringIO(raw.decode('utf-8', errors='strict'), newline='')):
        require(len(row) == 3, 'RECORD columns')
        name, hashed, size = row
        member_name(name)
        require(name in names and name not in result, 'RECORD member/duplicate')
        if name == record_name:
            require(hashed == size == '', 'RECORD self fields')
            result[name] = None
            continue
        require(re.fullmatch(r'sha256=[A-Za-z0-9_-]{43}', hashed) is not None and re.fullmatch(r'0|[1-9][0-9]*', size) is not None, 'RECORD SHA/size')
        decoded = base64.urlsafe_b64decode(hashed[7:] + '=')
        require(base64.urlsafe_b64encode(decoded).decode().rstrip('=') == hashed[7:], 'RECORD noncanonical hash')
        result[name] = {'bytes': int(size), 'sha256': decoded.hex()}
    require(result.keys() == names.keys(), 'RECORD exact archive roster')
    return result


def inspect_wheel(path, wheel, raw_inventory):
    pinned(path, wheel)
    dist = wheel['name'] + '-' + wheel['version'] + '.dist-info'
    allowed = {wheel['name'], dist}
    if wheel['name'] == 'pillow':
        allowed = {'PIL', 'pillow.libs', dist}
    elif wheel['name'] == 'pyproj':
        allowed.add('pyproj.libs')
    with zipfile.ZipFile(path) as archive:
        names, explicit_directories = wheel_roster(archive)
        require(all(name.split('/')[0] in allowed for name in [*names, *explicit_directories]), 'wheel unexpected top-level package')
        record_name = dist + '/RECORD'
        records = record_rows(archive.read(record_name), names, record_name)
        rows = []
        for name, info in names.items():
            raw = archive.read(info)
            row = {'member': name, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}
            if records[name] is not None:
                exact({key: row[key] for key in ('bytes', 'sha256')}, records[name], 'RECORD ' + name)
            rows.append(row)
        meta = email.parser.BytesParser().parsebytes(archive.read(dist + '/METADATA'))
        require(meta['Name'].casefold() == wheel['name'] and meta['Version'] == wheel['version'], 'wheel metadata identity')
        mandatory = [item for item in meta.get_all('Requires-Dist', []) if ';' not in item]
        require(mandatory == (['certifi'] if wheel['name'] == 'pyproj' else []), 'mandatory dependency roster')
        require(all('extra ==' in item for item in meta.get_all('Requires-Dist', []) if ';' in item), 'unreviewed conditional runtime dependency')
        headers = email.parser.BytesParser().parsebytes(archive.read(dist + '/WHEEL'))
        require(headers['Wheel-Version'] == '1.0' and headers.get_all('Tag') == (['py3-none-any'] if wheel['name'] == 'certifi' else ['cp312-cp312-win_amd64']), 'wheel ABI')
        require(headers['Root-Is-Purelib'] == ('true' if wheel['name'] == 'certifi' else 'false'), 'wheel install scheme')
    row_map = {row['member']: row for row in rows}
    natives = [row for row in rows if row['member'].lower().endswith(('.pyd', '.dll'))]
    exact(sorted(natives, key=lambda r: r['member']), sorted(raw_inventory['native_binaries'], key=lambda r: r['member']), 'native inventory')
    for row in raw_inventory['metadata']:
        exact(row_map[row['member']], row, 'retained metadata/license/database')
    require(len(natives) == EXPECTED_LOCK['raw_wheel_inventory']['native_binary_counts'][wheel['name']], 'native binary count')
    require(meta.get_all('License-File'), 'license notices required')
    for notice in meta.get_all('License-File'):
        require(dist + '/licenses/' + member_name(notice) in names, 'missing license notice')
    return sorted(rows, key=lambda r: r['member']), explicit_directories


def source_plan(args):
    lock, lock_hash = lock_file(SOURCE / 'tools-v1.lock.json')
    manifest = baseline_manifest(args.runtime_manifest, args.baseline)
    inputs = plain(args.inputs)
    require(inputs.is_dir(), 'input directory missing')
    raw_pin = lock['raw_wheel_inventory']
    inventory_path = inputs / 'wheel-inspection' / 'inventory.json'
    pinned(inventory_path, raw_pin)
    inventory = strict_json(inventory_path.read_bytes(), 65536)
    by_name = {row['filename']: row for row in inventory['wheels']}
    require(len(by_name) == 3 and set(by_name) == {row['filename'] for row in lock['wheels']}, 'raw inventory wheel roster')
    rows, mappings, explicit_directory_mappings, acquisitions = [], [], [], []
    for entry in manifest['files']:
        if entry['path'] != 'Lib/site-packages' and not entry['path'].startswith('Lib/site-packages/'):
            rows.append({'path': 'environment/' + entry['path'], 'bytes': entry['bytes'], 'sha256': entry['sha256']})
    directories = ['environment'] + ['environment/' + name for name in manifest['directories'] if name != 'Lib/site-packages' and not name.startswith('Lib/site-packages/')]
    for wheel in lock['wheels']:
        exact({key: by_name[wheel['filename']][key] for key in ('filename', 'bytes', 'sha256')}, {key: wheel[key] for key in ('filename', 'bytes', 'sha256')}, 'raw wheel identity')
        wheel_rows, wheel_directories = inspect_wheel(inputs / wheel['filename'], wheel, by_name[wheel['filename']])
        acquisitions.append({'filename': wheel['filename'], 'url': wheel['url'], **pinned(inputs / wheel['filename'], wheel)})
        for row in wheel_rows:
            name = row['member']
            destination = 'proj-data/' + name[len(PROJ_PREFIX):] if name.startswith(PROJ_PREFIX) else 'environment/Lib/site-packages/' + name
            rows.append({'path': destination, 'bytes': row['bytes'], 'sha256': row['sha256']})
            mappings.append({'wheel': wheel['filename'], 'member': name, 'installed_path': destination, 'bytes': row['bytes'], 'sha256': row['sha256']})
        for name in wheel_directories:
            if name == PROJ_PREFIX.rstrip('/'):
                destination = 'proj-data'
            elif name.startswith(PROJ_PREFIX):
                destination = 'proj-data/' + name[len(PROJ_PREFIX):]
            else:
                destination = 'environment/Lib/site-packages/' + name
            directories.append(destination)
            explicit_directory_mappings.append({'wheel': wheel['filename'], 'member': name + '/', 'installed_path': destination})
    for spec in (lock['grid'], lock['grid']['readme']):
        row = pinned(inputs / spec['filename'], spec)
        rows.append({'path': 'proj-data/' + spec['filename'], **row})
        acquisitions.append({'filename': spec['filename'], 'url': spec['url'], **row})
    for filename, spec in [('proj-grid-registry-v2.geojson', lock['grid']['registry_snapshot']), ('wheel-inspection/inventory.json', raw_pin)]:
        acquisitions.append({'filename': filename, 'url': spec.get('url'), **pinned(inputs / filename, spec)})
    require(len({row['path'].casefold() for row in rows}) == len(rows), 'installed path collision')
    require(sum(row['bytes'] for row in rows) <= MAX_INSTALLED_BYTES, 'installed-byte budget')
    for row in rows:
        member_name(row['path'])
    expected = {'files': sorted(rows, key=lambda r: r['path']), 'directories': directory_closure(rows, directories)}
    file_keys = {row['path'].casefold() for row in rows}
    require(all(name.casefold() not in file_keys for name in expected['directories']), 'installed file/directory collision')
    return lock, manifest, {
        'schema': 'TerrainToolInstallation/v1', 'lock_sha256': lock_hash,
        'baseline_manifest_sha256': EXPECTED_LOCK['host']['frozen_runtime_manifest_sha256'],
        'baseline_executable': str(plain(args.baseline)), 'copied_executable_relative_path': 'environment/python.exe',
        'interpreter_upstream_acquisition_archive': None, 'environment_kind': 'separate-full-interpreter-copy-not-venv',
        'inherited_site_packages': False, 'wheel_record_locations_relocated': True,
        'acquisition_times': 'not inferred by installer; retain original acquisition receipts separately; unknown wheel times remain unknown',
        'acquired_inputs': acquisitions, 'wheel_members': mappings,
        'explicit_wheel_directories': explicit_directory_mappings, 'installed': expected,
    }


def verify_install(tool, creation):
    # Reconstructed from locked original archives + locked full baseline, not a
    # caller-editable manifest assertion. A changed creation.json cannot add code.
    actual = tree(tool)
    require(any(row['path'] == 'creation.json' for row in actual['files']), 'creation receipt missing')
    actual['files'] = [row for row in actual['files'] if row['path'] != 'creation.json']
    exact(actual, creation['installed'], 'installed complete tree')
    exact(strict_json((tool / 'creation.json').read_bytes(), 16 * 1024 * 1024), creation, 'creation provenance')
    embedded = tool / 'environment/Lib/site-packages/pyproj/proj_dir/share/proj'
    require(not embedded.exists(), 'alternate bundled PROJ data root')


def create(args, creation):
    tool = output_path(args.tool_root)
    require(not tool.exists(), 'tool root exists; no overwrite')
    tool.mkdir(parents=True)
    base = plain(args.baseline).parent
    for name in creation['installed']['directories']:
        (tool / name).mkdir(exist_ok=True)
    for row in creation['installed']['files']:
        name = row['path']
        if name.startswith('environment/') and not name.startswith('environment/Lib/site-packages/'):
            source = base / name[len('environment/'):]
            with plain(source).open('rb') as src, (tool / name).open('xb') as dst:
                shutil.copyfileobj(src, dst, 1024 * 1024)
    inputs = plain(args.inputs)
    for wheel in EXPECTED_LOCK['wheels']:
        with zipfile.ZipFile(inputs / wheel['filename']) as archive:
            for row in creation['wheel_members']:
                if row['wheel'] == wheel['filename']:
                    with (tool / row['installed_path']).open('xb') as stream:
                        stream.write(archive.read(row['member']))
    for spec in (EXPECTED_LOCK['grid'], EXPECTED_LOCK['grid']['readme']):
        with (inputs / spec['filename']).open('rb') as src, (tool / 'proj-data' / spec['filename']).open('xb') as dst:
            shutil.copyfileobj(src, dst, 1024 * 1024)
    write_json(tool / 'creation.json', creation)
    verify_install(tool, creation)


def child_environment(data, cache):
    # Construct a small allowlist; do not copy PYTHON*, PROJ*, GDAL*, SSL* or a
    # caller PATH. No global environment setting is changed.
    env = {key: os.environ[key] for key in ('SystemRoot', 'WINDIR', 'COMSPEC', 'TEMP', 'TMP') if key in os.environ}
    env.update({'PATH': str(Path(os.environ['SystemRoot']) / 'System32'),
                'PROJ_DATA': str(data), 'PROJ_USER_WRITABLE_DIRECTORY': str(cache),
                'PROJ_NETWORK': 'OFF', 'PROJ_ONLY_BEST_DEFAULT': 'YES',
                'PYTHONDONTWRITEBYTECODE': '1', 'PYTHONNOUSERSITE': '1'})
    return env


def run_child(args, job, tool, work, cache, request):
    work.mkdir()
    cache.mkdir()
    request_path = work.parent / (work.name + '-request.json')
    result_path = work.parent / (work.name + '-result.json')
    write_json(request_path, request)
    command = [str(tool / 'environment/python.exe'), '-I', '-B', '-S', str(SOURCE / 'terrain_tools.py'), '_worker', '--job', job,
               '--request', str(request_path), '--result', str(result_path)]
    with (work.parent / (work.name + '-stdout.txt')).open('xb') as stdout, (work.parent / (work.name + '-stderr.txt')).open('xb') as stderr:
        result = subprocess.run(command, cwd=work, env=child_environment(tool / 'proj-data', cache), stdout=stdout, stderr=stderr,
                                timeout=MAX_QUALIFY_SECONDS, check=False)
    require(result.returncode == 0 and result_path.is_file(), 'qualification child failed: ' + job)
    report = strict_json(result_path.read_bytes(), 8 * 1024 * 1024)
    require(report['passed'] is True, 'qualification child refused: ' + job)
    require(not list(cache.iterdir()) and not list(work.iterdir()), 'worker created cache/cwd files')
    return report


def qualify(args, creation):
    tool = output_path(args.tool_root)
    verify_install(tool, creation)
    require(args.raster is not None, 'qualification requires the pinned actual east raster')
    pinned(args.raster, RASTER)
    receipt = output_path(args.receipt_root)
    sources = {'baseline': str(plain(args.baseline)), 'runtime_manifest': str(plain(args.runtime_manifest)), 'inputs': str(plain(args.inputs))}
    request = {'tool_root': str(tool), 'creation': creation, 'raster': str(plain(args.raster)), **sources}
    positive = run_child(args, 'qualify', tool, receipt / 'positive-work', receipt / 'positive-cache', request)
    failures = []
    # Every fault starts from a separate fresh, verified copy. Good environment
    # remains intact. Only declared resource bytes are modified in each copy.
    for resource, mutation in [('grid', 'missing'), ('grid', 'changed'), ('database', 'missing'), ('database', 'changed')]:
        name = resource + '-' + mutation
        clone = receipt / ('fault-' + name)
        shutil.copytree(tool, clone, copy_function=shutil.copyfile)
        verify_install(clone, creation)
        spec = EXPECTED_LOCK['grid'] if resource == 'grid' else EXPECTED_LOCK['proj_database']
        target = clone / 'proj-data' / spec['filename']
        if mutation == 'missing':
            # This sole file is known and beneath a fresh disposable clone.
            target.unlink()
        else:
            with target.open('r+b') as stream:
                value = stream.read(1)
                stream.seek(0)
                stream.write(bytes([value[0] ^ 1]))
        try:
            verify_install(clone, creation)
        except Refusal as error:
            failures.append({'resource': resource, 'mutation': mutation, 'before_import_refused': True, 'message': str(error)})
        else:
            raise Refusal('resource mutation admitted')
        if resource == 'grid' and mutation == 'missing':
            # Low-level strict grid-open refusal, no real-coordinate evaluation.
            # The child first verifies the exact expected single-file omission.
            missing_request = {'tool_root': str(clone), 'creation': creation, 'missing_path': 'proj-data/' + spec['filename'], **sources}
            failures[-1]['strict_proj_refusal'] = run_child(args, 'missing-grid', clone, receipt / (name + '-work'), receipt / (name + '-cache'), missing_request)
    verify_install(tool, creation)
    return {'positive': positive, 'resource_mutations': failures, 'good_environment_unchanged': True}


def peak_working_set():
    from ctypes import wintypes
    class Counters(ctypes.Structure):
        _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD), ('PeakWorkingSetSize', ctypes.c_size_t),
                    ('WorkingSetSize', ctypes.c_size_t), ('QuotaPeakPagedPoolUsage', ctypes.c_size_t), ('QuotaPagedPoolUsage', ctypes.c_size_t),
                    ('QuotaPeakNonPagedPoolUsage', ctypes.c_size_t), ('QuotaNonPagedPoolUsage', ctypes.c_size_t),
                    ('PagefileUsage', ctypes.c_size_t), ('PeakPagefileUsage', ctypes.c_size_t)]
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    psapi = ctypes.WinDLL('psapi', use_last_error=True)
    psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
    psapi.GetProcessMemoryInfo.restype = wintypes.BOOL
    info = Counters()
    info.cb = ctypes.sizeof(info)
    require(bool(psapi.GetProcessMemoryInfo(kernel.GetCurrentProcess(), ctypes.byref(info), info.cb)), 'process memory observation failed')
    return info.PeakWorkingSetSize


def loaded_modules():
    from ctypes import wintypes
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    psapi = ctypes.WinDLL('psapi', use_last_error=True)
    psapi.EnumProcessModules.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.HMODULE), wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
    psapi.EnumProcessModules.restype = wintypes.BOOL
    psapi.GetModuleFileNameExW.argtypes = [wintypes.HANDLE, wintypes.HMODULE, wintypes.LPWSTR, wintypes.DWORD]
    psapi.GetModuleFileNameExW.restype = wintypes.DWORD
    modules = (wintypes.HMODULE * 2048)()
    needed = wintypes.DWORD()
    process = kernel.GetCurrentProcess()
    require(bool(psapi.EnumProcessModules(process, modules, ctypes.sizeof(modules), ctypes.byref(needed))) and needed.value <= ctypes.sizeof(modules), 'loaded module enumeration')
    paths = []
    for index in range(needed.value // ctypes.sizeof(wintypes.HMODULE)):
        buf = ctypes.create_unicode_buffer(32768)
        count = psapi.GetModuleFileNameExW(process, modules[index], buf, len(buf))
        require(0 < count < len(buf) - 1, 'loaded module path')
        # OS modules can legitimately be WinSxS hard links. Record these paths;
        # the caller separately applies strict pinned-file checks to tool DLLs.
        paths.append(os.path.abspath(buf.value))
    return sorted(set(paths), key=str.casefold)


def proj_api(tool):
    """PROJ 9.5 public C API, loaded from the exact inspected wheel DLL only."""
    dll = tool / 'environment/Lib/site-packages' / PROJ_DLL
    library = ctypes.CDLL(str(dll))
    library.proj_context_create.argtypes = []
    library.proj_context_create.restype = ctypes.c_void_p
    library.proj_context_destroy.argtypes = [ctypes.c_void_p]
    library.proj_context_destroy.restype = None
    library.proj_context_set_search_paths.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)]
    library.proj_context_set_search_paths.restype = None
    library.proj_context_set_enable_network.argtypes = [ctypes.c_void_p, ctypes.c_int]
    library.proj_context_set_enable_network.restype = ctypes.c_int
    library.proj_context_is_network_enabled.argtypes = [ctypes.c_void_p]
    library.proj_context_is_network_enabled.restype = ctypes.c_int
    library.proj_context_set_database_path.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_char_p)]
    library.proj_context_set_database_path.restype = ctypes.c_int
    library.proj_context_get_database_path.argtypes = [ctypes.c_void_p]
    library.proj_context_get_database_path.restype = ctypes.c_char_p
    library.proj_grid_get_info_from_database.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
    library.proj_grid_get_info_from_database.restype = ctypes.c_int
    library.proj_create.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    library.proj_create.restype = ctypes.c_void_p
    library.proj_destroy.argtypes = [ctypes.c_void_p]
    library.proj_destroy.restype = ctypes.c_void_p
    context = library.proj_context_create()
    require(context, 'PROJ context creation')
    try:
        data = tool / 'proj-data'
        paths = (ctypes.c_char_p * 1)(str(data).encode('utf-8'))
        library.proj_context_set_search_paths(context, 1, paths)
        library.proj_context_set_enable_network(context, 0)
        require(library.proj_context_is_network_enabled(context) == 0, 'C API network disabled')
        require(library.proj_context_set_database_path(context, str(data / 'proj.db').encode('utf-8'), None, None) == 1, 'C API pinned database admission')
        return library, context
    except BaseException:
        library.proj_context_destroy(context)
        raise


def strict_grid_pipeline(path):
    # Deliberately a resource-open probe only, never a selected terrain operation.
    # Quoted absolute path avoids lookup by an uncontrolled filename/search root.
    require('"' not in str(path), 'quoted PROJ resource path')
    return ('+proj=vgridshift +grids="' + str(path).replace('\\', '/') + '"').encode('utf-8')


def inspect_proj(tool, pyproj):
    data = tool / 'proj-data'
    database = data / 'proj.db'
    grid = data / EXPECTED_LOCK['grid']['filename']
    pinned(database, EXPECTED_LOCK['proj_database'])
    pinned(grid, EXPECTED_LOCK['grid'])
    expected_meta = {'PROJ.VERSION': '9.5.1', 'EPSG.VERSION': 'v11.022', 'EPSG.DATE': '2024-11-05',
                     'PROJ_DATA.VERSION': '1.20', 'DATABASE.LAYOUT.VERSION.MAJOR': '1', 'DATABASE.LAYOUT.VERSION.MINOR': '4'}
    connection = sqlite3.connect(database.as_uri() + '?mode=ro&immutable=1', uri=True)
    try:
        all_meta = dict(connection.execute('SELECT key, value FROM metadata'))
        for key, value in expected_meta.items():
            require(all_meta[key] == value and pyproj.database.get_database_metadata(key) == value, 'actual database metadata: ' + key)
        cursor = connection.execute('SELECT * FROM grid_alternatives WHERE proj_grid_name = ?', (grid.name,))
        columns = [item[0] for item in cursor.description]
        terms = [dict(zip(columns, row)) for row in cursor.fetchall()]
    finally:
        connection.close()
    # Inspect a fixed database operation and its resource paths without selecting
    # it for any source or evaluating a coordinate. This is not terrain admission.
    # EPSG records the legacy g2018u0.bin name. The sealed grid_alternatives
    # row explicitly maps it to the pinned PROJ GeoTIFF; request that documented
    # representation, never an automatic substitute operation or download.
    operation_metadata = pyproj.crs.CoordinateOperation.from_authority('EPSG', '9595', use_proj_alternative_grid_names=True)
    actual_pyproj_grids = []
    for resource in operation_metadata.grids:
        require(resource.short_name == grid.name and resource.available,
                'pyproj database operation resource availability: ' + repr((resource.short_name, resource.available, resource.full_name)))
        resolved = plain(Path(resource.full_name))
        require(os.path.normcase(str(resolved)) == os.path.normcase(str(grid)), 'actual pyproj resolved grid path')
        actual_pyproj_grids.append({'short_name': resource.short_name, 'full_name': str(resolved), **pinned(resolved, EXPECTED_LOCK['grid'])})
    require(len(actual_pyproj_grids) == 1, 'fixed database operation resource roster')
    crs_introspection = []
    for code in (4979, 5703):
        crs = pyproj.CRS.from_epsg(code)
        crs_introspection.append({'authority': ['EPSG', str(code)], 'wkt': crs.to_wkt(), 'projjson': crs.to_json_dict(),
                                  'axes': [{'name': axis.name, 'abbreviation': axis.abbrev, 'direction': axis.direction,
                                            'unit': axis.unit_name, 'unit_conversion_factor': axis.unit_conversion_factor} for axis in crs.axis_info]})
    lib, ctx = proj_api(tool)
    try:
        actual_db = lib.proj_context_get_database_path(ctx)
        require(actual_db is not None and os.path.normcase(actual_db.decode('utf-8')) == os.path.normcase(str(database)), 'actual C API database path')
        full, package, url = ctypes.c_char_p(), ctypes.c_char_p(), ctypes.c_char_p()
        direct, opened, available = ctypes.c_int(), ctypes.c_int(), ctypes.c_int()
        ok = lib.proj_grid_get_info_from_database(ctx, grid.name.encode(), ctypes.byref(full), ctypes.byref(package), ctypes.byref(url), ctypes.byref(direct), ctypes.byref(opened), ctypes.byref(available))
        require(ok == 1 and available.value == 1 and full.value is not None, 'actual C API grid availability')
        actual_grid = plain(Path(full.value.decode('utf-8')))
        require(os.path.normcase(str(actual_grid)) == os.path.normcase(str(grid)), 'actual resolved grid path')
        pinned(actual_grid, EXPECTED_LOCK['grid'])
        operation = lib.proj_create(ctx, strict_grid_pipeline(grid))
        require(operation, 'strict absolute grid-open probe')
        lib.proj_destroy(operation)
        return {'database_path_c_api_context': actual_db.decode('utf-8'), 'database_metadata': all_meta,
                'grid_path_c_api_context': str(actual_grid), 'grid_package': package.value.decode() if package.value else None,
                'grid_url': url.value.decode() if url.value else None, 'grid_open_license': opened.value,
                'grid_database_terms_rows': terms, 'resource_open_only_no_coordinate_transform': True,
                'actual_pyproj_grid_paths': actual_pyproj_grids,
                'database_operation_introspection_only': {'authority': ['EPSG', '9595'], 'name': operation_metadata.name,
                    'use_proj_alternative_grid_names': True,
                    'accuracy': operation_metadata.accuracy, 'projjson': operation_metadata.to_json_dict(), 'wkt': operation_metadata.to_wkt()},
                'crs_introspection_only': crs_introspection,
                'selected_source_operation': None, 'source_compatibility_or_accuracy_claim': False}
    finally:
        lib.proj_context_destroy(ctx)


def worker(args):
    request = strict_json(plain(args.request).read_bytes(), 16 * 1024 * 1024)
    tool = plain(request['tool_root'])
    creation = request['creation']
    report = {'schema': 'TerrainToolWorker/v1', 'job': args.job, 'passed': False}
    started = time.monotonic()
    try:
        require(sys.flags.isolated == 1 and sys.flags.no_site == 1 and sys.dont_write_bytecode, 'isolated no-site/no-bytecode launch required')
        require(os.path.normcase(sys.executable) == os.path.normcase(str(tool / 'environment/python.exe')), 'copied child executable identity')
        require(os.path.normcase(sys.prefix) == os.path.normcase(str(tool / 'environment')), 'copied Python prefix')
        require(os.path.normcase(sys.base_prefix) == os.path.normcase(str(tool / 'environment')), 'no inherited venv/base prefix')
        require(all(within(Path(item), tool / 'environment') for item in sys.path), 'inherited interpreter import path')
        require(platform.python_version() == '3.12.14' and struct.calcsize('P') == 8 and sys.byteorder == 'little', 'child CPython ABI')
        # Internal worker requests cannot supply alternate pins or an invented
        # installed manifest. Reconstruct against the frozen baseline/archives.
        source_args = argparse.Namespace(**{key: request[key] for key in ('baseline', 'runtime_manifest', 'inputs')})
        _, _, reconstructed = source_plan(source_args)
        exact(creation, reconstructed, 'worker pinned installation provenance')
        require(os.environ.get('PROJ_DATA') == str(tool / 'proj-data') and os.environ.get('PROJ_NETWORK') == 'OFF' and os.environ.get('PROJ_ONLY_BEST_DEFAULT') == 'YES', 'pre-import PROJ environment')
        cache = plain(os.environ['PROJ_USER_WRITABLE_DIRECTORY'])
        require(cache.is_dir() and not list(cache.iterdir()) and not list(Path.cwd().iterdir()), 'fresh empty cache and cwd')
        if args.job == 'missing-grid':
            expected = json.loads(json.dumps(creation['installed']))
            expected['files'] = [row for row in expected['files'] if row['path'] != request['missing_path']]
            observed = tree(tool)
            observed['files'] = [row for row in observed['files'] if row['path'] != 'creation.json']
            exact(observed, expected, 'isolated exact missing-resource fixture')
            require(not (tool / request['missing_path']).exists(), 'missing-grid fixture actually missing')
            # DLL load is permitted only in this verified disposable fault tree.
            with os.add_dll_directory(str(tool / 'environment/Lib/site-packages/pyproj.libs')):
                lib, ctx = proj_api(tool)
                try:
                    operation = lib.proj_create(ctx, strict_grid_pipeline(tool / request['missing_path']))
                    if operation:
                        lib.proj_destroy(operation)
                    require(not operation, 'PROJ accepted an absent mandatory absolute grid')
                finally:
                    lib.proj_context_destroy(ctx)
            report['missing_absolute_grid_refused'] = True
        else:
            verify_install(tool, creation)
            site = tool / 'environment/Lib/site-packages'
            sys.path.append(str(site))
            import pyproj
            import PIL
            import certifi
            from PIL import Image, features
            runtime_versions = {'pyproj': pyproj.__version__, 'pillow': PIL.__version__, 'certifi': certifi.__version__}
            report['package_runtime_versions'] = runtime_versions
            # The pinned certifi module spells its date with zero padding;
            # inspect_wheel separately verified its canonical METADATA2025.8.3.
            require(runtime_versions == {'pyproj': '3.7.2', 'pillow': '12.3.0', 'certifi': '2025.08.03'}, 'actual package runtime versions')
            report['verified_wheel_metadata_versions'] = {row['name']: row['version'] for row in EXPECTED_LOCK['wheels']}
            require(pyproj.__proj_version__ == '9.5.1' and pyproj.__proj_compiled_version__ == '9.5.1', 'compiled/runtime PROJ versions')
            for module in (pyproj, PIL, certifi):
                require(within(plain(module.__file__), site), 'module outside copied environment')
            pyproj.datadir.set_data_dir(str(tool / 'proj-data'))
            pyproj.network.set_network_enabled(False)
            require(os.path.normcase(pyproj.datadir.get_data_dir()) == os.path.normcase(str(tool / 'proj-data')) and not pyproj.network.is_network_enabled(), 'effective single data root/offline')
            report['proj'] = inspect_proj(tool, pyproj)
            # Import the independent stdlib strip probe only from reviewed source.
            sys.path.insert(0, str(SOURCE))
            from terrain_decode import decode_qualification
            sys.path.pop(0)
            report['decode'] = decode_qualification(plain(request['raster']), Image, features)
            modules = loaded_modules()
            expected_native = {Path(row['installed_path']).name.casefold(): row for row in creation['wheel_members'] if row['member'].lower().endswith(('.pyd', '.dll'))}
            actual_native = []
            for module in modules:
                path = Path(module)
                key = path.name.casefold()
                if key in expected_native:
                    row = expected_native[key]
                    wanted = tool / row['installed_path']
                    require(os.path.normcase(str(path)) == os.path.normcase(str(wanted)), 'loaded wheel DLL outside environment')
                    pinned(path, row)
                    actual_native.append({'path': str(path), **digest(path)})
                elif path.suffix.lower() in ('.pyd', '.dll') and not within(path, tool / 'environment'):
                    # System DLLs are recorded, not falsely called wheel binaries.
                    require(within(path, Path(os.environ['SystemRoot'])), 'unexpected non-system external native library')
            require(any(Path(row['path']).name == Path(PROJ_DLL).name for row in actual_native), 'actual PROJ DLL not observed')
            require(any(Path(row['path']).name.startswith('_imaging.') for row in actual_native), 'actual Pillow decoder binary not observed')
            report.update({'pyproj_version': pyproj.__version__, 'proj_runtime': pyproj.__proj_version__, 'proj_compiled': pyproj.__proj_compiled_version__,
                           'pillow_version': PIL.__version__, 'certifi_version': certifi.__version__,
                           'python_executable': sys.executable, 'python_version': sys.version,
                           'effective_pyproj_data_directory': pyproj.datadir.get_data_dir(),
                           'network_enabled': pyproj.network.is_network_enabled(), 'loaded_wheel_native_binaries': actual_native,
                           'all_loaded_module_paths': modules, 'site_path_added_explicitly': str(site)})
            verify_install(tool, creation)
        report['peak_working_set_bytes'] = peak_working_set()
        require(report['peak_working_set_bytes'] <= MAX_PEAK_WORKING_SET, 'qualification memory budget exceeded')
        require(time.monotonic() - started <= MAX_QUALIFY_SECONDS, 'qualification elapsed budget exceeded')
        report['passed'] = True
    except BaseException as error:
        report['error'] = str(error)
        report['traceback'] = traceback.format_exc()
    report['elapsed_seconds'] = time.monotonic() - started
    write_json(plain(args.result), report)
    return 0 if report['passed'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode', required=True)
    for mode in ('create', 'qualify'):
        command = sub.add_parser(mode)
        for name in ('baseline', 'runtime-manifest', 'inputs', 'tool-root', 'receipt-root'):
            command.add_argument('--' + name, required=True)
        command.add_argument('--raster')
    internal = sub.add_parser('_worker', help=argparse.SUPPRESS)
    internal.add_argument('--job', choices=('qualify', 'missing-grid'), required=True)
    internal.add_argument('--request', required=True)
    internal.add_argument('--result', required=True)
    args = parser.parse_args()
    if args.mode == '_worker':
        return worker(args)
    receipt = output_path(args.receipt_root)
    report = {'schema': 'TerrainToolAttempt/v1', 'mode': args.mode, 'passed': False,
              'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
    try:
        require(os.name == 'nt' and sys.flags.isolated == 1 and sys.flags.no_site == 1 and sys.dont_write_bytecode, 'Windows isolated launcher required')
        require(receipt.is_dir() and {item.name for item in receipt.iterdir()} == {'launcher.json'}, 'fresh launcher receipt required')
        launcher = strict_json((receipt / 'launcher.json').read_bytes())
        require(launcher['passed'] is True and launcher['baseline']['checked_before_python_process'] is True, 'pre-process baseline audit required')
        require(os.path.normcase(sys.executable) == os.path.normcase(str(plain(args.baseline))), 'explicit baseline executable')
        tool = output_path(args.tool_root)
        for source in (plain(args.baseline).parent, plain(args.inputs), plain(args.runtime_manifest), receipt):
            require(not within(tool, source) and not within(source, tool), 'tool/input/baseline/receipt overlap')
        require(not within(receipt, plain(args.inputs)) and not within(plain(args.inputs), receipt), 'receipt/input overlap')
        lock, manifest, creation = source_plan(args)
        report['lock_sha256'] = creation['lock_sha256']
        report['baseline_manifest_sha256'] = creation['baseline_manifest_sha256']
        report['source_files'] = [{'path': str(SOURCE / name), **digest(SOURCE / name)} for name in ('bootstrap.ps1', 'terrain_pins.py', 'terrain_tools.py', 'terrain_decode.py')]
        if args.mode == 'create':
            create(args, creation)
            report['creation'] = {'tool_root': str(tool), 'creation_json': digest(tool / 'creation.json'),
                                  'files': len(creation['installed']['files']), 'directories': len(creation['installed']['directories']),
                                  'installed_bytes': sum(row['bytes'] for row in creation['installed']['files'])}
        else:
            report['qualification'] = qualify(args, creation)
            pinned(args.raster, RASTER)
        for row in creation['acquired_inputs']:
            pinned(plain(args.inputs) / row['filename'], row)
        baseline_manifest(args.runtime_manifest, args.baseline)
        report['baseline_unchanged_after_attempt'] = True
        report['passed'] = True
    except BaseException as error:
        report['error'] = str(error)
        report['traceback'] = traceback.format_exc()
    report['finished_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    write_json(receipt / 'receipt.json', report)
    print('Terrain tools: ' + ('PASS' if report['passed'] else 'REFUSED; retain receipt') + ' ' + str(receipt))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
