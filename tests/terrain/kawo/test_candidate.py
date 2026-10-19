"""Explicit-path independent candidate comparison; no compiler/codec imports.

Not invoked by unittest discovery. It compares independently frozen selected
words and source relationships; full native admission remains a separate gate.
"""
import argparse
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import re
import stat
import struct

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parents[2]
REFERENCE_SHA = 'ed63fb9a14cff9db1ab5dbd6ae0637d62591da9acfed43077f804155a7744cb2'
PINS_SHA = '0665004e2ccc95502ede62a8cc2ee342bc5d4784181c6a42aa7ccfc837f97aa8'
ROLES = ('airport', 'dossier', 'tile55', 'tile55_metadata', 'tile56',
         'tile56_metadata', 'tool_qualification')
RAW_PINS = {
    'airport': (37101, '63463d30c55f8aba56a3426efd7c2dd61287a99d66d307f3940b589b97fd6c18'),
    'dossier': (15785, '974345fd8eedff2e339e4eb21b8ac3a09ed69c66c4d2a045b430f9655bd15cee'),
    'tile55': (494331204, 'c0115806df9b1c228b8c074adcdd342bb9a01cf936d2c39be218a5b61ead0ccf'),
    'tile55_metadata': (12169, 'ef382998233ddd833be510e4737c3052f20718e9fe2b2bea523c42cbc3952381'),
    'tile56': (497020458, 'b62bd2d39d081642fd2b1710a2e3971a216702903b36812304a61ec79f6ac97e'),
    'tile56_metadata': (12170, 'c969dc8fcc548ef0670e3fb315ea461cc1f1f59461539816e3b946328f91f8dc'),
    'tool_qualification': (76231, '71c0e5b2251dbe1c8e97c163b2cd7dd9237ee02b47e4b73c6732ee517458312c'),
}
GRID = {'east_origin_m': -6144, 'south_origin_m': -4096, 'spacing_m': 4,
        'columns': 3073, 'rows': 2049, 'vertices': 6296577, 'valid_words': 98385}
LIMITATIONS = [
    'generic NAD83 realization and epoch unknown',
    'GEOID18 evaluated under an unverified NAD83(2011) assumption',
    'NAVD88 DEM and FAA feet MSL are separate', 'total3D accuracy UNKNOWN',
    'EPSG1188 published4m is an operation component only',
    'obstacle and airport operational detail incomplete',
    'material coefficients are original prototypes',
]


def require(condition, label):
    if not condition:
        raise ValueError(label)


def closed(value, keys, label):
    require(type(value) is dict and set(value) == set(keys), label)


def ordinary(path):
    path = Path(path)
    require(path.is_absolute(), 'comparison paths must be explicit absolute paths')
    for part in (path, *path.parents):
        info = part.lstat()
        require(not stat.S_ISLNK(info.st_mode) and not getattr(info, 'st_file_attributes', 0) & 0x400,
                'comparison symlink/reparse path')
    return path


def digest(path):
    count, h = 0, hashlib.sha256()
    with ordinary(path).open('rb') as stream:
        while block := stream.read(1048576):
            count += len(block)
            h.update(block)
    return count, h.hexdigest()


def read(path, limit):
    path = ordinary(path)
    require(path.is_file() and path.stat().st_size <= limit, 'bounded ordinary comparison file')
    with path.open('rb') as stream:
        raw = stream.read(limit + 1)
    require(len(raw) <= limit, 'comparison file grew beyond bound')
    return raw


def json_read(path, limit):
    raw = read(path, limit)
    require(not raw.startswith(b'\xef\xbb\xbf'), 'JSON BOM')
    def pairs(rows):
        obj = {}
        for key, value in rows:
            require(key not in obj, 'duplicate comparison JSON key')
            obj[key] = value
        return obj
    def invalid(value):
        raise ValueError('nonfinite comparison JSON token ' + value)
    obj = json.loads(raw.decode('utf-8'), object_pairs_hook=pairs, parse_constant=invalid)
    return raw, obj


def tag(value):
    return {'$binary64_le': struct.pack('<d', value).hex()}


def scalar(value):
    closed(value, ('$binary64_le',), 'closed scalar tag')
    require(type(value['$binary64_le']) is str and re.fullmatch('[0-9a-f]{16}', value['$binary64_le']),
            'finite LE scalar spelling')
    result = struct.unpack('<d', bytes.fromhex(value['$binary64_le']))[0]
    require(math.isfinite(result), 'finite comparison scalar')
    return result


def expected_tag(record):
    # Frozen words are MSB-first, independent of machine endianness/decimal field.
    return {'$binary64_le': bytes.fromhex(record['b64_be_hex'])[::-1].hex()}


def compare(candidate, inputs_path, controls_path):
    control_raw, source = json_read(controls_path, 756727)
    require(len(control_raw) == 756727 and hashlib.sha256(control_raw).hexdigest() == REFERENCE_SHA,
            'exact frozen independent reference')
    require(source['schema'] == 'KawoTerrainSelectedControls/v1' and
            source['source_acceptance_flags'] == {'passed': True, 'accepted_reference': False,
                                                  'compiler_admission': False}, 'frozen scope flags')
    controls = source['controls']
    pins_raw, pins = json_read(REPOSITORY / 'docs/contracts/world/kawo-terrain-pins-v1.json', 65536)
    require(hashlib.sha256(pins_raw).hexdigest() == PINS_SHA, 'exact contract portable pins')
    _, inputs = json_read(inputs_path, 65536)
    closed(inputs, ('schema', *ROLES), 'closed source descriptor')
    require(inputs['schema'] == 'KawoTerrainInputs/v1', 'source descriptor version')
    paths, before = {}, {}
    for role in ROLES:
        row = inputs[role]
        closed(row, ('absolute_path', 'sha256', 'bytes'), 'closed source file descriptor')
        require((row['bytes'], row['sha256']) == RAW_PINS[role], 'frozen reference source identity ' + role)
        paths[role] = ordinary(row['absolute_path'])
        before[role] = digest(paths[role])
        require(before[role] == RAW_PINS[role], 'actual source bytes ' + role)
    _, airport = json_read(paths['airport'], 4 * 1024**2)
    _, dossier = json_read(paths['dossier'], 4 * 1024**2)
    require(airport['dossier_sha256'] == RAW_PINS['dossier'][1], 'source pair relationship')
    require(dossier['purpose'] == 'source-record' and airport['review_state'] == 'draft', 'source states preserved')
    candidate = ordinary(candidate)
    require(candidate.is_dir() and {p.name for p in candidate.iterdir()} ==
            {'ground.fgrd', 'compile-receipt.json', 'VALIDATION-REQUIRED.txt'}, 'closed successful candidate roster')
    ground = read(candidate / 'ground.fgrd', 276946836)
    ground_sha = hashlib.sha256(ground).hexdigest()
    receipt_raw, receipt = json_read(candidate / 'compile-receipt.json', 4 * 1024**2)
    require(read(candidate / 'VALIDATION-REQUIRED.txt', 128) ==
            b'Candidate only; independent validation required.\n', 'candidate marker')
    require(receipt_raw == (json.dumps(receipt, sort_keys=True, separators=(',', ':'),
                                      ensure_ascii=True, allow_nan=False) + '\n').encode('utf-8'),
            'deterministic receipt serialization')
    closed(receipt, ('schema', 'contract_id', 'quality', 'inputs', 'tools', 'operations', 'frame', 'grid',
                     'mosaic', 'construction', 'validation', 'airport_geometry', 'outputs', 'limitations'),
           'receipt root')
    require((receipt['schema'], receipt['contract_id'], receipt['quality']) ==
            ('KawoTerrainCompileReceipt/v1', 'kawo-approx-terrain-v1', 'approximate-unverified-frame-v1'),
            'candidate contract scope')
    require(receipt['operations'] == pins['operations'], 'unchanged discovery records, not constructor JSON')
    require(receipt['grid'] == GRID and receipt['limitations'] == LIMITATIONS, 'fixed extent and limits')
    require(receipt['tools'] == {
        'lock_sha256': 'e2251bd539487ddb8fc46cea698a094fe3081ee63390be6a2941489c93a10999',
        'qualification_sha256': RAW_PINS['tool_qualification'][1],
        'python_executable_sha256': 'd41bad46673f64e0d02f23797f53f90ccf60f27d6eda8d86dd2d4bbeae5a858c',
        'pyproj_wheel_sha256': '11614a054cd86a2ed968a657d00987a86eeb91fdcbd9ad3310478685dc14a128',
        'pillow_wheel_sha256': 'a2b55dd6b2a4c4b7d87ffa56bdb33fdc5fdb9a462173861a7bc097f17d91cb09',
        'certifi_wheel_sha256': 'f6c12493cfb1b06ba2ff328595af9350c65d6644968e5d3a2ffd78699af217a5',
        'proj_db_sha256': '47a7205d83ba6b7774b763f276ab57331f4dade2b2cfbcc0d486677e6543350b',
        'geoid_sha256': 'fa9a407ac7ee3f5a3694008e4bcd09ce9cc250452f0c3b11700a4960340abce2'},
        'fixed recorded tool identities; actual closure remains external')
    require(receipt['frame'] == {
        'world_anchor': pins['frame']['world_anchor'],
        'horizontal_policy': 'epsg1188-geog2d-approximation',
        'vertical_policy': 'navd88-plus-geoid18-unverified-frame',
        'source_realization': None, 'source_epoch_year': None, 'total3d_accuracy': 'unknown'},
        'fixed approximate frame semantics')
    require(receipt['mosaic'] == {
        'policy': 'global-lattice-owner-before-bilinear', 'seam_easting_m': 560000,
        'source_sample_offset_m': tag(.5), 'overlap_columns': 12,
        'overlap_word_mismatches': 103896,
        'max_overlap_difference_m': pins['overlap']['maximum_difference_m']}, 'fixed source mosaic facts')
    require(receipt['construction'] == {
        'method': 'anchor-up-fixed-point-v1', 'initial_y_m': tag(0.), 'updates': 8,
        'pre_round_residual_limit_m': tag(2.**-12), 'last_delta_limit_m': tag(2.**-12),
        'post_round_residual_limit_m': tag(2.**-10), 'rounding': 'ieee754-binary32-nearest-even',
        'reverse_horizontal': 'inverse-epsg1188-then-forward-utm10n',
        'reverse_vertical': 'inverse-epsg9595-with-positive-zero-height'}, 'fixed construction policy')
    require(receipt['outputs'] == [{'path': 'ground.fgrd', 'sha256': ground_sha, 'bytes': len(ground)}],
            'payload output relationship')
    input_rows = receipt['inputs']
    require(len(input_rows) == 7 and tuple(r['role'] for r in input_rows) == ROLES, 'source role order')
    url = 'https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/1m/Projects/WA_Western_North_2016/'
    for role, row in zip(ROLES, input_rows):
        closed(row, ('role', 'locator', 'sha256', 'bytes'), 'receipt source row')
        if role in ('airport', 'dossier'):
            locator = 'source-pair:' + role
        elif role == 'tool_qualification':
            locator = 'tool-qualification:terrain-tools-v1'
        else:
            tile = '55' if role.startswith('tile55') else '56'
            filename = 'USGS_one_meter_x' + tile + 'y534_WA_Western_North_2016'
            locator = url + ('metadata/' + filename + '_meta.xml' if role.endswith('metadata')
                             else 'TIFF/' + filename + '.tif')
        require((row['bytes'], row['sha256']) == before[role] and row['locator'] == locator,
                'actual source receipt binding ' + role)
    require(len(ground) >= 104 and ground[:8] == b'FGRDLE1\x00', 'fixed ground magic/header')
    require(struct.unpack_from('<IIQ', ground, 8) == (1, 0x01020304, len(ground)), 'version/endian/total')
    require(struct.unpack_from('<8I', ground, 24) == (3073, 2049, 6296577, 98385, 2, 2, 8, 0),
            'exact grid/material/polygon counts')
    require(ground[56:64] == bytes((4, 2, 0, 0, 0, 0, 0, 0)), 'spacing/missing/reserved')
    anchor = pins['frame']['world_anchor']
    expected_anchor = b''.join(bytes.fromhex(anchor[k]['$binary64_le']) for k in
                               ('latitude_rad', 'longitude_rad', 'ellipsoid_height_m'))
    require(ground[64:88] == expected_anchor and ground[88:104] == struct.pack('<dd', -6144., -4096.),
            'bit-exact anchor/origins')
    valid_at = 104 + 4 * 6296577
    body_at = valid_at + 8 * 98385
    require(len(ground) >= body_at and ground[valid_at:body_at - 8] == b'\xff' * (8 * 98384)
            and ground[body_at - 8:body_at] == b'\x01\x00\x00\x00\x00\x00\x00\x00',
            'all6296577 valid and zero padding')
    require(len(controls['vertices']) == 81, 'frozen selected count')
    for vertex in controls['vertices'].values():
        at = 104 + 4 * (vertex['row'] * 3073 + vertex['column'])
        require(ground[at:at + 4].hex() == vertex['final_f32_le'], 'selected final f32 word')
    lo, hi = math.inf, -math.inf
    for (value,) in struct.iter_unpack('<f', memoryview(ground)[104:valid_at]):
        require(math.isfinite(value) and -1000 <= value <= 4096, 'all final f32 finite/range')
        lo, hi = min(lo, value), max(hi, value)
    require(Fraction(hi) - Fraction(lo) + Fraction(1, 32) <= 2048, 'exact final bracket span')
    cursor = body_at
    def take(fmt):
        nonlocal cursor
        size = struct.calcsize(fmt)
        require(size <= len(ground) - cursor, 'bounded sequential field')
        value = struct.unpack_from(fmt, ground, cursor)
        cursor += size
        return value
    def identifier():
        nonlocal cursor
        (size,) = take('<B')
        require(1 <= size <= 128 and size <= len(ground) - cursor, 'bounded ID')
        value = ground[cursor:cursor + size].decode('ascii')
        cursor += size
        return value
    for name in ('original.terrain-prototype', 'original.asphalt'):
        require(identifier() == name, 'material order/identity')
        # Compare raw words, preserving permitted bit representations.
        require(take('<QQ') == struct.unpack('<QQ', struct.pack('<dd', .8, .6)), 'prototype friction bits')
    for expected in controls['runway_footprints']:
        require(identifier() == expected['id'] and take('<IBI') == (1, 100, 4), 'polygon header/order')
        require([list(take('<ii')) for _ in range(4)] == expected['footprint_mm'], 'exact footprint mm words')
    require(cursor == len(ground), 'no trailing/omitted payload fields')
    geometry = receipt['airport_geometry']
    closed(geometry, ('schema', 'source_airport_sha256', 'ground_payload_sha256', 'world_anchor',
                      'position_frame', 'bearing_reference', 'runways'), 'compiled geometry')
    require(geometry['schema'] == 'CompiledAirportGeometry/v1' and
            geometry['source_airport_sha256'] == before['airport'][1] and
            geometry['ground_payload_sha256'] == ground_sha and geometry['world_anchor'] == anchor and
            geometry['position_frame'] == 'anchor-eus-metres' and
            geometry['bearing_reference'] == 'published-geographic-true-degrees', 'geometry sources/frame')
    require(len(geometry['runways']) == len(airport['runways']) == 2, 'two source runways')
    endpoint_index = 0
    for index, (actual, original) in enumerate(zip(geometry['runways'], airport['runways'])):
        closed(actual, ('id', 'material_polygon_id', 'published_length_m', 'width_m', 'footprint_mm', 'ends'),
               'compiled runway')
        require(actual['id'] == original['id'] == actual['material_polygon_id'] and
                actual['footprint_mm'] == controls['runway_footprints'][index]['footprint_mm'] and
                actual['published_length_m'] == tag(original['length_m']['value']) and
                actual['width_m'] == tag(original['width_m']['value']) and len(actual['ends']) == 2,
                'source dimensions/polygon relation')
        for end, published in zip(actual['ends'], original['ends']):
            expected = controls['physical_ends'][endpoint_index]
            endpoint_index += 1
            closed(end, ('designator', 'eus_m', 'published_true_bearing_deg'), 'compiled end')
            require(end['designator'] == expected['designator'] == published['designator']['value'] and
                    end['eus_m'] == [expected_tag(v) for v in expected['root']['eus']] and
                    end['published_true_bearing_deg'] == tag(published['true_bearing_deg']['value']),
                    'physical source end/frozen rounded facet/true bearing')
    validation = receipt['validation']
    closed(validation, ('valid_vertices', 'missing_vertices', 'min_up_m', 'max_up_m',
                        'max_gradient_norm', 'bracket_span_m', 'max_pre_round_residual_m',
                        'max_last_delta_m', 'max_post_round_residual_m', 'core_definition_valid',
                        'decoded_source_sha256'), 'validation record')
    require(validation['valid_vertices'] == 6296577 and validation['missing_vertices'] == 0 and
            validation['core_definition_valid'] is True and validation['min_up_m'] == tag(lo) and
            validation['max_up_m'] == tag(hi), 'receipt counts/extrema')
    for field, upper in (('max_pre_round_residual_m', 2.**-12), ('max_last_delta_m', 2.**-12),
                         ('max_post_round_residual_m', 2.**-10), ('max_gradient_norm', 16.),
                         ('bracket_span_m', 2048.)):
        require(0 <= scalar(validation[field]) <= upper, 'reported bounded validation ' + field)
    require(validation['decoded_source_sha256'] == {
        'tile55': '17bfa820d54edca27ab130f945f65f6f159d7e598673d3589415ac392832cb85',
        'tile56': 'bf94d3dd0750bd904198beca2b9d2a5b8ac0cfa4d377ff5b9d39ec427efab8ca'},
        'full decoded-plane identity observations')
    for role in ROLES:
        require(digest(paths[role]) == before[role], 'source changed during comparison ' + role)
    return {'comparison_passed': True, 'selected_f32_words': 81, 'compiled_endpoints': 4,
            'exact_mm_coordinates': 16, 'ground_sha256': ground_sha,
            'receipt_sha256': hashlib.sha256(receipt_raw).hexdigest(),
            'reference_sha256': REFERENCE_SHA, 'compiler_acceptance': False,
            'limits': 'No observed solver-trace comparison. Whole-payload native/core admission, external source-pair preflight, sealed tool closure, all-vertex solver/gradient evidence, repeat determinism/resource/rights/runtime gates remain separate.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--inputs', required=True, type=Path)
    parser.add_argument('--controls', type=Path, default=HERE / 'fixtures/source-controls-v1.json')
    args = parser.parse_args()
    print(json.dumps(compare(args.candidate, args.inputs, args.controls), sort_keys=True, allow_nan=False))
