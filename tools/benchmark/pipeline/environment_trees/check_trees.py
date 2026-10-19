"""Bounded original-evergreen GLB structural checks, standard library only.

Private _check_glb consumes a trusted fixed roster identity. The public bundle
entry admits the closed six-export/source receipt roster, never identity flags.
Structural acceptance never establishes natural artwork, importer or runtime fit.
"""
from fractions import Fraction
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import struct
import sys


class InvalidGlb(ValueError):
    pass


ROSTER = {
    ('tall-narrow', 0): 'OriginalTallNarrowL0', ('tall-narrow', 1): 'OriginalTallNarrowL1',
    ('broad-tiered', 0): 'OriginalBroadTieredL0', ('broad-tiered', 1): 'OriginalBroadTieredL1',
    ('irregular-mature', 0): 'OriginalIrregularMatureL0', ('irregular-mature', 1): 'OriginalIrregularMatureL1',
}
CLASS_BOUNDS = {'tall-narrow': ((24, 26), (4.5, 6), (4.3, 5.8)),
                'broad-tiered': ((18, 20), (8, 11), (7.5, 10.5)),
                'irregular-mature': ((21, 24), (7, 10), (6.5, 9.5))}
MATERIALS = {'EvergreenBark': ([0.125, 0.0625, 0.03125, 1], 0, 0.875),
             'EvergreenInner': ([0.015625, 0.0625, 0.03125, 1], 0, 1),
             'EvergreenOuter': ([0.03125, 0.125, 0.0625, 1], 0, 0.875)}
CHILD_MATERIALS = {'Bark': 'EvergreenBark', 'InnerNeedles': 'EvergreenInner', 'OuterNeedles': 'EvergreenOuter'}
MAX_GLB = 2 * 1024 * 1024
MAX_JSON = 1024 * 1024
CONTRACT_PATH = 'docs/contracts/world/original-evergreens-v1.md'
CONTRACT_SHA = 'eb3aea53ba869b80117eaed952ac1f65ec2e1e3df1fe731524715fd7e3ae40d6'
SOURCE_LEAF = 'assets_source/environment/original-evergreens-v1'
GENERATOR_PATH = SOURCE_LEAF + '/generate_trees.py'
NOTICE_PATH = 'third_party/licenses/notices/OriginalEvergreens-MIT.txt'
NOTICE_SHA = '65f8c7cf7043c71c07865ae41a9dbaf0a4938d4aff3c38162bfd3e0c1aa8205f'
SCOPE = 'Original decorative evergreen art; no botanical, geographic or obstacle claim'
ORDERED_EXPORTS = [(name, lod, 'exports/' + name + '-lod' + str(lod) + '.glb')
                   for name in ('tall-narrow', 'broad-tiered', 'irregular-mature') for lod in (0, 1)]


def _need(value, message):
    if not value:
        raise InvalidGlb(message)


def _object(value, required, optional=()):
    _need(type(value) is dict and set(required) <= value.keys() <= set(required) | set(optional), 'closed object keys')
    return value


def _array(value, length=None):
    _need(type(value) is list and (length is None or len(value) == length), 'array length/type')
    return value


def _integer(value, lo=0, hi=MAX_GLB):
    _need(type(value) is int and lo <= value <= hi, 'integer domain')
    return value


def _number(value):
    _need(type(value) in (int, float), 'JSON numeric type')
    try:
        _need(math.isfinite(value), 'finite JSON number')
    except OverflowError as error:
        raise InvalidGlb('unbounded JSON numeric value') from error
    return value


def _string(value):
    _need(type(value) is str, 'string type')
    try:
        _need(len(value.encode('utf-8', errors='strict')) <= 256, 'bounded string')
    except UnicodeError as error:
        raise InvalidGlb('invalid Unicode string') from error
    return value


def _index(value, length):
    return _integer(value, 0, length - 1)


def _parse(raw):
    _need(type(raw) is bytes and 28 <= len(raw) <= MAX_GLB, 'GLB byte budget')
    _need(struct.unpack_from('<III', raw) == (0x46546C67, 2, len(raw)), 'GLB header')
    json_length, json_type = struct.unpack_from('<II', raw, 12)
    _need(json_type == 0x4E4F534A and 0 < json_length <= MAX_JSON and json_length % 4 == 0, 'JSON chunk header')
    boundary = 20 + json_length
    _need(boundary + 8 <= len(raw), 'JSON span')
    bin_length, bin_type = struct.unpack_from('<II', raw, boundary)
    _need(bin_type == 0x004E4942 and bin_length % 4 == 0 and boundary + 8 + bin_length == len(raw), 'BIN chunk/trailing bytes')
    payload = raw[20:boundary]
    _need(not payload.startswith(b'\xef\xbb\xbf'), 'JSON BOM')
    def pairs(rows):
        result = {}
        for key, value in rows:
            _need(key not in result, 'duplicate JSON key')
            result[key] = value
        return result
    def constant(value):
        raise InvalidGlb('nonfinite JSON constant: ' + value)
    try:
        text = payload.decode('utf-8', errors='strict')
        start = len(text) - len(text.lstrip(' \t\r\n'))
        document, end = json.JSONDecoder(object_pairs_hook=pairs, parse_constant=constant).raw_decode(text, start)
        _need(text[end:] == ' ' * (len(text) - end) and len(text) - end <= 3, 'JSON space padding')
    except (ValueError, UnicodeError, RecursionError) as error:
        raise InvalidGlb('invalid JSON chunk: ' + str(error)) from error
    # Fixed subset needs fewer than a thousand values. Bound malformed nesting
    # and metadata before semantic traversal; no recursive candidate evaluation.
    pending, seen = [(document, 0)], 0
    while pending:
        value, depth = pending.pop()
        seen += 1
        _need(seen <= 10000 and depth <= 16, 'JSON structure budget')
        if type(value) is dict:
            pending.extend((item, depth + 1) for item in value.values())
        elif type(value) is list:
            pending.extend((item, depth + 1) for item in value)
        elif type(value) in (int, float):
            _number(value)
    return document, raw[boundary + 8:]


def _materials(rows):
    _array(rows, 3)
    names = {}
    for material in rows:
        _object(material, ('name', 'pbrMetallicRoughness'), ('alphaMode', 'doubleSided'))
        name = _string(material['name'])
        _need(name in MATERIALS and name not in names, 'material identity roster')
        _need(material.get('alphaMode', 'OPAQUE') == 'OPAQUE' and material.get('doubleSided', False) is False, 'opaque single-sided material')
        pbr = _object(material['pbrMetallicRoughness'], ('baseColorFactor', 'metallicFactor', 'roughnessFactor'))
        expected_rgba, metallic, roughness = MATERIALS[name]
        rgba = _array(pbr['baseColorFactor'], 4)
        for value, expected in zip(rgba, expected_rgba):
            _need(0 <= _number(value) <= 1 and abs(value - expected) <= 1e-6, 'RGBA material factor/domain')
        for key, expected in [('metallicFactor', metallic), ('roughnessFactor', roughness)]:
            value = _number(pbr[key])
            _need(0 <= value <= 1 and abs(value - expected) <= 1e-6, 'PBR factor/domain')
        names[name] = len(names)
    return {index: row['name'] for index, row in enumerate(rows)}


def _sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def _geometry(positions, normals, indices, coincident_faces):
    # Finite decoded f32 coordinates promoted to Python float convert exactly to
    # rationals. No geometric epsilon can turn a degenerate face into a triangle.
    exact_positions = [tuple(Fraction(value) for value in row) for row in positions]
    exact_normals = [tuple(Fraction(value) for value in row) for row in normals]
    faces, edges = [], {}
    for offset in range(0, len(indices), 3):
        ids = indices[offset:offset + 3]
        a, b, c = (exact_positions[index] for index in ids)
        cross = _cross(_sub(b, a), _sub(c, a))
        _need(any(cross), 'degenerate triangle')
        average_direction = tuple(sum(exact_normals[index][axis] for index in ids) for axis in range(3))
        _need(_dot(cross, average_direction) > 0, 'triangle winding opposes/has no normal direction')
        key = tuple(sorted((a, b, c)))
        _need(key not in coincident_faces, 'duplicate coincident triangle')
        coincident_faces.add(key)
        face = len(faces)
        faces.append((a, b, c, cross))
        for u, v in ((a, b), (b, c), (c, a)):
            edges.setdefault(tuple(sorted((u, v))), []).append((face, 1 if u < v else -1))
    neighbors = [set() for _ in faces]
    for owners in edges.values():
        # At most5000triangles, but coincident edges from touching components can
        # have many owners. Union via one owner avoids a quadratic clique.
        first = owners[0][0]
        for face, _ in owners[1:]:
            neighbors[first].add(face)
            neighbors[face].add(first)
    unvisited, components = set(range(len(faces))), []
    while unvisited:
        first = next(iter(unvisited))
        group, todo = set(), [first]
        while todo:
            face = todo.pop()
            if face in group:
                continue
            group.add(face)
            unvisited.discard(face)
            todo.extend(neighbors[face] - group)
        a0, _, _, normal = faces[first]
        coplanar = all(_dot(normal, _sub(vertex, a0)) == 0 for face in group for vertex in faces[face][:3])
        _need(not coplanar, 'zero-thickness coplanar component')
        closed = True
        for owners in edges.values():
            if owners[0][0] in group:
                if len(owners) != 2 or owners[0][1] + owners[1][1] != 0:
                    closed = False
        signed_volume = sum(_dot(faces[face][0], _cross(faces[face][1], faces[face][2])) for face in group) / 6
        if closed:
            _need(signed_volume > 0, 'closed component has inward winding/zero signed volume')
        components.append({'triangles': len(group), 'closed_oriented_edge_incidence': closed,
                           'signed_volume_m3_when_closed': float(signed_volume) if closed else None})
    return components


def _check_glb(raw, silhouette, lod):
    """Private trusted-roster check. Returns structure-only observations or raises.

    The caller, never candidate metadata, chooses the fixed roster identity.
    """
    _need(type(silhouette) is str and type(lod) is int and (silhouette, lod) in ROSTER, 'trusted roster identity')
    root_name = ROSTER[(silhouette, lod)]
    max_vertices, max_triangles = (15000, 5000) if lod == 0 else (2700, 900)
    document, binary = _parse(raw)
    _object(document, ('asset', 'scene', 'scenes', 'nodes', 'meshes', 'materials', 'accessors', 'bufferViews', 'buffers'))
    asset = _object(document['asset'], ('version',), ('generator', 'copyright'))
    _need(asset['version'] == '2.0', 'glTF version')
    for key in ('generator', 'copyright'):
        if key in asset:
            _string(asset[key])
    scenes = _array(document['scenes'], 1)
    _need(_index(document['scene'], 1) == 0, 'sole default scene')
    scene = _object(scenes[0], ('nodes',), ('name',))
    if 'name' in scene:
        _string(scene['name'])
    nodes = _array(document['nodes'], 4)
    names = {}
    for index, node in enumerate(nodes):
        _object(node, ('name',), ('children', 'mesh', 'translation', 'rotation', 'scale'))
        name = _string(node['name'])
        _need(name not in names, 'duplicate node name')
        names[name] = index
        for key, identity in [('translation', [0, 0, 0]), ('rotation', [0, 0, 0, 1]), ('scale', [1, 1, 1])]:
            if key in node:
                values = _array(node[key], len(identity))
                _need(all(_number(value) == expected for value, expected in zip(values, identity)), 'nonidentity transform')
    _need(set(names) == {root_name, *CHILD_MATERIALS}, 'exact node-name roster')
    root_index = names[root_name]
    _need(_array(scene['nodes'], 1) == [root_index] and type(scene['nodes'][0]) is int, 'scene owns sole root')
    root = nodes[root_index]
    _need('mesh' not in root, 'root has no mesh')
    children = _array(root.get('children'), 3)
    _need(all(type(value) is int for value in children) and set(children) == {names[name] for name in CHILD_MATERIALS}, 'root direct children')
    material_names = _materials(document['materials'])
    meshes = _array(document['meshes'], 3)
    accessors = _array(document['accessors'], 9)
    views = _array(document['bufferViews'], 9)
    buffers = _array(document['buffers'], 1)
    buffer = _object(buffers[0], ('byteLength',))
    declared_bytes = _integer(buffer['byteLength'], 1)
    _need(0 <= len(binary) - declared_bytes <= 3 and not any(binary[declared_bytes:]), 'BIN declared length/zero padding')
    binary = binary[:declared_bytes]
    intervals = []
    for index, view in enumerate(views):
        _object(view, ('buffer', 'byteLength'), ('byteOffset', 'target'))
        _need(type(view['buffer']) is int and view['buffer'] == 0, 'sole buffer reference')
        offset = _integer(view.get('byteOffset', 0))
        length = _integer(view['byteLength'], 1)
        _need(offset <= declared_bytes and length <= declared_bytes - offset, 'bufferView span')
        intervals.append((offset, offset + length, index))
    previous = 0
    for start, end, _ in sorted(intervals):
        _need(start >= previous, 'overlapping bufferViews')
        previous = end
    used_meshes, used_accessors, used_views, used_spans = set(), set(), set(), []
    decoded = {}
    for name in CHILD_MATERIALS:
        node = nodes[names[name]]
        _need('children' not in node, 'mesh child has no descendants')
        mesh_id = _index(node.get('mesh'), 3)
        _need(mesh_id not in used_meshes, 'mesh sharing/unreferenced mesh')
        used_meshes.add(mesh_id)
        mesh = _object(meshes[mesh_id], ('primitives',), ('name',))
        if 'name' in mesh:
            _string(mesh['name'])
        primitive = _object(_array(mesh['primitives'], 1)[0], ('attributes', 'indices', 'material'), ('mode',))
        _need(type(primitive.get('mode', 4)) is int and primitive.get('mode', 4) == 4, 'TRIANGLES primitive')
        material_id = _index(primitive['material'], 3)
        _need(material_names[material_id] == CHILD_MATERIALS[name], 'mesh/material meaning')
        attributes = _object(primitive['attributes'], ('POSITION', 'NORMAL'))
        data = {}
        for role, accessor_id in [('POSITION', attributes['POSITION']), ('NORMAL', attributes['NORMAL']), ('indices', primitive['indices'])]:
            accessor_id = _index(accessor_id, 9)
            _need(accessor_id not in used_accessors, 'shared/unreferenced accessor')
            used_accessors.add(accessor_id)
            accessor = _object(accessors[accessor_id], ('bufferView', 'componentType', 'count', 'type'), ('byteOffset', 'normalized', 'min', 'max'))
            _need(accessor.get('normalized', False) is False, 'normalized accessor')
            view_id = _index(accessor['bufferView'], 9)
            _need(view_id not in used_views, 'shared/unreferenced bufferView')
            used_views.add(view_id)
            view = views[view_id]
            component = accessor['componentType']
            _need(type(component) is int, 'component integer type')
            if role == 'indices':
                _need(component in (5123, 5125) and accessor['type'] == 'SCALAR', 'index accessor format')
                count = _integer(accessor['count'], 3, 3 * max_triangles)
                _need(count % 3 == 0, 'triangle index count')
                unit, code, width, target = (2, 'H', 1, 34963) if component == 5123 else (4, 'I', 1, 34963)
            else:
                _need(component == 5126 and accessor['type'] == 'VEC3', 'vertex accessor format')
                count = _integer(accessor['count'], 1, max_vertices)
                unit, code, width, target = 4, 'f', 3, 34962
            if 'target' in view:
                _need(type(view['target']) is int and view['target'] == target, 'bufferView target')
            local = _integer(accessor.get('byteOffset', 0))
            view_offset = view.get('byteOffset', 0)
            length = count * unit * width
            _need(local % unit == 0 and view_offset % unit == 0 and (role == 'indices' or (view_offset + local) % 4 == 0), 'accessor alignment')
            _need(local <= view['byteLength'] and length <= view['byteLength'] - local, 'accessor span before read')
            start, end = view_offset + local, view_offset + local + length
            values = list(struct.iter_unpack('<' + code * width, binary[start:end]))
            _need(len(values) == count, 'decoded count')
            _need(all(math.isfinite(value) for row in values for value in row), 'nonfinite vertex/normal')
            minima = [min(row[axis] for row in values) for axis in range(width)]
            maxima = [max(row[axis] for row in values) for axis in range(width)]
            _need(role != 'POSITION' or {'min', 'max'} <= accessor.keys(), 'POSITION extrema required')
            for key, expected in [('min', minima), ('max', maxima)]:
                if key in accessor:
                    supplied = _array(accessor[key], width)
                    _need(all(_number(actual) == wanted for actual, wanted in zip(supplied, expected)), 'accessor extrema disagree with decoded values')
            used_spans.append((start, end))
            data[role] = values if role != 'indices' else [row[0] for row in values]
            if role == 'POSITION':
                data['aabb_min'], data['aabb_max'] = minima, maxima
        _need(len(data['POSITION']) == len(data['NORMAL']), 'position/normal count mismatch')
        _need(all(0 <= index < len(data['POSITION']) for index in data['indices']), 'index exceeds vertex count')
        _need(all(abs(math.sqrt(sum(value * value for value in normal)) - 1) <= 1e-4 for normal in data['NORMAL']), 'normal length')
        decoded[name] = data
    _need(len(used_meshes) == 3 and len(used_accessors) == len(used_views) == 9, 'unreferenced objects')
    previous = 0
    for start, end in sorted(used_spans):
        _need(start >= previous and not any(binary[previous:start]), 'nonzero unused alignment bytes')
        previous = end
    _need(not any(binary[previous:]), 'nonzero trailing unused buffer bytes')
    total_vertices = sum(len(data['POSITION']) for data in decoded.values())
    total_triangles = sum(len(data['indices']) // 3 for data in decoded.values())
    _need(total_vertices <= max_vertices and total_triangles <= max_triangles, 'tree resource ceiling')
    all_positions = [position for data in decoded.values() for position in data['POSITION']]
    _need(all(abs(x) <= 8 and abs(z) <= 8 and -1e-5 <= y <= 26 for x, y, z in all_positions), 'hard meter-space coordinate limits')
    minimum = [min(position[axis] for position in all_positions) for axis in range(3)]
    maximum = [max(position[axis] for position in all_positions) for axis in range(3)]
    _need(abs(minimum[1]) <= 1e-5 and minimum[0] < 0 < maximum[0] and minimum[2] < 0 < maximum[2], 'foot pivot/axis bounds')
    height, width, depth = maximum[1] - minimum[1], maximum[0] - minimum[0], maximum[2] - minimum[2]
    for value, (low, high) in zip((height, width, depth), CLASS_BOUNDS[silhouette]):
        _need(low - 1e-5 <= value <= high + 1e-5, 'silhouette authored dimensions')
    bark = decoded['Bark']
    _need(abs(bark['aabb_min'][1]) <= 1e-5 and bark['aabb_min'][0] < 0 < bark['aabb_max'][0] and bark['aabb_min'][2] < 0 < bark['aabb_max'][2], 'Bark foot/axis bounds')
    canopy_low = min(decoded[name]['aabb_min'][1] for name in ('InnerNeedles', 'OuterNeedles'))
    _need(bark['aabb_max'][1] >= canopy_low, 'trunk does not reach canopy bounds')
    coincident_faces, geometry = set(), {}
    for name, data in decoded.items():
        geometry[name] = _geometry(data['POSITION'], data['NORMAL'], data['indices'], coincident_faces)
    return {'kind': 'OriginalEvergreenGlbStructure/v1', 'structural_pass': True, 'silhouette': silhouette, 'lod': lod,
            'root': root_name, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
            'vertices': total_vertices, 'triangles': total_triangles, 'materials': 3,
            'aabb_min': minimum, 'aabb_max': maximum, 'height_width_depth_m': [height, width, depth],
            'geometric_components': geometry,
            'artwork_accepted': False, 'full_bundle_accepted': False, 'import_accepted': False, 'runtime_accepted': False,
            'limits': ['Structural bounds do not prove continuous plausible trunk/solid axis coverage, botanical art or visual silhouettes.',
                       'No blanket watertight topology rule is introduced; nonclosed components require visual/export review.',
                       'No six-file roster/source receipt/LOD-pair provenance or actual importer/capture validation is established.']}


def _plain(path):
    path = Path(path)
    _need(path.is_absolute() and not str(path).startswith('\\\\'), 'absolute ordinary local path required')
    _need(all(':' not in part for part in path.parts[1:]), 'alternate stream path')
    path = Path(os.path.abspath(path))
    for parent in (path, *path.parents):
        try:
            info = parent.lstat()
        except FileNotFoundError:
            continue
        _need(not stat.S_ISLNK(info.st_mode) and not getattr(info, 'st_file_attributes', 0) & 0x400, 'symlink/reparse path')
        _need(stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode), 'special path')
        if stat.S_ISREG(info.st_mode):
            _need(info.st_nlink == 1, 'hard-linked input')
    return path


def _file(path, maximum):
    path = _plain(path)
    _need(path.is_file() and 0 < path.stat().st_size <= maximum, 'file byte bound')
    raw = path.read_bytes()
    _need(0 < len(raw) <= maximum, 'file byte bound after read')
    return raw


def _hash(raw):
    return hashlib.sha256(raw).hexdigest()


def _hex(value):
    _need(type(value) is str and re.fullmatch('[0-9a-f]{64}', value) is not None, 'SHA256 syntax')
    return value


def _receipt(raw):
    _need(len(raw) <= 65536 and not raw.startswith(b'\xef\xbb\xbf'), 'receipt size/BOM')
    def pairs(rows):
        value = {}
        for key, item in rows:
            _need(key not in value, 'duplicate receipt key')
            value[key] = item
        return value
    def bad(value):
        raise InvalidGlb('receipt nonfinite constant: ' + value)
    try:
        value = json.loads(raw.decode('utf-8', errors='strict'), object_pairs_hook=pairs, parse_constant=bad)
    except (ValueError, UnicodeError, RecursionError) as error:
        raise InvalidGlb('receipt JSON: ' + str(error)) from error
    pending, count = [(value, 0)], 0
    while pending:
        item, depth = pending.pop()
        count += 1
        _need(depth <= 8 and count <= 1024, 'receipt depth/value bound')
        if type(item) is dict:
            pending.extend((child, depth + 1) for child in item.values())
        elif type(item) is list:
            pending.extend((child, depth + 1) for child in item)
        elif type(item) in (int, float):
            _number(item)
    return value


def _trusted_source_pins(project):
    contract = _file(project / CONTRACT_PATH, 65536)
    _need(_hash(contract) == CONTRACT_SHA and b'\r' not in contract, 'checked LF contract identity')
    generator = _file(project / GENERATOR_PATH, 1024 * 1024)
    notice = _file(project / NOTICE_PATH, 16384)
    _need(_hash(notice) == NOTICE_SHA and b'\r' not in notice, 'fixed full original MIT notice identity/encoding')
    return {'contract_sha256': CONTRACT_SHA,
            'generator': {'path': GENERATOR_PATH, 'sha256': _hash(generator)},
            'notice': {'path': NOTICE_PATH, 'sha256': _hash(notice)}}


def _candidate_roster(source, project):
    tracked = project / SOURCE_LEAF
    local = project / '.local'
    _need(source == tracked or (source != local and source.is_relative_to(local)), 'candidate must be fixed tracked leaf or checkout .local')
    _need(source.is_dir(), 'candidate directory absent')
    permitted = {path for _, _, path in ORDERED_EXPORTS} | {'original-evergreens.blend', 'evergreen-source-v1.json'}
    if source == tracked:
        permitted |= {'README.md', 'generate_trees.py'}
    files, dirs, todo = set(), set(), [source]
    while todo:
        folder = todo.pop()
        for path in folder.iterdir():
            path = _plain(path)
            relative = path.relative_to(source).as_posix()
            if path.is_dir():
                _need(relative == 'exports', 'extra candidate directory')
                dirs.add(relative)
                todo.append(path)
            else:
                _need(relative in permitted and relative not in files, 'extra/aliased candidate file')
                files.add(relative)
    _need(dirs == {'exports'} and files == permitted, 'missing candidate roster entry')


def _check_bundle(source_dir, project_root=None):
    # project_root is private for independent synthetic filesystem tests only.
    # Public CLI always derives the reviewed checkout from this module's path.
    project = _plain(Path(__file__).absolute().parents[4] if project_root is None else project_root)
    source = _plain(source_dir)
    pins = _trusted_source_pins(project)
    _candidate_roster(source, project)
    receipt_raw = _file(source / 'evergreen-source-v1.json', 65536)
    receipt = _object(_receipt(receipt_raw), ('kind', 'version', 'license', 'scope', 'contract_sha256', 'generator', 'blender', 'blend', 'exports', 'notice'))
    _need(receipt['kind'] == 'OriginalEvergreenSource/v1' and type(receipt['version']) is int and receipt['version'] == 1 and receipt['license'] == 'MIT' and receipt['scope'] == SCOPE, 'source receipt identity/scope')
    _need(_hex(receipt['contract_sha256']) == pins['contract_sha256'], 'receipt contract hash')
    for key in ('generator', 'notice'):
        record = _object(receipt[key], ('path', 'sha256'))
        _need(record['path'] == pins[key]['path'] and _hex(record['sha256']) == pins[key]['sha256'], 'fixed source/notice hash')
    blender = _object(receipt['blender'], ('version', 'build_hash'))
    _need(blender == {'version': '4.5.14 LTS', 'build_hash': '62c1db4208e8'}, 'receipt Blender readback strings')
    blend = _object(receipt['blend'], ('path', 'bytes', 'sha256'))
    _need(blend['path'] == 'original-evergreens.blend', 'blend relative path')
    blend_raw = _file(source / blend['path'], 32 * 1024 * 1024)
    _need(_integer(blend['bytes'], 12, 32 * 1024 * 1024) == len(blend_raw) and _hex(blend['sha256']) == _hash(blend_raw), 'blend byte identity')
    _need(len(blend_raw) >= 12 and blend_raw[:7] == b'BLENDER' and blend_raw[7:8] in (b'-', b'_') and blend_raw[8:9] in (b'v', b'V') and blend_raw[9:12].isdigit(), 'ordinary uncompressed blend header')
    exports, reports, aggregate = _array(receipt['exports'], 6), [], 0
    for row, (silhouette, lod, path) in zip(exports, ORDERED_EXPORTS):
        _object(row, ('id', 'lod', 'path', 'bytes', 'sha256'))
        _need(row['id'] == silhouette and type(row['lod']) is int and row['lod'] == lod and row['path'] == path, 'ordered closed export roster')
        raw = _file(source / path, MAX_GLB)
        _need(_integer(row['bytes'], 28, MAX_GLB) == len(raw) and _hex(row['sha256']) == _hash(raw), 'export byte identity')
        aggregate += len(raw)
        reports.append(_check_glb(raw, silhouette, lod))
    _need(aggregate <= 12 * 1024 * 1024, 'six-export byte budget')
    for index in (0, 2, 4):
        for key in ('aabb_min', 'aabb_max'):
            _need(all(abs(a - b) <= 0.02 for a, b in zip(reports[index][key], reports[index + 1][key])), 'paired LOD bounds exceed0.02m')
    _need(_trusted_source_pins(project) == pins, 'trusted source continuity')
    _need(_file(source / 'evergreen-source-v1.json', 65536) == receipt_raw, 'receipt continuity')
    for row in [blend, *exports]:
        raw = _file(source / row['path'], 32 * 1024 * 1024 if row is blend else MAX_GLB)
        _need(len(raw) == row['bytes'] and _hash(raw) == row['sha256'], 'candidate file continuity')
    _candidate_roster(source, project)
    return {'kind': 'OriginalEvergreenBundleStructure/v1', 'source_receipt_integrity_pass': True,
            'all_six_glb_structure_pass': True, 'lod_pair_bounds_pass': True, 'export_bytes': aggregate,
            'source_receipt_sha256': _hash(receipt_raw), 'source_pins': pins, 'blend': blend, 'exports': reports,
            'artwork_accepted': False, 'import_accepted': False, 'runtime_accepted': False,
            'limits': ['Receipt tool strings are not independent executable/invocation proof.',
                       'Blend header/hash are checked; editable content, scripts/external links and source/export correspondence require isolated Blender review.',
                       'Structural boxes can pass these synthetic source/LOD checks; visual tree art is a separate gate.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', required=True)
    args = parser.parse_args()
    try:
        report = _check_bundle(args.source_dir)
        print(json.dumps(report, sort_keys=True, allow_nan=False))
        return 0
    except (InvalidGlb, OSError) as error:
        print('EVERGREEN_STRUCTURE_REFUSED ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
