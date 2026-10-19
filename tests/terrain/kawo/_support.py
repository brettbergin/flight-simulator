"""Small stdlib-only loader/bit helpers for independent compiler unit tests."""
import importlib.util
from pathlib import Path
import struct
import sys

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parents[2]


def compiler():
    name = '_kawo_compiler_under_test'
    if name not in sys.modules:
        path = REPOSITORY / 'tools/ingest/terrain/kawo_terrain_v1.py'
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        try:
            spec.loader.exec_module(module)
        except BaseException:
            del sys.modules[name]
            raise
    return sys.modules[name]


def b64(word):
    return struct.unpack('>d', bytes.fromhex(word))[0]


def word64(value):
    return struct.pack('>d', value).hex()


def f32(word):
    return struct.unpack('>f', bytes.fromhex(word))[0]
