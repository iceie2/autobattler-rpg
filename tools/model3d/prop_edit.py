#!/usr/bin/env python3
"""Axis-band edits on a generated prop: stretch a region, split materials.

Blender script. Meshy props arrive as ONE object with ZERO materials, aligned
along their longest axis. Everything a prop needs before it can be socketed --
lengthening a feature that generated too short, and carving out the region that
has to shade differently -- is a selection by position along that axis, so both
live here rather than in a per-hero one-off.

WHY BANDS AND NOT ISLANDS. strip_region.py works on loose parts because a
character mesh comes back as hundreds of islands. A prop is a single welded
island; the only handle on it is geometry. `--profile` prints the radius per
slab so the bands are chosen from measurements, not from squinting at a render.

  # measure first, always
  blender -b --python prop_edit.py -- --model syringe.glb --profile

  # needle (first 4.5% of length) 3x longer and twice as thick, then a
  # separate material on the barrel's fluid span
  blender -b --python prop_edit.py -- --model syringe.glb --out syringe2.glb \
      --stretch 0:0.045:-0.10 --radial 0:0.045:2.0 \
      --band 0.28:0.76:Fluid --base-mat Body

--stretch LO:HI:D moves every vertex in the band by D along the axis, so the
geometry BETWEEN the band and the rest stretches to follow -- the band's own
shape is preserved and only the joining span deforms. Sign matters: negative
pushes toward the axis minimum.

--recentre T moves the mesh so the point T along the axis (and the off-axis
centreline) sits at the object origin -- i.e. T is the point that will land in
the hand when rig_weapon.py places it.

--band LO:HI:NAME assigns faces whose CENTRE falls in the band to a second
material slot. Face centres, not vertices: a face straddling the boundary lands
on one side cleanly instead of leaving a ragged seam.
"""
import json
import sys

import bpy
import numpy as np
from mathutils import Vector


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"model": None, "out": None, "profile": False, "slabs": 24,
         "stretch": [], "radial": [], "band": [], "base_mat": "Body",
         "recentre": None,
         "base_color": None, "band_color": None, "json": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--profile":
            o["profile"] = True; i += 1; continue
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:].replace("-", "_"), argv[i + 1]
            if k in ("stretch", "radial", "band"):
                o[k].append(v)
            elif k == "slabs":
                o[k] = int(v)
            else:
                o[k] = v
            i += 2
        else:
            i += 1
    return o


def hexcol(s):
    s = s.lstrip("#")
    return [int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)] + [1.0]


def main():
    o = args()
    R = {"model": o["model"]}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    ob = next(x for x in bpy.data.objects if x.type == "MESH")
    me = ob.data

    co = np.array([list(v.co) for v in me.vertices])
    size = co.max(0) - co.min(0)
    ax = int(np.argmax(size))
    lo, hi = float(co[:, ax].min()), float(co[:, ax].max())
    L = hi - lo
    others = [i for i in range(3) if i != ax]
    R.update(axis="XYZ"[ax], length=round(L, 5),
             size=[round(float(x), 5) for x in size], verts=len(me.vertices),
             polys=len(me.polygons))
    print("axis %s  length %.4f  verts %d  polys %d"
          % (R["axis"], L, len(me.vertices), len(me.polygons)))

    def t_of(vals):
        return (vals - lo) / L

    if o["profile"]:
        prof = []
        a = co[:, ax]
        for k in range(o["slabs"]):
            t0, t1 = k / o["slabs"], (k + 1) / o["slabs"]
            m = (t_of(a) >= t0) & (t_of(a) <= t1)
            if not m.any():
                prof.append([round(t0, 3), round(t1, 3), 0, None]); continue
            sub = co[m][:, others]
            r = float(np.linalg.norm(sub - sub.mean(0), axis=1).max())
            prof.append([round(t0, 3), round(t1, 3), int(m.sum()), round(r, 4)])
            print("  %.3f..%.3f  n=%4d  r=%.4f" % (t0, t1, m.sum(), r))
        R["profile"] = prof

    # ---- radial thickening (before stretch: both read the same band) --------
    axis_centre = co[:, others].mean(0)
    for spec in o["radial"]:
        a0, a1, k = spec.split(":")
        a0, a1, k = float(a0), float(a1), float(k)
        n = 0
        for v in me.vertices:
            t = (v.co[ax] - lo) / L
            if a0 <= t <= a1:
                for j, oi in enumerate(others):
                    v.co[oi] = axis_centre[j] + (v.co[oi] - axis_centre[j]) * k
                n += 1
        print("  radial %.3f..%.3f x%.2f -> %d verts" % (a0, a1, k, n))
        R.setdefault("radial", []).append([a0, a1, k, n])

    for spec in o["stretch"]:
        a0, a1, d = spec.split(":")
        a0, a1, d = float(a0), float(a1), float(d)
        n = 0
        for v in me.vertices:
            t = (v.co[ax] - lo) / L
            if a0 <= t <= a1:
                v.co[ax] += d
                n += 1
        print("  stretch %.3f..%.3f by %+.4f -> %d verts" % (a0, a1, d, n))
        R.setdefault("stretch", []).append([a0, a1, d, n])

    # ---- re-centre on the grip point ---------------------------------------
    # rig_weapon.py sends the prop's ORIGIN to the grip bone, so wherever the
    # origin sits is where the hand ends up. A syringe is held at the finger
    # flange (t~0.8), a sword at its guard -- not at the bounding-box centre.
    # Baking that into the mesh keeps the placement exact and axis-aligned;
    # doing it as a bone-space --offset instead would go through this rig
    # family's corrupt bone frames.
    if o["recentre"] is not None:
        t = float(o["recentre"])
        # recompute: earlier ops may have moved the extremes
        cur = np.array([list(v.co) for v in me.vertices])
        lo2, hi2 = float(cur[:, ax].min()), float(cur[:, ax].max())
        target = lo2 + (hi2 - lo2) * t
        for v in me.vertices:
            v.co[ax] -= target
        # keep the off-axis centreline on the origin too, so the prop does not
        # hang to one side of the hand
        for j, oi in enumerate(others):
            c = (cur[:, oi].min() + cur[:, oi].max()) / 2.0
            for v in me.vertices:
                v.co[oi] -= c
        print("  recentre t=%.3f -> shifted axis by %+.4f" % (t, -target))
        R["recentre"] = [t, round(-target, 5)]
        # The band pass below resolves t against lo/L. Those were captured at
        # import; after this shift they are stale, and a band silently lands on
        # the wrong span (measured: 101 faces became 3374).
        cur = np.array([list(v.co) for v in me.vertices])
        lo, hi = float(cur[:, ax].min()), float(cur[:, ax].max())
        L = hi - lo

    # ---- material slots ----------------------------------------------------
    if o["band"] or o["base_color"]:
        me.materials.clear()
        base = bpy.data.materials.new(o["base_mat"])
        base.use_nodes = True
        if o["base_color"]:
            base.node_tree.nodes["Principled BSDF"].inputs[
                "Base Color"].default_value = hexcol(o["base_color"])
        me.materials.append(base)
        for spec in o["band"]:
            a0, a1, name = spec.split(":")
            a0, a1 = float(a0), float(a1)
            m = bpy.data.materials.new(name)
            m.use_nodes = True
            if o["band_color"]:
                m.node_tree.nodes["Principled BSDF"].inputs[
                    "Base Color"].default_value = hexcol(o["band_color"])
            me.materials.append(m)
            idx = len(me.materials) - 1
            n = 0
            for p in me.polygons:
                c = sum((me.vertices[i].co for i in p.vertices),
                        Vector()) / len(p.vertices)
                t = (c[ax] - lo) / L
                if a0 <= t <= a1:
                    p.material_index = idx
                    n += 1
            print("  band %.3f..%.3f -> slot %d '%s'  %d faces" % (a0, a1, idx, name, n))
            R.setdefault("bands", []).append([a0, a1, name, idx, n])
        R["materials"] = [m.name for m in me.materials]

    co2 = np.array([list(v.co) for v in me.vertices])
    R["size_after"] = [round(float(x), 5) for x in (co2.max(0) - co2.min(0))]
    print("  size after", R["size_after"])

    if o["out"]:
        bpy.ops.export_scene.gltf(filepath=o["out"], export_format="GLB",
                                  use_selection=False)
        R["out"] = o["out"]
    if o["json"]:
        json.dump(R, open(o["json"], "w"), indent=1)


if __name__ == "__main__":
    main()
