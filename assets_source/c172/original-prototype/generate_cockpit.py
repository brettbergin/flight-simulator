"""Original MIT. SOURCE PROPOSAL; run only in Root-admitted portable Blender.

Consumes independently captured Godot arrays, never derives expected geometry
from authored output. Output is fresh staging; this script never adopts files.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import stat
import struct
import sys
import zlib

REFERENCE_SHA = '76a44bb463dfd04a883e4f93f9db81ee6fc0f4c0a2bd004a6c05e8fb64cee57c'
CONTRACT_SHA = '2a9cbef98a6e88a67c6f0bf39846b231b1350ff5918fa3640923efbf67504cac'
BLENDER_VERSION = '4.5.14 LTS'
BLENDER_BUILD = '62c1db4208e8'
TEXTURED = {'Cloth', 'Leather', 'Dark', 'Black'}
PRIMITIVE_CLASSES = {'box': 'BoxMesh', 'cylinder_between_endpoints': 'CylinderMesh', 'sphere_scaled': 'SphereMesh', 'torus': 'TorusMesh'}
PRIMITIVE_PROPERTIES = {'BoxMesh': {'add_uv2': 'bool', 'custom_aabb': 'aabb', 'flip_faces': 'bool', 'material': 'null', 'uv2_padding': 'float', 'size': 'vec3', 'subdivide_depth': 'int', 'subdivide_height': 'int', 'subdivide_width': 'int'}, 'CylinderMesh': {'add_uv2': 'bool', 'custom_aabb': 'aabb', 'flip_faces': 'bool', 'material': 'null', 'uv2_padding': 'float', 'bottom_radius': 'float', 'cap_bottom': 'bool', 'cap_top': 'bool', 'height': 'float', 'radial_segments': 'int', 'rings': 'int', 'top_radius': 'float'}, 'SphereMesh': {'add_uv2': 'bool', 'custom_aabb': 'aabb', 'flip_faces': 'bool', 'material': 'null', 'uv2_padding': 'float', 'height': 'float', 'is_hemisphere': 'bool', 'radial_segments': 'int', 'radius': 'float', 'rings': 'int'}, 'TorusMesh': {'add_uv2': 'bool', 'custom_aabb': 'aabb', 'flip_faces': 'bool', 'material': 'null', 'uv2_padding': 'float', 'inner_radius': 'float', 'outer_radius': 'float', 'ring_segments': 'int', 'rings': 'int'}}

def require(value, message):
    if not value:
        raise ValueError(message)

def pairs(rows):
    out = {}
    for key, value in rows:
        require(key not in out, 'duplicate JSON key')
        out[key] = value
    return out

def load(path):
    data = path.read_bytes()
    require(len(data) <= 32 * 1024 * 1024, 'bounded source input')
    return json.loads(data, object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite JSON')))

def closed(value, names):
    require(type(value) is dict and set(value) == set(names), 'closed input shape')

def filepin(path):
    path = path.absolute()
    for item in [path, *path.parents]:
        info = item.lstat()
        require(not stat.S_ISLNK(info.st_mode) and not getattr(info, 'st_file_attributes', 0) & 0x400,
                'no symlink/reparse input ancestor')
    require(stat.S_ISREG(path.stat().st_mode), 'ordinary input file')
    path = path.resolve(strict=True)
    data = path.read_bytes()
    return {'path': str(path), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}

def pinned(path, digest):
    require(len(digest) == 64 and all(c in '0123456789abcdef' for c in digest), 'lowercase raw digest')
    require(filepin(path)['sha256'] == digest, 'raw input drift')
    return load(path)

def vector(value, count):
    require(type(value) is list and len(value) == count and
            all(type(x) in (int, float) and math.isfinite(x) for x in value), 'finite fixed vector')
    return tuple(value)

def blender_vector(value):
    x, y, z = vector(value, 3)
    return x, -z, y

def linear(channel):
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4

def admit_primitive_observation(observation, recipe):
    # Provenance from the original mesh; never an alternative mesh generator.
    closed(observation, ['class', 'properties'])
    require(observation['class'] == PRIMITIVE_CLASSES[recipe['primitive']],
            'actual source primitive class')
    types = PRIMITIVE_PROPERTIES[observation['class']]
    closed(observation['properties'], types)
    for name, kind in types.items():
        value = observation['properties'][name]
        if kind == 'bool':
            require(type(value) is bool, 'actual primitive bool')
        elif kind == 'int':
            require(type(value) is int and 0 <= value <= 0x7fffffff, 'actual nonnegative primitive integer')
        elif kind == 'float':
            # JSON may spell an actual integral FLOAT without a decimal point.
            require(type(value) in (int, float) and math.isfinite(value), 'actual finite primitive scalar')
        elif kind in ('vec3', 'aabb'):
            vector(value, 3 if kind == 'vec3' else 6)
        else:
            require(kind == 'null' and value is None, 'primitive material observed null')

def admit_baseline(baseline, reference):
    closed(baseline, ['schema', 'source_sha256', 'reference_sha256', 'godot_version',
                     'node_roster', 'parts', 'material_linear_rgba', 'complete',
                     'captured_before_asset', 'capture_receipt'])
    require(baseline['schema'] == 'OriginalCockpitIndependentBaseline/v1' and
            baseline['source_sha256'] == reference['source_raw_sha256'] and
            baseline['reference_sha256'] == REFERENCE_SHA and
            baseline['godot_version'] == '4.7.2-stable' and
            baseline['complete'] is True and baseline['captured_before_asset'] is True,
            'actual independent pre-output baseline required')
    closed(baseline['capture_receipt'], ['path', 'bytes', 'sha256'])
    require(filepin(Path(baseline['capture_receipt']['path'])) == baseline['capture_receipt'],
            'actual baseline capture receipt pin')
    names = ['OriginalCockpitAsset', 'Static'] + [r['name'] for r in reference['markers_and_pivots']] + [r['name'] for r in reference['parts']]
    require(len(names) == len(set(names)) == 84 and baseline['node_roster'] == names,
            'closed baseline node roster in reference order')
    require(type(baseline['parts']) is list and len(baseline['parts']) == 74, 'complete74 baseline parts')
    triangles = 0
    for part, recipe in zip(baseline['parts'], reference['parts']):
        closed(part, ['name', 'parent', 'material', 'vertices_parent_m', 'normals_parent', 'uv0', 'indices_cw', 'primitive_properties'])
        admit_primitive_observation(part['primitive_properties'], recipe)
        require(all(part[k] == recipe[k] for k in ['name', 'parent', 'material']), 'baseline recipe identity')
        vertices, normals, uv, indices = (part[k] for k in ['vertices_parent_m', 'normals_parent', 'uv0', 'indices_cw'])
        require(all(type(x) is list for x in [vertices, normals, uv, indices]) and
                3 <= len(vertices) <= 60000 and len(vertices) == len(normals) == len(uv) and
                len(indices) >= 3 and len(indices) % 3 == 0, 'bounded complete mesh arrays')
        for v, n, t in zip(vertices, normals, uv):
            require(all(abs(x) <= 10 for x in vector(v, 3)), 'bounded local geometry')
            require(abs(sum(x*x for x in vector(n, 3)) - 1) <= 1e-5, 'baseline unit normals')
            require(all(0 <= x <= 1 for x in vector(t, 2)), 'original normalized primitive UVs')
        require(all(type(i) is int and 0 <= i < len(vertices) for i in indices), 'baseline index bounds')
        triangles += len(indices) // 3
    require(triangles <= 20000, 'unchanged topology within contract triangle guard')
    closed(baseline['material_linear_rgba'], [r['name'] for r in reference['materials']])
    for row in reference['materials']:
        expected = [linear(x) for x in row['original_godot_albedo_rgb']] + [1.0]
        observed = vector(baseline['material_linear_rgba'][row['name']], 4)
        require(all(abs(a-b) <= 1e-6 for a,b in zip(observed, expected)),
                'source sRGB to linear-glTF factor correspondence; actual importer check still required')

def png_bytes(roughness=False):
    """Original bounded repeating weave; no borrowed image/font/manufacturer art."""
    scanlines = bytearray()
    for y in range(256):
        scanlines.append(0)
        for x in range(256):
            weave = ((x % 8 < 2) + (y % 8 < 2) + ((x+y) % 16 < 2))
            if roughness:
                scanlines.extend((255, 255 - 4*weave, 255, 255))
            else:
                v = 255 - 6*weave
                scanlines.extend((v, v, v, 255))
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag+data) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 256, 256, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(bytes(scanlines), 9)) + chunk(b'IEND', b''))

def check_export_images(path, expected_images):
    data = path.read_bytes()
    require(len(data) <= 12*1024*1024 and len(data) >= 28, 'bounded actual GLB')
    magic, version, size = struct.unpack_from('<III', data)
    require(magic == 0x46546c67 and version == 2 and size == len(data), 'GLB header')
    length, kind = struct.unpack_from('<II', data, 12)
    require(kind == 0x4e4f534a and 20+length+8 <= len(data), 'GLB JSON chunk')
    model = json.loads(data[20:20+length], object_pairs_hook=pairs)
    bin_length, bin_kind = struct.unpack_from('<II', data, 20+length)
    binary = data[28+length:]
    require(bin_kind == 0x004e4942 and len(binary) == bin_length, 'single BIN chunk')
    require(len(model.get('images', [])) == 2, 'exact two embedded images')
    seen = set()
    for image in model['images']:
        require('uri' not in image and image.get('mimeType') == 'image/png', 'embedded PNG only')
        view = model['bufferViews'][image['bufferView']]
        require(view.get('buffer') == 0 and type(view.get('byteLength')) is int, 'closed image storage')
        start, length = view.get('byteOffset', 0), view['byteLength']
        require(type(start) is int and start >= 0 and start+length <= len(binary), 'image bounds')
        payload = binary[start:start+length]
        matches = [name for name, raw in expected_images.items() if payload == raw]
        require(len(matches) == 1 and matches[0] not in seen, 'exporter must preserve both original PNG bytes; no fitted replacement')
        seen.add(matches[0])
    require(seen == set(expected_images), 'complete original image correspondence')

def share_export_texture_aliases(data):
    """Closed source-generation step: eight identical texture aliases -> two resources.

    Only pbr texture indices and the texture alias roster change. The original
    BIN chunk (all geometry/UV/normal/image bytes and padding) is copied verbatim.
    This is not a general GLB optimizer or a patch to an accepted artifact.
    """
    require(len(data) >= 28, 'fresh GLB header')
    magic, version, size = struct.unpack_from('<III', data)
    require(magic == 0x46546c67 and version == 2 and size == len(data), 'fresh GLB2 exact size')
    length, kind = struct.unpack_from('<II', data, 12)
    require(kind == 0x4e4f534a and length % 4 == 0 and 20+length+8 <= len(data), 'one aligned JSON chunk')
    bin_length, bin_kind = struct.unpack_from('<II', data, 20+length)
    require(bin_kind == 0x004e4942 and bin_length % 4 == 0 and 28+length+bin_length == len(data), 'one exact BIN chunk only')
    original = json.loads(data[20:20+length], object_pairs_hook=pairs)
    expected = [{'sampler':0,'source':0}, {'sampler':0,'source':1}]
    textures = original.get('textures')
    require(type(textures) is list and len(textures) == 8, 'exact eight known exporter aliases')
    for index, texture in enumerate(textures):
        require(type(texture) is dict and set(texture) == {'sampler','source'} and
                all(type(value) is int for value in texture.values()) and texture == expected[index % 2],
                'aliases must be exact same sampler/source objects, no names/extensions/extras')
    require(type(original.get('images')) is list and len(original['images']) == 2 and
            type(original.get('samplers')) is list and len(original['samplers']) == 1 and
            type(original.get('materials')) is list and len(original['materials']) == 7, 'closed shared image/sampler/material roster')
    allowed = set()
    for index, material in enumerate(original['materials']):
        if material.get('name') in TEXTURED:
            for slot in ['baseColorTexture','metallicRoughnessTexture']:
                allowed.add(('materials',index,'pbrMetallicRoughness',slot))
    require(len(allowed) == 8, 'four original textured materials with both slots')
    observed = []
    def visit(value, path=()):
        if type(value) is dict:
            for key, child in value.items():
                current = path+(key,)
                if key.endswith('Texture'):
                    require(current in allowed and type(child) is dict and set(child) == {'index'} and
                            type(child['index']) is int and 0 <= child['index'] < 8,
                            'only closed original PBR texture references')
                    require(child['index'] % 2 == (0 if key == 'baseColorTexture' else 1), 'original image role preserved')
                    observed.append((current,child['index']))
                visit(child,current)
        elif type(value) is list:
            for index, child in enumerate(value):visit(child,path+(index,))
    visit(original)
    require({path for path,index in observed} == allowed and sorted(index for path,index in observed) == list(range(8)),
            'every original alias referenced exactly once, no other texture use')
    result = json.loads(json.dumps(original, allow_nan=False))
    result['textures'] = expected
    for path, index in observed:
        target = result
        for key in path:target = target[key]
        target['index'] = index % 2
    # Inverse check guards every other JSON value, including factors and accessors.
    inverse = json.loads(json.dumps(result, allow_nan=False));inverse['textures'] = textures
    for path, index in observed:
        target = inverse
        for key in path:target = target[key]
        target['index'] = index
    require(inverse == original, 'whole JSON inverse except declared aliases/indices')
    encoded = json.dumps(result, ensure_ascii=True, separators=(',',':'), allow_nan=False).encode('utf-8')
    encoded += b' ' * (-len(encoded) % 4)
    binary_chunk = data[20+length:]
    output = struct.pack('<III',0x46546c67,2,20+len(encoded)+len(binary_chunk)) + struct.pack('<II',len(encoded),0x4e4f534a) + encoded + binary_chunk
    require(output[20+len(encoded):] == binary_chunk, 'entire original BIN chunk byte exact')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ['baseline', 'baseline-review', 'accepted-contract', 'reference', 'output']:
        parser.add_argument('--'+key, type=Path, required=True)
    for key in ['baseline-sha256', 'baseline-review-sha256', 'accepted-contract-sha256']:
        parser.add_argument('--'+key, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    baseline = pinned(args.baseline, args.baseline_sha256)
    peer = pinned(args.baseline_review, args.baseline_review_sha256)
    acceptance = pinned(args.accepted_contract, args.accepted_contract_sha256)
    reference = pinned(args.reference, REFERENCE_SHA)
    require(peer['approved'] is True and peer['disposition'] == 'APPROVE_COCKPIT_BASELINE_ONLY' and
            peer['candidate'] == filepin(args.baseline), 'independent exact baseline review')
    closed(acceptance, ['schema', 'merged', 'merge_commit', 'contract_sha256', 'reference_sha256'])
    require(acceptance['schema'] == 'OriginalCockpitContractAcceptance/v1' and acceptance['merged'] is True and
            type(acceptance['merge_commit']) is str and len(acceptance['merge_commit']) == 40 and
            all(c in '0123456789abcdef' for c in acceptance['merge_commit']) and
            acceptance['contract_sha256'] == CONTRACT_SHA and acceptance['reference_sha256'] == REFERENCE_SHA,
            'actual checked contract acceptance; record is Root invocation trust, not hostile-user authorization')
    admit_baseline(baseline, reference)
    import bpy
    from mathutils import Matrix, Vector
    require(bpy.app.version_string == BLENDER_VERSION and bpy.app.build_hash.decode() == BLENDER_BUILD,
            'pinned Blender version and build')
    require('--factory-startup' in sys.argv and '--background' in sys.argv, 'isolated factory authoring invocation')
    output = args.output.resolve()
    require(not output.exists(), 'fresh output; preserve failed attempts')
    output.mkdir(parents=False)
    source = output/'assets_source/c172/original-prototype';runtime = output/'app/cockpit/assets'
    (source/'textures').mkdir(parents=True);runtime.mkdir(parents=True)
    images = {'original-surface-albedo': png_bytes(), 'original-surface-roughness': png_bytes(True)}
    for name, raw in images.items():(source/'textures'/f'{name}.png').write_bytes(raw)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for collection in [bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.actions]:
        for item in list(collection):collection.remove(item)
    scene = bpy.context.scene;scene.name = 'OriginalCockpitAsset'
    scene.unit_settings.system = 'METRIC';scene.unit_settings.scale_length = 1.0
    def empty(name, parent=None, translation=(0,0,0)):
        obj = bpy.data.objects.new(name, None);scene.collection.objects.link(obj)
        obj.parent = parent;obj.location = blender_vector(list(translation));return obj
    root = empty('OriginalCockpitAsset');nodes = {'OriginalCockpitAsset': root, 'Static': empty('Static', root)}
    for marker in reference['markers_and_pivots']:
        nodes[marker['name']] = empty(marker['name'], root, marker['translation_m'])
    textures = {}
    for name in images:
        image = bpy.data.images.load(str(source/'textures'/f'{name}.png'), check_existing=False)
        image.name = name;image.colorspace_settings.name = 'sRGB' if name.endswith('albedo') else 'Non-Color'
        textures[name] = image
    materials = {}
    for row in reference['materials']:
        mat = bpy.data.materials.new(row['name']);mat.use_nodes = True
        mat.use_backface_culling = True  # Preserve original Godot CULL_BACK; opaque alpha stays1.
        shader = mat.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = baseline['material_linear_rgba'][row['name']]
        shader.inputs['Metallic'].default_value = row['metallic'];shader.inputs['Roughness'].default_value = row['roughness']
        if row['name'] in TEXTURED:
            # glTF factors remain source factors; shared images modulate them on import.
            # Exporter node recognition/byte preservation must pass the real export gate.
            color = mat.node_tree.nodes.new('ShaderNodeTexImage');color.image = textures['original-surface-albedo'];color.extension = 'REPEAT';color.interpolation = 'Linear'
            # Pinned Blender4.5 gather_color_info recognizes MIX/RGBA, not legacy MIX_RGB.
            # The constant remains the independently captured original linear RGBA.
            mix = mat.node_tree.nodes.new('ShaderNodeMix');mix.data_type = 'RGBA';mix.blend_type = 'MULTIPLY';mix.inputs[0].default_value = 1
            mix_a = next(socket for socket in mix.inputs if socket.identifier == 'A_Color')
            mix_b = next(socket for socket in mix.inputs if socket.identifier == 'B_Color')
            mix_color = next(socket for socket in mix.outputs if socket.identifier == 'Result_Color')
            mix_b.default_value = baseline['material_linear_rgba'][row['name']]
            mat.node_tree.links.new(color.outputs['Color'], mix_a);mat.node_tree.links.new(mix_color, shader.inputs['Base Color'])
            rough = mat.node_tree.nodes.new('ShaderNodeTexImage');rough.image = textures['original-surface-roughness'];rough.extension = 'REPEAT';rough.interpolation = 'Linear'
            separate = mat.node_tree.nodes.new('ShaderNodeSeparateColor');mat.node_tree.links.new(rough.outputs['Color'], separate.inputs['Color'])
            multiply = mat.node_tree.nodes.new('ShaderNodeMath');multiply.operation = 'MULTIPLY';multiply.inputs[1].default_value = row['roughness']
            mat.node_tree.links.new(separate.outputs['Green'], multiply.inputs[0]);mat.node_tree.links.new(multiply.outputs[0], shader.inputs['Roughness'])
            # The authored PNG already has unity B (metallic) and varying G (roughness).
            # Connecting BOTH identity-mapped channels avoids exporter's FillWhite(B)
            # reconstruction path; B * original metallic0 preserves original semantics.
            metal = mat.node_tree.nodes.new('ShaderNodeMath');metal.operation = 'MULTIPLY';metal.inputs[1].default_value = row['metallic']
            mat.node_tree.links.new(separate.outputs['Blue'], metal.inputs[0]);mat.node_tree.links.new(metal.outputs[0], shader.inputs['Metallic'])
        materials[row['name']] = mat
    recipes = {row['name']:row for row in reference['parts']}
    for part in baseline['parts']:
        recipe = recipes[part['name']]
        vertices = [blender_vector(v) for v in part['vertices_parent_m']]
        normals = [blender_vector(n) for n in part['normals_parent']]
        original_frame = part['name'] in {'LeftSeatBack','RightSeatBack'}
        if original_frame:
            # Frozen original center/Xrotation, not a fitted normal correction.
            # Cardinal pole normals remain representable in Blender's mesh-local
            # custom-normal space; the object restores the original parent pose.
            require(recipe['primitive'] == 'sphere_scaled' and recipe['rotation_xyz_deg'] == [-8,0,0], 'two original SeatBack frames only')
            center = Vector(blender_vector(recipe['center_m']))
            rotation = Matrix.Rotation(math.radians(recipe['rotation_xyz_deg'][0]),3,'X')
            inverse = rotation.transposed()
            vertices = [tuple(inverse @ (Vector(v)-center)) for v in vertices]
            normals = [tuple(inverse @ Vector(n)) for n in normals]
        indices = part['indices_cw'];faces = [(indices[i], indices[i+2], indices[i+1]) for i in range(0,len(indices),3)]
        mesh = bpy.data.meshes.new(part['name']);mesh.from_pydata(vertices, [], faces);mesh.update()
        # Flat storage avoids smoothing-fan loss at retained degenerate sphere
        # poles. Explicit frozen normals still supply all intended smooth shading.
        for polygon in mesh.polygons:polygon.use_smooth = recipe['primitive'] != 'sphere_scaled'
        mesh.normals_split_custom_set_from_vertices(normals)
        uv = mesh.uv_layers.new(name='OriginalPrimitiveUV')
        for loop in mesh.loops:uv.data[loop.index].uv = part['uv0'][loop.vertex_index]
        obj = bpy.data.objects.new(part['name'], mesh);scene.collection.objects.link(obj);obj.parent = nodes[part['parent']]
        if original_frame:
            obj.location = center;obj.rotation_mode = 'XYZ';obj.rotation_euler = (math.radians(recipe['rotation_xyz_deg'][0]),0,0)
        mesh.materials.append(materials[part['material']])
    require(len(scene.objects) == 84 and len(bpy.data.meshes) == 74 and len(bpy.data.materials) == 7, 'closed authored object/resource roster')
    blend = source/'original-cockpit.blend';glb = runtime/'original-cockpit.glb'
    # Relative references are authored before the sole fresh save. Loaded pixels
    # remain in memory; saving establishes this source folder as Blender's // base.
    for image in textures.values():image.filepath = '//textures/'+Path(image.filepath).name
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    # The exporter intermediate is never the declared runtime artifact. Produce
    # the final GLB once through the closed, inverse-checked sharing step below.
    blender_glb = runtime/'.original-cockpit-blender-export.glb'
    bpy.ops.export_scene.gltf(filepath=str(blender_glb), export_format='GLB', export_yup=True,
                              export_animations=False, export_materials='EXPORT',
                              export_apply=False, export_cameras=False, export_lights=False,
                              export_extras=False, export_tangents=False, export_image_format='AUTO')
    raw_export = blender_glb.read_bytes()
    raw_export_sha256 = hashlib.sha256(raw_export).hexdigest()
    require(not glb.exists(), 'declared runtime GLB must be fresh')
    glb.write_bytes(share_export_texture_aliases(raw_export))
    check_export_images(glb, images)
    blender_glb.unlink()  # Only this fresh generator-owned scratch file.
    for path, expected in [(args.baseline,args.baseline_sha256),(args.baseline_review,args.baseline_review_sha256),(args.accepted_contract,args.accepted_contract_sha256),(args.reference,REFERENCE_SHA)]:
        require(filepin(path)['sha256'] == expected, 'input continuity after export')
    receipt = {'schema':'OriginalCockpitSourceGeneration/v1','license':'MIT','author':'Flight Simulator contributors',
               'manufacturer_geometry':False,'blender_version':bpy.app.version_string,'blender_build':bpy.app.build_hash.decode(),
               'generator':filepin(Path(__file__)),'baseline':filepin(args.baseline),'baseline_review':filepin(args.baseline_review),
               'texture_sharing':{'operation':'closed8-to2-alias-canonicalization','raw_blender_export_sha256':raw_export_sha256,'bin_chunk_byte_exact':True,'json_inverse_checked':True},
               'contract_acceptance':filepin(args.accepted_contract),'reference':filepin(args.reference),
               'outputs':[filepin(blend),filepin(glb)]+[filepin(source/'textures'/f'{name}.png') for name in images],
               'geometry':'independent source-baseline arrays; composed parent-local geometry; two frozen original SeatBack center/Xrotation frames; sphere flat-storage with explicit frozen custom normals; CW to CCW index reversal; (x,-z,y) basis',
               'scope':'Generated only. Independent GLB topology/UV/color/import/readability/rights/delivery checks pending.'}
    (source/'cockpit-source.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('ORIGINAL_COCKPIT_GENERATED_NOT_ACCEPTED '+json.dumps(receipt))

if __name__ == '__main__':
    main()
