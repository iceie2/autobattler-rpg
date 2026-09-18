#!/usr/bin/env python3
"""Delete geometry the rig cannot articulate. Blender script.

WHY THIS EXISTS: Meshy's auto-rig is a FIXED 24-bone biped -- Hips, legs, three
spine bones, arms, neck, Head, head_end, headfront -- and that is all it will
ever be. Measured byte-identical across bouncer, bloodhound and headhunter;
bloodhound is a dog and still got the same human skeleton. So a tail, a cloak, a
hood or a long braid has no bone to drive it. It gets rigidly bound to whatever
bone is nearest (a tail lands on Hips) and then swings like a broomstick through
the legs on every walk and attack.

There are only two honest options for that geometry: leave it and accept the
clipping, or remove it. This removes it.

image-to-3d makes the problem likelier than it looks, because it INVENTS the
parts of the model the concept image does not show. Cross's concept was
deliberately tailless and front-facing only; the mesh came back with a full
ringed lemur tail, because the rear was never specified and "ring-tailed lemur"
implies one.

HOW IT CUTS -- by loose part, not by vertex. Meshy's remeshed output is not one
welded shell (Cross: 1045 separate islands), so deleting whole islands whose
CENTROID falls in the strip region removes the appendage without tearing a hole
in anything that remains. Deleting individual vertices inside a shared island
would leave an open boundary that needs patching; this does not.

Always renders nothing and asserts nothing about how it looks -- check the
result with turntable.py.

  blender --background --python strip_region.py -- \
      --model "assets/3d pipeline/hero/cross/cross.glb" \
      --out   "assets/3d pipeline/hero/cross/cross.glb" \
      --behind 0.15 --below 0.60

Axes are BLENDER space after glTF import (Z up, and the character faces -Y
because glTF +Z maps to Blender -Y), so "behind" is +Y.
"""
import sys
import os

import bpy
import bmesh
from mathutils import Vector


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"model": None, "out": None, "behind": None, "below": None,
         "above": None, "group": None, "dry_run": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--dry-run":
            o["dry_run"] = True
            i += 1
            continue
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:].replace("-", "_"), argv[i + 1]
            if k in ("behind", "below", "above"):
                v = float(v)
            o[k] = v
            i += 2
        else:
            i += 1
    return o


def main():
    o = args()
    if not o["model"] or not o["out"]:
        sys.exit("need --model and --out")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    for ob in list(bpy.data.objects):
        if ob.name.startswith("Icosphere"):
            bpy.data.objects.remove(ob, do_unlink=True)

    me = next(o_ for o_ in bpy.data.objects if o_.type == "MESH")
    mw = me.matrix_world

    bm = bmesh.new()
    bm.from_mesh(me.data)
    bm.verts.ensure_lookup_table()

    # Flood-fill into loose parts.
    seen = set()
    parts = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, comp = [v], []
        while stack:
            x = stack.pop()
            if x.index in seen:
                continue
            seen.add(x.index)
            comp.append(x)
            for e in x.link_edges:
                stack.append(e.other_vert(x))
        parts.append(comp)

    doomed = []
    for comp in parts:
        c = Vector((0, 0, 0))
        for v in comp:
            c += mw @ v.co
        c /= len(comp)
        hit = True
        if o["behind"] is not None and not c.y >= o["behind"]:
            hit = False
        if o["below"] is not None and not c.z <= o["below"]:
            hit = False
        if o["above"] is not None and not c.z >= o["above"]:
            hit = False
        if hit:
            doomed.append(comp)

    n_v = sum(len(c) for c in doomed)
    print(f"loose parts {len(parts)}, matching {len(doomed)}, vertices {n_v}"
          f" of {len(bm.verts)}")
    if o["dry_run"]:
        for c in doomed[:20]:
            lo = Vector((1e9,) * 3)
            hi = Vector((-1e9,) * 3)
            for v in c:
                w = mw @ v.co
                for i in range(3):
                    lo[i] = min(lo[i], w[i])
                    hi[i] = max(hi[i], w[i])
            print(f"   n={len(c):5d}  y {lo.y:+.3f}..{hi.y:+.3f}  z {lo.z:.3f}..{hi.z:.3f}")
        return

    if not doomed:
        sys.exit("nothing matched the region -- refusing to write an unchanged file")

    bmesh.ops.delete(bm, geom=[v for c in doomed for v in c], context="VERTS")
    bm.to_mesh(me.data)
    bm.free()
    me.data.update()
    print(f"mesh now {len(me.data.vertices)} verts, {len(me.data.polygons)} faces")

    bpy.ops.export_scene.gltf(filepath=o["out"], export_format="GLB",
                              export_animations=True, use_selection=False)
    print("WROTE " + o["out"])


if __name__ == "__main__":
    main()
