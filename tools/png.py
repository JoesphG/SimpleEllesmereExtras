"""Minimal PNG read/write. Pure Python -- no PIL on this machine.

Reads the indexed-colour PNGs that Noto Color Emoji stores in its CBDT table and
writes RGBA ones, because every texture EllesmereUIChat ships is RGBA and
indexed PNG is not known to load in WoW.
"""

import struct
import zlib


def _chunks(blob):
    assert blob[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    i = 8
    while i < len(blob):
        (ln,) = struct.unpack(">I", blob[i : i + 4])
        tag = blob[i + 4 : i + 8]
        yield tag, blob[i + 8 : i + 8 + ln]
        i += 12 + ln


def _unfilter(raw, height, stride, bpp):
    out = bytearray()
    prev = bytearray(stride)
    pos = 0
    for _ in range(height):
        ft = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        pos += stride
        if ft == 1:
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x - bpp]) & 0xFF
        elif ft == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 0xFF
        elif ft == 3:
            for x in range(stride):
                left = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 0xFF
        elif ft == 4:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 0xFF
        elif ft != 0:
            raise ValueError("filter %d" % ft)
        out += line
        prev = line
    return bytes(out)


def read_rgba(blob):
    """-> (width, height, rgba bytes). Indexed and RGBA sources only."""
    idat = b""
    plte = trns = None
    width = height = depth = ctype = None
    for tag, data in _chunks(blob):
        if tag == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", data)
            if interlace:
                raise ValueError("interlaced")
            if ctype == 3:
                if depth not in (1, 2, 4, 8):
                    raise ValueError("bit depth %d" % depth)
            elif depth != 8:
                raise ValueError("bit depth %d" % depth)
        elif tag == b"PLTE":
            plte = data
        elif tag == b"tRNS":
            trns = data
        elif tag == b"IDAT":
            idat += data

    raw = zlib.decompress(idat)

    if ctype == 6:
        return width, height, _unfilter(raw, height, width * 4, 4)

    if ctype == 3:
        # Noto stores some glyphs at 4 bits per pixel, so indices can be packed
        # several to a byte. Filtering still works a byte at a time.
        stride = (width * depth + 7) // 8
        packed = _unfilter(raw, height, stride, 1)
        if depth == 8:
            px = packed
        else:
            per = 8 // depth
            mask = (1 << depth) - 1
            px = bytearray(width * height)
            for y in range(height):
                row = y * stride
                base = y * width
                for x in range(width):
                    byte = packed[row + x // per]
                    shift = 8 - depth * (x % per + 1)
                    px[base + x] = (byte >> shift) & mask
        alpha = [0xFF] * (len(plte) // 3)
        if trns:
            for i, a in enumerate(trns):
                alpha[i] = a
        out = bytearray(width * height * 4)
        for i, v in enumerate(px):
            out[i * 4 + 0] = plte[v * 3 + 0]
            out[i * 4 + 1] = plte[v * 3 + 1]
            out[i * 4 + 2] = plte[v * 3 + 2]
            out[i * 4 + 3] = alpha[v]
        return width, height, bytes(out)

    raise ValueError("colour type %d" % ctype)


def _chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_rgba(width, height, rgba):
    rows = bytearray()
    stride = width * 4
    for y in range(height):
        rows += b"\x00" + rgba[y * stride : (y + 1) * stride]
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + _chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + _chunk(b"IEND", b"")
    )


def square(width, height, rgba):
    """Pad to a square canvas so a |T tex:16|t draws with no squash."""
    side = max(width, height)
    if width == height:
        return side, rgba
    out = bytearray(side * side * 4)
    ox, oy = (side - width) // 2, (side - height) // 2
    for y in range(height):
        src = y * width * 4
        dst = ((y + oy) * side + ox) * 4
        out[dst : dst + width * 4] = rgba[src : src + width * 4]
    return side, bytes(out)


def halve(width, height, rgba):
    """Box-downscale by 2. Chat draws these at ~14px, so 136 is wasted bytes.

    Averaged on premultiplied alpha, or the transparent black around a glyph
    bleeds a dark fringe into its edge.
    """
    w2, h2 = width // 2, height // 2
    out = bytearray(w2 * h2 * 4)
    for y in range(h2):
        r0 = (y * 2) * width * 4
        r1 = (y * 2 + 1) * width * 4
        for x in range(w2):
            pr = pg = pb = pa = 0
            for base in (r0, r1):
                for dx in (0, 1):
                    i = base + (x * 2 + dx) * 4
                    a = rgba[i + 3]
                    pr += rgba[i] * a
                    pg += rgba[i + 1] * a
                    pb += rgba[i + 2] * a
                    pa += a
            o = (y * w2 + x) * 4
            if pa:
                out[o] = min(255, (pr + pa // 2) // pa)
                out[o + 1] = min(255, (pg + pa // 2) // pa)
                out[o + 2] = min(255, (pb + pa // 2) // pa)
                out[o + 3] = (pa + 2) // 4
    return w2, h2, bytes(out)
