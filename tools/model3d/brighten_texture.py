"""Brighten an embedded glTF texture with a gamma curve. Python (no Blender).

For a character whose Meshy texture bakes out too dark — Bloodhound measured
mean 41/255, median 32/255, with detail almost entirely below 93/255 — a flat
brightness ADD blows out the already-bright bits (teeth, highlights) while
barely lifting the shadows where all the actual texture detail lives. A gamma
curve (output = (input/255)^(1/gamma) * 255) lifts the shadow/midtone range
much harder than the highlights, so it brightens exactly the part that's too
dark without flattening the parts that already read fine.

This edits the .glb directly (no Blender import/export round-trip needed —
it's pure 2D image data), so it can run standalone on any merged model.

  py -3 brighten_texture.py "assets/3d pipeline/hero/bloodhound/bloodhound.glb" \
      --gamma 1.8 [--out other.glb]

gamma 1.0 = no change. Higher lifts shadows harder. Bloodhound was calibrated
at 1.8 (2026-09-06) after comparing renders at 1.5/1.8/2.2 — 1.8 brightened
the fur enough to read as red-brown instead of black without going flat or
grey.
"""
import argparse
import io
import json
import struct


def read_glb(path):
    b = open(path, "rb").read()
    off, js, bin_ = 12, None, b""
    while off < len(b):
        ln, ty = struct.unpack_from("<II", b, off)
        off += 8
        chunk = b[off:off + ln]
        off += ln
        if ty == 0x4E4F534A:
            js = json.loads(chunk)
        elif ty == 0x004E4942:
            bin_ = chunk
    return js, bytearray(bin_)


def write_glb(path, js, bin_):
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * (-len(jb) % 4)
    bb = bytes(bin_) + b"\x00" * (-len(bin_) % 4)
    total = 12 + 8 + len(jb) + 8 + len(bb)
    with open(path, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(bb), 0x004E4942) + bb)


def brighten(js, bin_, gamma, only_names=None):
    from PIL import Image
    lut = bytes(min(255, round(((i / 255.0) ** (1.0 / gamma)) * 255)) for i in range(256))
    replacements = {}
    for img in js.get("images", []):
        if "bufferView" not in img:
            continue
        # A file can carry OTHER images that are not colour albedo at all —
        # a normal map or metallic/roughness map gamma-corrected the same way
        # as a colour texture comes out corrupted (those aren't perceptual
        # colour, gamma doesn't apply). only_names restricts this to the
        # actual albedo(s); leave it unset only when every image in the file
        # really is a plain colour texture.
        if only_names is not None and img.get("name") not in only_names:
            continue
        bv = js["bufferViews"][img["bufferView"]]
        off = bv.get("byteOffset", 0)
        raw = bytes(bin_[off:off + bv["byteLength"]])
        im = Image.open(io.BytesIO(raw))
        mode = im.mode
        rgb = im.convert("RGB").point(lut * 3)
        if mode in ("RGBA", "LA", "P"):
            out_im = rgb.convert("RGBA")
            out_im.putalpha(im.convert("RGBA").split()[-1])
        else:
            out_im = rgb
        out = io.BytesIO()
        out_im.save(out, format="PNG", optimize=True)
        replacements[img["bufferView"]] = out.getvalue()
        print("  brightened %s (gamma %.2f)" % (img.get("name"), gamma))
    if not replacements:
        return bin_
    new_bin = bytearray()
    for i, bv in enumerate(js["bufferViews"]):
        data = replacements.get(i)
        if data is None:
            off = bv.get("byteOffset", 0)
            data = bytes(bin_[off:off + bv["byteLength"]])
        while len(new_bin) % 4:
            new_bin.append(0)
        bv["byteOffset"] = len(new_bin)
        bv["byteLength"] = len(data)
        new_bin.extend(data)
    return new_bin


def main():
    p = argparse.ArgumentParser()
    p.add_argument("model")
    p.add_argument("--gamma", type=float, default=1.8)
    p.add_argument("--images", help="comma-separated image names to brighten (default: all — "
                                     "only safe when every image in the file is a colour texture)")
    p.add_argument("--out")
    a = p.parse_args()

    only_names = set(a.images.split(",")) if a.images else None
    js, bin_ = read_glb(a.model)
    bin_ = brighten(js, bin_, a.gamma, only_names)
    js["buffers"] = [{"byteLength": len(bin_)}]
    dest = a.out or a.model
    write_glb(dest, js, bin_)
    print("wrote %s" % dest)


main()
