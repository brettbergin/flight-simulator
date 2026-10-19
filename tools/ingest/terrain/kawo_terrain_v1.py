"""Bounded offline KAWO candidate compiler. No runtime or source-pair authority.

Enter with the admitted copied CPython using -I -B -S. Imports at module load
are stdlib only; the installed seal is verified before pyproj/Pillow import.
The only production evaluator is constructed internally from the frozen inputs.
"""
from __future__ import annotations

import argparse
from array import array
from fractions import Fraction
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import stat
import struct
import sys
import time


SOURCE = Path(__file__).absolute().parent
REPOSITORY = SOURCE.parents[2]
CONTRACT_SHA = 'e840a1035315c9a7989cd4ae1bcdf5b52812430ba84df1cd875d21cea11a56fb'
PINS_SHA = '0665004e2ccc95502ede62a8cc2ee342bc5d4784181c6a42aa7ccfc837f97aa8'
CONSTRUCTOR_SHA = '51449b75dd8f16014515d5133cabf8579b2f1d89dddffb7a1cf3ae949a2a0e45'
CREATION_SHA = 'fe460208fb4dcf6ef8ac3a5d0147636afecb4291fb444c547fae7e0e550072ad'
QUALIFICATION_SHA = '71c0e5b2251dbe1c8e97c163b2cd7dd9237ee02b47e4b73c6732ee517458312c'
HELPER_PINS = {
    'terrain_tools.py': '5f62cd58f0574694b8344a99a06c6660ed66e4a45b45b2693c92d1a0aa885e58',
    'terrain_pins.py': '9d6ae9eadc5cd57a6e1ccc4f77496f5568d1ef4c154670d5339f5c0cd9e5037a',
    'terrain_decode.py': '7b721ee962bda0f2a5823db0762c87c9f1a67e058c701a4d4b89033ac1504e63',
}
PYTHON_SHA = 'd41bad46673f64e0d02f23797f53f90ccf60f27d6eda8d86dd2d4bbeae5a858c'
LOCK_SHA = 'e2251bd539487ddb8fc46cea698a094fe3081ee63390be6a2941489c93a10999'
SOURCE_PINS = {
    'tile55': (494331204, 'c0115806df9b1c228b8c074adcdd342bb9a01cf936d2c39be218a5b61ead0ccf'),
    'tile55_metadata': (12169, 'ef382998233ddd833be510e4737c3052f20718e9fe2b2bea523c42cbc3952381'),
    'tile56': (497020458, 'b62bd2d39d081642fd2b1710a2e3971a216702903b36812304a61ec79f6ac97e'),
    'tile56_metadata': (12170, 'c969dc8fcc548ef0670e3fb315ea461cc1f1f59461539816e3b946328f91f8dc'),
    'tool_qualification': (76231, QUALIFICATION_SHA),
}
ROLES = ('airport', 'dossier', 'tile55', 'tile55_metadata', 'tile56', 'tile56_metadata', 'tool_qualification')
OP_IDS = ('horizontal-epsg1188', 'source-utm10n', 'mathematical-wgs84-ecef', 'vertical-epsg9595')
GRID = {'east_origin_m': -6144, 'south_origin_m': -4096, 'spacing_m': 4,
        'columns': 3073, 'rows': 2049, 'vertices': 6296577, 'valid_words': 98385}
MAX_HORIZONTAL = float.fromhex('0x1.0624dd2f1a9fcp-9')
MIN_UP = float.fromhex('0x1.ffff583a53b8ep-1')
PRE_LIMIT = 2.0 ** -12
POST_LIMIT = 2.0 ** -10
MAX_BLOCK = 49168
MAX_SECONDS = 1800
MAX_ARRAY_BYTES = 2 * 1024 ** 3
MAX_PROCESS_BYTES = 3 * 1024 ** 3
INVALID_WORD = 0x7fc00000
HASH = re.compile(r'[0-9a-f]{64}\Z')
STABLE_ID = re.compile(r'[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\Z')
LIMITATIONS = [
    'generic NAD83 realization and epoch unknown',
    'GEOID18 evaluated under an unverified NAD83(2011) assumption',
    'NAVD88 DEM and FAA feet MSL are separate',
    'total3D accuracy UNKNOWN',
    'EPSG1188 published4m is an operation component only',
    'obstacle and airport operational detail incomplete',
    'material coefficients are original prototypes',
]


class Refusal(ValueError):
    """A bounded candidate refusal, never a partially accepted surface."""


def need(condition, message):
    if not condition:
        raise Refusal(message)


def closed(value, keys, label):
    need(type(value) is dict and set(value) == set(keys), label + ': exact members')


def finite(value, label='finite scalar'):
    need(type(value) in (int, float), label)
    try:
        result = float(value)
    except OverflowError as error:
        raise Refusal(label) from error
    need(math.isfinite(result), label)
    return result


def strict_json(raw, limit=65536, max_depth=16, max_values=20000):
    need(type(raw) is bytes and len(raw) <= limit and not raw.startswith(b'\xef\xbb\xbf'), 'JSON bytes/size/BOM')
    def pairs(items):
        obj = {}
        for key, value in items:
            need(key not in obj, 'duplicate JSON member')
            obj[key] = value
        return obj
    def invalid(_value):
        raise Refusal('nonfinite JSON token')
    try:
        value = json.loads(raw.decode('utf-8', errors='strict'), object_pairs_hook=pairs, parse_constant=invalid)
    except (UnicodeError, ValueError, RecursionError) as error:
        raise Refusal('invalid strict JSON') from error
    todo, count = [(value, 1)], 0
    while todo:
        item, depth = todo.pop()
        count += 1
        need(depth <= max_depth and count <= max_values, 'JSON depth/value budget')
        if type(item) is float:
            need(math.isfinite(item), 'overflow/nonfinite JSON number')
        elif type(item) is dict:
            todo.extend((child, depth + 1) for child in item.values())
        elif type(item) is list:
            todo.extend((child, depth + 1) for child in item)
    return value


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True, allow_nan=False)


def decode_b64(tag):
    closed(tag, ('$binary64_le',), 'binary64 tag')
    token = tag['$binary64_le']
    need(type(token) is str and re.fullmatch('[0-9a-f]{16}', token) is not None, 'binary64 lowercase word')
    value = struct.unpack('<d', bytes.fromhex(token))[0]
    need(math.isfinite(value), 'finite binary64 tag')
    return value


def b64(value):
    return {'$binary64_le': struct.pack('<d', finite(value)).hex()}


def dot3(a, b):
    t0 = a[0] * b[0]
    t1 = a[1] * b[1]
    s01 = t0 + t1
    t2 = a[2] * b[2]
    return s01 + t2


def target_ecef(x, y, z, anchor, basis):
    result = []
    for j in range(3):
        xe = x * basis['east'][j]
        q0 = anchor[j] + xe
        yu = y * basis['up'][j]
        q1 = q0 + yu
        zs = z * basis['south'][j]
        result.append(q1 + zs)
    return tuple(result)


def scalar_update(y, h, H, N, c):
    need(all(math.isfinite(v) for v in (y, h, H, N, c)) and c >= MIN_UP, 'finite/cone update')
    target = H + N
    error = target - h
    correction = error / c
    result = y + correction
    need(math.isfinite(result), 'nonfinite update')
    return result


def bilinear(H00, H10, H01, H11, t, u):
    need(all(math.isfinite(v) for v in (H00, H10, H01, H11, t, u)) and 0 <= t < 1 and 0 <= u < 1, 'finite bilinear operands/fractions')
    a = H00 + t * (H10 - H00)
    b = H01 + t * (H11 - H01)
    result = a + u * (b - a)
    need(math.isfinite(result), 'finite bilinear result')
    return result


class SourcePlane:
    def __init__(self, values, nodata_word, width=10012, height=10012, origin_easting=549994):
        need(type(width) is int and type(height) is int and width > 0 and height > 0 and len(values) == width * height, 'plane dimensions/storage')
        need(type(nodata_word) is int and 0 <= nodata_word <= 0xffffffff, 'plane sentinel word')
        self.values, self.width, self.height = values, width, height
        self.origin_easting, self.nodata_word = origin_easting, nodata_word
        self.nodata = struct.unpack('<f', struct.pack('<I', nodata_word))[0]


def lattice_sample(planes, i, j):
    owner = 55 if i < 560000 else 56
    need(owner in planes, 'missing mosaic owner')
    plane = planes[owner]
    col, row = i - plane.origin_easting, 5340005 - j
    need(0 <= col < plane.width and 0 <= row < plane.height, 'source support outside owner')
    value = plane.values[row * plane.width + col]
    need(math.isfinite(value) and value != plane.nodata, 'invalid owner source sample')
    return float(value)


def sample_mosaic(planes, E, N):
    need(math.isfinite(E) and math.isfinite(N), 'finite source query')
    i, j = math.floor(E - 0.5), math.floor(N - 0.5)
    t, u = E - (i + 0.5), N - (j + 0.5)
    # Fetch all four even when t/u is zero. Never rescue with the other tile.
    H00 = lattice_sample(planes, i, j)
    H10 = lattice_sample(planes, i + 1, j)
    H01 = lattice_sample(planes, i, j + 1)
    H11 = lattice_sample(planes, i + 1, j + 1)
    return bilinear(H00, H10, H01, H11, t, u)


def f32_round(value):
    need(math.isfinite(value), 'finite f32 rounding input')
    try:
        raw = struct.pack('<f', value)
    except (OverflowError, struct.error) as error:
        raise Refusal('f32 overflow') from error
    promoted = struct.unpack('<f', raw)[0]
    need(math.isfinite(promoted), 'finite rounded f32')
    return promoted, struct.unpack('<I', raw)[0]


def f32_units(word):
    need(type(word) is int and 0 <= word <= 0xffffffff, 'f32 raw word')
    exponent, fraction = (word >> 23) & 255, word & 0x7fffff
    need(exponent != 255, 'finite f32 word')
    magnitude = fraction if exponent == 0 else ((1 << 23) + fraction) << (exponent - 1)
    return -magnitude if word & 0x80000000 else magnitude


def gradient_admitted(w00, w10, w01, w11):
    a, b, c, d = (f32_units(w) for w in (w00, w10, w01, w11))
    bound = (64 << 149) ** 2
    return (d - c) ** 2 + (c - a) ** 2 <= bound and (b - a) ** 2 + (d - b) ** 2 <= bound


def round_mm(value):
    value = finite(value, 'finite mm operand')
    numerator, denominator = value.as_integer_ratio()
    magnitude, remainder = divmod(abs(numerator) * 1000, denominator)
    if 2 * remainder >= denominator:
        magnitude += 1
    result = -magnitude if numerator < 0 else magnitude
    need(-(1 << 31) <= result < (1 << 31), 'mm signed32 bound')
    return result


def footprint(first_eus, second_eus, width):
    need(len(first_eus) == len(second_eus) == 3 and all(math.isfinite(v) for v in (*first_eus, *second_eus, width)) and width > 0, 'finite footprint operands')
    dx, dz = second_eus[0] - first_eus[0], second_eus[2] - first_eus[2]
    xx, zz = dx * dx, dz * dz
    ll = xx + zz
    length = math.sqrt(ll)
    need(math.isfinite(length) and length > 0, 'nonzero centerline')
    ux, uz = dx / length, dz / length
    px, pz = -uz, ux
    half = width * 0.5
    ox, oz = px * half, pz * half
    result = [(round_mm(first_eus[0] - ox), round_mm(first_eus[2] - oz)),
              (round_mm(first_eus[0] + ox), round_mm(first_eus[2] + oz)),
              (round_mm(second_eus[0] + ox), round_mm(second_eus[2] + oz)),
              (round_mm(second_eus[0] - ox), round_mm(second_eus[2] - oz))]
    validate_ring(result)
    return result


def validate_ring(points):
    need(3 <= len(points) <= 4096 and len(set(points)) == len(points), 'polygon distinct points/count')
    need(all(type(v) is int and -8192000 <= v <= 8192000 for point in points for v in point), 'polygon integer coordinate bound')
    def cross(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    def on(a, b, p):
        return cross(a, b, p) == 0 and min(a[0], b[0]) <= p[0] <= max(a[0], b[0]) and min(a[1], b[1]) <= p[1] <= max(a[1], b[1])
    n = len(points)
    area = sum(points[k][0] * points[(k + 1) % n][1] - points[(k + 1) % n][0] * points[k][1] for k in range(n))
    need(area < 0, 'polygon negative area')
    for i in range(n):
        a, b = points[i], points[(i + 1) % n]
        c = points[(i + 2) % n]
        need(not (on(a, b, c) or on(b, c, a)), 'adjacent polygon overlap')
        for j in range(i + 1, n):
            if j == i + 1 or (i == 0 and j == n - 1):
                continue
            c, d = points[j], points[(j + 1) % n]
            x1, x2, x3, x4 = cross(a, b, c), cross(a, b, d), cross(c, d, a), cross(c, d, b)
            intersect = (x1 * x2 < 0 and x3 * x4 < 0) or on(a, b, c) or on(a, b, d) or on(c, d, a) or on(c, d, b)
            need(not intersect, 'polygon self intersection')


def solve_block(evaluator, xs, zs):
    """The actual fixed driver; evaluator is fixed internally by the CLI.

    Test adapters may call this same private function directly. There is no
    descriptor, CLI option, expression engine or plugin that selects an adapter.
    """
    count = len(xs)
    need(0 < count <= MAX_BLOCK and len(zs) == count, 'block point bound')
    ys, seventh = array('d', [0.0]) * count, None
    def evaluate(values):
        record = evaluator.evaluate(values)
        closed(record, ('h', 'H', 'N', 'c'), 'fixed map result')
        need(all(type(v) is array and v.typecode == 'd' and v.itemsize == 8 and len(v) == count for v in record.values()), 'fixed map owned binary64 arrays')
        need(all(math.isfinite(x) for v in record.values() for x in v) and all(c >= MIN_UP for c in record['c']), 'finite map/cone')
        return record
    for step in range(8):
        if step == 7:
            seventh = array('d', ys)
        record = evaluate(ys)
        for i in range(count):
            ys[i] = scalar_update(ys[i], record['h'][i], record['H'][i], record['N'][i], record['c'][i])
    record = evaluate(ys)
    max_pre = max_delta = max_post = 0.0
    heights, words, promoted = array('f'), array('I'), array('d')
    for i in range(count):
        target = record['H'][i] + record['N'][i]
        pre = abs(record['h'][i] - target)
        delta = abs(ys[i] - seventh[i])
        need(pre <= PRE_LIMIT and delta <= PRE_LIMIT, 'pre-round residual/last delta')
        value, word = f32_round(ys[i])
        need(-1000 <= value <= 4096 and word != INVALID_WORD, 'final f32 range/sentinel')
        promoted.append(value)
        heights.append(value)
        words.append(word)
        max_pre, max_delta = max(max_pre, pre), max(max_delta, delta)
    record = evaluate(promoted)
    for i in range(count):
        target = record['H'][i] + record['N'][i]
        residual = abs(record['h'][i] - target)
        need(residual <= POST_LIMIT, 'post-round physical residual')
        max_post = max(max_post, residual)
    return {'heights': heights, 'words': words, 'max_pre': max_pre, 'max_delta': max_delta, 'max_post': max_post}


def ordinary(path):
    need(isinstance(path, (str, Path)), 'path type')
    path = Path(path)
    need(path.is_absolute() and not str(path).startswith('\\\\') and all(':' not in p for p in path.parts[1:]), 'ordinary absolute local path')
    path = Path(os.path.abspath(path))
    for part in (path, *path.parents):
        try:
            info = part.lstat()
        except FileNotFoundError:
            continue
        need(not stat.S_ISLNK(info.st_mode) and not getattr(info, 'st_file_attributes', 0) & 0x400, 'symlink/reparse path')
        need(stat.S_ISDIR(info.st_mode) or (stat.S_ISREG(info.st_mode) and info.st_nlink == 1), 'special/hardlinked path')
    return path


def digest(path):
    value, count = hashlib.sha256(), 0
    with ordinary(path).open('rb') as stream:
        while block := stream.read(1024 * 1024):
            value.update(block)
            count += len(block)
    return {'sha256': value.hexdigest(), 'bytes': count}


def read_bound(path, limit):
    path = ordinary(path)
    need(path.is_file() and path.stat().st_size <= limit, 'bounded ordinary input file')
    with path.open('rb') as stream:
        raw = stream.read(limit + 1)
    need(len(raw) <= limit, 'input grew beyond byte bound')
    return raw


def pin_json(path, sha, size, depth=16, values=20000):
    raw = read_bound(path, size)
    need(len(raw) == size and hashlib.sha256(raw).hexdigest() == sha, 'static JSON raw pin')
    return strict_json(raw, size, depth, values)


def admit_descriptor(raw):
    value = strict_json(raw, 65536, 8, 2048)
    closed(value, ('schema', *ROLES), 'inputs descriptor')
    need(value['schema'] == 'KawoTerrainInputs/v1', 'inputs schema')
    paths = {}
    for role in ROLES:
        row = value[role]
        closed(row, ('absolute_path', 'sha256', 'bytes'), 'input descriptor ' + role)
        need(type(row['absolute_path']) is str and type(row['sha256']) is str and HASH.fullmatch(row['sha256']) is not None and type(row['bytes']) is int and row['bytes'] > 0, 'descriptor field type')
        token = row['absolute_path']
        need(4 <= len(token) <= 65536 and re.match(r'^[A-Za-z]:[\\/]', token) is not None, 'descriptor Windows absolute path')
        parts = re.split(r'[\\/]', token[3:])
        need(all(part and part not in ('.', '..') and re.search(r'[<>:"|?*\x00-\x1f]', part) is None for part in parts), 'descriptor path components')
        if role in SOURCE_PINS:
            need((row['bytes'], row['sha256']) == SOURCE_PINS[role], 'fixed source/qualification descriptor pin')
        else:
            need(row['bytes'] <= 4 * 1024 ** 2, 'airport/dossier byte bound')
        path = ordinary(row['absolute_path'])
        need(path.is_file() and digest(path) == {'bytes': row['bytes'], 'sha256': row['sha256']}, 'supplied raw input bytes')
        paths[role] = path
    need(len({os.path.normcase(str(p)) for p in paths.values()}) == len(paths), 'distinct input files')
    return value, paths


def load_source(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    need(spec is not None and spec.loader is not None, 'bounded helper loader')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def in_area(latitude, longitude, area):
    return (math.isfinite(latitude) and math.isfinite(longitude) and -90 <= latitude <= 90 and -180 <= longitude <= 180
            and area['south_deg'] <= latitude <= area['north_deg'] and area['west_deg'] <= longitude <= area['east_deg'])


class SealedStack:
    def __init__(self, tool_root, output, paths, inputs_path):
        need(os.name == 'nt' and sys.version_info[:3] == (3, 12, 14) and sys.byteorder == 'little' and struct.calcsize('P') == 8,
             'qualified Windows x64 CPython3.12.14 only')
        need(sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode and sys.prefix == sys.base_prefix, 'isolated copied interpreter/no venv')
        self.root = ordinary(tool_root)
        self.work = ordinary(Path.cwd())
        self.cache = ordinary(os.environ.get('PROJ_USER_WRITABLE_DIRECTORY', ''))
        self.output = ordinary(output)
        need(self.root.is_dir() and self.work.is_dir() and self.cache.is_dir(), 'tool/work/cache directories')
        need(self.work != self.cache and not list(self.work.iterdir()) and not list(self.cache.iterdir()), 'fresh separate empty work/cache')
        need(not self.output.exists() and self.output.parent.is_dir(), 'new output directory/existing parent')
        for root in (self.root, self.work, self.cache):
            need(not self.output.is_relative_to(root) and not root.is_relative_to(self.output), 'output/tool/work/cache disjoint')
        for source in (ordinary(inputs_path), SOURCE, *paths.values()):
            need(not source.is_relative_to(self.output) and not self.output.is_relative_to(source), 'input/output disjoint')
        env = self.root / 'environment'
        need(os.path.normcase(sys.executable) == os.path.normcase(str(env / 'python.exe')) and digest(Path(sys.executable))['sha256'] == PYTHON_SHA, 'exact copied interpreter')
        need(all(Path(p).is_relative_to(env) for p in sys.path), 'initial sealed Python search path')
        need(os.environ.get('PROJ_NETWORK') == 'OFF' and os.environ.get('PROJ_ONLY_BEST_DEFAULT') == 'YES'
             and os.environ.get('PROJ_DATA') == str(self.root / 'proj-data'), 'explicit offline sole data root')
        for filename, sha in HELPER_PINS.items():
            need(digest(SOURCE / filename)['sha256'] == sha, 'qualified LF helper source: ' + filename)
        need('terrain_pins' not in sys.modules and not any(k == 'pyproj' or k.startswith('pyproj.') or k == 'PIL' or k.startswith('PIL.') for k in sys.modules), 'no preloaded third-party modules')
        self.T = load_source('_kawo_admitted_tools', SOURCE / 'terrain_tools.py')
        creation_raw = read_bound(self.root / 'creation.json', 1024 * 1024)
        need(hashlib.sha256(creation_raw).hexdigest() == CREATION_SHA, 'exact installed creation seal')
        self.creation = strict_json(creation_raw, 1024 * 1024, 32, 200000)
        installed = self.creation['installed']
        need(len(installed['files']) == 2745 and len(installed['directories']) == 152
             and sum(row['bytes'] for row in installed['files']) == 111914037, 'fixed installed roster/counts')
        self.T.verify_install(self.root, self.creation)
        self.lock, lock_sha = self.T.lock_file(SOURCE / 'tools-v1.lock.json')
        need(lock_sha == LOCK_SHA, 'exact terrain tools lock bytes')
        docs = REPOSITORY / 'docs/contracts/world'
        need(digest(docs / 'kawo-terrain-compiler-v1.md')['sha256'] == CONTRACT_SHA, 'accepted compiler contract bytes')
        self.pins = pin_json(docs / 'kawo-terrain-pins-v1.json', PINS_SHA, 25080)
        self.constructors = pin_json(docs / 'kawo-terrain-constructor-metadata-v1.json', CONSTRUCTOR_SHA, 8517)
        closed(self.constructors, ('schema', 'source_pins_sha256', 'diagnostic_sha256', 'constructors', 'scope'), 'constructor companion')
        need(self.constructors['schema'] == 'KawoTerrainConstructorMetadata/v1' and self.constructors['source_pins_sha256'] == PINS_SHA
             and len(self.constructors['constructors']) == len(self.pins['operations']) == len(self.pins['authoring_operation_inputs']) == 4, 'constructor/pins relationship')
        # No external paths are added until the complete pre-import seal passes.
        sys.path.append(str(env / 'Lib/site-packages'))
        import pyproj
        import PIL
        from PIL import Image, features
        self.pyproj, self.Image, self.features = pyproj, Image, features
        need(pyproj.__version__ == '3.7.2' and pyproj.__proj_version__ == pyproj.__proj_compiled_version__ == '9.5.1'
             and PIL.__version__ == '12.3.0' and features.check_codec('libtiff'), 'qualified GIS/decoder versions')
        need(ordinary(pyproj.__file__).is_relative_to(env / 'Lib/site-packages') and ordinary(PIL.__file__).is_relative_to(env / 'Lib/site-packages'), 'actual third-party module locations')
        pyproj.datadir.set_data_dir(str(self.root / 'proj-data'))
        pyproj.network.set_network_enabled(False)
        need(pyproj.datadir.get_data_dir() == str(self.root / 'proj-data') and not pyproj.network.is_network_enabled(), 'actual offline data selection')
        self.resources = self.T.inspect_proj(self.root, pyproj)
        self.operations = []
        for index, (constructor, record, actual_pin) in enumerate(zip(self.pins['authoring_operation_inputs'], self.pins['operations'], self.constructors['constructors'])):
            closed(constructor, ('id', 'format', 'literal'), 'authoring input')
            closed(actual_pin, ('id', 'definition', 'projjson'), 'constructor record')
            need(constructor['id'] == record['id'] == actual_pin['id'] == OP_IDS[index] and actual_pin['definition'] == record['definition'], 'ordered metadata identities')
            need(constructor['format'] == ('WKT' if index in (0, 3) else 'PROJ-pipeline'), 'fixed constructor format')
            operation = pyproj.Transformer.from_pipeline(constructor['literal'])
            need(operation.definition == actual_pin['definition'] and canonical(operation.to_json_dict()) == actual_pin['projjson'], 'exact actual constructor definition/JSON')
            self.operations.append(operation)
        frame = self.pins['frame']
        self.anchor = tuple(decode_b64(v) for v in frame['anchor_ecef_m'])
        self.basis = {key: tuple(decode_b64(v) for v in frame['anchor_eus_basis'][key]) for key in ('east', 'up', 'south')}
        self.anchor_position = {key: decode_b64(value) for key, value in frame['world_anchor'].items()}
        self.calls, self.points = [0] * 4, [0] * 4
        self.native = self.audit_native()
        self.D = load_source('_kawo_admitted_decoder', SOURCE / 'terrain_decode.py')

    def audit_native(self):
        mappings = {Path(row['installed_path']).name.casefold(): row for row in self.creation['wheel_members'] if row['member'].lower().endswith(('.pyd', '.dll'))}
        admitted, loaded = [], self.T.loaded_modules()
        environment, windows = self.root / 'environment', Path(os.environ['SystemRoot'])
        for filename in loaded:
            path, key = Path(filename), Path(filename).name.casefold()
            if key in mappings:
                row = mappings[key]
                need(os.path.normcase(str(path)) == os.path.normcase(str(self.root / row['installed_path'])), 'actual wheel native path')
                self.T.pinned(path, row)
                admitted.append({'path': str(path), 'bytes': row['bytes'], 'sha256': row['sha256']})
            elif path.suffix.lower() in ('.dll', '.pyd'):
                need(path.is_relative_to(environment) or path.is_relative_to(windows), 'unexpected external native module')
        need(any(Path(row['path']).name == Path(self.T.PROJ_DLL).name for row in admitted)
             and any(Path(row['path']).name.startswith('_imaging.') for row in admitted), 'actual PROJ/Pillow native binaries')
        return {'all_module_paths': loaded, 'loaded_pinned_wheel_binaries': admitted}

    def transform(self, index, columns, inverse=False):
        need(2 <= len(columns) <= 3 and 0 < len(columns[0]) <= MAX_BLOCK, 'bounded transform shape')
        count = len(columns[0])
        need(all(type(v) is array and v.typecode == 'd' and v.itemsize == 8 and len(v) == count for v in columns), 'owned input binary64 arrays')
        need(all(math.isfinite(x) for v in columns for x in v), 'finite transform inputs')
        # All geographic calls are guarded before PROJ; ECEF inverse takes XYZ.
        if index in (0, 3):
            area = self.pins['operations'][index]['area_of_use']
            need(all(in_area(lat, lon, area) for lat, lon in zip(columns[0], columns[1])), 'recorded geographic operation area')
        elif index == 1 or (index == 2 and not inverse):
            need(all(-180 <= lon <= 180 and -90 <= lat <= 90 for lon, lat in zip(columns[0], columns[1])), 'conversion angular range')
        before = [value.tobytes() for value in columns]
        direction = self.pyproj.enums.TransformDirection.INVERSE if inverse else self.pyproj.enums.TransformDirection.FORWARD
        result = self.operations[index].transform(*columns, direction=direction, errcheck=True, inplace=False)
        self.calls[index] += 1
        self.points[index] += count
        need(len(result) == len(columns) and all(type(v) is array and v.typecode == 'd' and v.itemsize == 8 and len(v) == count for v in result), 'actual owned output adapter shape')
        need(len({id(v) for v in result}) == len(result) and all(v is not source for v in result for source in columns), 'output object alias')
        need(all(v.tobytes() == raw for v, raw in zip(columns, before)), 'transform mutated input')
        need(all(math.isfinite(x) for v in result for x in v), 'finite transform outputs')
        return result

    def finish(self):
        need(not list(self.cache.iterdir()) and not list(self.work.iterdir()), 'work/cache write detected')
        self.native = self.audit_native()
        self.T.verify_install(self.root, self.creation)


def decode_plane(path, role, stack):
    west = role == 'tile55'
    origin, word, text = (549994, 0xff7fffff, '-3.4028234663852886e+38') if west else (559994, 0xc97423f0, '-999999')
    observation = stack.pins['source_planes'][0 if west else 1]
    blocks = stack.D.TiffBlocks(path)
    try:
        need((blocks.width, blocks.height, blocks.block_width, blocks.block_height, blocks.across, blocks.down, blocks.tiled) == (10012, 10012, 256, 256, 40, 40, True), 'fixed primary TIFF tile layout')
        need(blocks.endian == '<' and blocks.tags.get(317, 1) == 1, 'little-endian Predictor1 source')
        expected = {33550: [1.0, 1.0, 0.0], 33922: [0.0, 0.0, 0.0, float(origin), 5340006.0, 0.0],
            34735: [1, 1, 0, 8, 1024, 0, 1, 1, 1025, 0, 1, 1, 1026, 34737, 21, 0, 2049, 34737, 6, 21,
                    2054, 0, 1, 9102, 2062, 34736, 3, 0, 3072, 0, 1, 26910, 3076, 0, 1, 9001],
            34736: [0.0, 0.0, 0.0], 34737: 'NAD83 / UTM zone 10N|NAD83|', 42113: text}
        need(all(blocks.tags.get(k) == v for k, v in expected.items()), 'fixed source geographic/registration/NoData tags')
        stack.Image.MAX_IMAGE_PIXELS = 10012 * 10012
        with stack.Image.open(path) as image:
            image.seek(0)
            need(image.mode == 'F' and image.size == (10012, 10012), 'Pillow primary Float32 mode/size')
            frames = image.n_frames
            image.seek(0)
            need(frames == 6, 'actual primary source frame roster')
            for tag in (256, 257, 258, 259, 262, 277, 284, 339, *expected):
                value = image.tag_v2.get(tag, 1 if tag == 284 else None)
                if isinstance(value, tuple):
                    value = value[0] if len(value) == 1 else list(value)
                need(value == blocks.tags.get(tag, 1 if tag == 284 else None), 'Pillow/raw metadata correspondence')
            image.load()
            raw = image.tobytes()
        need(len(raw) == 400960576 and hashlib.sha256(raw).hexdigest() == observation['decoded_primary_plane_sha256'], 'qualified complete primary-plane bytes')
        values = array('f')
        need(values.itemsize == 4 and sys.byteorder == 'little', 'native Float32 plane ABI')
        values.frombytes(raw)
        del raw
        need(struct.pack('<I', word).hex() == observation['nodata_f32_le'] and text == observation['nodata_tag'], 'source sentinel correspondence')
        return SourcePlane(values, word, origin_easting=origin)
    finally:
        blocks.close()


def check_overlap(planes):
    west, east = planes[55].values, planes[56].values
    mismatch, maximum = 0, Fraction(0)
    for row in range(10012):
        base = row * 10012
        for offset in range(12):
            w, e = west[base + 10000 + offset], east[base + offset]
            need(math.isfinite(w) and math.isfinite(e), 'finite source overlap')
            mismatch += struct.pack('<f', w) != struct.pack('<f', e)
            maximum = max(maximum, abs(Fraction.from_float(w) - Fraction.from_float(e)))
    need(mismatch == 103896 and maximum == Fraction(953, 524288), 'qualified exact overlap facts')


def up_vector(latitude_rad, longitude_rad):
    sp, cp = math.sin(latitude_rad), math.cos(latitude_rad)
    return cp * math.cos(longitude_rad), cp * math.sin(longitude_rad), sp


class GeographicEvaluator:
    def __init__(self, stack, planes, xs, zs):
        self.stack, self.planes, self.xs, self.zs = stack, planes, xs, zs

    def evaluate(self, ys):
        s, count = self.stack, len(ys)
        xyz = [array('d') for _ in range(3)]
        for i in range(count):
            point = target_ecef(self.xs[i], ys[i], self.zs[i], s.anchor, s.basis)
            for j in range(3):
                xyz[j].append(point[j])
        longitude, latitude, heights = s.transform(2, xyz, inverse=True)
        c = array('d')
        for lat, lon in zip(latitude, longitude):
            need(-90 <= lat <= 90 and -180 <= lon <= 180, 'inverse ECEF angular range')
            up = up_vector(math.radians(lat), math.radians(lon))
            direction = tuple(dot3(s.basis[k], up) for k in ('east', 'up', 'south'))
            need(abs(direction[0]) <= MAX_HORIZONTAL and abs(direction[2]) <= MAX_HORIZONTAL and direction[1] >= MIN_UP, 'actual inverse-warp core cone')
            c.append(direction[1])
        source_lat, source_lon = s.transform(0, (latitude, longitude), inverse=True)
        east, north = s.transform(1, (source_lon, source_lat))
        H = array('d', (sample_mosaic(self.planes, E, N) for E, N in zip(east, north)))
        zero = array('d', [0.0]) * count
        _lat, _lon, correction = s.transform(3, (source_lat, source_lon, zero), inverse=True)
        return {'h': heights, 'H': H, 'N': correction, 'c': c}


def check_time(started):
    need(time.monotonic() - started <= MAX_SECONDS, 'compiler 30-minute budget exceeded')


def build_grid(stack, planes, started):
    columns, rows, count = GRID['columns'], GRID['rows'], GRID['vertices']
    heights = array('f', [0.0]) * count
    need(heights.itemsize == 4 and array('I').itemsize == 4 and array('Q').itemsize == 8, 'grid scalar ABI')
    maxima = {'max_pre': 0.0, 'max_delta': 0.0, 'max_post': 0.0}
    for first_row in range(0, rows, 16):
        check_time(started)
        xs, zs = array('d'), array('d')
        for row in range(first_row, min(first_row + 16, rows)):
            z = float(-4096 + 4 * row)
            for col in range(columns):
                xs.append(float(-6144 + 4 * col))
                zs.append(z)
        result = solve_block(GeographicEvaluator(stack, planes, xs, zs), xs, zs)
        offset = first_row * columns
        heights[offset:offset + len(xs)] = result['heights']
        for key in maxima:
            maxima[key] = max(maxima[key], result[key])
        need(stack.T.peak_working_set() <= MAX_PROCESS_BYTES, 'compiler peak process budget exceeded')
    return heights, maxima


def validate_grid(heights, columns=3073, rows=2049):
    need(type(columns) is int and type(rows) is int and 2 <= columns <= 8193 and 2 <= rows <= 8193
         and len(heights) == columns * rows, 'final grid dimensions')
    minimum, maximum, maximum_square = math.inf, -math.inf, 0
    previous = None
    bound = (64 << 149) ** 2
    for row in range(rows):
        current = []
        for col in range(columns):
            value = heights[row * columns + col]
            need(math.isfinite(value) and -1000 <= value <= 4096, 'valid final height')
            promoted, word = f32_round(value)
            need(struct.pack('<d', promoted) == struct.pack('<d', value), 'final height must already be f32')
            current.append(f32_units(word))
            minimum, maximum = min(minimum, value), max(maximum, value)
        if previous is not None:
            for col in range(columns - 1):
                a, b, c, d = previous[col], previous[col + 1], current[col], current[col + 1]
                s0 = (d - c) ** 2 + (c - a) ** 2
                s1 = (b - a) ** 2 + (d - b) ** 2
                need(s0 <= bound and s1 <= bound, 'exact canonical gradient exceeds16')
                maximum_square = max(maximum_square, s0, s1)
        previous = current
    span = Fraction.from_float(maximum) - Fraction.from_float(minimum) + Fraction(1, 32)
    need(span <= 2048, 'exact canonical bracket span')
    norm_square = Fraction(maximum_square, 1 << 302)  # (4*2^149)^2
    return {'minimum': minimum, 'maximum': maximum, 'span': float(span), 'max_gradient': math.sqrt(float(norm_square))}


def endpoint_at(a, d, h):
    result = []
    for j in range(3):
        hd = h * d[j]
        result.append(a[j] + hd)
    need(all(math.isfinite(v) for v in result), 'finite rounded endpoint')
    return tuple(result)


def facet_intersection(a, d, heights, columns, rows, east_origin, south_origin, spacing, ymin, ymax, valid_words=None):
    """Certified core ray on final f32 facets; exact Fractions only for four ends."""
    need(len(a) == len(d) == 3 and all(math.isfinite(v) for v in (*a, *d, east_origin, south_origin, ymin, ymax)), 'finite facet query')
    need(abs(d[0]) <= MAX_HORIZONTAL and abs(d[2]) <= MAX_HORIZONTAL and d[1] >= MIN_UP, 'facet query core cone')
    need(type(columns) is int and type(rows) is int and 2 <= columns <= 8193 and 2 <= rows <= 8193
         and spacing in (2, 4) and len(heights) == columns * rows and -1000 <= ymin <= ymax <= 4096, 'facet grid bounds')
    if valid_words is not None:
        need(len(valid_words) == (columns * rows + 63) // 64, 'facet validity words')
    F = Fraction.from_float
    aa, dd = tuple(F(float(x)) for x in a), tuple(F(float(x)) for x in d)
    ylo, yhi = F(float(ymin)) - Fraction(1, 64), F(float(ymax)) + Fraction(1, 64)
    need(yhi - ylo <= 2048, 'facet bracket span')
    hlo, hhi = (ylo - aa[1]) / dd[1], (yhi - aa[1]) / dd[1]
    supports = []
    for axis, origin, vertices in ((0, east_origin, columns), (2, south_origin, rows)):
        origin = F(float(origin))
        low, high = sorted((aa[axis] + hlo * dd[axis], aa[axis] + hhi * dd[axis]))
        need(low >= origin and high < origin + spacing * (vertices - 1), 'full ray support outside half-open grid')
        supports.append((int((low - origin) // spacing), int((high - origin) // spacing)))
    (c0, c1), (r0, r1) = supports
    def valid_cell(col, row):
        if valid_words is None:
            return True
        n = row * columns + col
        return all(valid_words[k // 64] & (1 << (k % 64)) for k in (n, n + 1, n + columns, n + columns + 1))
    for row in range(r0, r1 + 1):
        for col in range(c0, c1 + 1):
            need(valid_cell(col, row), 'missing physical facet support')
    pc0, pc1 = max(0, c0 - 1), min(columns - 2, c1 + 1)
    pr0, pr1 = max(0, r0 - 1), min(rows - 2, r1 + 1)
    candidates = (pc1 - pc0 + 1) * (pr1 - pr0 + 1)
    need(candidates <= 64, 'facet padded candidate budget')
    hit = None
    for row in range(pr0, pr1 + 1):
        for col in range(pc0, pc1 + 1):
            if not valid_cell(col, row):
                continue
            n = row * columns + col
            values = tuple(heights[k] for k in (n, n + 1, n + columns, n + columns + 1))
            need(all(math.isfinite(v) and -1000 <= v <= 4096 and f32_round(v)[0] == v for v in values), 'canonical valid facet heights')
            y00, y10, y01, y11 = (F(float(v)) for v in values)
            x0, z0 = F(float(east_origin)) + spacing * col, F(float(south_origin)) + spacing * row
            for triangle in (0, 1):
                p = (y11 - y01 if triangle == 0 else y10 - y00) / spacing
                q = (y01 - y00 if triangle == 0 else y11 - y10) / spacing
                need(p * p + q * q <= 256, 'facet exact gradient bound')
                denominator = dd[1] - p * dd[0] - q * dd[2]
                need(denominator > 0, 'positive exact facet denominator')
                numerator = y00 + p * (aa[0] - x0) + q * (aa[2] - z0) - aa[1]
                h = numerator / denominator
                y = aa[1] + h * dd[1]
                if not ylo <= y <= yhi:
                    continue
                x, z = aa[0] + h * dd[0], aa[2] + h * dd[2]
                if not (x0 <= x < x0 + spacing and z0 <= z < z0 + spacing):
                    continue
                diagonal = (z - z0) - (x - x0)
                if (triangle == 0 and diagonal < 0) or (triangle == 1 and diagonal >= 0):
                    continue
                need(hit is None, 'nonunique owned facet root')
                hit = h, col, row, triangle, p, q, y00 - p * x0 - q * z0
    need(hit is not None, 'no certified owned facet root')
    exact_h, col, row, triangle, p, q, intercept = hit
    # Fraction.__float__ performs one correctly rounded rational->binary64 step.
    h = float(exact_h)
    need(math.isfinite(h), 'finite rounded facet root')
    eus = endpoint_at(a, d, h)
    residual = abs(F(eus[1]) - (p * F(eus[0]) + q * F(eus[2]) + intercept))
    need(residual <= Fraction(1, 4096), 'rounded endpoint facet residual')
    return {'h': h, 'eus': eus, 'cell': (col, row), 'triangle': triangle,
            'p': float(p), 'q': float(q), 'support': (c0, c1, r0, r1), 'candidates': candidates}


def core_ray(latitude, longitude, stack):
    """Core's binary64 geodesy operands, not an alternate terrain transform.

    Inverse-warp conversions use the frozen PROJ operation. Endpoint rays use the
    accepted native core's explicit geodetic-normal mathematical definition.
    """
    latitude, longitude = stack.transform(0, (array('d', [latitude]), array('d', [longitude])))
    phi, lam = math.radians(latitude[0]), math.radians(longitude[0])
    sp, cp, sl, cl = math.sin(phi), math.cos(phi), math.sin(lam), math.cos(lam)
    f = 1.0 / 298.257223563
    e2 = f * (2.0 - f)
    term = e2 * sp
    square = term * sp
    radius = 6378137.0 / math.sqrt(1.0 - square)
    point = ((radius * cp) * cl, (radius * cp) * sl, (radius * (1.0 - e2)) * sp)
    delta = tuple(point[j] - stack.anchor[j] for j in range(3))
    up = (cp * cl, cp * sl, sp)
    a = tuple(dot3(stack.basis[k], delta) for k in ('east', 'up', 'south'))
    d = tuple(dot3(stack.basis[k], up) for k in ('east', 'up', 'south'))
    if phi == stack.anchor_position['latitude_rad'] and lam == stack.anchor_position['longitude_rad']:
        a, d = (0.0, -stack.anchor_position['ellipsoid_height_m'], 0.0), (0.0, 1.0, 0.0)
    return a, d


def known_number(observation, label, positive=False):
    need(type(observation) is dict and observation.get('status') == 'known', label + ': known source value')
    value = finite(observation.get('value'), label)
    need(not positive or value > 0, label + ': positive')
    return value


def source_point(observation):
    need(type(observation) is dict and observation.get('status') == 'known', 'known physical source point')
    crs = observation.get('horizontal_crs')
    need(crs == {'authority': 'EPSG', 'code': '4269', 'realization': None, 'epoch_year': None}, 'generic NAD83 source point')
    lat, lon = finite(observation.get('latitude_deg')), finite(observation.get('longitude_deg'))
    need(-90 <= lat <= 90 and -180 <= lon <= 180, 'source angular range')
    return lat, lon


def admit_airport(airport_raw, dossier_raw):
    airport = strict_json(airport_raw, 4 * 1024 ** 2, 32, 100000)
    dossier = strict_json(dossier_raw, 4 * 1024 ** 2, 32, 100000)
    closed(airport, ('schema', 'airport_icao', 'purpose', 'dossier_sha256', 'review_state', 'name', 'reference_point', 'field_elevation', 'runways', 'notes'), 'normalized airport root')
    need(airport['schema'] == 'NormalizedAirport/v1' and airport['airport_icao'] == 'KAWO' and airport['purpose'] == 'source-record'
         and airport['review_state'] in ('draft', 'cross-checked') and airport['dossier_sha256'] == hashlib.sha256(dossier_raw).hexdigest(), 'source pair raw relation')
    need(type(dossier) is dict and dossier.get('schema') == 'AirportSourceDossier/v1' and dossier.get('airport_icao') == 'KAWO', 'supplied source dossier')
    need(source_point(airport['reference_point']) == (48.16075, -122.15902777), 'fixed NASR source ARP')
    need(type(airport['runways']) is list and len(airport['runways']) == 2, 'two physical source runways')
    for runway, identifier, labels in zip(airport['runways'], ('kawo.runway.11-29', 'kawo.runway.16-34'), (('11', '29'), ('16', '34'))):
        need(type(runway) is dict and runway.get('id') == identifier and type(runway.get('ends')) is list and len(runway['ends']) == 2, 'ordered source runways')
        known_number(runway.get('length_m'), 'published length', True)
        known_number(runway.get('width_m'), 'published width', True)
        for end, label in zip(runway['ends'], labels):
            need(type(end) is dict and end.get('id') == 'kawo.end.' + label and type(end.get('designator')) is dict
                 and end['designator'].get('status') == 'known' and end['designator'].get('value') == label, 'ordered physical source labels')
            source_point(end.get('physical_end'))
            bearing = known_number(end.get('true_bearing_deg'), 'published true bearing')
            need(0 <= bearing < 360, 'source true bearing range')
    # Complete source-schema/semantic validation remains Root's external gate.
    # This parser only admits the compiler's consumed fields and raw relation.
    return airport


def runway_geometry(airport, stack, heights, extrema):
    runways, polygons, local_observations = [], [], []
    for runway in airport['runways']:
        ends = []
        for source in runway['ends']:
            lat, lon = source_point(source['physical_end'])
            a, d = core_ray(lat, lon, stack)
            result = facet_intersection(a, d, heights, GRID['columns'], GRID['rows'], -6144.0, -4096.0, 4, extrema['minimum'], extrema['maximum'])
            label = source['designator']['value']
            ends.append({'designator': label, 'eus_m': [b64(v) for v in result['eus']], 'published_true_bearing_deg': b64(known_number(source['true_bearing_deg'], 'true bearing'))})
            local_observations.append({'designator': label, 'ground_ellipsoid_height_m': result['h'], 'cell': result['cell'],
                                       'triangle': result['triangle'], 'support': result['support'], 'candidates': result['candidates']})
        width = known_number(runway['width_m'], 'width', True)
        first, second = (tuple(decode_b64(v) for v in end['eus_m']) for end in ends)
        ring = footprint(first, second, width)
        polygons.append({'id': runway['id'], 'material_index': 1, 'priority': 100, 'vertices': ring})
        runways.append({'id': runway['id'], 'material_polygon_id': runway['id'],
                        'published_length_m': b64(known_number(runway['length_m'], 'length', True)),
                        'width_m': b64(width), 'footprint_mm': [list(v) for v in ring], 'ends': ends})
    return runways, polygons, local_observations


def codec_header(columns, rows, material_count, polygons, total_bytes, anchor, east_origin, south_origin, spacing=4):
    n, w = columns * rows, (columns * rows + 63) // 64
    vertices = sum(len(p['vertices']) for p in polygons)
    need(2 <= columns <= 8193 and 2 <= rows <= 8193 and 1 <= material_count <= 32 and len(polygons) <= 128
         and vertices <= 4096 and 104 <= total_bytes <= 276946836, 'codec structural bounds')
    raw = bytearray(104)
    raw[:8] = b'FGRDLE1\0'
    struct.pack_into('<IIQ', raw, 8, 1, 0x01020304, total_bytes)
    struct.pack_into('<IIIIIIII', raw, 24, columns, rows, n, w, material_count, len(polygons), vertices, 0)
    struct.pack_into('<BBHI', raw, 56, spacing, 2, 0, 0)
    struct.pack_into('<ddddd', raw, 64, *anchor, east_origin, south_origin)
    return raw


def encode_payload(path, heights, valid_words, anchor, polygons):
    materials = [('original.terrain-prototype', 0.8, 0.6), ('original.asphalt', 0.8, 0.6)]
    need(type(heights) is array and heights.typecode == 'f' and heights.itemsize == 4 and len(heights) == GRID['vertices'], 'payload exact f32 vector')
    need(type(valid_words) is array and valid_words.typecode == 'Q' and valid_words.itemsize == 8 and len(valid_words) == GRID['valid_words'], 'payload exact validity vector')
    need(valid_words[-1] == 1 and all(v == 0xffffffffffffffff for v in valid_words[:-1]), 'allvalid payload mask/padding')
    need(len(polygons) == 2 and [p['id'] for p in polygons] == ['kawo.runway.11-29', 'kawo.runway.16-34'], 'payload closed polygon roster')
    material_records, polygon_records = [], []
    for identifier, static, dynamic in materials:
        token = identifier.encode('ascii')
        need(STABLE_ID.fullmatch(identifier) and 1 <= len(token) <= 128 and 0 <= dynamic <= static <= 5, 'codec material')
        material_records.append(struct.pack('<B', len(token)) + token + struct.pack('<dd', static, dynamic))
    for polygon in polygons:
        token = polygon['id'].encode('ascii')
        validate_ring(polygon['vertices'])
        need(STABLE_ID.fullmatch(polygon['id']) and 1 <= len(token) <= 128 and polygon['material_index'] == 1 and polygon['priority'] == 100 and len(polygon['vertices']) == 4, 'codec fixed polygon')
        raw = struct.pack('<B', len(token)) + token + struct.pack('<IBI', 1, 100, 4)
        raw += b''.join(struct.pack('<ii', *point) for point in polygon['vertices'])
        polygon_records.append(raw)
    total = 104 + 4 * len(heights) + 8 * len(valid_words) + sum(map(len, material_records)) + sum(map(len, polygon_records))
    header = codec_header(GRID['columns'], GRID['rows'], len(materials), polygons, total, anchor, -6144.0, -4096.0)
    checksum, count = hashlib.sha256(), 0
    with ordinary(path).open('xb') as stream:
        def emit(raw):
            nonlocal count
            need(count + len(raw) <= total, 'payload writer cursor overflow')
            need(stream.write(raw) == len(raw), 'payload short write')
            checksum.update(raw)
            count += len(raw)
        emit(header)
        for values in (heights, valid_words):
            view = memoryview(values).cast('B')
            for offset in range(0, len(view), 1024 * 1024):
                emit(view[offset:offset + 1024 * 1024])
            del view
        for raw in (*material_records, *polygon_records):
            emit(raw)
        need(count == total, 'payload exact final cursor')
        stream.flush()
        os.fsync(stream.fileno())
    return {'path': 'ground.fgrd', 'sha256': checksum.hexdigest(), 'bytes': count}


def receipt_value(descriptor, airport, stack, extrema, residuals, runways, payload):
    base = 'https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/1m/Projects/WA_Western_North_2016/'
    locators = {'airport': 'source-pair:airport', 'dossier': 'source-pair:dossier', 'tool_qualification': 'tool-qualification:terrain-tools-v1'}
    for tile in (55, 56):
        locators['tile' + str(tile)] = base + 'TIFF/USGS_one_meter_x' + str(tile) + 'y534_WA_Western_North_2016.tif'
        locators['tile' + str(tile) + '_metadata'] = base + 'metadata/USGS_one_meter_x' + str(tile) + 'y534_WA_Western_North_2016_meta.xml'
    lock = stack.lock
    wheels = {row['name']: row for row in lock['wheels']}
    world_anchor = stack.pins['frame']['world_anchor']
    geometry = {'schema': 'CompiledAirportGeometry/v1', 'source_airport_sha256': descriptor['airport']['sha256'],
                'ground_payload_sha256': payload['sha256'], 'world_anchor': world_anchor,
                'position_frame': 'anchor-eus-metres', 'bearing_reference': 'published-geographic-true-degrees', 'runways': runways}
    return {
        'schema': 'KawoTerrainCompileReceipt/v1', 'contract_id': 'kawo-approx-terrain-v1', 'quality': 'approximate-unverified-frame-v1',
        'inputs': [{'role': role, 'locator': locators[role], 'sha256': descriptor[role]['sha256'], 'bytes': descriptor[role]['bytes']} for role in ROLES],
        'tools': {'lock_sha256': LOCK_SHA, 'qualification_sha256': QUALIFICATION_SHA, 'python_executable_sha256': PYTHON_SHA,
                  'pyproj_wheel_sha256': wheels['pyproj']['sha256'], 'pillow_wheel_sha256': wheels['pillow']['sha256'],
                  'certifi_wheel_sha256': wheels['certifi']['sha256'], 'proj_db_sha256': lock['proj_database']['sha256'],
                  'geoid_sha256': lock['grid']['sha256']},
        # These original qualified discovery/authority records are intentionally
        # distinct from the exact current constructor serializations in51449.
        'operations': stack.pins['operations'],
        'frame': {'world_anchor': world_anchor, 'horizontal_policy': 'epsg1188-geog2d-approximation',
                  'vertical_policy': 'navd88-plus-geoid18-unverified-frame', 'source_realization': None,
                  'source_epoch_year': None, 'total3d_accuracy': 'unknown'},
        'grid': dict(GRID),
        'mosaic': {'policy': 'global-lattice-owner-before-bilinear', 'seam_easting_m': 560000, 'source_sample_offset_m': b64(0.5),
                   'overlap_columns': 12, 'overlap_word_mismatches': 103896, 'max_overlap_difference_m': b64(953 / 524288)},
        'construction': {'method': 'anchor-up-fixed-point-v1', 'initial_y_m': b64(0.0), 'updates': 8,
                         'pre_round_residual_limit_m': b64(PRE_LIMIT), 'last_delta_limit_m': b64(PRE_LIMIT),
                         'post_round_residual_limit_m': b64(POST_LIMIT), 'rounding': 'ieee754-binary32-nearest-even',
                         'reverse_horizontal': 'inverse-epsg1188-then-forward-utm10n',
                         'reverse_vertical': 'inverse-epsg9595-with-positive-zero-height'},
        'validation': {'valid_vertices': GRID['vertices'], 'missing_vertices': 0, 'min_up_m': b64(extrema['minimum']),
                       'max_up_m': b64(extrema['maximum']), 'max_gradient_norm': b64(extrema['max_gradient']),
                       'bracket_span_m': b64(extrema['span']), 'max_pre_round_residual_m': b64(residuals['max_pre']),
                       'max_last_delta_m': b64(residuals['max_delta']), 'max_post_round_residual_m': b64(residuals['max_post']),
                       'core_definition_valid': True,
                       'decoded_source_sha256': {key: stack.pins['source_planes'][index]['decoded_primary_plane_sha256']
                                                 for index, key in enumerate(('tile55', 'tile56'))}},
        'airport_geometry': geometry, 'outputs': [payload], 'limitations': list(LIMITATIONS),
    }


def write_candidate_json(path, value):
    raw = (canonical(value) + '\n').encode('utf-8')
    strict_json(raw, 4 * 1024 ** 2, 16, 20000)
    with ordinary(path).open('xb') as stream:
        need(stream.write(raw) == len(raw), 'receipt short write')
        stream.flush()
        os.fsync(stream.fileno())
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


def compile_candidate(descriptor, paths, airport, stack, started):
    stage_times = {}
    # Fixed bounded working-array allowance including decode copies, final
    # grid/mask,64 maximum block double arrays and two generously sized int rows.
    array_bound = 4 * 400960576 + 4 * GRID['vertices'] + 8 * GRID['valid_words'] + 64 * MAX_BLOCK * 8 + 2 * GRID['columns'] * 128
    need(array_bound <= MAX_ARRAY_BYTES, 'bounded authoring working arrays')
    stack.output.mkdir()
    at = time.monotonic()
    planes = {55: decode_plane(paths['tile55'], 'tile55', stack)}
    check_time(started)
    need(stack.T.peak_working_set() <= MAX_PROCESS_BYTES, 'decode peak process budget')
    planes[56] = decode_plane(paths['tile56'], 'tile56', stack)
    check_overlap(planes)
    stage_times['decode_seconds'] = time.monotonic() - at
    check_time(started)
    need(stack.T.peak_working_set() <= MAX_PROCESS_BYTES, 'decode/mosaic peak process budget')
    at = time.monotonic()
    heights, residuals = build_grid(stack, planes, started)
    stage_times['transform_seconds'] = time.monotonic() - at
    # Source planes are no longer required for final canonical facet queries.
    del planes
    at = time.monotonic()
    extrema = validate_grid(heights)
    runways, polygons, endpoint_observations = runway_geometry(airport, stack, heights, extrema)
    stage_times['validation_seconds'] = time.monotonic() - at
    check_time(started)
    # All N vertices valid, N mod64==1; unused high bits are exactly zero.
    valid_words = array('Q', [0xffffffffffffffff]) * GRID['valid_words']
    valid_words[-1] = 1
    anchor = tuple(stack.anchor_position[k] for k in ('latitude_rad', 'longitude_rad', 'ellipsoid_height_m'))
    at = time.monotonic()
    payload = encode_payload(stack.output / 'ground.fgrd', heights, valid_words, anchor, polygons)
    receipt = receipt_value(descriptor, airport, stack, extrema, residuals, runways, payload)
    receipt_identity = write_candidate_json(stack.output / 'compile-receipt.json', receipt)
    stage_times['encode_seconds'] = time.monotonic() - at
    check_time(started)
    need(stack.T.peak_working_set() <= MAX_PROCESS_BYTES, 'final compiler peak process budget')
    return {'payload': payload, 'compile_receipt': receipt_identity, 'times': stage_times,
            'accounted_working_array_bound_bytes': array_bound, 'peak_working_set_bytes': stack.T.peak_working_set(),
            'operation_calls': dict(zip(OP_IDS, stack.calls)), 'operation_points': dict(zip(OP_IDS, stack.points)),
            'map_evaluations_per_vertex': 10, 'updates': 8, 'blocks': 129, 'endpoints': endpoint_observations}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', required=True)
    parser.add_argument('--tools-root', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args(argv)
    started, stack, descriptor, paths = time.monotonic(), None, None, None
    result = {'kind': 'KawoTerrainCompilerExecution/v1', 'candidate_complete': False, 'external_source_pair_gate_proved': False,
              'native_acceptance': False, 'runtime_admission': False, 'total3d_accuracy': 'UNKNOWN'}
    error = None
    try:
        inputs_path = ordinary(args.inputs)
        input_raw = read_bound(inputs_path, 65536)
        descriptor, paths = admit_descriptor(input_raw)
        airport_raw = read_bound(paths['airport'], descriptor['airport']['bytes'])
        dossier_raw = read_bound(paths['dossier'], descriptor['dossier']['bytes'])
        need(hashlib.sha256(airport_raw).hexdigest() == descriptor['airport']['sha256']
             and hashlib.sha256(dossier_raw).hexdigest() == descriptor['dossier']['sha256'], 'same small source bytes at parse')
        airport = admit_airport(airport_raw, dossier_raw)
        stack = SealedStack(args.tools_root, args.output, paths, inputs_path)
        result['observations'] = compile_candidate(descriptor, paths, airport, stack, started)
        need(read_bound(inputs_path, 65536) == input_raw, 'descriptor changed during compilation')
    except Exception as failure:
        error = failure
    finally:
        if stack is not None:
            try:
                stack.finish()
                result['installation_after_unchanged'] = True
                result['actual_resources'] = stack.resources
                result['actual_native'] = stack.native
            except Exception as failure:
                result['installation_after_unchanged'] = False
                error = error or failure
        if descriptor is not None and paths is not None:
            try:
                for role in ROLES:
                    need(digest(paths[role]) == {'bytes': descriptor[role]['bytes'], 'sha256': descriptor[role]['sha256']}, 'input changed after compilation')
                result['raw_inputs_after_unchanged'] = True
            except Exception as failure:
                result['raw_inputs_after_unchanged'] = False
                error = error or failure
    try:
        check_time(started)
        if error is None:
            need(stack is not None and result.get('installation_after_unchanged') is True and result.get('raw_inputs_after_unchanged') is True, 'completed final input/seal checks')
            marker = b'Candidate only; independent validation required.\n'
            with (stack.output / 'VALIDATION-REQUIRED.txt').open('xb') as stream:
                need(stream.write(marker) == len(marker), 'candidate marker short write')
                stream.flush()
                os.fsync(stream.fileno())
            need({p.name for p in stack.output.iterdir()} == {'ground.fgrd', 'compile-receipt.json', 'VALIDATION-REQUIRED.txt'}, 'exact three candidate outputs')
            result['candidate_complete'] = True
    except Exception as failure:
        error = error or failure
    if error is not None:
        result['error_type'], result['error'] = type(error).__name__, str(error)[:2048]
    result['elapsed_seconds'] = time.monotonic() - started
    print(canonical(result))
    return 0 if result['candidate_complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
