"""Original static evergreen studies. Run only through reviewed pinned Blender.

blender --background --factory-startup --python THIS_FILE -- --output FRESH_DIR
No source imagery/assets, compiler, imported script or runtime placement is used.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import stat
import struct
import sys

import bpy


ROOT = Path(__file__).absolute().parents[3]
CONTRACT = 'docs/contracts/world/original-evergreens-v1.md'
CONTRACT_SHA = 'eb3aea53ba869b80117eaed952ac1f65ec2e1e3df1fe731524715fd7e3ae40d6'
GENERATOR = 'assets_source/environment/original-evergreens-v1/generate_trees.py'
NOTICE = 'third_party/licenses/notices/OriginalEvergreens-MIT.txt'
NOTICE_SHA = '65f8c7cf7043c71c07865ae41a9dbaf0a4938d4aff3c38162bfd3e0c1aa8205f'
SCOPE = 'Original decorative evergreen art; no botanical, geographic or obstacle claim'
MATERIALS = [('EvergreenBark', (0.125, 0.0625, 0.03125, 1), 0.875),
             ('EvergreenInner', (0.015625, 0.0625, 0.03125, 1), 1),
             ('EvergreenOuter', (0.03125, 0.125, 0.0625, 1), 0.875)]
# Explicit original design dimensions/seeds, not measurements or source species.
DESIGNS = [
    {'id': 'tall-narrow', 'root': 'OriginalTallNarrow', 'height': 25.0, 'half_x': 2.5, 'half_y': 2.5,
     'seed': 17231, 'trunk_radius': 0.34, 'core_offset': (0.04, -0.06)},
    {'id': 'broad-tiered', 'root': 'OriginalBroadTiered', 'height': 19.0, 'half_x': 4.75, 'half_y': 4.5,
     'seed': 29411, 'trunk_radius': 0.42, 'core_offset': (-0.08, 0.09)},
    {'id': 'irregular-mature', 'root': 'OriginalIrregularMature', 'height': 22.5, 'half_x': 4.25, 'half_y': 4.0,
     'seed': 59357, 'trunk_radius': 0.55, 'core_offset': (0.19, -0.16)},
]


def need(condition, message):
    if not condition:
        raise RuntimeError(message)


def ordinary(path):
    path = Path(path)
    need(path.is_absolute() and not str(path).startswith('\\\\'), 'absolute ordinary path required')
    need(all(':' not in part for part in path.parts[1:]), 'alternate stream refused')
    path = Path(os.path.abspath(path))
    for parent in (path, *path.parents):
        try:
            info = parent.lstat()
        except FileNotFoundError:
            continue
        need(not stat.S_ISLNK(info.st_mode) and not getattr(info, 'st_file_attributes', 0) & 0x400, 'symlink/reparse refused')
        need(stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode), 'special path refused')
        if stat.S_ISREG(info.st_mode):
            need(info.st_nlink == 1, 'hard-linked project input refused')
    return path


def pin(path):
    raw = ordinary(path).read_bytes()
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


def write_new(path, raw):
    ordinary(path)
    with path.open('xb') as stream:
        stream.write(raw)


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(vector):
    length = math.sqrt(sum(value * value for value in vector))
    need(math.isfinite(length) and length > 0, 'authored nonzero direction')
    return tuple(value / length for value in vector)


class Geometry:
    def __init__(self):
        self.vertices, self.faces = [], []

    def connected_rings(self, rings, start, end):
        sides = len(rings[0])
        need(all(len(ring) == sides for ring in rings), 'authoring ring correspondence')
        base = len(self.vertices)
        for ring in rings:
            self.vertices.extend(ring)
        first, last = len(self.vertices), len(self.vertices) + 1
        self.vertices.extend((start, end))
        for ring in range(len(rings) - 1):
            for side in range(sides):
                a = base + ring * sides + side
                b = base + ring * sides + (side + 1) % sides
                c, d = b + sides, a + sides
                self.faces.extend(((a, b, c), (a, c, d)))
        top = base + (len(rings) - 1) * sides
        for side in range(sides):
            other = (side + 1) % sides
            self.faces.extend(((first, base + other, base + side), (last, top + side, top + other)))

    def absorb_faces(self, geometry, face_indices):
        # Assign original branch-clump faces to needle materials, without
        # introducing a second surface or changing their authored positions.
        mapping = {}
        for index in face_indices:
            face = []
            for source in geometry.faces[index]:
                if source not in mapping:
                    mapping[source] = len(self.vertices)
                    self.vertices.append(geometry.vertices[source])
                face.append(mapping[source])
            self.faces.append(tuple(face))

    def branch_clump(self, design, plan, lod):
        # A radial solid, with a horizontal longitudinal axis and a vertical
        # cross section. Every LOD retains every branch and its two end tips.
        # Central-ring cardinal vertices are identical before simplification.
        sides = 8 if lod == 0 else 4
        stations = (-0.58, 0.0, 0.58) if lod == 0 else (0.0,)
        # Intermediate shoulders follow the same linear end-to-center taper
        # as LOD1 rather than making a broad body that vanishes in LOD1.
        widths = (0.42, 1.0, 0.42) if lod == 0 else (1.0,)
        hx, hy = design['half_x'], design['half_y']
        ca, sa = math.cos(plan['angle']), math.sin(plan['angle'])
        radius, across = plan['radius'], plan['across']
        center, half_height, droop = plan['center'], plan['half_height'], plan['droop']
        rings = []
        for station, width in zip(stations, widths):
            ring = []
            for index in range(sides):
                theta = 2 * math.pi * index / sides
                # Only diagonal corners receive small uneven scallops. Neither
                # cardinal dimensions nor the shared LOD1 central ring depend
                # on the diagonal refinement or on a post-export adjustment.
                scallop = 1 - (0.21 + 0.05 * math.sin(plan['phase'] + theta + station)) * math.sin(2 * theta) ** 2
                lateral = across * width * scallop * math.cos(theta)
                vertical = half_height * width * scallop * math.sin(theta)
                radial = radius * (0.52 + 0.48 * station)
                ring.append((hx * (radial * ca - lateral * sa),
                             hy * (radial * sa + lateral * ca),
                             center[2] - droop * station + vertical))
            rings.append(ring)
        self.connected_rings(rings,
                             (hx * radius * 0.04 * ca, hy * radius * 0.04 * sa, center[2] + droop),
                             (hx * radius * ca, hy * radius * sa, center[2] - droop))

    def crown(self, design, lod):
        # Narrow dark internal support only; the individual branch clumps own
        # the crown outline and reach the top independently of this support.
        sides = 12 if lod == 0 else 8
        levels = (0.185, 0.25, 0.34, 0.43, 0.52, 0.61, 0.70, 0.79)
        hx, hy, height = design['half_x'], design['half_y'], design['height']
        ox, oy = design['core_offset']
        rings = []
        # This support is much narrower than the radial branch masses. It must
        # never become another dominant smooth, full-width canopy.
        support_radii = (0.10, 0.17, 0.16, 0.13, 0.10, 0.08, 0.05, 0.02)
        for ring_index, (level, radius) in enumerate(zip(levels, support_radii)):
            bend_x = ox + 0.035 * math.sin(5 * level)
            bend_y = oy - 0.025 * math.sin(7 * level)
            ring = []
            for index in range(sides):
                theta = 2 * math.pi * index / sides
                contour = 1 - 0.085 * math.sin(3 * theta + 0.39 * ring_index) ** 2
                ring.append((bend_x + hx * radius * contour * math.cos(theta),
                             bend_y + hy * radius * contour * math.sin(theta), height * level))
            rings.append(ring)
        self.connected_rings(rings, (ox, oy, height * 0.16),
                             (ox, oy, height * 0.82))

    def tube(self, start, end, start_radius, end_radius, sides):
        axis = unit(sub(end, start))
        reference = (1, 0, 0) if abs(axis[2]) > 0.9 else (0, 0, 1)
        u = unit(cross(reference, axis))
        v = cross(axis, u)
        rings = []
        for center, radius in ((start, start_radius), (end, end_radius)):
            rings.append([tuple(center[k] + radius * (u[k] * math.cos(2 * math.pi * i / sides) + v[k] * math.sin(2 * math.pi * i / sides))
                                for k in range(3)) for i in range(sides)])
        self.connected_rings(rings, start, end)


def plans(design):
    height, hx, hy = design['height'], design['half_x'], design['half_y']
    rng = random.Random(design['seed'])
    result = []
    mature = design['id'] == 'irregular-mature'
    broad = design['id'] == 'broad-tiered'
    # These are source shapes, not botanical measurements. Taller narrow crowns
    # taper steadily; the broad crown carries lower mass; mature mass bulges
    # higher with unequal branch lengths, droop and azimuths.
    levels = (0.18, 0.30, 0.45, 0.60, 0.75, 0.88, 0.965)
    profiles = {
        'tall-narrow': (0.82, 1.0, 0.84, 0.63, 0.41, 0.22, 0.06),
        'broad-tiered': (0.78, 1.0, 0.82, 0.61, 0.41, 0.23, 0.07),
        'irregular-mature': (0.63, 0.88, 1.0, 0.84, 0.62, 0.34, 0.10)}
    profile = profiles[design['id']]

    def envelope(level):
        for index in range(len(levels) - 1):
            if level <= levels[index + 1]:
                t = (level - levels[index]) / (levels[index + 1] - levels[index])
                return profile[index] * (1 - t) + profile[index + 1] * t
        return profile[-1]

    def add(angle, level, radius, width, thickness, droop):
        result.append({'center': (0.52 * hx * radius * math.cos(angle),
                                  0.52 * hy * radius * math.sin(angle), height * level),
                       'radius': radius, 'across': radius * width,
                       'half_height': height * thickness, 'angle': angle,
                       'phase': rng.uniform(0, 2 * math.pi), 'droop': height * droop})

    # Four complete low/mid branch masses carry the exact shared authored X/Y
    # extents in both LODs. Their tips occur at unequal heights, not on a plate.
    peak = 0.41 if mature else (0.275 if broad else 0.29)
    for index, angle in enumerate((0, math.pi / 2, math.pi, 3 * math.pi / 2)):
        add(angle, peak + (0.0, 0.023, -0.016, 0.011)[index], 1.0,
            0.46 if broad else 0.43, 0.040 if mature else 0.034,
            (0.022 if broad else 0.016) * (1 + 0.12 * index))

    # A golden-angle progression visits different sides at consecutive heights.
    # Each branch stretches from 4% of its radius near the trunk to its radial
    # tip; overlapping wide central sections provide crown mass at BOTH LODs.
    # No full-circle surface or synchronized horizontal ring is authored.
    golden = math.pi * (3 - math.sqrt(5))
    for index in range(59):
        u = index / 58
        level = 0.205 + 0.750 * u + rng.uniform(-0.005, 0.005)
        angle = index * golden + rng.uniform(-0.13, 0.13) + (0.63 if mature else (0.29 if broad else 0.07))
        irregularity = 0.84 + 0.14 * rng.random()
        if mature:
            irregularity *= 0.91 + 0.09 * math.sin(angle + 1.7 * u) ** 2
        radius = envelope(level) * irregularity
        width = (0.47 if broad else (0.46 if mature else 0.43)) * rng.uniform(0.92, 1.10)
        thickness = ((0.039 if mature else (0.035 if broad else 0.032)) - 0.015 * u) * rng.uniform(0.92, 1.08)
        droop = (0.021 if broad else (0.018 if mature else 0.013)) * (1 - 0.60 * u) * rng.uniform(0.85, 1.15)
        add(angle, level, radius, width, thickness, droop)

    # The final small branch has a shared upper cardinal vertex exactly at H.
    # Its short radial axis and modest droop complete the tapered leader rather
    # than extending the internal support into a long smooth needle.
    add(0.73 if mature else 0.31, 0.975, 0.065 if mature else 0.050,
        0.43, 0.025, 0.008)
    need(len(result) == 64, 'original shared branch-clump roster')
    return result


def branch_canopy(design, lod, all_plans, inner, outer):
    sides = 8 if lod == 0 else 4
    ring_count = 3 if lod == 0 else 1
    side_faces = 2 * sides * (ring_count - 1)
    for plan in all_plans:
        branch = Geometry()
        branch.branch_clump(design, plan, lod)
        light_faces, dark_faces = [], []
        for index in range(len(branch.faces)):
            # The same radial solid owns both surfaces. Split its upper and
            # lower half by authored cross-section side, including end fans;
            # dark undersides are not separate overlapping garnish geometry.
            side = (index // 2) % sides if index < side_faces else (index - side_faces) // 2
            (light_faces if side < sides // 2 else dark_faces).append(index)
        outer.absorb_faces(branch, light_faces)
        inner.absorb_faces(branch, dark_faces)


def build_geometry(design, lod):
    height, hx, hy = design['height'], design['half_x'], design['half_y']
    bark, inner, outer = Geometry(), Geometry(), Geometry()
    sides = 12 if lod == 0 else 8
    levels = (0, 0.04, 0.18, 0.35, 0.56, 0.74, 0.87, 0.94) if lod == 0 else (0, 0.08, 0.32, 0.57, 0.79, 0.94)
    rings = []
    for level in levels:
        radius = design['trunk_radius'] * (1 - 0.92 * (level / 0.94) ** 0.7)
        rings.append([(radius * math.cos(2 * math.pi * i / sides), radius * math.sin(2 * math.pi * i / sides), height * level) for i in range(sides)])
    bark.connected_rings(rings, (0, 0, 0), (0, 0, height * 0.94))
    all_plans = plans(design)
    # All 64 original radial branch masses survive LOD1. Only cross-section
    # refinement changes; no branches disappear and no circular plates remain.
    branch_canopy(design, lod, all_plans, inner, outer)
    inner.crown(design, lod)
    branches = list(range(20)) if lod == 0 else [0, 1, 2, 3, 4, 7, 10, 13]
    for index in branches:
        center = all_plans[index]['center']
        bark.tube((0, 0, center[2] + height * 0.05), (center[0] * 0.92, center[1] * 0.92, center[2] - height * 0.025),
                  height * 0.003, 0.022, 6 if lod == 0 else 4)
    return [('Bark', bark), ('InnerNeedles', inner), ('OuterNeedles', outer)]


def materials():
    result = []
    for name, rgba, roughness in MATERIALS:
        material = bpy.data.materials.new(name)
        material.diffuse_color = rgba
        material.use_nodes = True
        material.use_backface_culling = True
        principled = material.node_tree.nodes.get('Principled BSDF')
        need(principled is not None, 'factory Principled material')
        principled.inputs['Base Color'].default_value = rgba
        principled.inputs['Metallic'].default_value = 0
        principled.inputs['Roughness'].default_value = roughness
        principled.inputs['Alpha'].default_value = 1
        result.append(material)
    return result


def gltf_vector(vector):
    return (float(vector[0]), float(vector[2]), -float(vector[1]))


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def export_glb(root_name, objects):
    binary, views, accessors, meshes = bytearray(), [], [], []
    total_triangles, total_vertices = 0, 0
    def append(values, role):
        while len(binary) % 4:
            binary.append(0)
        start = len(binary)
        for row in values:
            binary.extend(struct.pack('<' + ('H' if role == 'indices' else 'fff'), *row))
        view = len(views)
        views.append({'buffer': 0, 'byteOffset': start, 'byteLength': len(binary) - start,
                      'target': 34963 if role == 'indices' else 34962})
        accessor = {'bufferView': view, 'componentType': 5123 if role == 'indices' else 5126,
                    'count': len(values), 'type': 'SCALAR' if role == 'indices' else 'VEC3'}
        if role == 'POSITION':
            accessor['min'] = [min(row[k] for row in values) for k in range(3)]
            accessor['max'] = [max(row[k] for row in values) for k in range(3)]
        accessors.append(accessor)
        return len(accessors) - 1
    for material_index, obj in enumerate(objects):
        mesh = obj.data
        positions, normals = [], []
        # Export actual stored bpy Float32 positions. Flat corner normals are
        # computed from those positions; this is the first export, not a repair.
        for face in mesh.polygons:
            need(len(face.vertices) == 3, 'original source triangles only')
            triangle = [gltf_vector(mesh.vertices[index].co) for index in face.vertices]
            normal = tuple(f32(value) for value in unit(cross(sub(triangle[1], triangle[0]), sub(triangle[2], triangle[0]))))
            positions.extend(triangle)
            normals.extend([normal] * 3)
        total_triangles += len(positions) // 3
        total_vertices += len(positions)
        p, n, indices = append(positions, 'POSITION'), append(normals, 'NORMAL'), append([(i,) for i in range(len(positions))], 'indices')
        meshes.append({'primitives': [{'attributes': {'POSITION': p, 'NORMAL': n}, 'indices': indices, 'material': material_index, 'mode': 4}]})
    lod = int(root_name[-1])
    need(total_triangles <= (5000 if lod == 0 else 900) and total_vertices <= (15000 if lod == 0 else 2700), 'original authored resource budget')
    document = {'asset': {'version': '2.0', 'generator': 'OriginalEvergreens/v1 explicit Blender mesh export', 'copyright': '2026 Flight Simulator contributors'},
                'scene': 0, 'scenes': [{'nodes': [0]}],
                'nodes': [{'name': root_name, 'children': [1, 2, 3]}] + [{'name': name, 'mesh': i} for i, name in enumerate(('Bark', 'InnerNeedles', 'OuterNeedles'))],
                'meshes': meshes, 'accessors': accessors, 'bufferViews': views, 'buffers': [{'byteLength': len(binary)}],
                'materials': [{'name': name, 'pbrMetallicRoughness': {'baseColorFactor': list(rgba), 'metallicFactor': 0, 'roughnessFactor': roughness},
                               'alphaMode': 'OPAQUE', 'doubleSided': False} for name, rgba, roughness in MATERIALS]}
    payload = json.dumps(document, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')
    payload += b' ' * (-len(payload) % 4)
    binary.extend(b'\0' * (-len(binary) % 4))
    need(len(payload) <= 1024 * 1024, 'JSON export budget')
    raw = struct.pack('<III', 0x46546C67, 2, 28 + len(payload) + len(binary)) + struct.pack('<II', len(payload), 0x4E4F534A) + payload + struct.pack('<II', len(binary), 0x004E4942) + bytes(binary)
    need(len(raw) <= 2 * 1024 * 1024, 'GLB export budget')
    return raw


def main():
    need(bpy.app.version_string == '4.5.14 LTS' and bpy.app.build_hash.decode() == '62c1db4208e8', 'reviewed Blender identity')
    need('--factory-startup' in sys.argv and '--background' in sys.argv, 'factory background authoring invocation')
    need('--' in sys.argv, 'explicit generator arguments')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    output = ordinary(args.output)
    local = ordinary(ROOT / '.local')
    need(output != local and output.is_relative_to(local) and not output.exists(), 'fresh output strictly beneath checkout .local')
    need(Path(__file__).absolute() == ROOT / GENERATOR, 'fixed project generator path')
    contract_pin = pin(ROOT / CONTRACT)
    need(contract_pin['sha256'] == CONTRACT_SHA and b'\r' not in (ROOT / CONTRACT).read_bytes(), 'checked raw LF contract')
    source_pin, notice_pin = pin(ROOT / GENERATOR), pin(ROOT / NOTICE)
    need(notice_pin['sha256'] == NOTICE_SHA, 'fixed full original MIT notice')
    output.mkdir(parents=True)
    (output / 'exports').mkdir()
    # Only original static mesh/material resources remain in the editable source.
    for item in list(bpy.data.objects):
        bpy.data.objects.remove(item, do_unlink=True)
    for group in (bpy.data.collections, bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights, bpy.data.images, bpy.data.texts):
        for item in list(group):
            group.remove(item)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1
    material_set = materials()
    exports = []
    for design in DESIGNS:
        for lod in (0, 1):
            root_name = design['root'] + 'L' + str(lod)
            collection = bpy.data.collections.new(root_name)
            scene.collection.children.link(collection)
            root = bpy.data.objects.new(root_name, None)
            collection.objects.link(root)
            objects = []
            for index, (name, geometry) in enumerate(build_geometry(design, lod)):
                mesh = bpy.data.meshes.new(root_name + '_' + name)
                mesh.from_pydata(geometry.vertices, [], geometry.faces)
                mesh.update()
                for polygon in mesh.polygons:
                    polygon.use_smooth = False
                obj = bpy.data.objects.new(name, mesh)
                collection.objects.link(obj)
                obj.parent = root
                mesh.materials.append(material_set[index])
                objects.append(obj)
            # Blender object names are globally unique across collections. Their
            # requested child semantics are exported from fixed names above,
            # while editable .blend children use the root-prefixed object IDs.
            for name, obj in zip(('Bark', 'InnerNeedles', 'OuterNeedles'), objects):
                obj.name = root_name + '_' + name
            raw = export_glb(root_name, objects)
            relative = 'exports/' + design['id'] + '-lod' + str(lod) + '.glb'
            write_new(output / relative, raw)
            exports.append({'id': design['id'], 'lod': lod, 'path': relative, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
    need(len(scene.objects) == 24 and len(bpy.data.meshes) == 18 and len(bpy.data.materials) == 3 and not bpy.data.texts and not bpy.data.images, 'closed original scene roster')
    blend = output / 'original-evergreens.blend'
    need(not blend.exists(), 'fresh blend output')
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=False, check_existing=False, copy=True)
    blend_pin = pin(blend)
    need(0 < blend_pin['bytes'] <= 32 * 1024 * 1024 and sum(row['bytes'] for row in exports) <= 12 * 1024 * 1024, 'source/aggregate byte budgets')
    need(pin(ROOT / CONTRACT) == contract_pin and pin(ROOT / GENERATOR) == source_pin and pin(ROOT / NOTICE) == notice_pin, 'project input continuity')
    receipt = {'kind': 'OriginalEvergreenSource/v1', 'version': 1, 'license': 'MIT', 'scope': SCOPE,
               'contract_sha256': contract_pin['sha256'], 'generator': {'path': GENERATOR, 'sha256': source_pin['sha256']},
               'blender': {'version': bpy.app.version_string, 'build_hash': bpy.app.build_hash.decode()},
               'blend': {'path': 'original-evergreens.blend', **blend_pin}, 'exports': exports,
               'notice': {'path': NOTICE, 'sha256': notice_pin['sha256']}}
    raw = (json.dumps(receipt, indent=2, allow_nan=False) + '\n').encode('utf-8')
    need(len(raw) <= 65536, 'source receipt byte bound')
    write_new(output / 'evergreen-source-v1.json', raw)
    print('ORIGINAL_EVERGREENS_GENERATED_NOT_ACCEPTED ' + json.dumps(receipt, sort_keys=True))


if __name__ == '__main__':
    main()




