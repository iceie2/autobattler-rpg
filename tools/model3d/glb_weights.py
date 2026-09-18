#!/usr/bin/env python3
"""Inspect (and optionally harden) skin weights in a .glb.

Meshy's auto-rigging bleeds forearm influence into the boxing glove, so the glove
deforms and lags instead of moving as one rigid block with the hand. This reads
the JOINTS_0 / WEIGHTS_0 attributes directly so the problem can be measured
before anyone opens a GUI.

  py -3 glb_weights.py <file.glb> --bone RightHand
      report how many vertices the bone influences and how much of their weight
      leaks to other bones.

  py -3 glb_weights.py <file.glb> --bone RightHand --harden 0.5 --out fixed.glb
      every vertex whose weight on <bone> is >= the threshold becomes 100% that
      bone. That is exactly "make the glove rigid", without needing to know which
      polygons are glove.
"""
import json
import os
import struct
import sys

COMP = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
        5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    b = open(path, "rb").read()
    if b[:4] != b"glTF":
        raise ValueError(path + " is not a binary glTF")
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


def accessor(js, bin_, idx):
    """Return a list of tuples for accessor `idx`, honouring bufferView stride."""
    acc = js["accessors"][idx]
    n = NCOMP[acc["type"]]
    fmt, size = COMP[acc["componentType"]]
    bv = js["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or (n * size)
    out = []
    for i in range(acc["count"]):
        o = base + i * stride
        out.append(struct.unpack_from("<" + fmt * n, bin_, o))
    return out, acc, bv, base, stride, fmt, size, n


def main():
    argv = sys.argv[1:]
    if not argv:
        print(__doc__)
        return 1
    path = argv[0]
    bone = None
    harden = None
    out_path = None
    if "--bone" in argv:
        bone = argv[argv.index("--bone") + 1]
    if "--harden" in argv:
        harden = float(argv[argv.index("--harden") + 1])
    if "--out" in argv:
        out_path = argv[argv.index("--out") + 1]

    js, bin_ = read_glb(path)
    names = [n.get("name") for n in js["nodes"]]
    skin = js["skins"][0]
    joints = skin["joints"]                       # joint index -> node index
    jnames = [names[j] for j in joints]
    print("skin joints (%d): %s" % (len(jnames), ", ".join(jnames)))

    prim = js["meshes"][0]["primitives"][0]
    jdata, _, _, _, _, _, _, _ = accessor(js, bin_, prim["attributes"]["JOINTS_0"])
    wdata, wacc, wbv, wbase, wstride, wfmt, wsize, wn = accessor(
        js, bin_, prim["attributes"]["WEIGHTS_0"])
    norm = wacc.get("normalized", False) or wacc["componentType"] != 5126
    scale = {5121: 255.0, 5123: 65535.0}.get(wacc["componentType"], 1.0)

    if bone is None:
        print("\npass --bone <name> to analyse one bone")
        return 0
    if bone not in jnames:
        print("\nno joint named %r" % bone)
        return 1
    target = jnames.index(bone)

    influenced = 0
    leaked = 0
    leak_total = 0.0
    partners = {}
    rows = []
    for vi, (jj, ww) in enumerate(zip(jdata, wdata)):
        w = [x / scale for x in ww] if norm else list(ww)
        tw = sum(w[k] for k in range(4) if jj[k] == target)
        if tw <= 0.0:
            continue
        influenced += 1
        other = sum(w[k] for k in range(4) if jj[k] != target and w[k] > 0)
        if other > 0.001:
            leaked += 1
            leak_total += other
            for k in range(4):
                if jj[k] != target and w[k] > 0.001:
                    partners[jnames[jj[k]]] = partners.get(jnames[jj[k]], 0.0) + w[k]
        rows.append((vi, tw, other))

    print("\nvertices influenced by %s: %d" % (bone, influenced))
    print("  of those, sharing weight with another bone: %d (%.1f%%)"
          % (leaked, 100.0 * leaked / max(influenced, 1)))
    if leaked:
        print("  average leaked weight on those: %.3f" % (leak_total / leaked))
    for k, v in sorted(partners.items(), key=lambda kv: -kv[1]):
        print("    shares with %-16s total weight %.2f" % (k, v))

    if harden is None:
        return 0

    # ── harden ────────────────────────────────────────────────────────────────
    changed = 0
    for vi, tw, other in rows:
        if tw < harden:
            continue
        jj = list(jdata[vi])
        # Put the whole weight on the target bone, zero the rest.
        new_j = [target, 0, 0, 0]
        new_w = [1.0, 0.0, 0.0, 0.0]
        o = wbase + vi * wstride
        if norm:
            struct.pack_into("<" + wfmt * wn, bin_, o,
                             *[int(round(x * scale)) for x in new_w])
        else:
            struct.pack_into("<" + wfmt * wn, bin_, o, *new_w)
        # JOINTS_0 lives in its own accessor/bufferView.
        jacc = js["accessors"][prim["attributes"]["JOINTS_0"]]
        jbv = js["bufferViews"][jacc["bufferView"]]
        jfmt, jsize = COMP[jacc["componentType"]]
        jstride = jbv.get("byteStride") or (4 * jsize)
        jo = jbv.get("byteOffset", 0) + jacc.get("byteOffset", 0) + vi * jstride
        struct.pack_into("<" + jfmt * 4, bin_, jo, *new_j)
        changed += 1

    print("\nhardened %d vertices to 100%% %s (threshold %.2f)" % (changed, bone, harden))
    if out_path:
        write_glb(out_path, js, bin_)
        print("wrote %s (%.1f MB)" % (out_path, os.path.getsize(out_path) / 1e6))
    else:
        print("(no --out given, nothing written)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
