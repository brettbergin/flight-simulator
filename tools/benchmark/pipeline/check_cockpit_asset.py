"""Original MIT. Independent original-cockpit GLB check; stdlib, offline, no engine.

Expected geometry comes from the independently reviewed original Godot capture,
embedded in cockpit_asset_baseline.gd before candidate generation. A successful
parse is not import, visual readability, performance or aircraft acceptance.
"""
import argparse
import collections
import hashlib
import itertools
import json
import math
from pathlib import Path
import re
import stat
import struct
import zlib

POSITION_EPS = 1e-6
NORMAL_DOT = 0.99999
MAX_GLB = 12*1024*1024
MAX_DECODED = 8*1024*1024
MAX_TRIANGLES = 20000
TEXTURED = {'Cloth', 'Leather', 'Dark', 'Black'}
FIXTURE_SHA256 = '6804bbd48deb17dd4730dd10e2b61b0b37c86640656c176e4774a9af51736dde'

def require(value, label):
    if not value: raise ValueError(label)

def integer(value, low, high, label):
    require(type(value) is int and low <= value <= high, label)
    return value

def vector(value, size, label):
    require(type(value) is list and len(value) == size and
            all(type(v) in (int, float) and math.isfinite(v) for v in value), label)
    return value

def keys(value, required, optional=()):
    require(type(value) is dict and set(required) <= set(value) <= set(required)|set(optional), 'closed object keys')

def pairs(rows):
    result = {}
    for key, value in rows:
        require(key not in result, 'duplicate JSON key')
        result[key] = value
    return result

def parse_json(raw):
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite JSON')))

def raw_file(path, cap=MAX_GLB):
    path = Path(path).absolute()
    for item in [path, *path.parents]:
        observed = item.lstat()
        require(not stat.S_ISLNK(observed.st_mode) and not getattr(observed, 'st_file_attributes', 0)&0x400, 'nonreparse input')
    observed = path.stat()
    require(stat.S_ISREG(observed.st_mode) and observed.st_nlink == 1 and 0 < observed.st_size <= cap, 'ordinary bounded single-link input')
    raw = path.read_bytes()
    require(len(raw) == observed.st_size, 'complete input read')
    return raw

def fixtures(path):
    raw = raw_file(path, 8*1024*1024)
    require(hashlib.sha256(raw).hexdigest()==FIXTURE_SHA256,'exact independently frozen source fixture bytes')
    text = raw.decode('utf-8')
    match = re.search(r'^const BASELINE_JSON: String = (".*")$', text, re.MULTILINE)
    require(match is not None, 'frozen independent baseline string')
    value = parse_json(json.loads(match.group(1)))
    keys(value, ['schema', 'baseline_sha256', 'source_sha256', 'reference_sha256', 'parts', 'markers', 'materials', 'material_linear_rgba', 'runtime_retained', 'control_cases', 'baseline_degeneracies', 'aperture_rays'])
    require(value['schema'] == 'OriginalCockpitIndependentFixture/v1' and len(value['parts']) == 74 and len(value['markers']) == 8 and len(value['materials']) == 7, 'frozen baseline roster')
    require(value['baseline_sha256'] == 'fbe01696c09d17042079060739d5599d649e30164727c4a414492c1402a88eba', 'reviewed actual original capture')
    return value

def decode_glb(raw):
    require(type(raw) is bytes and 28 <= len(raw) <= MAX_GLB, 'bounded GLB bytes')
    magic, version, size = struct.unpack_from('<III', raw)
    require((magic, version, size) == (0x46546c67, 2, len(raw)), 'exact GLB header')
    length, kind = struct.unpack_from('<II', raw, 12)
    require(kind == 0x4e4f534a and length%4 == 0 and 20+length+8 <= len(raw), 'single aligned JSON chunk')
    model = parse_json(raw[20:20+length].decode('utf-8'))
    blen, bkind = struct.unpack_from('<II', raw, 20+length)
    binary = raw[28+length:]
    require(bkind == 0x004e4942 and blen%4 == 0 and len(binary) == blen, 'single aligned BIN chunk/no trailing chunks')
    return model, binary

def accessor(model, binary, index, semantic):
    index = integer(index, 0, len(model['accessors'])-1, 'accessor index')
    a = model['accessors'][index]
    keys(a, ['bufferView', 'componentType', 'count', 'type'], ['byteOffset', 'min', 'max', 'normalized', 'name'])
    require(a.get('normalized', False) is False, 'unnormalized source accessor')
    if semantic == 'indices':
        require(a['componentType'] in (5121,5123,5125) and type(a['componentType']) is int and a['type'] == 'SCALAR', 'unsigned scalar indices')
        fmt, width, count = {5121:('B',1,1),5123:('H',2,1),5125:('I',4,1)}[a['componentType']]
    else:
        count = 2 if semantic == 'TEXCOORD_0' else 3
        require(type(a['componentType']) is int and a['componentType'] == 5126 and a['type'] == ('VEC2' if count == 2 else 'VEC3'), 'float32 source vector')
        fmt, width = 'f', 4
    n = integer(a['count'], 1, 60000, 'bounded accessor count')
    view_index = integer(a['bufferView'], 0, len(model['bufferViews'])-1, 'accessor view')
    view = model['bufferViews'][view_index]
    start = integer(a.get('byteOffset',0), 0, view['byteLength'], 'accessor offset')
    stride = integer(view.get('byteStride', width*count), width*count, 252, 'bounded accessor stride')
    require(start%width == 0 and stride%width == 0, 'accessor component alignment')
    require(start+(n-1)*stride+width*count <= view['byteLength'], 'full accessor fits its view')
    require(n*width*count <= MAX_DECODED, 'bounded decoded accessor')
    begin = view.get('byteOffset',0)+start
    result = [list(struct.unpack_from('<'+fmt*count, binary, begin+i*stride)) for i in range(n)]
    if fmt == 'f': require(all(math.isfinite(x) for row in result for x in row), 'finite float32 accessors')
    for bound, fn in [('min', min), ('max', max)]:
        if bound in a:
            observed = vector(a[bound], count, 'accessor extrema')
            require(all(abs(observed[i]-fn(row[i] for row in result)) <= POSITION_EPS for i in range(count)), 'actual accessor min/max')
    return ([r[0] for r in result] if semantic == 'indices' else result), n*width*count, view_index

def png_rgba(raw):
    require(raw.startswith(b'\x89PNG\r\n\x1a\n') and len(raw) <= 1024*1024, 'bounded PNG')
    offset=8; tags=[]; encoded=bytearray()
    while offset < len(raw):
        require(offset+12 <= len(raw), 'PNG chunk header')
        length = struct.unpack_from('>I',raw,offset)[0]
        require(length <= 1024*1024 and offset+12+length <= len(raw), 'PNG chunk cap')
        tag=raw[offset+4:offset+8]; data=raw[offset+8:offset+8+length]
        crc=struct.unpack_from('>I',raw,offset+8+length)[0]
        require(zlib.crc32(tag+data)&0xffffffff == crc, 'PNG CRC')
        tags.append(tag)
        if tag == b'IHDR': require(data == struct.pack('>IIBBBBB',256,256,8,6,0,0,0), '256x256 RGBA8 PNG')
        elif tag == b'IDAT': encoded.extend(data)
        else: require(tag == b'IEND' and length == 0 and offset+12 == len(raw), 'no metadata/artwork/extra PNG chunks')
        offset += 12+length
    require(tags == [b'IHDR',b'IDAT',b'IEND'], 'closed source PNG chunks')
    decoder=zlib.decompressobj(); pixels=decoder.decompress(bytes(encoded),256*(1+256*4)+1)
    require(len(pixels)==256*(1+256*4) and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail, 'bounded complete PNG decode')
    require(all(pixels[y*1025]==0 for y in range(256)), 'original unfiltered PNG rows')
    return b''.join(pixels[y*1025+1:(y+1)*1025] for y in range(256))

def check_png_detail(raw, roughness):
    pixels=png_rgba(raw)
    for y in range(256):
        for x in range(256):
            weave=int(x%8<2)+int(y%8<2)+int((x+y)%16<2)
            expected=(255,255-4*weave,255,255) if roughness else (255-6*weave,)*3+(255,)
            require(tuple(pixels[(y*256+x)*4:(y*256+x+1)*4])==expected, 'original bounded weave/no telemetry art')

def _cell(triangle):
    return tuple(math.floor(sum(c[0][i] for c in triangle)/3/POSITION_EPS) for i in range(3))

def compare_triangles(vertices, normals, uv, indices, expected, gltf=True):
    require(len(vertices)==len(normals)==len(uv) and len(indices)%3==0, 'complete triangle arrays')
    require(all(type(i) is int and 0 <= i < len(vertices) for i in indices), 'actual index bounds')
    require(all(abs(sum(x*x for x in n)-1)<=1e-5 for n in normals), 'unit normals')
    require(all(len(t)==2 and all(0<=x<=1 for x in t) for t in uv), 'normalized UVs')
    ev,en,et,ei=[expected[k] for k in ['vertices_parent_m','normals_parent','uv0','indices_cw']]
    require(len(indices)==len(ei), 'exact original triangle multiplicity including poles/seams')
    buckets=collections.defaultdict(list)
    for i in range(0,len(ei),3):
        ids=ei[i:i+3]; ids=[ids[0],ids[2],ids[1]] if gltf else ids
        triangle=[(ev[j],en[j],[et[j][0],1-et[j][1]] if gltf else et[j]) for j in ids]
        buckets[_cell(triangle)].append(triangle)
    maximum_position=0.0; minimum_dot=1.0; maximum_uv=0.0
    for i in range(0,len(indices),3):
        actual=[(vertices[j],normals[j],uv[j]) for j in indices[i:i+3]]
        cell=_cell(actual); found=None
        for delta in itertools.product((-1,0,1),repeat=3):
            key=tuple(a+b for a,b in zip(cell,delta))
            for candidate_index, candidate in enumerate(buckets.get(key, [])):
                for shift in range(3):
                    arranged=candidate[shift:]+candidate[:shift]
                    pos=max(abs(a[0][d]-e[0][d]) for a,e in zip(actual,arranged) for d in range(3))
                    normal=min(sum(a[1][d]*e[1][d] for d in range(3)) for a,e in zip(actual,arranged))
                    tex=max(abs(a[2][d]-e[2][d]) for a,e in zip(actual,arranged) for d in range(2))
                    if pos<=POSITION_EPS and normal>=NORMAL_DOT and tex<=POSITION_EPS:
                        found=(key,candidate_index,pos,normal,tex);break
                if found:break
            if found:break
        require(found is not None, 'oriented complete triangle/normal/UV correspondence; no reversed/extra/covered opening')
        key,index,pos,normal,tex=found; buckets[key].pop(index)
        maximum_position=max(maximum_position,pos); minimum_dot=min(minimum_dot,normal);maximum_uv=max(maximum_uv,tex)
    require(not any(buckets.values()), 'no missing original triangle')
    return {'maximum_position_element_error_m':maximum_position,'minimum_normal_dot':minimum_dot,'maximum_uv_error':maximum_uv}

# Exact original reference frames, not candidate-derived fitting. The other72
# part nodes, root and every group/eye/control pivot retain their prior guards.
LOCAL_PART_FRAMES = {'LeftSeatBack':[-0.29,0.08,0.06], 'RightSeatBack':[0.29,0.08,0.06]}

def part_transform(node):
    center=LOCAL_PART_FRAMES.get(node['name'])
    if center is None:return [[1,0,0],[0,1,0],[0,0,1]],[0,0,0]
    if 'matrix' in node:
        value=vector(node['matrix'],16,'original seat local matrix')
        require(all(abs(value[i]-v)<=POSITION_EPS for i,v in [(3,0),(7,0),(11,0),(15,1)]),'affine original seat matrix')
        basis=[[value[c*4+r] for c in range(3)] for r in range(3)]
        translation=value[12:15]
    else:
        x,y,z,w=vector(node.get('rotation',[0,0,0,1]),4,'original seat local quaternion')
        require(abs(x*x+y*y+z*z+w*w-1)<=POSITION_EPS,'unit original seat quaternion')
        scale=vector(node.get('scale',[1,1,1]),3,'original seat unit scale')
        require(scale==[1,1,1],'unit original seat scale')
        basis=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
               [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
               [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
        translation=vector(node.get('translation',[0,0,0]),3,'original seat local translation')
    identity=[[1,0,0],[0,1,0],[0,0,1]]
    angle=math.radians(-8);c,s=math.cos(angle),math.sin(angle)
    original=[[1,0,0],[0,c,-s],[0,s,c]]
    def matches(expected,position):
        return max(abs(basis[r][c]-expected[r][c]) for r in range(3) for c in range(3))<=POSITION_EPS and max(abs(x-y) for x,y in zip(translation,position))<=POSITION_EPS
    require(matches(identity,[0,0,0]) or matches(original,center),'only baked identity or exact original two-seat local frame')
    return basis,translation

def compose_part_arrays(node,vertices,normals):
    if node['name'] not in LOCAL_PART_FRAMES:return vertices,normals
    basis,translation=part_transform(node)
    # The admitted basis is a proper original rotation. Use its actual inverse
    # transpose for normals, including finite float32 representation roundoff.
    a,b,c=basis[0];d,e,f=basis[1];g,h,i=basis[2]
    cofactors=[[e*i-f*h,f*g-d*i,d*h-e*g],
               [c*h-b*i,a*i-c*g,b*g-a*h],
               [b*f-c*e,c*d-a*f,a*e-b*d]]
    det=a*cofactors[0][0]+b*cofactors[0][1]+c*cofactors[0][2]
    require(math.isfinite(det) and det>0,'proper original seat frame')
    normal_basis=[[x/det for x in row] for row in cofactors]
    positions=[[sum(basis[r][k]*v[k] for k in range(3))+translation[r] for r in range(3)] for v in vertices]
    transformed=[]
    for normal in normals:
        require(abs(sum(x*x for x in normal)-1)<=1e-5,'unit original seat local normal')
        value=[sum(normal_basis[r][k]*normal[k] for k in range(3)) for r in range(3)]
        length=math.sqrt(sum(x*x for x in value));require(math.isfinite(length) and length>0,'finite original seat composed normal')
        transformed.append([x/length for x in value])
    return positions,transformed

def validate(model,binary,fixture,source_pngs):
    keys(model,['asset','scene','scenes','nodes','meshes','materials','accessors','bufferViews','buffers','images','textures','samplers'],['extensionsUsed','extensionsRequired'])
    for field in ('scenes','nodes','meshes','materials','accessors','bufferViews','buffers','images','textures','samplers'):
        require(type(model[field]) is list,'actual glTF array '+field)
    keys(model['asset'],['version'],['generator','minVersion'])
    require(model['asset']['version']=='2.0' and model['asset'].get('minVersion','2.0')=='2.0', 'glTF2')
    require(not model.get('extensionsRequired') and not model.get('extensionsUsed'), 'no extension/compression/executable behavior')
    require(model['scene']==0 and type(model['scene']) is int and len(model['scenes'])==1, 'sole scene')
    require(len(model['nodes'])==84 and len(model['meshes'])==74 and len(model['materials'])==7 and len(model['images'])==len(model['textures'])==2, 'closed resource counts')
    require(len(model['buffers'])==1 and set(model['buffers'][0])=={'byteLength'}, 'sole embedded buffer')
    declared=integer(model['buffers'][0]['byteLength'],1,len(binary),'buffer size')
    require(len(binary)-declared<=3 and not any(binary[declared:]),'zero BIN alignment padding')
    require(type(model['accessors']) is list and len(model['accessors'])<=296 and type(model['bufferViews']) is list and len(model['bufferViews'])<=298, 'bounded accessor/view roster')
    for view in model['bufferViews']:
        keys(view,['buffer','byteLength'],['byteOffset','byteStride','target','name'])
        require(type(view['buffer']) is int and view['buffer']==0,'sole buffer view')
        begin=integer(view.get('byteOffset',0),0,declared,'view offset'); length=integer(view['byteLength'],1,declared,'view length')
        require(begin%4==0 and begin+length<=declared,'view alignment/complete bounds')
        if 'target' in view: require(type(view['target']) is int and view['target'] in (34962,34963),'geometry view target')
    cursor=0
    for view in sorted(model['bufferViews'],key=lambda v:v.get('byteOffset',0)):
        begin=view.get('byteOffset',0)
        require(cursor<=begin<=cursor+3 and not any(binary[cursor:begin]),'disjoint complete views with zero alignment padding only')
        cursor=begin+view['byteLength']
    require(cursor==declared,'no hidden or unused BIN bytes')
    expected_names=['OriginalCockpitAsset','Static']+[r['name'] for r in fixture['markers']]+[p['name'] for p in fixture['parts']]
    names=[n.get('name') for n in model['nodes']]
    require(all(type(name) is str for name in names),'actual node names')
    require(len(set(names))==84 and set(names)==set(expected_names),'exact unique names')
    index={name:i for i,name in enumerate(names)}; parents={}
    for node_index,node in enumerate(model['nodes']):
        keys(node,['name'],['children','mesh','translation','rotation','scale','matrix'])
        children=node.get('children',[]);require(type(children) is list and len(children)==len(set(children)),'unique children')
        for child in children:
            integer(child,0,83,'child index');require(child not in parents and child!=node_index,'single parent/no self edge');parents[child]=node_index
        require(not ('matrix' in node and any(k in node for k in ('translation','rotation','scale'))),'one transform representation')
        if node['name'] in LOCAL_PART_FRAMES:
            part_transform(node)
            continue
        if 'matrix' in node:
            m=vector(node['matrix'],16,'matrix');require(max(abs(x-y) for x,y in zip(m,[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]))<=POSITION_EPS,'identity baked matrix')
        else:
            require(max(abs(x-y) for x,y in zip(vector(node.get('rotation',[0,0,0,1]),4,'rotation'),[0,0,0,1]))<=POSITION_EPS,'no axis correction')
            require(max(abs(x-1) for x in vector(node.get('scale',[1,1,1]),3,'scale'))<=POSITION_EPS,'meter scale1')
        target=next((r['translation_m'] for r in fixture['markers'] if r['name']==node['name']),[0,0,0])
        require(max(abs(x-y) for x,y in zip(vector(node.get('translation',[0,0,0]),3,'translation'),target))<=POSITION_EPS,'exact rest translation/eye/pivot')
    root=index['OriginalCockpitAsset']; keys(model['scenes'][0],['nodes'],['name']);require(model['scenes'][0]['nodes']==[root] and root not in parents and 'mesh' not in model['nodes'][root],'sole empty actual root')
    require(set(model['nodes'][root].get('children',[]))=={index[n] for n in expected_names[1:10]},'exact nine direct groups')
    for name in expected_names[1:10]:require(parents.get(index[name])==root and 'mesh' not in model['nodes'][index[name]],'ordinary empty group/marker')
    materials={m.get('name'):m for m in model['materials']};require(set(materials)=={m['name'] for m in fixture['materials']},'exact material names')
    for expected in fixture['materials']:
        m=materials[expected['name']];keys(m,['name','pbrMetallicRoughness'],['doubleSided','alphaMode','alphaCutoff'])
        require(m.get('doubleSided',False) is False and m.get('alphaMode','OPAQUE')=='OPAQUE' and 'alphaCutoff' not in m,'opaque original material')
        pbr=m['pbrMetallicRoughness']; keys(pbr,['baseColorFactor','metallicFactor','roughnessFactor'],['baseColorTexture','metallicRoughnessTexture'])
        color=vector(pbr['baseColorFactor'],4,'linear base factor')
        require(max(abs(a-b) for a,b in zip(color,fixture['material_linear_rgba'][expected['name']]))<=POSITION_EPS,'sRGB conversion exactly once')
        for field in ('metallic','roughness'):
            v=pbr[field+'Factor'];require(type(v) in (int,float) and math.isfinite(v) and abs(v-expected[field])<=POSITION_EPS,'source material factor')
        for field in ('baseColorTexture','metallicRoughnessTexture'):
            require((field in pbr)==(expected['name'] in TEXTURED),'exact textured material subset')
            if field in pbr:
                keys(pbr[field],['index'],['texCoord']);integer(pbr[field]['index'],0,1,'texture index');integer(pbr[field].get('texCoord',0),0,0,'original UV0 only')
    require(1<=len(model['samplers'])<=2,'bounded shared samplers')
    for sampler in model['samplers']:
        keys(sampler,['magFilter','minFilter'],['wrapS','wrapT','name'])
        for field in ('magFilter','minFilter','wrapS','wrapT'):
            if field in sampler:integer(sampler[field],0,65535,'actual sampler INT')
        require(sampler['magFilter']==9729 and sampler['minFilter']==9987 and sampler.get('wrapS',10497)==10497 and sampler.get('wrapT',10497)==10497,'linear full-mip repeat sampler')
    image_roles={};used_views=set();used_textures=set()
    for image_index,image in enumerate(model['images']):
        keys(image,['mimeType','bufferView'],['name']);require(image['mimeType']=='image/png','embedded PNG only')
        vi=integer(image['bufferView'],0,len(model['bufferViews'])-1,'image view');v=model['bufferViews'][vi]
        require('byteStride' not in v and 'target' not in v,'image byte view');used_views.add(vi)
        payload=binary[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
        roles=[name for name,raw in source_pngs.items() if payload==raw];require(len(roles)==1 and roles[0] not in image_roles.values(),'both exact original source PNGs/no reencode')
        image_roles[image_index]=roles[0]
    require(set(image_roles.values())=={'albedo','roughness'},'two distinct image roles')
    for t in model['textures']:
        keys(t,['sampler','source'],['name']);integer(t['sampler'],0,len(model['samplers'])-1,'sampler index');integer(t['source'],0,1,'image index')
    require({t['sampler'] for t in model['textures']}==set(range(len(model['samplers']))),'no unused sampler')
    shared={}
    for expected in fixture['materials']:
        if expected['name'] not in TEXTURED:continue
        p=materials[expected['name']]['pbrMetallicRoughness']
        for field,role in [('baseColorTexture','albedo'),('metallicRoughnessTexture','roughness')]:
            ti=p[field]['index'];used_textures.add(ti);require(image_roles[model['textures'][ti]['source']]==role,'correct albedo/data texture slot')
            require(role not in shared or shared[role]==ti,'same two shared texture resources');shared[role]=ti
    require(used_textures=={0,1},'no unused textures')
    used_accessors=set();accessor_semantics={};used_meshes=set();decoded=0;triangles=0;observations=[]
    for expected in fixture['parts']:
        node=model['nodes'][index[expected['name']]];require(not node.get('children') and parents.get(index[expected['name']])==index[expected['parent']],'fixed part parent/leaf')
        mi=integer(node.get('mesh'),0,73,'mesh reference');require(mi not in used_meshes,'one mesh per original part');used_meshes.add(mi)
        mesh=model['meshes'][mi];keys(mesh,['name','primitives']);require(mesh['name']==expected['name'] and len(mesh['primitives'])==1,'one named source mesh/surface')
        primitive=mesh['primitives'][0];keys(primitive,['attributes','indices','material'],['mode']);require(type(primitive.get('mode',4)) is int and primitive.get('mode',4)==4,'triangles only')
        require(set(primitive['attributes'])=={'POSITION','NORMAL','TEXCOORD_0'},'only declared attributes')
        mat=integer(primitive['material'],0,6,'material reference');require(model['materials'][mat]['name']==expected['material'],'per-part source material')
        arrays={}
        for semantic,ai in list(primitive['attributes'].items())+[('indices',primitive['indices'])]:
            arrays[semantic],size,vi=accessor(model,binary,ai,semantic);used_views.add(vi)
            # Identical accessor references are legal shared storage. Each part
            # still receives the complete independent geometry comparison below.
            if ai in used_accessors:
                require(accessor_semantics[ai]==semantic,'shared accessor retains one channel semantic')
            else:
                used_accessors.add(ai);accessor_semantics[ai]=semantic;decoded+=size
            require(decoded<=MAX_DECODED,'decoded8MiB cap')
        triangles+=len(arrays['indices'])//3;require(triangles<=MAX_TRIANGLES,'triangle cap')
        composed_vertices,composed_normals=compose_part_arrays(node,arrays['POSITION'],arrays['NORMAL'])
        result=compare_triangles(composed_vertices,composed_normals,arrays['TEXCOORD_0'],arrays['indices'],expected)
        observations.append(dict(name=expected['name'],triangles=len(arrays['indices'])//3,**result))
    require(used_accessors==set(range(len(model['accessors']))) and used_views==set(range(len(model['bufferViews']))) and used_meshes==set(range(74)),'no unused/hidden geometry storage')
    return {'schema':'OriginalCockpitIndependentGlbChecks/v1','passed':True,'parts':74,'nodes':84,'materials':7,'images':2,'triangles':triangles,'decoded_array_bytes':decoded,'parts_observed':observations,'scope':'Independent GLB topology/material/PNG checks only; actual Godot import, pixels and delivery pending.'}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('glb','fixtures','albedo','roughness','output'):parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();fixture=fixtures(args.fixtures)
    pngs={name:raw_file(getattr(args,name),1024*1024) for name in ('albedo','roughness')}
    for name,raw in pngs.items():check_png_detail(raw,name=='roughness')
    raw=raw_file(args.glb);model,binary=decode_glb(raw);result=validate(model,binary,fixture,pngs)
    result['inputs']={name:{'path':str(path.absolute()),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()} for name,path,data in [('glb',args.glb,raw),('fixtures',args.fixtures,raw_file(args.fixtures,8*1024*1024))]+[(name,getattr(args,name),pngs[name]) for name in pngs]}
    with args.output.open('x',encoding='utf-8',newline='\n') as f:json.dump(result,f,indent=2);f.write('\n')
    print('ORIGINAL_COCKPIT_GLB_CHECKED_NOT_IMPORTED')

if __name__=='__main__':main()
