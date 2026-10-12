"""Original MIT. Synthetic malformed-content checks, never aircraft/asset proof."""
import copy
import importlib.util
import json
import math
from pathlib import Path
import struct
import unittest
import zlib

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('independent_cockpit_checks',HERE/'check_cockpit_asset.py')
checker=importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

def png(roughness=False):
    rows=bytearray()
    for y in range(256):
        rows.append(0)
        for x in range(256):
            n=int(x%8<2)+int(y%8<2)+int((x+y)%16<2)
            rows.extend((255,255-4*n,255,255) if roughness else (255-6*n,)*3+(255,))
    def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',256,256,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(rows)))+chunk(b'IEND',b'')

def synthetic_reference_model(fixture,shared_indices=False,local_seat_frames=False):
    """Deliberate fixture arrays, no Blender/export/import observation."""
    m={'asset':{'version':'2.0'},'scene':0,'scenes':[{'nodes':[0]}],
       'nodes':[{'name':'OriginalCockpitAsset','children':list(range(1,10))},{'name':'Static','children':[]}],
       'meshes':[],'materials':[],'accessors':[],'bufferViews':[],'buffers':[],
       'images':[],'textures':[{'sampler':0,'source':0},{'sampler':0,'source':1}],
       'samplers':[{'magFilter':9729,'minFilter':9987,'wrapS':10497,'wrapT':10497}]}
    m['nodes'].extend({'name':row['name'],'translation':row['translation_m'],'children':[]} for row in fixture['markers'])
    nodes={node['name']:i for i,node in enumerate(m['nodes'])};binary=bytearray();index_storage={}
    def view(raw):
        while len(binary)%4:binary.append(0)
        offset=len(binary);binary.extend(raw)
        m['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(raw)})
        return len(m['bufferViews'])-1
    def access(rows,components):
        raw=b''.join(struct.pack('<' + ('I' if components==1 else 'f')*components,*(r if components!=1 else [r])) for r in rows)
        if shared_indices and components==1 and raw in index_storage:return index_storage[raw]
        m['accessors'].append({'bufferView':view(raw),'componentType':5125 if components==1 else 5126,'count':len(rows),'type':{1:'SCALAR',2:'VEC2',3:'VEC3'}[components]})
        result=len(m['accessors'])-1
        if shared_indices and components==1:index_storage[raw]=result
        return result
    for material in fixture['materials']:
        p={'baseColorFactor':fixture['material_linear_rgba'][material['name']], 'metallicFactor':material['metallic'],'roughnessFactor':material['roughness']}
        if material['name'] in checker.TEXTURED:p.update(baseColorTexture={'index':0},metallicRoughnessTexture={'index':1})
        m['materials'].append({'name':material['name'],'pbrMetallicRoughness':p})
    materials={row['name']:i for i,row in enumerate(fixture['materials'])}
    for original_part in fixture['parts']:
        part=copy.deepcopy(original_part)
        local_frame=local_seat_frames and part['name'] in ('LeftSeatBack','RightSeatBack')
        center=[-.29 if part['name']=='LeftSeatBack' else .29,.08,.06]
        angle=math.radians(-8);c,s=math.cos(angle),math.sin(angle)
        if local_frame:
            def unrotate(value):return [value[0],c*value[1]+s*value[2],-s*value[1]+c*value[2]]
            part['vertices_parent_m']=[unrotate([v[k]-center[k] for k in range(3)]) for v in part['vertices_parent_m']]
            part['normals_parent']=[unrotate(n) for n in part['normals_parent']]
        indices=part['indices_cw'];indices=[x for i in range(0,len(indices),3) for x in (indices[i],indices[i+2],indices[i+1])]
        primitive={'attributes':{'POSITION':access(part['vertices_parent_m'],3),'NORMAL':access(part['normals_parent'],3),'TEXCOORD_0':access([[t[0],1-t[1]] for t in part['uv0']],2)},'indices':access(indices,1),'material':materials[part['material']]}
        mi=len(m['meshes']);m['meshes'].append({'name':part['name'],'primitives':[primitive]})
        ni=len(m['nodes']);m['nodes'].append({'name':part['name'],'mesh':mi});m['nodes'][nodes[part['parent']]]['children'].append(ni)
        if local_frame:m['nodes'][ni].update(translation=center,rotation=[math.sin(angle/2),0,0,math.cos(angle/2)])
    pngs={'albedo':png(), 'roughness':png(True)}
    for raw in pngs.values():m['images'].append({'mimeType':'image/png','bufferView':view(raw)})
    m['buffers']=[{'byteLength':len(binary)}]
    while len(binary)%4:binary.append(0)
    return m,bytes(binary),pngs

class Geometry(unittest.TestCase):
    def setUp(self):
        self.part={'vertices_parent_m':[[0,0,0],[0,1,0],[1,0,0]],'normals_parent':[[0,0,1]]*3,'uv0':[[0,0],[0,1],[1,0]],'indices_cw':[0,1,2]}
        self.v=self.part['vertices_parent_m'];self.n=self.part['normals_parent'];self.t=[[0,1],[0,0],[1,1]];self.i=[0,2,1]
    def compare(self,v=None,n=None,t=None,i=None):return checker.compare_triangles(v or self.v,n or self.n,t or self.t,i or self.i,self.part)
    def test_original_cw_to_gltf_ccw_and_uv_flip(self):self.compare()
    def test_split_reindexed_vertices(self):self.compare(v=self.v*2,n=self.n*2,t=self.t*2,i=[3,5,4])
    def test_cyclic_order_is_equivalent(self):self.compare(i=[2,1,0])
    def test_reverse_extra_missing_normals_uv_units(self):
        for kw in [{'i':[0,1,2]},{'i':[0,2,1]*2},{'n':[[0,0,-1]]*3},{'t':self.part['uv0']},{'v':[[x*100 for x in v] for v in self.v]},{'v':[[x+.00001 for x in v] for v in self.v]}]:
            with self.subTest(kw=kw),self.assertRaises(ValueError):self.compare(**kw)
    def test_original_degenerate_multiplicity(self):
        self.part['indices_cw']=[0,0,1];self.compare(i=[0,1,0])
        with self.assertRaises(ValueError):self.compare(i=[0,1,2])

class Parser(unittest.TestCase):
    def test_headers(self):
        for raw in [b'',b'x'*28,struct.pack('<III',0x46546c67,1,28)+b'x'*16,struct.pack('<III',0x46546c67,2,999)+b'x'*16]:
            with self.subTest(raw=raw),self.assertRaises(ValueError):checker.decode_glb(raw)
    def test_duplicate_and_nonfinite(self):
        for raw in [b'{"a":1,"a":2}',b'{"a":NaN}',b'{"a":Infinity}']:
            with self.subTest(raw=raw),self.assertRaises(ValueError):checker.parse_json(raw)
    def test_png_actual_pattern_and_negative_crc(self):
        checker.check_png_detail(png(),False);checker.check_png_detail(png(True),True)
        for bad in [png()[:-1],png()+b'extra',png()[:20]+bytes([png()[20]^1])+png()[21:]]:
            with self.subTest(size=len(bad)),self.assertRaises(ValueError):checker.png_rgba(bad)

class FullSynthetic(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path=HERE.parents[2]/'tests/instruments/cockpit_asset_baseline.gd'
        cls.fixture=checker.fixtures(path)
        cls.model,cls.binary,cls.pngs=synthetic_reference_model(cls.fixture)
    def check(self,m=None,b=None):return checker.validate(m if m is not None else self.model,b if b is not None else self.binary,self.fixture,self.pngs)
    def test_synthetic_complete_reference_is_only_parser_fixture(self):
        result=self.check();self.assertEqual(result['triangles'],14328)
    def test_closed_content_negatives(self):
        cases=[]
        def case(label,fn):
            m=copy.deepcopy(self.model);fn(m);cases.append((label,m))
        case('unit100',lambda m:m['nodes'][0].update(scale=[100,100,100]))
        case('unit001',lambda m:m['nodes'][0].update(scale=[.01,.01,.01]))
        case('axisflip',lambda m:m['nodes'][0].update(scale=[1,1,-1]))
        case('eye',lambda m:m['nodes'][2].update(translation=[0,0,0]))
        case('wrong_parent',lambda m:m['nodes'][1]['children'].pop())
        case('extra_node',lambda m:m['nodes'].append({'name':'hidden'}))
        case('duplicate_name',lambda m:m['nodes'][1].update(name=m['nodes'][2]['name']))
        case('script',lambda m:m['nodes'][1].update(extras={'script':'payload'}))
        case('camera',lambda m:m.update(cameras=[{}]))
        case('skin',lambda m:m.update(skins=[{}]))
        case('animation',lambda m:m.update(animations=[{}]))
        case('light_extension',lambda m:m.update(extensionsUsed=['KHR_lights_punctual']))
        case('external_buffer',lambda m:m['buffers'][0].update(uri='remote.bin'))
        case('external_image',lambda m:m['images'][0].update(uri='remote.png'))
        case('extra_image',lambda m:m['images'].append(dict(m['images'][0])))
        case('wrong_uvset',lambda m:m['meshes'][0]['primitives'][0]['attributes'].update(TEXCOORD_1=0))
        case('sparse',lambda m:m['accessors'][0].update(sparse={}))
        case('normalized',lambda m:m['accessors'][0].update(normalized=True))
        case('float_index',lambda m:m['accessors'][3].update(componentType=5126))
        case('bool_count',lambda m:m['accessors'][0].update(count=True))
        case('overflow_count',lambda m:m['accessors'][0].update(count=60001))
        case('truncated_view',lambda m:m['bufferViews'][0].update(byteLength=4))
        case('bad_stride',lambda m:m['bufferViews'][0].update(byteStride=11))
        case('roughness',lambda m:m['materials'][0]['pbrMetallicRoughness'].update(roughnessFactor=.01))
        case('wrong_color_space_factor',lambda m:m['materials'][0]['pbrMetallicRoughness'].update(baseColorFactor=[.46,.43,.36,1]))
        case('emission',lambda m:m['materials'][0].update(emissiveFactor=[1,1,1]))
        case('alpha',lambda m:m['materials'][0].update(alphaMode='BLEND'))
        case('filter',lambda m:m['samplers'][0].update(minFilter=9729))
        case('wrap',lambda m:m['samplers'][0].update(wrapS=33071))
        case('wrong_texture_role',lambda m:m['textures'][0].update(source=1))
        for label,m in cases:
            with self.subTest(label=label),self.assertRaises(ValueError):self.check(m)

    def test_identical_shared_indices_count_storage_once(self):
        model,binary,pngs=synthetic_reference_model(self.fixture,shared_indices=True)
        result=checker.validate(model,binary,self.fixture,pngs)
        self.assertLess(len(model['accessors']),len(self.model['accessors']))
        self.assertEqual(result['triangles'],14328)
        widths={5121:1,5123:2,5125:4,5126:4}
        components={'SCALAR':1,'VEC2':2,'VEC3':3}
        expected=sum(a['count']*widths[a['componentType']]*components[a['type']] for a in model['accessors'])
        self.assertEqual(result['decoded_array_bytes'],expected)

    def test_shared_storage_does_not_admit_wrong_part_or_unused_resources(self):
        model,binary,pngs=synthetic_reference_model(self.fixture,shared_indices=True)
        def reject(change):
            malformed=copy.deepcopy(model);change(malformed)
            with self.assertRaises(ValueError):checker.validate(malformed,binary,self.fixture,pngs)
        # Aliasing a different surface's indices must still fail the original
        # per-part triangle/index/normal/UV correspondence, not skip comparison.
        indices=[mesh['primitives'][0]['indices'] for mesh in model['meshes']]
        different=next(ai for ai in indices if model['accessors'][ai]['count']!=model['accessors'][indices[0]]['count'])
        reject(lambda m:m['meshes'][0]['primitives'][0].update(indices=different))
        reject(lambda m:m['meshes'][0]['primitives'][0]['attributes'].update(NORMAL=m['meshes'][0]['primitives'][0]['attributes']['POSITION']))
        reject(lambda m:m['accessors'].append(copy.deepcopy(m['accessors'][0])))
        reject(lambda m:m['bufferViews'].append(copy.deepcopy(m['bufferViews'][0])))
        # Mutating a multiply referenced index accessor is observed by every
        # consuming part; resource sharing grants no topology/content waiver.
        counts={ai:indices.count(ai) for ai in set(indices)}
        shared=next(ai for ai,n in counts.items() if n>1)
        a=model['accessors'][shared];view=model['bufferViews'][a['bufferView']]
        damaged=bytearray(binary);struct.pack_into('<I',damaged,view['byteOffset'],60000)
        with self.assertRaises(ValueError):checker.validate(model,bytes(damaged),self.fixture,pngs)


    def test_original_seat_local_frames_compose_to_frozen_geometry(self):
        model,binary,pngs=synthetic_reference_model(self.fixture,shared_indices=True,local_seat_frames=True)
        result=checker.validate(model,binary,self.fixture,pngs)
        self.assertEqual(result['triangles'],14328)
        for part in result['parts_observed']:
            self.assertLessEqual(part['maximum_position_element_error_m'],checker.POSITION_EPS)
            self.assertGreaterEqual(part['minimum_normal_dot'],checker.NORMAL_DOT)
        # The same exact reference pose represented by a glTF affine matrix is
        # valid too; it must not change any complete composed surface comparison.
        for node in model['nodes']:
            if node['name'] not in ('LeftSeatBack','RightSeatBack'):continue
            basis,translation=checker.part_transform(node)
            node['matrix']=[basis[r][c] for c in range(3) for r in range(3) for _ in [0]]
            node['matrix']=[basis[r][c] if r<3 and c<3 else translation[r] if c==3 and r<3 else 1 if r==c==3 else 0 for c in range(4) for r in range(4)]
            del node['rotation'];del node['translation']
        checker.validate(model,binary,self.fixture,pngs)

    def test_local_frame_is_not_a_pose_or_geometry_waiver(self):
        model,binary,pngs=synthetic_reference_model(self.fixture,shared_indices=True,local_seat_frames=True)
        nodes={node['name']:i for i,node in enumerate(model['nodes'])}
        mutations=[
            lambda m:m['nodes'][nodes['LeftSeatBack']].update(translation=[-.29,.081,.06]),
            lambda m:m['nodes'][nodes['LeftSeatBack']].update(rotation=[0,0,0,1]),
            lambda m:m['nodes'][nodes['RightSeatBack']].update(scale=[1.01,1,1]),
            lambda m:m['nodes'][nodes['Roof']].update(translation=[-.29,.08,.06]),
            lambda m:m['nodes'][0].update(translation=[-.29,.08,.06]),
            lambda m:m['nodes'][nodes['CopiedPilotYoke']].update(rotation=[-.06975647,0,0,.99756405]),
        ]
        for change in mutations:
            malformed=copy.deepcopy(model);change(malformed)
            with self.assertRaises(ValueError):checker.validate(malformed,binary,self.fixture,pngs)
        # Identity node plus unchanged local-frame accessor data fails complete
        # geometry; an admitted node pose never replaces surface correspondence.
        malformed=copy.deepcopy(model)
        node=malformed['nodes'][nodes['LeftSeatBack']];del node['rotation'];del node['translation']
        with self.assertRaises(ValueError):checker.validate(malformed,binary,self.fixture,pngs)

    def test_real_accessor_payload_negatives(self):
        prim=self.model['meshes'][0]['primitives'][0]
        for semantic,mutation in [('POSITION','position'),('NORMAL','normal'),('TEXCOORD_0','uv'),('indices','winding')]:
            ai=prim['indices'] if semantic=='indices' else prim['attributes'][semantic]
            accessor=self.model['accessors'][ai];view=self.model['bufferViews'][accessor['bufferView']];offset=view['byteOffset']
            raw=bytearray(self.binary)
            if mutation=='winding':
                a,b,c=struct.unpack_from('<III',raw,offset);struct.pack_into('<III',raw,offset,a,c,b)
            elif mutation=='normal':
                v=struct.unpack_from('<fff',raw,offset);struct.pack_into('<fff',raw,offset,*[-x for x in v])
            elif mutation=='uv':struct.pack_into('<f',raw,offset,2.0)
            else:struct.pack_into('<f',raw,offset,struct.unpack_from('<f',raw,offset)[0]+.01)
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):self.check(b=bytes(raw))

if __name__=='__main__':unittest.main()
