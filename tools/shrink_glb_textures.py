"""Scales every texture inside a .glb down to at most N pixels, changing
nothing else (skeleton, skin and meshes stay byte-for-byte the same data).
Blender re-exports can alter a skin's rest pose, so this edits the GLB itself.

  python tools/shrink_glb_textures.py <in.glb> <out.glb> [max_px]
"""
import io
import json
import struct
import sys

from PIL import Image


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2, "not a glTF 2 binary"
    off = 12
    doc, binc = None, b""
    while off < len(data):
        ln, kind = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + ln]
        if kind == 0x4E4F534A:
            doc = json.loads(chunk.decode("utf-8"))
        elif kind == 0x004E4942:
            binc = chunk
        off += 8 + ln
    return doc, binc


def pad4(b, fill=b"\0"):
    return b + fill * ((4 - len(b) % 4) % 4)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    max_px = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    doc, binc = read_glb(src)
    views = doc["bufferViews"]
    replaced = {}
    for img in doc.get("images", []):
        if "bufferView" not in img:
            continue
        vi = img["bufferView"]
        v = views[vi]
        raw = binc[v.get("byteOffset", 0): v.get("byteOffset", 0) + v["byteLength"]]
        im = Image.open(io.BytesIO(raw))
        if max(im.size) <= max_px:
            continue
        f = max_px / max(im.size)
        im = im.resize((max(1, int(im.width * f)), max(1, int(im.height * f))), Image.LANCZOS)
        out = io.BytesIO()
        if img.get("mimeType") == "image/jpeg":
            im.convert("RGB").save(out, "JPEG", quality=88)
        else:
            im.save(out, "PNG", optimize=True)
        replaced[vi] = out.getvalue()
    # rebuild the binary chunk with every view in its original order
    new_bin = b""
    for i, v in enumerate(views):
        if v.get("buffer", 0) != 0:
            continue
        chunk = replaced.get(i)
        if chunk is None:
            chunk = binc[v.get("byteOffset", 0): v.get("byteOffset", 0) + v["byteLength"]]
        new_bin = pad4(new_bin)
        v["byteOffset"] = len(new_bin)
        v["byteLength"] = len(chunk)
        new_bin += chunk
    new_bin = pad4(new_bin)
    doc["buffers"][0]["byteLength"] = len(new_bin)
    js = pad4(json.dumps(doc, separators=(",", ":")).encode("utf-8"), b" ")
    total = 12 + 8 + len(js) + 8 + len(new_bin)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(new_bin), 0x004E4942) + new_bin)
    print("textures resized: %d, %d -> %d bytes" % (len(replaced), len(binc), len(new_bin)))


if __name__ == "__main__":
    main()
