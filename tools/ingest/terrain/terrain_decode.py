"""Bounded full-plane Pillow qualification plus independent TIFF/LZW blocks.

This reader is a qualification oracle for the one pinned Float32 source, not a
general ingestion library. Its supported TIFF subset is intentionally explicit.
"""
import hashlib
import math
from pathlib import Path
import struct
import time


class DecodeRefusal(ValueError):
    pass


def need(condition, message):
    if not condition:
        raise DecodeRefusal(message)


def lzw_tiff(raw, expected_bytes):
    """MSB-first TIFF LZW, clear/end codes, early-change=1, max 12 bits."""
    need(0 < expected_bytes <= 8 * 1024 * 1024, 'LZW output block bound')
    table = [bytes([index]) for index in range(256)] + [None, None]
    width, next_code, position, previous = 9, 258, 0, None
    output = bytearray()
    started, ended = False, False
    count = 0
    while position + width <= len(raw) * 8:
        code = 0
        for _ in range(width):
            code = (code << 1) | ((raw[position // 8] >> (7 - position % 8)) & 1)
            position += 1
        count += 1
        need(count <= expected_bytes * 2 + 1024, 'LZW code budget')
        if not started:
            need(code == 256, 'TIFF LZW starts with clear')
            started = True
        if code == 256:
            table = [bytes([index]) for index in range(256)] + [None, None]
            width, next_code, previous = 9, 258, None
            continue
        if code == 257:
            ended = True
            break
        if code < next_code and code < len(table):
            entry = table[code]
            need(entry is not None, 'LZW reserved code')
        else:
            need(code == next_code and previous is not None, 'invalid LZW dictionary code')
            entry = previous + previous[:1]
        need(len(output) + len(entry) <= expected_bytes, 'LZW expanded block overrun')
        output.extend(entry)
        if previous is not None and next_code < 4096:
            table.append(previous + entry[:1])
            next_code += 1
            if next_code == (1 << width) - 1 and width < 12:
                width += 1
        previous = entry
    need(ended and len(output) == expected_bytes, 'LZW missing end/short decoded block')
    return bytes(output)


def float_counts(raw):
    need(len(raw) % 4 == 0, 'Float32 byte alignment')
    nodata = nonfinite = 0
    minimum, maximum = math.inf, -math.inf
    for (value,) in struct.iter_unpack('<f', raw):
        if not math.isfinite(value):
            nonfinite += 1
        elif value == -999999.0:
            nodata += 1
        else:
            minimum, maximum = min(minimum, value), max(maximum, value)
    return {'samples': len(raw) // 4, 'nodata': nodata, 'nonfinite': nonfinite,
            'minimum_valid': minimum if math.isfinite(minimum) else None,
            'maximum_valid': maximum if math.isfinite(maximum) else None}


class TiffBlocks:
    """Classic TIFF 42 primary IFD only, one-band Float32 LZW, Predictor=1.

    Do not silently extend this oracle to floating-point Predictor=3. Its byte
    shuffle/endian semantics require separate fixed hand fixtures and review.
    """
    def __init__(self, path):
        self.path = Path(path)
        self.size = self.path.stat().st_size
        self.stream = self.path.open('rb')
        try:
            header = self.read(0, 8)
            need(header[:2] in (b'II', b'MM'), 'TIFF byte order')
            self.endian = '<' if header[:2] == b'II' else '>'
            need(struct.unpack(self.endian + 'H', header[2:4])[0] == 42, 'classic TIFF 42 only')
            offset = struct.unpack(self.endian + 'I', header[4:])[0]
            count = struct.unpack(self.endian + 'H', self.read(offset, 2))[0]
            need(0 < count <= 128, 'IFD count bound')
            entries = self.read(offset + 2, 12 * count + 4)
            self.next_ifd = struct.unpack(self.endian + 'I', entries[-4:])[0]
            need(self.next_ifd == 0 or 8 <= self.next_ifd <= self.size - 2, 'subsequent IFD pointer bounds')
            self.tags = {}
            types = {1: ('B', 1), 2: ('s', 1), 3: ('H', 2), 4: ('I', 4), 5: ('I', 8),
                     6: ('b', 1), 7: ('B', 1), 8: ('h', 2), 9: ('i', 4), 10: ('i', 8), 11: ('f', 4), 12: ('d', 8)}
            for index in range(count):
                entry = entries[index * 12:(index + 1) * 12]
                tag, kind, length = struct.unpack(self.endian + 'HHI', entry[:8])
                need(tag not in self.tags and kind in types and 0 < length <= 1024 * 1024, 'IFD type/count/duplicate')
                code, size = types[kind]
                byte_count = length * size
                need(byte_count <= 8 * 1024 * 1024, 'tag byte bound')
                payload = entry[8:8 + byte_count] if byte_count <= 4 else self.read(struct.unpack(self.endian + 'I', entry[8:])[0], byte_count)
                if kind == 2:
                    need(payload.endswith(b'\0'), 'TIFF ASCII termination')
                    value = payload[:-1].decode('ascii', errors='strict')
                else:
                    values = struct.unpack(self.endian + code * (length * 2 if kind in (5, 10) else length), payload)
                    value = values[0] if len(values) == 1 else list(values)
                self.tags[tag] = value
            for tag, value in {258: 32, 259: 5, 262: 1, 277: 1, 339: 3}.items():
                need(self.tags.get(tag) == value, 'source TIFF format tag ' + str(tag))
            need(self.tags.get(284, 1) == 1 and self.tags.get(274, 1) == 1, 'TIFF planar/orientation')
            need(self.tags.get(317, 1) == 1, 'unqualified TIFF predictor; no silent predictor conversion')
            self.width, self.height = self.tags[256], self.tags[257]
            need(type(self.width) is int and type(self.height) is int and 0 < self.width <= 16384 and 0 < self.height <= 16384, 'TIFF dimensions')
            tiled = 324 in self.tags
            need(not (tiled and 273 in self.tags), 'mixed tile/strip storage')
            self.block_width = self.tags[322] if tiled else self.width
            self.block_height = self.tags[323] if tiled else self.tags[278]
            need(type(self.block_width) is int and type(self.block_height) is int and 0 < self.block_width <= 16384 and 0 < self.block_height <= 16384, 'block dimensions')
            self.offsets = self.tags[324 if tiled else 273]
            self.counts = self.tags[325 if tiled else 279]
            if type(self.offsets) is int:
                self.offsets = [self.offsets]
            if type(self.counts) is int:
                self.counts = [self.counts]
            self.across = (self.width + self.block_width - 1) // self.block_width
            self.down = (self.height + self.block_height - 1) // self.block_height
            self.tiled = tiled
            need(len(self.offsets) == len(self.counts) == self.across * self.down <= 65536, 'block roster')
            need(self.block_width * self.block_height * 4 <= 8 * 1024 * 1024, 'decoded block memory budget')
        except BaseException:
            self.stream.close()
            raise

    def read(self, offset, length):
        need(type(offset) is int and type(length) is int and 0 <= offset <= self.size and 0 <= length <= self.size - offset, 'TIFF read span')
        self.stream.seek(offset)
        raw = self.stream.read(length)
        need(len(raw) == length, 'TIFF short read')
        return raw

    def block(self, index):
        need(0 <= index < len(self.offsets), 'block index')
        offset, count = self.offsets[index], self.counts[index]
        need(0 < count <= 16 * 1024 * 1024, 'compressed block budget')
        x = (index % self.across) * self.block_width
        y = (index // self.across) * self.block_height
        rows = self.block_height if self.tiled else min(self.block_height, self.height - y)
        result = lzw_tiff(self.read(offset, count), self.block_width * rows * 4)
        if self.endian == '>':
            result = b''.join(result[index:index + 4][::-1] for index in range(0, len(result), 4))
        return x, y, self.block_width, rows, result

    def close(self):
        self.stream.close()


def decode_qualification(path, Image, features):
    started = time.monotonic()
    # Hash is also checked by the parent before child launch. Check again at
    # point of decode so a changed source is not certified accidentally.
    source_hash = hashlib.sha256()
    with path.open('rb') as stream:
        while data := stream.read(1024 * 1024):
            source_hash.update(data)
    need(path.stat().st_size == 497020458 and source_hash.hexdigest() == 'b62bd2d39d081642fd2b1710a2e3971a216702903b36812304a61ec79f6ac97e', 'actual east source pin')
    need(features.check_codec('libtiff'), 'Pillow libtiff unavailable')
    blocks = TiffBlocks(path)
    try:
        need((blocks.width, blocks.height) == (10012, 10012), 'actual source dimensions')
        expected_tags = {
            33550: [1.0, 1.0, 0.0], 33922: [0.0, 0.0, 0.0, 559994.0, 5340006.0, 0.0],
            34735: [1, 1, 0, 8, 1024, 0, 1, 1, 1025, 0, 1, 1, 1026, 34737, 21, 0, 2049, 34737, 6, 21,
                    2054, 0, 1, 9102, 2062, 34736, 3, 0, 3072, 0, 1, 26910, 3076, 0, 1, 9001],
            34736: [0.0, 0.0, 0.0], 34737: 'NAD83 / UTM zone 10N|NAD83|', 42113: '-999999',
        }
        for tag, value in expected_tags.items():
            need(blocks.tags.get(tag) == value, 'actual source geographic/NoData tag ' + str(tag))
        # This exact hashed source exceeds Pillow's generic warning threshold;
        # admit its fixed dimensions, never disable the pixel limit generally.
        Image.MAX_IMAGE_PIXELS = 10012 * 10012
        with Image.open(path) as image:
            image.seek(0)
            need(image.mode == 'F' and image.size == (10012, 10012) and image.tell() == 0, 'actual Pillow primary Float32 full-plane mode')
            reported_frames = image.n_frames
            image.seek(0)
            # Reading raw Float32 preserves elevation bits; no 8-bit conversion.
            image.load()
            raw = image.tobytes()
            need(len(raw) == 400960576, 'full-plane Float32 byte count')
            for tag in (256, 257, 258, 259, 262, 277, 284, 339, *expected_tags.keys()):
                value = image.tag_v2.get(tag, 1 if tag == 284 else None)
                if isinstance(value, tuple):
                    value = value[0] if len(value) == 1 else list(value)
                need(value == blocks.tags.get(tag, 1 if tag == 284 else None), 'Pillow/raw tag disagreement ' + str(tag))
            count = len(blocks.offsets)
            selected = sorted({0, count - 1, *(i * (count - 1) // 11 for i in range(12))})
            comparisons = []
            for index in selected:
                x, y, width, rows, independent = blocks.block(index)
                clipped_width, clipped_rows = min(width, blocks.width - x), min(rows, blocks.height - y)
                compared = hashlib.sha256()
                for row in range(clipped_rows):
                    expected = independent[row * width * 4:(row * width + clipped_width) * 4]
                    start = ((y + row) * blocks.width + x) * 4
                    actual = raw[start:start + clipped_width * 4]
                    need(actual == expected, 'independent TIFF LZW block mismatch ' + str(index))
                    compared.update(actual)
                comparisons.append({'block': index, 'x': x, 'y': y, 'width': clipped_width, 'height': clipped_rows,
                                    'independently_compared_bytes': clipped_width * clipped_rows * 4, 'sha256': compared.hexdigest()})
            samples = []
            for x, y in ((0, 0), (10011, 0), (0, 10011), (10011, 10011), (5006, 5006), (511, 512), (8191, 8192)):
                offset = (y * blocks.width + x) * 4
                samples.append({'column': x, 'row': y, 'little_endian_float32_hex': raw[offset:offset + 4].hex(),
                                'value': struct.unpack_from('<f', raw, offset)[0]})
            counts = float_counts(raw)
            need(counts['nodata'] == 0 and counts['nonfinite'] == 0, 'actual source invalid samples: reject before future terrain processing')
            return {'source_sha256': source_hash.hexdigest(), 'mode': image.mode, 'width': image.width, 'height': image.height,
                    'full_plane_bytes': len(raw), 'full_plane_sha256': hashlib.sha256(raw).hexdigest(),
                    'full_plane_hash_is_observation_not_independent_expected_value': True,
                    'raw_source_tags': {str(key): value for key, value in blocks.tags.items()},
                    'source_byte_order': blocks.endian, 'lzw_predictor': blocks.tags.get(317, 1),
                    'qualified_ifd_index': 0, 'next_ifd_offset': blocks.next_ifd, 'pillow_reported_frames': reported_frames,
                    'libtiff_version': features.version_codec('libtiff'), 'float32_counts': counts,
                    'samples': samples, 'independent_blocks': comparisons,
                    'independent_coverage': 'deterministic twelve compressed blocks, clipped to valid raster pixels; not every pixel',
                    'elapsed_seconds': time.monotonic() - started, 'streaming_decoder_claim': False}
    finally:
        blocks.close()
