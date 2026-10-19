"""Literal independent evergreen GLB reference bytes; SOURCE ONLY before review.

This is not candidate-art authoring, a GLB checker or a bundle generator. It only
packs the hand packet's three fixed boxes into two literal numeric witnesses.
No files are written; no project, Blender, Godot or production tool is imported.
"""
import hashlib
import json
from pathlib import Path
import struct
import sys

MAX_CHECK_BYTES = 1048576
WORDS = {
    "0":0x00000000,"1":0x3F800000,"-1":0xBF800000,
    "0.25":0x3E800000,"-0.25":0xBE800000,
    "2.5":0x40200000,"-2.5":0xC0200000,"-2":0xC0000000,
    "1.5":0x3FC00000,"-1.5":0xBFC00000,"2":0x40000000,
    "8":0x41000000,"16":0x41800000,"18":0x41900000,
    "22":0x41B00000,"25":0x41C80000,
}
# Every vertex below is transcribed explicitly from the hand packet's face table.
# No box(bounds), botanical parameter, random seed or candidate-art routine exists.
POSITIONS = (
    (
        ("0.25","0","-0.25"),("0.25","22","-0.25"),("0.25","22","0.25"),("0.25","0","0.25"),
        ("-0.25","0","0.25"),("-0.25","22","0.25"),("-0.25","22","-0.25"),("-0.25","0","-0.25"),
        ("-0.25","22","-0.25"),("-0.25","22","0.25"),("0.25","22","0.25"),("0.25","22","-0.25"),
        ("-0.25","0","0.25"),("-0.25","0","-0.25"),("0.25","0","-0.25"),("0.25","0","0.25"),
        ("0.25","0","0.25"),("0.25","22","0.25"),("-0.25","22","0.25"),("-0.25","0","0.25"),
        ("-0.25","0","-0.25"),("-0.25","22","-0.25"),("0.25","22","-0.25"),("0.25","0","-0.25"),
    ),
    (
        ("2.5","8","-2.5"),("2.5","18","-2.5"),("2.5","18","2.5"),("2.5","8","2.5"),
        ("-2.5","8","2.5"),("-2.5","18","2.5"),("-2.5","18","-2.5"),("-2.5","8","-2.5"),
        ("-2.5","18","-2.5"),("-2.5","18","2.5"),("2.5","18","2.5"),("2.5","18","-2.5"),
        ("-2.5","8","2.5"),("-2.5","8","-2.5"),("2.5","8","-2.5"),("2.5","8","2.5"),
        ("2.5","8","2.5"),("2.5","18","2.5"),("-2.5","18","2.5"),("-2.5","8","2.5"),
        ("-2.5","8","-2.5"),("-2.5","18","-2.5"),("2.5","18","-2.5"),("2.5","8","-2.5"),
    ),
    (
        ("1.5","16","-1.5"),("1.5","25","-1.5"),("1.5","25","2"),("1.5","16","2"),
        ("-2","16","2"),("-2","25","2"),("-2","25","-1.5"),("-2","16","-1.5"),
        ("-2","25","-1.5"),("-2","25","2"),("1.5","25","2"),("1.5","25","-1.5"),
        ("-2","16","2"),("-2","16","-1.5"),("1.5","16","-1.5"),("1.5","16","2"),
        ("1.5","16","2"),("1.5","25","2"),("-2","25","2"),("-2","16","2"),
        ("-2","16","-1.5"),("-2","25","-1.5"),("1.5","25","-1.5"),("1.5","16","-1.5"),
    ),
)
FACE_NORMALS = (("1","0","0"),("-1","0","0"),("0","1","0"),
                ("0","-1","0"),("0","0","1"),("0","0","-1"))
INDICES = (0,1,2,0,2,3,4,5,6,4,6,7,8,9,10,8,10,11,
           12,13,14,12,14,15,16,17,18,16,18,19,20,21,22,20,22,23)
BOUNDS = (((-.25,0,-.25),(.25,22,.25)),
          ((-2.5,8,-2.5),(2.5,18,2.5)),
          ((-2,16,-1.5),(1.5,25,2)))
NAMES = ("Bark","InnerNeedles","OuterNeedles")
MATERIALS = (
    {"name":"EvergreenBark","pbrMetallicRoughness":{
        "baseColorFactor":[.125,.0625,.03125,1],"metallicFactor":0,"roughnessFactor":.875}},
    {"name":"EvergreenInner","pbrMetallicRoughness":{
        "baseColorFactor":[.015625,.0625,.03125,1],"metallicFactor":0,"roughnessFactor":1}},
    {"name":"EvergreenOuter","pbrMetallicRoughness":{
        "baseColorFactor":[.03125,.125,.0625,1],"metallicFactor":0,"roughnessFactor":.875}},
)
LAYOUT_U16 = ((0,288,576),(648,936,1224),(1296,1584,1872))
LAYOUT_U32 = ((0,288,576),(720,1008,1296),(1440,1728,2016))


def literal_document(u32):
    offsets = LAYOUT_U32 if u32 else LAYOUT_U16
    views,accessors,meshes = [],[],[]
    for m in range(3):
        views.extend((
            {"buffer":0,"byteOffset":offsets[m][0],"byteLength":288,"target":34962},
            {"buffer":0,"byteOffset":offsets[m][1],"byteLength":288,"target":34962},
            {"buffer":0,"byteOffset":offsets[m][2],"byteLength":144 if u32 else 72,"target":34963},
        ))
        accessors.extend((
            {"bufferView":3*m,"byteOffset":0,"componentType":5126,"count":24,"type":"VEC3",
             "min":list(BOUNDS[m][0]),"max":list(BOUNDS[m][1])},
            {"bufferView":3*m+1,"byteOffset":0,"componentType":5126,"count":24,"type":"VEC3"},
            {"bufferView":3*m+2,"byteOffset":0,"componentType":5125 if u32 else 5123,"count":36,"type":"SCALAR"},
        ))
        meshes.append({"primitives":[{"attributes":{"POSITION":3*m,"NORMAL":3*m+1},
                                      "indices":3*m+2,"material":m,"mode":4}]})
    return {"asset":{"version":"2.0","generator":"Independent hand fixture v1"},
            "scene":0,"scenes":[{"nodes":[0]}],
            "nodes":[{"name":"OriginalTallNarrowL0","children":[1,2,3]},
                     {"name":"Bark","mesh":0},{"name":"InnerNeedles","mesh":1},
                     {"name":"OuterNeedles","mesh":2}],
            "meshes":meshes,"materials":list(MATERIALS),"accessors":accessors,
            "bufferViews":views,"buffers":[{"byteLength":2160 if u32 else 1944}]}


def literal_binary(u32):
    chunks = []
    normal_words = [WORDS[value] for normal in FACE_NORMALS for _ in range(4) for value in normal]
    for positions in POSITIONS:
        position_words = [WORDS[value] for vertex in positions for value in vertex]
        chunks.append(struct.pack("<72I",*position_words))
        chunks.append(struct.pack("<72I",*normal_words))
        chunks.append(struct.pack("<36I" if u32 else "<36H",*INDICES))
    result = b"".join(chunks)
    if len(result) != (2160 if u32 else 1944):
        raise AssertionError("literal BIN length changed")
    return result


def literal_fixture(u32):
    document = literal_document(u32)
    unpadded_json = json.dumps(document,sort_keys=True,separators=(",",":"),
                               ensure_ascii=True,allow_nan=False).encode("ascii")
    padding = b" "*((-len(unpadded_json))%4)
    json_bytes = unpadded_json+padding
    binary = literal_binary(u32)
    total = 28+len(json_bytes)+len(binary)
    glb = (struct.pack("<III",0x46546C67,2,total)
           +struct.pack("<II",len(json_bytes),0x4E4F534A)+json_bytes
           +struct.pack("<II",len(binary),0x004E4942)+binary)
    if len(glb) != total:
        raise AssertionError("literal complete GLB length changed")
    return {"id":"tall-narrow-lod0-u32-control" if u32 else "tall-narrow-lod0-u16-baseline",
            "per_glb_numeric_subset_expected":"accept",
            "complete_artwork_or_bundle_expected":"not established; boxes fail natural-art visual gate",
            "bytes":len(glb),"sha256":hashlib.sha256(glb).hexdigest(),"hex":glb.hex(),
            "json_document":document,"json_unpadded_bytes":len(unpadded_json),
            "json_unpadded_hex":unpadded_json.hex(),"json_padding_hex":padding.hex(),
            "bin_bytes":len(binary),"bin_hex":binary.hex(),
            "offsets":{"header":0,"header_bytes":12,"json_chunk_header":12,
                       "json_chunk_type":16,"json_data":20,"json_padded_bytes":len(json_bytes),
                       "bin_chunk_header":20+len(json_bytes),"bin_chunk_type":24+len(json_bytes),
                       "bin_data":28+len(json_bytes),"bin_padding_bytes":0},
            "view_offsets_absolute":[28+len(json_bytes)+view["byteOffset"] for view in document["bufferViews"]]}


def make_artifact():
    source = Path(__file__)
    oracle = source.with_name("hand-oracles.json")
    return {"kind":"independent-literal-evergreen-glb-reference","version":1,
            "producer_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),
            "hand_oracles_sha256":hashlib.sha256(oracle.read_bytes()).hexdigest(),
            "serialization":{"json":"ASCII, sorted keys, compact comma/colon separators, allow_nan=False",
                             "json_padding":"ASCII space only to4-byte alignment","bin":"explicit LE raw words, no padding"},
            "fixtures":[literal_fixture(False),literal_fixture(True)],
            "decoded_reference_vectors":{
                "positions_decimal_strings":POSITIONS,
                "position_raw_f32_words_hex":[[[f"{WORDS[c]:08x}" for c in v] for v in mesh] for mesh in POSITIONS],
                "normal_raw_f32_words_hex":[[f"{WORDS[c]:08x}" for c in n] for n in FACE_NORMALS for _ in range(4)],
                "indices":INDICES,"per_mesh_aabb":BOUNDS,
                "per_mesh_signed_volume_m3":[5.5,250,110.25],
                "overall_aabb_min":[-2.5,0,-2.5],"overall_aabb_max":[2.5,25,2.5],
                "totals":{"stored_vertices":72,"indices":108,"triangles":36,"meshes":3,"nodes":4,"materials":3}},
            "scope":"numeric per-GLB witness only; not finished artwork, full bundle, source receipt, importer or runtime evidence"}


def unique_object(pairs):
    result = {}
    for key,value in pairs:
        if key in result:
            raise ValueError("duplicate expected JSON key")
        result[key] = value
    return result


def reject_nonfinite(value):
    raise ValueError("nonfinite expected JSON constant: "+value)


def main():
    if len(sys.argv) == 1:
        print(json.dumps(make_artifact(),indent=2,sort_keys=True))
        return 0
    if len(sys.argv) != 3 or sys.argv[1] != "--check":
        print("usage: producer.py [--check expected.json]",file=sys.stderr)
        return 2
    try:
        with Path(sys.argv[2]).open("rb") as source:
            data = source.read(MAX_CHECK_BYTES+1)
        if len(data)>MAX_CHECK_BYTES:
            raise ValueError("expected JSON exceeds1MiB")
        expected = json.loads(data.decode("utf-8"),object_pairs_hook=unique_object,
                              parse_constant=reject_nonfinite)
        # Artifact vectors use tuples internally; JSON owns arrays. Compare their
        # canonical JSON values, not Python tuple/list representation details.
        actual = json.loads(json.dumps(make_artifact(),sort_keys=True,allow_nan=False))
        if expected != actual:
            print("literal evergreen reference mismatch",file=sys.stderr)
            return 1
    except (OSError,UnicodeError,ValueError) as error:
        print("literal evergreen reference check failed: "+str(error),file=sys.stderr)
        return 1
    print("literal evergreen reference matches")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
